#!/usr/bin/env python3
import argparse
import cmd
import shlex
from pathlib import Path

from assembler import Assembler
from vmp import CPU

try:
    from vmdbg_tui import KM32TUI
except ImportError:
    KM32TUI = None


def parse_int(value):
    try:
        return int(value, 0)
    except ValueError:
        raise argparse.ArgumentTypeError(f"invalid integer: {value}")


def parse_watch_mem(value):
    parts = value.split(":")
    if len(parts) == 1:
        return parse_int(parts[0]), 1
    if len(parts) == 2:
        return parse_int(parts[0]), parse_int(parts[1])
    raise argparse.ArgumentTypeError(f"invalid watch-mem syntax: {value}")


class VMDbgShell(cmd.Cmd):
    intro = "KR32 VM debugger. Type help or ? for commands."
    prompt = "vmdbg> "

    def __init__(self, cpu, trace=False):
        super().__init__()
        self.cpu = cpu
        self.trace = trace

    def preloop(self):
        self.print_state()

    def print_state(self):
        print(f"PC=0x{self.cpu.pc:08X} mode={'USER' if self.cpu.mode == 1 else 'KERNEL'}")
        print(f"stop_reason={self.cpu.stop_reason} stop_info={self.cpu.stop_info}")

    def do_run(self, args):
        "run         - execute until breakpoint/watchpoint/halt"
        self.cpu.stop_reason = None
        self.cpu.stop_info = None
        self.cpu.running = True
        self.cpu.run(self.cpu.pc, trace=self.trace)
        print(f"stopped: {self.cpu.stop_reason} pc=0x{self.cpu.pc:08X}")

    def do_continue(self, args):
        "continue    - alias for run"
        return self.do_run(args)

    def do_restart(self, args):
        "restart     - reload image and reset CPU state, preserving breakpoints/watchpoints"
        try:
            self.cpu.reset()
            print(f"restarted debug session, PC=0x{self.cpu.pc:08X}")
        except Exception as exc:
            print(f"restart failed: {exc}")

    do_r = do_restart

    def do_step(self, args):
        "step [n]    - execute n instructions (default 1)"
        count = 1
        if args:
            try:
                count = parse_int(args.strip())
            except argparse.ArgumentTypeError as exc:
                print(exc)
                return
        for i in range(count):
            cont = self.cpu.step(trace=self.trace)
            print(f"step {i+1}: pc=0x{self.cpu.pc:08X} stop_reason={self.cpu.stop_reason}")
            if not cont:
                break

    def do_break(self, args):
        "break ADDR    - add a breakpoint at ADDR"
        try:
            addr = parse_int(args.strip())
        except argparse.ArgumentTypeError as exc:
            print(exc)
            return
        self.cpu.add_breakpoint(addr)
        print(f"breakpoint added at 0x{addr:08X}")

    def do_clear(self, args):
        "clear INDEX   - remove a breakpoint by index"
        try:
            idx = parse_int(args.strip())
        except argparse.ArgumentTypeError as exc:
            print(exc)
            return
        self.cpu.clear_breakpoint_index(idx)
        print(f"breakpoint {idx} removed")

    def do_cb(self, args):
        "cb INDEX      - remove a breakpoint by index"
        return self.do_clear(args)

    def do_watch(self, args):
        "watch reg N | watch mem ADDR[:SIZE] - add a watchpoint"
        parts = shlex.split(args)
        if not parts:
            print("usage: watch reg N | watch mem ADDR[:SIZE]")
            return
        kind = parts[0]
        if kind == "reg" and len(parts) == 2:
            try:
                reg = parse_int(parts[1])
            except argparse.ArgumentTypeError as exc:
                print(exc)
                return
            idx = self.cpu.add_watchpoint_reg(reg)
            print(f"watchpoint {idx} reg R{reg}")
        elif kind == "mem" and len(parts) == 2:
            try:
                addr, size = parse_watch_mem(parts[1])
            except argparse.ArgumentTypeError as exc:
                print(exc)
                return
            idx = self.cpu.add_watchpoint_mem(addr, size)
            print(f"watchpoint {idx} mem 0x{addr:08X}:{size}")
        else:
            print("usage: watch reg N | watch mem ADDR[:SIZE]")

    def do_unwatch(self, args):
        "unwatch INDEX  - remove a watchpoint by index"
        try:
            idx = parse_int(args.strip())
        except argparse.ArgumentTypeError as exc:
            print(exc)
            return
        self.cpu.clear_watchpoint(idx)
        print(f"watchpoint {idx} removed")

    def do_cw(self, args):
        "cw INDEX      - remove a watchpoint by index"
        return self.do_unwatch(args)

    def do_info(self, args):
        "info breakpoints|watchpoints - list configured breakpoints/watchpoints"
        arg = args.strip()
        if arg == "breakpoints":
            for idx, addr in enumerate(self.cpu.list_breakpoints()):
                print(f"{idx}: 0x{addr:08X}")
        elif arg == "watchpoints":
            for idx, watch in enumerate(self.cpu.list_watchpoints()):
                print(f"{idx}: {watch}")
        elif arg == "":
            print(f"breakpoints ({len(self.cpu.breakpoints)})")
            for idx, addr in enumerate(self.cpu.list_breakpoints()):
                print(f"{idx}: 0x{addr:08X}")
            print()
            print(f"watchpoints ({len(self.cpu.watchpoints)})")
            for idx, watch in enumerate(self.cpu.list_watchpoints()):
                print(f"{idx}: {watch}")
        else:
            print("usage: info breakpoints|watchpoints")

    def do_regs(self, args):
        "regs        - print registers"
        regs = " ".join(f"R{i}=0x{self.cpu.r(i):08X}" for i in range(0, 16))
        print(regs)
        print(f"SP=0x{self.cpu.sp:08X} FP=0x{self.cpu.fp:08X} LR=0x{self.cpu.r(self.cpu.LR_REG):08X}")
        print(f"Z={int(self.cpu.Z)} N={int(self.cpu.N)} C={int(self.cpu.C)} V={int(self.cpu.V)}")

    def do_mem(self, args):
        "mem ADDR SIZE - dump memory bytes at ADDR"
        parts = shlex.split(args)
        if len(parts) != 2:
            print("usage: mem ADDR SIZE")
            return
        try:
            addr = parse_int(parts[0])
            size = parse_int(parts[1])
        except argparse.ArgumentTypeError as exc:
            print(exc)
            return
        self.cpu.hexdump(addr, size)

    def do_disasm(self, args):
        "disasm ADDR COUNT - disassemble COUNT instructions starting at ADDR"
        parts = shlex.split(args)
        if len(parts) != 2:
            print("usage: disasm ADDR COUNT")
            return
        try:
            addr = parse_int(parts[0])
            count = parse_int(parts[1])
        except argparse.ArgumentTypeError as exc:
            print(exc)
            return
        pc = addr
        for _ in range(count):
            instr = self.cpu.mem_read_u32(pc, access="x")
            op = (instr >> 24) & 0xFF
            a = (instr >> 16) & 0xFF
            b = (instr >> 8) & 0xFF
            c = instr & 0xFF
            ext = None
            if op in (0x05, 0x06, 0x07, 0x0F, 0x12, 0x13, 0x14, 0x15, 0x1A, 0x1B, 0x1C, 0x1D, 0x30):
                ext = self.cpu.mem_read_u32(pc + 4, access="x")
            print(f"0x{pc:08X}: {self.cpu.disasm(op, a, b, c, ext)}")
            pc += 4 + (4 if ext is not None else 0)

    def do_state(self, args):
        "state       - print CPU state and stop reason"
        self.print_state()

    def do_exit(self, args):
        "exit        - quit debugger"
        return True

    def do_quit(self, args):
        "quit        - quit debugger"
        return True

    def do_EOF(self, args):
        print()
        return True

    def emptyline(self):
        return False


def main():
    parser = argparse.ArgumentParser(description="KR32 VM debugger shell")
    parser.add_argument("--asm", default="kernelshed.asm", help="assembly source file to build")
    parser.add_argument("--image", default="memory.img", help="memory image file")
    parser.add_argument("--no-build", action="store_true", help="do not rebuild the image")
    parser.add_argument("--breakpoint", "-b", action="append", default=[], help="add a breakpoint address")
    parser.add_argument("--watch-reg", action="append", default=[], help="watch register number")
    parser.add_argument("--watch-mem", action="append", default=[], help="watch memory address[:size]")
    parser.add_argument("--trace", action="store_true", help="enable CPU trace during execution")
    parser.add_argument("--run", action="store_true", help="run immediately until breakpoint/halt before entering shell")
    parser.add_argument("--tui", action="store_true", help="use curses-based TUI debugger")
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
        addr = parse_int(bp)
        cpu.add_breakpoint(addr)
    for reg in args.watch_reg:
        idx = parse_int(reg)
        cpu.add_watchpoint_reg(idx)
    for wm in args.watch_mem:
        addr, size = parse_watch_mem(wm)
        cpu.add_watchpoint_mem(addr, size)

    if args.tui:
        if KM32TUI is None:
            raise SystemExit("TUI support is unavailable. Make sure vmdbg_tui.py is present.")
        ui = KM32TUI(cpu, trace=args.trace)
        if args.run:
            cpu.stop_reason = None
            cpu.stop_info = None
            cpu.running = True
            cpu.run(cpu.pc, trace=args.trace)
        ui.start()
        return

    shell = VMDbgShell(cpu, trace=args.trace)
    if args.run:
        shell.do_run("")
    shell.cmdloop()


if __name__ == "__main__":
    main()
