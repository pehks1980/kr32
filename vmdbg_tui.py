#!/usr/bin/env python3
import argparse
from bisect import bisect_right
import curses
import re
import shlex
import time
from pathlib import Path

from assembler import Assembler
from vmp import CPU


def parse_int(value):
    try:
        return int(value, 0)
    except ValueError:
        raise ValueError(f"invalid integer: {value}")


def parse_watch_mem(value):
    parts = value.split(":")
    if len(parts) == 1:
        return parse_int(parts[0]), 1
    if len(parts) == 2:
        return parse_int(parts[0]), parse_int(parts[1])
    raise ValueError(f"invalid watch-mem syntax: {value}")


class KM32TUI:
    HELP_TEXT = "Enter/s=step r=run restart=reset t=toggle b=break cb=clear c=continue d=disasm m=mem i=info w=watch u=unwatch cw=unwatch regs=regs h=help q=quit"
    HELP_LINES = [
        "Commands:",
        "  Enter         - step 1 instruction",
        "  s [N]         - step N instructions (default 1)",
        "  r             - run until breakpoint/watchpoint/halt",
        "  restart       - reload image and reset CPU state",
        "  t [ADDR]      - toggle breakpoint at ADDR or current PC",
        "  b ADDR        - set breakpoint at ADDR",
        "  cb INDEX      - clear breakpoint by index",
        "  c             - continue (alias for run)",
        "  d ADDR [CNT]  - disassemble CNT instructions from ADDR",
        "  m ADDR SIZE   - dump memory at ADDR",
        "  i breakpoints - show breakpoint list",
        "  i watchpoints - show watchpoints",
        "  w reg N       - watch register N",
        "  w mem ADDR[:SIZE] - watch memory range",
        "  u INDEX       - remove watchpoint by index",
        "  cw INDEX      - remove watchpoint by index",
        "  regs          - show register values",
        "  h             - show this help",
        "  q             - quit",
    ]

    LISTING_ADDR_RE = re.compile(r"^0x([0-9A-Fa-f]{8})\s+(.*)$")

    def __init__(self, cpu, trace=False, lst_path=None):
        self.cpu = cpu
        self.trace = trace
        self.status = "Ready"
        self.cmd_history = []
        self.history_index = None
        self.message_lines = []
        self.output_lines = ["Ready"]
        self.disasm_win = None
        self.list_win = None
        self.info_win = None
        self.output_win = None
        self.cmd_win = None
        self.lst_path = Path(lst_path) if lst_path else None
        self.listing_lines = []
        self.listing_addr_to_index = {}
        self.listing_addrs = []
        self._load_listing()
        self.prev_info_state = None
        # do not override CPU trace_output/quiet here; main() controls them

    def start(self):
        curses.wrapper(self._main)

    def _main(self, stdscr):
        self.stdscr = stdscr
        try:
            curses.curs_set(1)
        except curses.error:
            pass
        try:
            curses.use_default_colors()
        except curses.error:
            pass
        self._init_colors()
        stdscr.keypad(True)
        stdscr.clear()
        self._loop()

    def _init_colors(self):
        self.colors = {
            "title": curses.A_BOLD,
            "pc": curses.A_REVERSE,
            "addr": curses.A_NORMAL,
            "comment": curses.A_DIM,
            "label": curses.A_BOLD,
            "status": curses.A_NORMAL,
            "error": curses.A_BOLD,
            "changed": curses.A_DIM,
        }
        if not curses.has_colors():
            return
        curses.start_color()
        pairs = [
            ("title", curses.COLOR_CYAN, -1),
            ("pc", curses.COLOR_BLACK, curses.COLOR_CYAN),
            ("addr", curses.COLOR_YELLOW, -1),
            ("comment", curses.COLOR_GREEN, -1),
            ("label", curses.COLOR_MAGENTA, -1),
            ("status", curses.COLOR_WHITE, -1),
            ("error", curses.COLOR_RED, -1),
            ("changed", curses.COLOR_CYAN, -1),
        ]
        for idx, (name, fg, bg) in enumerate(pairs, start=1):
            try:
                curses.init_pair(idx, fg, bg)
                self.colors[name] = curses.color_pair(idx)
                if name in ("title", "label", "error"):
                    self.colors[name] |= curses.A_BOLD
                if name == "changed":
                    self.colors[name] |= curses.A_DIM
            except curses.error:
                pass

    def _load_listing(self):
        if not self.lst_path:
            return
        try:
            self.listing_lines = self.lst_path.read_text().splitlines()
        except OSError as exc:
            self.status = f"lst disabled: {exc}"
            self.listing_lines = []
            return
        for idx, line in enumerate(self.listing_lines):
            match = self.LISTING_ADDR_RE.match(line)
            if match:
                self.listing_addr_to_index[int(match.group(1), 16)] = idx
        self.listing_addrs = sorted(self.listing_addr_to_index)

    def _loop(self):
        while True:
            if not self._draw():
                if self._wait_for_resize_or_quit():
                    break
                continue
            cmd = self._read_command()
            if cmd is None:
                break
            self._resume_after_debug_pause()
            should_exit = self._handle_command(cmd)
            if should_exit:
                break

    def _resume_after_debug_pause(self):
        timer = getattr(self.cpu, "timer", None)
        if timer is not None and hasattr(timer, "last_tick"):
            timer.last_tick = time.time()

    def _draw(self):
        self.stdscr.erase()
        max_y, max_x = self.stdscr.getmaxyx()
        info_w = max(24, min(40, max_x // 4))
        cmd_h = 4
        output_h = min(max(8, max_y // 4), max_y - 10)
        top_h = max_y - output_h - cmd_h
        disasm_w = max_x - info_w - 1
        if max_x < 50 or disasm_w < 30 or top_h < 8:
            self.disasm_win = None
            self.list_win = None
            self.info_win = None
            self.output_win = None
            self.cmd_win = None
            message = "Terminal too small for KR32 TUI. Resize and retry, or press q to quit."
            if max_y > 0 and max_x > 0:
                self.stdscr.addstr(0, 0, message[: max_x - 1])
            self.stdscr.refresh()
            return False

        show_listing = bool(self.listing_lines) and disasm_w >= 70
        if show_listing:
            cpu_disasm_w = max(30, min(disasm_w // 2, 52))
            list_w = disasm_w - cpu_disasm_w - 1
            self.disasm_win = self.stdscr.subwin(top_h, cpu_disasm_w, 0, 0)
            self.list_win = self.stdscr.subwin(top_h, list_w, 0, cpu_disasm_w + 1)
        else:
            self.disasm_win = self.stdscr.subwin(top_h, disasm_w, 0, 0)
            self.list_win = None
        self.info_win = self.stdscr.subwin(top_h, info_w, 0, disasm_w + 1)
        self.output_win = self.stdscr.subwin(output_h, max_x, top_h, 0)
        self.cmd_win = self.stdscr.subwin(cmd_h, max_x, top_h + output_h, 0)

        self.disasm_win.box()
        if self.list_win:
            self.list_win.box()
        self.info_win.box()
        self.output_win.box()
        self.cmd_win.box()

        self.disasm_win.addstr(0, 2, " DISASM ", self.colors["title"])
        if self.list_win:
            self.list_win.addstr(0, 2, f" {self.lst_path.name} ", self.colors["title"])
        self.info_win.addstr(0, 2, " CPU INFO ", self.colors["title"])
        self.output_win.addstr(0, 2, " OUTPUT ", self.colors["title"])
        self.cmd_win.addstr(0, 2, " COMMAND ", self.colors["title"])

        self._draw_disasm()
        if self.list_win:
            self._draw_listing()
        self._draw_info()
        self._draw_output()
        self._draw_command_area()

        self.stdscr.refresh()
        self.disasm_win.refresh()
        if self.list_win:
            self.list_win.refresh()
        self.info_win.refresh()
        self.output_win.refresh()
        self.cmd_win.refresh()
        self.prev_info_state = self._info_state()
        return True

    def _wait_for_resize_or_quit(self):
        while True:
            try:
                ch = self.stdscr.get_wch()
            except curses.error:
                return True
            if isinstance(ch, str) and ch.lower() in ("q", "\x03"):
                return True
            if ch == curses.KEY_RESIZE:
                return False
            max_y, max_x = self.stdscr.getmaxyx()
            info_w = max(34, min(50, max_x // 4))
            disasm_w = max_x - info_w - 1
            output_h = min(max(8, max_y // 4), max_y - 10)
            top_h = max_y - output_h - 4
            if max_x >= 50 and disasm_w >= 30 and top_h >= 8:
                return False

    def _draw_command_line(self, prompt, buffer, cursor_pos):
        self.cmd_win.move(1, 1)
        self.cmd_win.clrtoeol()
        line = prompt + "".join(buffer)
        width = self.cmd_win.getmaxyx()[1] - 2
        if len(line) > width:
            start = len(line) - width
            line = line[start:]
            cursor_x = len(prompt) + cursor_pos - start
        else:
            cursor_x = len(prompt) + cursor_pos
        self.cmd_win.addstr(1, 1, line)
        self.cmd_win.move(1, 1 + max(0, min(cursor_x, width)))

    def _read_command(self):
        prompt = "cmd> "
        curses.noecho()
        self.cmd_win.keypad(True)
        buffer = []
        cursor_pos = 0
        if self.history_index is None:
            self.history_index = len(self.cmd_history)

        self._draw_command_line(prompt, buffer, cursor_pos)
        self.cmd_win.addstr(2, 1, self.HELP_TEXT[: self.cmd_win.getmaxyx()[1] - 2])
        self.cmd_win.refresh()

        while True:
            try:
                ch = self.cmd_win.get_wch()
            except curses.error:
                return None
            if isinstance(ch, str):
                if ch in ("\n", "\r"):
                    command = "".join(buffer).strip()
                    if command:
                        self.cmd_history.append(command)
                    self.history_index = len(self.cmd_history)
                    return command
                if ch == "\x7f" or ch == "\b":
                    if cursor_pos > 0:
                        del buffer[cursor_pos - 1]
                        cursor_pos -= 1
                elif ch == "\x03":
                    return None
                elif ch.isprintable():
                    buffer.insert(cursor_pos, ch)
                    cursor_pos += 1
            else:
                if ch == curses.KEY_BACKSPACE:
                    if cursor_pos > 0:
                        del buffer[cursor_pos - 1]
                        cursor_pos -= 1
                elif ch == curses.KEY_UP:
                    if self.cmd_history:
                        if self.history_index > 0:
                            self.history_index -= 1
                        if self.history_index < len(self.cmd_history):
                            buffer = list(self.cmd_history[self.history_index])
                            cursor_pos = len(buffer)
                elif ch == curses.KEY_DOWN:
                    if self.cmd_history:
                        if self.history_index < len(self.cmd_history) - 1:
                            self.history_index += 1
                            buffer = list(self.cmd_history[self.history_index])
                            cursor_pos = len(buffer)
                        else:
                            self.history_index = len(self.cmd_history)
                            buffer = []
                            cursor_pos = 0
                elif ch == curses.KEY_LEFT:
                    cursor_pos = max(0, cursor_pos - 1)
                elif ch == curses.KEY_RIGHT:
                    cursor_pos = min(len(buffer), cursor_pos + 1)
                elif ch == curses.KEY_HOME:
                    cursor_pos = 0
                elif ch == curses.KEY_END:
                    cursor_pos = len(buffer)
            self._draw_command_line(prompt, buffer, cursor_pos)
            self.cmd_win.addstr(2, 1, self.HELP_TEXT[: self.cmd_win.getmaxyx()[1] - 2])
            self.cmd_win.refresh()

    def _draw_disasm(self):
        lines = self._disasm_lines()
        height, width = self.disasm_win.getmaxyx()
        max_lines = height - 2
        for idx in range(max_lines):
            y = idx + 1
            self.disasm_win.move(y, 1)
            self.disasm_win.clrtoeol()
            if idx < len(lines):
                addr, text, is_pc = lines[idx]
                prefix = "=> " if is_pc else "   "
                line_text = prefix + text
                if len(line_text) > width - 2:
                    line_text = line_text[: width - 5] + "..."
                if is_pc:
                    self.disasm_win.addstr(y, 1, line_text, self.colors["pc"])
                else:
                    self.disasm_win.addstr(y, 1, line_text, self.colors["addr"])

    def _draw_listing(self):
        height, width = self.list_win.getmaxyx()
        max_lines = height - 2
        center = self._listing_index_for_pc(self.cpu.pc)
        start = max(0, center - max_lines // 2)
        end = min(len(self.listing_lines), start + max_lines)
        if end - start < max_lines:
            start = max(0, end - max_lines)
        for idx, src_idx in enumerate(range(start, end), start=1):
            line = self.listing_lines[src_idx]
            self.list_win.move(idx, 1)
            self.list_win.clrtoeol()
            is_pc = self._line_addr(line) == self.cpu.pc
            self._draw_listing_line(idx, line, width - 2, self.colors["pc"] if is_pc else None)

    def _listing_index_for_pc(self, pc):
        if pc in self.listing_addr_to_index:
            return self.listing_addr_to_index[pc]
        pos = bisect_right(self.listing_addrs, pc) - 1
        if pos < 0:
            return 0
        return self.listing_addr_to_index[self.listing_addrs[pos]]

    def _line_addr(self, line):
        match = self.LISTING_ADDR_RE.match(line)
        if not match:
            return None
        return int(match.group(1), 16)

    def _draw_listing_line(self, y, line, width, override_attr=None):
        text = line[:width]
        if override_attr is not None:
            self.list_win.addstr(y, 1, text, override_attr)
            return
        stripped = text.lstrip()
        if not stripped:
            return
        if stripped.startswith(";"):
            self.list_win.addstr(y, 1, text, self.colors["comment"])
            return
        if self.LISTING_ADDR_RE.match(stripped):
            comment_at = text.find(";")
            if comment_at >= 0:
                self.list_win.addstr(y, 1, text[:comment_at], self.colors["addr"])
                self.list_win.addstr(y, 1 + comment_at, text[comment_at:], self.colors["comment"])
            else:
                self.list_win.addstr(y, 1, text, self.colors["addr"])
            return
        attr = self.colors["label"] if stripped.endswith(":") else self.colors["status"]
        self.list_win.addstr(y, 1, text, attr)

    def _disasm_lines(self):
        pc = self.cpu.pc
        start = max(0, pc - 8 * 12)
        lines = []
        addr = start
        while len(lines) < 30 and addr < pc + 8 * 12:
            instr = self.cpu.mem_peek_u32(addr, access="x")
            if instr is None:
                # Unmapped/out-of-range: show placeholder, skip ahead.
                lines.append((addr, f"0x{addr:08X}: <unmapped>", addr == pc))
                addr += 4
                continue
            op = (instr >> 24) & 0xFF
            a = (instr >> 16) & 0xFF
            b = (instr >> 8) & 0xFF
            c = instr & 0xFF
            ext = None
            if op in (0x05, 0x06, 0x07, 0x0F, 0x12, 0x13, 0x14, 0x15, 0x1A, 0x1B, 0x1C, 0x1D, 0x30):
                ext = self.cpu.mem_peek_u32(addr + 4, access="x")
                if ext is None:
                    ext = 0
            try:
                asm = self.cpu.disasm(op, a, b, c, ext)
            except Exception:
                asm = f"UNKNOWN 0x{instr:08X}"
            lines.append((addr, f"0x{addr:08X}: {asm}", addr == pc))
            addr += 8 if ext is not None else 4

        if len(lines) > 0 and lines[0][0] != pc:
            # ensure current PC is visible roughly in the middle
            pc_index = next((i for i, item in enumerate(lines) if item[0] == pc), None)
            if pc_index is not None:
                start_index = max(0, pc_index - 10)
                lines = lines[start_index:]
        return lines

    def _format_watchpoint(self, watch):
        if watch["type"] == "reg":
            return f"reg R{watch['reg']}"
        return f"mem 0x{watch['addr']:08X}:{watch['size']}"

    def _draw_info(self):
        height, width = self.info_win.getmaxyx()
        rows = []
        current = self._info_state()
        prev = self.prev_info_state
        regs = []
        for i in range(0, 16):
            regs.append((f"R{i}", self.cpu.r(i)))
        col1 = regs[:8]
        col2 = regs[8:16]
        for i in range(8):
            rows.append((self._reg_row_segments(col1[i], col2[i], prev, current), self.colors["status"]))

        rows.append((f"FLAGS Z={int(self.cpu.Z)} N={int(self.cpu.N)} C={int(self.cpu.C)} V={int(self.cpu.V)}", self._changed_attr(prev, current, "FLAGS")))
        rows.append((f"MODE={'USER' if self.cpu.mode == 1 else 'KERNEL'}", self._changed_attr(prev, current, "MODE")))
        rows.append((f"PC=0x{self.cpu.pc:08X}", self._changed_attr(prev, current, "PC")))
        rows.append((f"SP=0x{self.cpu.sp:08X}", self._changed_attr(prev, current, "SP")))
        rows.append((f"FP=0x{self.cpu.fp:08X}", self._changed_attr(prev, current, "FP")))
        rows.append((f"LR=0x{self.cpu.r(self.cpu.LR_REG):08X}", self._changed_attr(prev, current, "LR")))
        rows.append((f"stop={self._format_stop_reason()}", self.colors["status"]))

        bp_addrs = self.cpu.list_breakpoints()
        rows.append((f"breaks={len(bp_addrs)}", self.colors["label"]))
        for bp_line in self._format_addr_rows(bp_addrs, width - 4):
            rows.append((f"  {bp_line}", self.colors["addr"]))

        wp_descs = [self._format_watchpoint(w) for w in self.cpu.list_watchpoints()]
        wp_line = " ".join(wp_descs)
        if len(wp_line) > width - 18:
            wp_line = wp_line[: width - 21] + "..."
        rows.append((f"watches={len(wp_descs)} {wp_line}".strip(), self.colors["status"]))

        status_lines = [f"status={line}" for line in self.status.splitlines() or [""]]
        rows.extend((line, self.colors["status"]) for line in status_lines)
        rows.append((f"trace={'on' if self.trace else 'off'}", self.colors["status"]))
        special_start = len(rows)
        rows.extend(self._special_info_rows(prev, current))

        max_rows = height - 2
        if len(rows) > max_rows and special_start < len(rows):
            special_rows = rows[special_start:]
            prefix_count = max(0, max_rows - len(special_rows))
            rows = rows[:prefix_count] + special_rows

        for i, (line, attr) in enumerate(rows, start=1):
            if i >= height - 1:
                break
            self._draw_info_row(i, line, width - 2, attr)

    def _reg_row_segments(self, left, right, prev, current):
        left_name, left_value = left
        right_name, right_value = right
        return [
            (f"{left_name}={left_value:08X}", self._changed_attr(prev, current, left_name)),
            ("  ", self.colors["status"]),
            (f"{right_name}={right_value:08X}", self._changed_attr(prev, current, right_name)),
        ]

    def _draw_info_row(self, y, line, width, attr):
        if isinstance(line, list):
            x = 1
            remaining = width
            for text, segment_attr in line:
                if remaining <= 0:
                    break
                part = text[:remaining]
                self.info_win.addstr(y, x, part, segment_attr)
                x += len(part)
                remaining -= len(part)
            return
        self.info_win.addstr(y, 1, line[:width], attr)

    def _info_state(self):
        state = {f"R{i}": self.cpu.r(i) for i in range(16)}
        state.update({
            "FLAGS": (bool(self.cpu.Z), bool(self.cpu.N), bool(self.cpu.C), bool(self.cpu.V)),
            "MODE": self.cpu.mode,
            "PC": self.cpu.pc,
            "SP": self.cpu.sp,
            "FP": self.cpu.fp,
            "LR": self.cpu.r(self.cpu.LR_REG),
            "MMU": getattr(self.cpu.mmu, "enabled", None),
            "PTBR": getattr(self.cpu.mmu, "ptbr_pa", None),
            "IDT": getattr(self.cpu, "idt_base_pa", None),
            "SSTATUS": getattr(self.cpu, "sstatus", None),
            "STVEC": getattr(self.cpu, "stvec", None),
            "SEPC": getattr(self.cpu, "sepc", None),
            "SCAUSE": getattr(self.cpu, "scause", None),
            "STVAL": getattr(self.cpu, "stval", None),
            "SSCRATCH": getattr(self.cpu, "sscratch", None),
            "SFLAGS": getattr(self.cpu, "sflags", None),
            "IE": getattr(self.cpu, "interrupt_enabled", None),
            "TRAP_EPC": getattr(self.cpu, "trap_epc", None),
            "TRAP_CAUSE": getattr(self.cpu, "trap_cause", None),
            "TRAP_VALUE": getattr(self.cpu, "trap_value", None),
            "TRAP_RET": getattr(self.cpu, "trap_return_pc", None),
        })
        return state

    def _changed(self, prev, current, key):
        return prev is not None and prev.get(key) != current.get(key)

    def _changed_attr(self, prev, current, key):
        return self.colors["changed"] if self._changed(prev, current, key) else self.colors["status"]

    def _format_addr_rows(self, addrs, width):
        rows = []
        current = ""
        for addr in addrs:
            item = f"0x{addr:08X}"
            sep = " " if current else ""
            if current and len(current) + len(sep) + len(item) > width:
                rows.append(current)
                current = item
            else:
                current += sep + item
        if current:
            rows.append(current)
        return rows

    def _special_info_rows(self, prev, current):
        rows = [("special:", self.colors["label"])]
        specs = [
            (("MMU", "PTBR"), f"MMU={'on' if current['MMU'] else 'off'} {self._hex_special('PTBR', current)}"),
            (("IDT", "IE"), f"{self._hex_special('IDT', current)} irq={'on' if current['IE'] else 'off'}"),
            (("SSTATUS",), self._hex_special("SSTATUS", current, "sstatus")),
            (("STVEC", "SEPC"), f"{self._hex_special('STVEC', current, 'stvec')} {self._hex_special('SEPC', current, 'sepc')}"),
            (("SCAUSE", "STVAL"), f"{self._hex_special('SCAUSE', current, 'scause')} {self._hex_special('STVAL', current, 'stval')}"),
            (("SSCRATCH", "SFLAGS"), f"{self._hex_special('SSCRATCH', current, 'sscratch')} {self._hex_special('SFLAGS', current, 'sflags')}"),
            (("TRAP_CAUSE", "TRAP_VALUE"), f"{self._hex_special('TRAP_CAUSE', current, 'trap_cause')} {self._hex_special('TRAP_VALUE', current, 'trap_value')}"),
            (("TRAP_EPC", "TRAP_RET"), f"{self._hex_special('TRAP_EPC', current, 'trap_epc')} {self._hex_special('TRAP_RET', current, 'trap_ret')}"),
        ]
        for keys, line in specs:
            attr = self.colors["changed"] if any(self._changed(prev, current, key) for key in keys) else self.colors["status"]
            rows.append((line, attr))
        return rows

    def _hex_special(self, key, current, label=None):
        label = label or key.lower()
        value = current.get(key)
        if value is None:
            return f"{label}=n/a"
        return f"{label}=0x{value:08X}"

    def _format_stop_reason(self):
        reason = self.cpu.stop_reason
        if reason is None:
            return "none"
        if isinstance(reason, tuple) and len(reason) == 2:
            if reason[0] == "breakpoint":
                return f"breakpoint @ 0x{reason[1]:08X}"
            return f"{reason[0]} @ 0x{reason[1]:08X}"
        return str(reason)

    def _draw_command_area(self):
        self.cmd_win.move(1, 1)
        self.cmd_win.clrtoeol()
        self.cmd_win.addstr(1, 1, "cmd> ")
        self.cmd_win.addstr(2, 1, self.HELP_TEXT[: self.cmd_win.getmaxyx()[1] - 2])

    def _draw_output(self):
        height, width = self.output_win.getmaxyx()
        max_lines = height - 2
        for idx in range(max_lines):
            y = idx + 1
            self.output_win.move(y, 1)
            self.output_win.clrtoeol()
            if idx < len(self.output_lines):
                line = self.output_lines[idx]
                if len(line) > width - 2:
                    line = line[: width - 5] + "..."
                self.output_win.addstr(y, 1, line)

    def _handle_command(self, command):
        if not command:
            self._step(1)
            return False
        parts = shlex.split(command)
        if not parts:
            self._step(1)
            return False
        op = parts[0].lower()

        try:
            if op in ("q", "quit", "exit"):
                return True
            if op in ("h", "help", "?"):
                self.status = "help"
                self.output_lines = self.HELP_LINES[: self.output_win.getmaxyx()[0] - 2]
                return False
            if op in ("s", "step"):
                count = 1
                if len(parts) > 1:
                    count = parse_int(parts[1])
                self._step(count)
                return False
            if op in ("restart", "reset"):
                self.cpu.reset()
                self.status = f"restarted debug session, PC=0x{self.cpu.pc:08X}"
                self.output_lines = [self.status]
                return False
            if op in ("r", "run", "c", "continue"):
                self.cpu.stop_reason = None
                self.cpu.stop_info = None
                self.cpu.running = True
                self.cpu.run(self.cpu.pc, trace=self.trace)
                self.status = f"ran to stop {self._format_stop_reason()}"
                self.output_lines = [self.status]
                return False
            if op in ("t", "toggle"):
                addr = self.cpu.pc if len(parts) == 1 else parse_int(parts[1])
                if addr in self.cpu.breakpoints:
                    self.cpu.clear_breakpoint(addr)
                    self.status = f"breakpoint cleared 0x{addr:08X}"
                else:
                    self.cpu.add_breakpoint(addr)
                    self.status = f"breakpoint set 0x{addr:08X}"
                self.output_lines = [self.status]
                return False
            if op in ("b", "break") and len(parts) >= 2:
                addr = parse_int(parts[1])
                self.cpu.add_breakpoint(addr)
                self.status = f"breakpoint set 0x{addr:08X}"
                self.output_lines = [self.status]
                return False
            if op in ("cb", "clear") and len(parts) >= 2:
                idx = parse_int(parts[1])
                self.cpu.clear_breakpoint_index(idx)
                self.status = f"cleared breakpoint {idx}"
                return False
            if op in ("i", "info"):
                if len(parts) == 1:
                    lines = [f"breakpoints ({len(self.cpu.breakpoints)})"] + [f"{idx}: 0x{addr:08X}" for idx, addr in enumerate(self.cpu.list_breakpoints())]
                    lines += ["", f"watchpoints ({len(self.cpu.watchpoints)})"] + [f"{idx}: {watch}" for idx, watch in enumerate(self.cpu.list_watchpoints())]
                    self.output_lines = lines[: self.output_win.getmaxyx()[0] - 2]
                    self.status = "info"
                elif parts[1] == "breakpoints":
                    lines = [f"breakpoints ({len(self.cpu.breakpoints)})"] + [f"{idx}: 0x{addr:08X}" for idx, addr in enumerate(self.cpu.list_breakpoints())]
                    self.output_lines = lines[: self.output_win.getmaxyx()[0] - 2]
                    self.status = "breakpoints"
                elif parts[1] == "watchpoints":
                    lines = [f"watchpoints ({len(self.cpu.watchpoints)})"] + [f"{idx}: {watch}" for idx, watch in enumerate(self.cpu.list_watchpoints())]
                    self.output_lines = lines[: self.output_win.getmaxyx()[0] - 2]
                    self.status = "watchpoints"
                else:
                    self.status = "info [breakpoints|watchpoints]"
                    self.output_lines = [self.status]
                return False
            if op in ("m", "mem") and len(parts) == 3:
                addr = parse_int(parts[1])
                size = parse_int(parts[2])
                self._show_mem(addr, size)
                return False
            if op in ("d", "disasm") and len(parts) >= 2:
                addr = parse_int(parts[1])
                count = 16
                if len(parts) >= 3:
                    count = parse_int(parts[2])
                self._show_disasm_block(addr, count)
                return False
            if op in ("w", "watch") and len(parts) >= 3:
                kind = parts[1]
                if kind == "reg":
                    idx = parse_int(parts[2])
                    self.cpu.add_watchpoint_reg(idx)
                    self.status = f"watch reg R{idx}"
                    return False
                if kind == "mem":
                    addr, size = parse_watch_mem(parts[2])
                    self.cpu.add_watchpoint_mem(addr, size)
                    self.status = f"watch mem 0x{addr:08X}:{size}"
                    return False
                raise ValueError("watch reg N | watch mem ADDR[:SIZE]")
            if op in ("u", "unwatch", "cw") and len(parts) == 2:
                idx = parse_int(parts[1])
                self.cpu.clear_watchpoint(idx)
                self.status = f"unwatched {idx}"
                return False
            if op == "regs":
                self.status = "reg values shown"
                self.output_lines = [f"R{i}=0x{self.cpu.r(i):08X}" for i in range(16)]
                return False
            self.status = f"unknown command: {op}"
            self.output_lines = [self.status]
        except Exception as exc:
            self.status = f"error: {exc}"
        return False

    def _step(self, count):
        for _ in range(count):
            cont = self.cpu.step(trace=self.trace)
            if not cont:
                break
        self.status = f"stepped {count} instr{'s' if count != 1 else ''}, PC=0x{self.cpu.pc:08X}"
        self.output_lines = [self.status]

    def _show_mem(self, addr, size):
        lines = []
        for offset in range(0, size, 16):
            row = addr + offset
            chunk = []
            for i in range(16):
                if offset + i < size:
                    value = self.cpu.mem_peek_u8(row + i, "r")
                    chunk.append(value)
            hexvals = " ".join("--" if v is None else f"{v:02X}" for v in chunk)
            lines.append(f"0x{row:08X}: {hexvals}")
        self.status = "mem"
        self.output_lines = lines[: self.output_win.getmaxyx()[0] - 2]

    def _show_disasm_block(self, addr, count):
        lines = []
        pc = addr
        for _ in range(count):
            instr = self.cpu.mem_peek_u32(pc, access="x")
            if instr is None:
                lines.append(f"0x{pc:08X}: <unmapped>")
                pc += 4
                continue
            op = (instr >> 24) & 0xFF
            a = (instr >> 16) & 0xFF
            b = (instr >> 8) & 0xFF
            c = instr & 0xFF
            ext = None
            if op in (0x05, 0x06, 0x07, 0x0F, 0x12, 0x13, 0x14, 0x15, 0x1A, 0x1B, 0x1C, 0x1D, 0x30):
                ext = self.cpu.mem_peek_u32(pc + 4, access="x")
                if ext is None:
                    ext = 0
            asm = self.cpu.disasm(op, a, b, c, ext)
            lines.append(f"0x{pc:08X}: {asm}")
            pc += 8 if ext is not None else 4
        self.status = "disasm"
        self.output_lines = lines[: self.output_win.getmaxyx()[0] - 2]


def main():
    parser = argparse.ArgumentParser(description="KR32 curses TUI debugger")
    parser.add_argument("--asm", default="kernelshed.asm", help="assembly source file to build")
    parser.add_argument("--image", default="memory.img", help="memory image file")
    parser.add_argument("--no-build", action="store_true", help="do not rebuild the image")
    parser.add_argument("--breakpoint", "-b", action="append", default=[], help="add a breakpoint address")
    parser.add_argument("--watch-reg", action="append", default=[], help="watch register number")
    parser.add_argument("--watch-mem", action="append", default=[], help="watch memory address[:size]")
    parser.add_argument("--lst", nargs="?", const="kernelshed.lst.asm", help="show listing file beside CPU disassembly")
    parser.add_argument("--trace", action="store_true", help="enable CPU trace during execution")
    parser.add_argument("--tracevirt", action="store_true", help="trace virtual->physical address translations")
    parser.add_argument("--traceint", action="store_true", help="trace trap/interrupt delivery")
    parser.add_argument("--tracefault", action="store_true", help="trace fault details")
    parser.add_argument("--run", action="store_true", help="run immediately until breakpoint/halt before starting TUI")
    args = parser.parse_args()

    image_path = Path(args.image)
    if not args.no_build:
        if args.asm == "kernelshed.asm":
            print("[BUILD] Preprocessing kernelshed.asm using preprocess_cmacros.py...")
            import subprocess
            subprocess.run("python3 tools/preprocess_cmacros.py kernelshed.asm > kernelshed_pre.asm", shell=True, check=True)
            src_file = "kernelshed_pre.asm"
        else:
            src_file = args.asm
            
        src = Path(src_file).read_text().splitlines()
        Assembler().build(src, out=str(image_path))
    elif not image_path.exists():
        raise SystemExit(f"error: image file {image_path} does not exist")

    cpu = CPU(trace=args.trace)
    cpu.tracevirt = args.tracevirt
    cpu.traceint = args.traceint
    cpu.trace_fault = args.tracefault
    # Enable CPU output when any tracing is requested so translation/trap
    # prints are visible while debugging through the TUI.
    cpu.trace_output = bool(args.trace or args.tracevirt or args.traceint or args.tracefault)
    cpu.quiet = not cpu.trace_output
    cpu.load_image(str(image_path))

    for bp in args.breakpoint:
        cpu.add_breakpoint(parse_int(bp))
    for reg in args.watch_reg:
        cpu.add_watchpoint_reg(parse_int(reg))
    for wm in args.watch_mem:
        addr, size = parse_watch_mem(wm)
        cpu.add_watchpoint_mem(addr, size)

    if args.run:
        cpu.stop_reason = None
        cpu.stop_info = None
        cpu.running = True
        cpu.run(cpu.pc, trace=args.trace)

    ui = KM32TUI(cpu, trace=args.trace, lst_path=args.lst)
    ui.start()


if __name__ == "__main__":
    main()
