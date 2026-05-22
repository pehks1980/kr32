#!/usr/bin/env python3
import argparse
import curses
import shlex
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
    HELP_TEXT = "s=step r=run restart=reset t=toggle b=break cb=clear c=continue d=disasm m=mem i=info w=watch u=unwatch cw=unwatch regs=regs h=help q=quit"
    HELP_LINES = [
        "Commands:",
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

    def __init__(self, cpu, trace=False):
        self.cpu = cpu
        self.trace = trace
        self.status = "Ready"
        self.cmd_history = []
        self.history_index = None
        self.message_lines = []
        self.output_lines = ["Ready"]
        self.cpu.trace_output = False
        self.cpu.quiet = True

    def start(self):
        curses.wrapper(self._main)

    def _main(self, stdscr):
        self.stdscr = stdscr
        curses.curs_set(1)
        curses.use_default_colors()
        stdscr.keypad(True)
        stdscr.clear()
        self._loop()

    def _loop(self):
        while True:
            self._draw()
            cmd = self._read_command()
            if cmd is None:
                break
            should_exit = self._handle_command(cmd)
            if should_exit:
                break

    def _draw(self):
        self.stdscr.erase()
        max_y, max_x = self.stdscr.getmaxyx()
        info_w = max(24, min(40, max_x // 4))
        cmd_h = 4
        output_h = min(max(8, max_y // 4), max_y - 10)
        top_h = max_y - output_h - cmd_h
        disasm_w = max_x - info_w - 1
        if max_x < 50 or disasm_w < 30 or top_h < 8:
            self.stdscr.addstr(0, 0, "Terminal too small for KR32 TUI. Resize and retry.")
            self.stdscr.refresh()
            return

        self.disasm_win = self.stdscr.subwin(top_h, disasm_w, 0, 0)
        self.info_win = self.stdscr.subwin(top_h, info_w, 0, disasm_w + 1)
        self.output_win = self.stdscr.subwin(output_h, max_x, top_h, 0)
        self.cmd_win = self.stdscr.subwin(cmd_h, max_x, top_h + output_h, 0)

        self.disasm_win.box()
        self.info_win.box()
        self.output_win.box()
        self.cmd_win.box()

        self.disasm_win.addstr(0, 2, " DISASM ")
        self.info_win.addstr(0, 2, " CPU INFO ")
        self.output_win.addstr(0, 2, " OUTPUT ")
        self.cmd_win.addstr(0, 2, " COMMAND ")

        self._draw_disasm()
        self._draw_info()
        self._draw_output()
        self._draw_command_area()

        self.stdscr.refresh()
        self.disasm_win.refresh()
        self.info_win.refresh()
        self.output_win.refresh()
        self.cmd_win.refresh()

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
            ch = self.cmd_win.get_wch()
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
                    self.disasm_win.addstr(y, 1, line_text, curses.A_REVERSE)
                else:
                    self.disasm_win.addstr(y, 1, line_text)

    def _disasm_lines(self):
        pc = self.cpu.pc
        start = max(0, pc - 8 * 12)
        lines = []
        addr = start
        while len(lines) < 30 and addr < pc + 8 * 12:
            try:
                instr = self.cpu.mem_read_u32(addr, access="x")
            except Exception:
                break
            op = (instr >> 24) & 0xFF
            a = (instr >> 16) & 0xFF
            b = (instr >> 8) & 0xFF
            c = instr & 0xFF
            ext = None
            if op in (0x05, 0x06, 0x07, 0x0F, 0x12, 0x13, 0x14, 0x15, 0x1A, 0x1B, 0x1C, 0x1D, 0x30):
                try:
                    ext = self.cpu.mem_read_u32(addr + 4, access="x")
                except Exception:
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
        regs = []
        for i in range(0, 16):
            regs.append((f"R{i}", self.cpu.r(i)))
        col1 = regs[:8]
        col2 = regs[8:16]
        for i in range(8):
            line = f"{col1[i][0]}={col1[i][1]:08X}"
            if i < len(col2):
                line += f"  {col2[i][0]}={col2[i][1]:08X}"
            rows.append(line)

        rows.append(f"Z={int(self.cpu.Z)} N={int(self.cpu.N)} C={int(self.cpu.C)} V={int(self.cpu.V)}")
        rows.append(f"MODE={'USER' if self.cpu.mode == 1 else 'KERNEL'}")
        rows.append(f"PC=0x{self.cpu.pc:08X}")
        rows.append(f"SP=0x{self.cpu.sp:08X}")
        rows.append(f"LR=0x{self.cpu.r(self.cpu.LR_REG):08X}")
        rows.append(f"stop={self._format_stop_reason()}")

        bp_addrs = self.cpu.list_breakpoints()
        bp_line = " ".join(f"0x{addr:08X}" for addr in bp_addrs)
        if len(bp_line) > width - 18:
            bp_line = bp_line[: width - 21] + "..."
        rows.append(f"breaks={len(bp_addrs)} {bp_line}".strip())

        wp_descs = [self._format_watchpoint(w) for w in self.cpu.list_watchpoints()]
        wp_line = " ".join(wp_descs)
        if len(wp_line) > width - 18:
            wp_line = wp_line[: width - 21] + "..."
        rows.append(f"watches={len(wp_descs)} {wp_line}".strip())

        status_lines = [f"status={line}" for line in self.status.splitlines() or [""]]
        rows.extend(status_lines)
        rows.append(f"trace={'on' if self.trace else 'off'}")

        for i, line in enumerate(rows, start=1):
            if i >= height - 1:
                break
            self.info_win.addstr(i, 1, line[: width - 2])

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
            self.status = "No command"
            self.output_lines = [self.status]
            return False
        parts = shlex.split(command)
        if not parts:
            self.status = "Empty command"
            self.output_lines = [self.status]
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
                for _ in range(count):
                    cont = self.cpu.step(trace=self.trace)
                    if not cont:
                        break
                self.status = f"stepped {count} instrs"
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

    def _show_mem(self, addr, size):
        lines = []
        for offset in range(0, size, 16):
            row = addr + offset
            chunk = []
            for i in range(16):
                if offset + i < size:
                    try:
                        value = self.cpu.mem_read_u8(row + i, "r")
                    except Exception:
                        value = 0
                    chunk.append(value)
            hexvals = " ".join(f"{v:02X}" for v in chunk)
            lines.append(f"0x{row:08X}: {hexvals}")
        self.status = "mem"
        self.output_lines = lines[: self.output_win.getmaxyx()[0] - 2]

    def _show_disasm_block(self, addr, count):
        lines = []
        pc = addr
        for _ in range(count):
            try:
                instr = self.cpu.mem_read_u32(pc, access="x")
            except Exception:
                break
            op = (instr >> 24) & 0xFF
            a = (instr >> 16) & 0xFF
            b = (instr >> 8) & 0xFF
            c = instr & 0xFF
            ext = None
            if op in (0x05, 0x06, 0x07, 0x0F, 0x12, 0x13, 0x14, 0x15, 0x1A, 0x1B, 0x1C, 0x1D, 0x30):
                try:
                    ext = self.cpu.mem_read_u32(pc + 4, access="x")
                except Exception:
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
    parser.add_argument("--trace", action="store_true", help="enable CPU trace during execution")
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

    ui = KM32TUI(cpu, trace=args.trace)
    ui.start()


if __name__ == "__main__":
    main()
