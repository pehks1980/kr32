import argparse


# =========================================================
# KR32-RISC CPU (FINAL STABLE VM)
# =========================================================
class CPU:
    ZERO_REG = 0
    SP_REG = 13
    FP_REG = 14
    LR_REG = 15
    MEM_SIZE = 1024 * 1024

    def __init__(self):

        # 32 general-purpose registers
        self.reg = [0] * 32

        self.pc = 0
        self.sp = 0xF000
        self.fp = 0xF000
        self.reg[self.SP_REG] = self.sp
        self.reg[self.FP_REG] = self.fp

        self.Z = 0
        self.N = 0

        self.running = True

        # byte-addressable memory
        self.mem = bytearray(self.MEM_SIZE)

    # -----------------------------------------------------
    # SAFE REGISTER ACCESS
    # -----------------------------------------------------
    def r(self, i):
        idx = i & 0x1F
        if idx == self.ZERO_REG:
            return 0
        return self.reg[idx]

    def setr(self, i, v):
        idx = i & 0x1F
        if idx == self.ZERO_REG:
            return
        self.reg[idx] = v & 0xFFFFFFFF
        if idx == self.SP_REG:
            self.sp = self.reg[idx]
        elif idx == self.FP_REG:
            self.fp = self.reg[idx]

    def get_sp(self):
        return self.r(self.SP_REG)

    def set_sp(self, v):
        self.setr(self.SP_REG, v)
        self.sp = self.r(self.SP_REG)

    def imm16(self, hi, lo):
        return ((hi & 0xFF) << 8) | (lo & 0xFF)

    def alu_rhs(self, c):
        if c & 0x80:
            return c & 0x7F
        return self.r(c)

    def reg_name(self, i):
        idx = i & 0x1F
        if idx == self.ZERO_REG:
            return "ZERO"
        if idx == self.SP_REG:
            return "SP"
        if idx == self.FP_REG:
            return "FP"
        if idx == self.LR_REG:
            return "LR"
        return f"R{idx}"

    def disasm(self, op, a, b, c):
        target = (a << 8) | b
        op_name = {
            0x01: "MOV",
            0x02: "ADD",
            0x03: "SUB",
            0x04: "CMP",
            0x05: "B",
            0x06: "BEQ",
            0x07: "BNE",
            0x10: "PUSH",
            0x11: "POP",
            0x20: "LDB",
            0x21: "LDH",
            0x22: "LDW",
            0x23: "STB",
            0x24: "STH",
            0x25: "STW",
            0x30: "BL",
            0x31: "RET",
            0x40: "SVC",
            0xFF: "HLT",
        }.get(op)

        if op == 0x01:
            if a & 0x80:
                return f"MOV {self.reg_name(a)}, {self.reg_name(b)}"
            return f"MOV {self.reg_name(a)}, 0x{self.imm16(b, c):04X}"
        if op in (0x02, 0x03):
            rhs = f"#{c & 0x7F}" if c & 0x80 else self.reg_name(c)
            return f"{op_name} {self.reg_name(a)}, {self.reg_name(b)}, {rhs}"
        if op == 0x04:
            return f"CMP {self.reg_name(a)}, {self.reg_name(b)}"
        if op in (0x05, 0x06, 0x07, 0x30):
            return f"{op_name} {target}"
        if op == 0x10:
            return f"PUSH {self.reg_name(a)}"
        if op == 0x11:
            return f"POP {self.reg_name(a)}"
        if op in (0x20, 0x21, 0x22, 0x23, 0x24, 0x25):
            offset = self.reg_name(c) if c & 0x80 else f"#{c}"
            return f"{op_name} {self.reg_name(a)}, [{self.reg_name(b)} + {offset}]"
        if op == 0x31:
            return "RET"
        if op == 0x40:
            return f"SVC {a}"
        if op == 0xFF:
            return "HLT"
        return f"UNKNOWN 0x{op:02X}"

    def trace_changes(self, before_reg, before_sp, before_pc, before_z, before_n, before_running, mem_write):
        changes = []

        for i, (old, new) in enumerate(zip(before_reg, self.reg)):
            if old != new:
                changes.append(f"{self.reg_name(i)}:0x{old:08X}->0x{new:08X}")

        if before_sp != self.sp and before_reg[self.SP_REG] == self.reg[self.SP_REG]:
            changes.append(f"SP:0x{before_sp:08X}->0x{self.sp:08X}")

        if before_pc != self.pc:
            changes.append(f"PC:0x{before_pc:04X}->0x{self.pc:04X}")

        if before_z != self.Z:
            changes.append(f"Z:{int(before_z)}->{int(self.Z)}")

        if before_n != self.N:
            changes.append(f"N:{int(before_n)}->{int(self.N)}")

        if before_running != self.running:
            changes.append(f"RUN:{int(before_running)}->{int(self.running)}")

        if mem_write is not None:
            addr, value, size = mem_write
            width = size * 2
            changes.append(f"MEM{size * 8}[0x{addr:08X}]=0x{value:0{width}X}")

        if not changes:
            return "no change"
        return " | ".join(changes)

    # -----------------------------------------------------
    # MEMORY SAFETY
    # -----------------------------------------------------
    def check_mem(self, addr, size):
        if addr < 0 or addr + size > len(self.mem):
            raise Exception(f"MEM OOB addr=0x{addr:08X} size={size}")

    def mem_read_u8(self, addr):
        self.check_mem(addr, 1)
        return self.mem[addr]

    def mem_read_u16(self, addr):
        self.check_mem(addr, 2)
        return int.from_bytes(self.mem[addr:addr + 2], "little")

    def mem_read_u32(self, addr):
        self.check_mem(addr, 4)
        return int.from_bytes(self.mem[addr:addr + 4], "little")

    def mem_write_u8(self, addr, val):
        self.check_mem(addr, 1)
        self.mem[addr] = val & 0xFF

    def mem_write_u16(self, addr, val):
        self.check_mem(addr, 2)
        self.mem[addr:addr + 2] = (val & 0xFFFF).to_bytes(2, "little")

    def mem_write_u32(self, addr, val):
        self.check_mem(addr, 4)
        self.mem[addr:addr + 4] = (val & 0xFFFFFFFF).to_bytes(4, "little")

    def hexdump(self, addr, size, width=16):
        self.check_mem(addr, size)
        for row in range(addr, addr + size, width):
            chunk = self.mem[row:min(row + width, addr + size)]
            hex_part = " ".join(f"{b:02X}" for b in chunk)
            hex_part = hex_part.ljust(width * 3 - 1)
            ascii_part = "".join(chr(b) if 32 <= b <= 126 else "." for b in chunk)
            print(f"{row:08X}  {hex_part}  |{ascii_part}|")

    # -----------------------------------------------------
    # STACK
    # -----------------------------------------------------
    def push(self, v):
        self.set_sp(self.get_sp() - 4)
        self.mem_write_u32(self.get_sp(), v)

    def pop(self):
        v = self.mem_read_u32(self.get_sp())
        self.set_sp(self.get_sp() + 4)
        return v

    # -----------------------------------------------------
    # LOAD IMAGE
    # -----------------------------------------------------
    def load_image(self, file):
        with open(file, "rb") as f:
            data = f.read()

        self.check_mem(0, len(data))
        self.mem[0:len(data)] = data

    # -----------------------------------------------------
    # FETCH
    # -----------------------------------------------------
    def fetch(self):
        instr = self.mem_read_u32(self.pc)
        self.pc += 4
        return instr

    # -----------------------------------------------------
    # RUN LOOP
    # -----------------------------------------------------
    def run(self, start=0, trace=False):
        self.pc = start
        self.running = True

        steps = 0
        MAX_STEPS = 1_000_000

        while self.running:

            steps += 1
            if steps > MAX_STEPS:
                print("[CPU] MAX STEPS REACHED -> STOP")
                break

            instr_pc = self.pc
            instr = self.fetch()

            op = (instr >> 24) & 0xFF
            a  = (instr >> 16) & 0xFF
            b  = (instr >> 8) & 0xFF
            c  = instr & 0xFF
            pc_before_exec = self.pc
            before_reg = self.reg[:]
            before_sp = self.sp
            before_z = self.Z
            before_n = self.N
            before_running = self.running
            mem_write = None
            syscall_message = None

            # =================================================
            # MOV
            # =================================================
            if op == 0x01:
                if a & 0x80:
                    self.setr(a, self.r(b))
                else:
                    self.setr(a, self.imm16(b, c))

            # =================================================
            # ADD / SUB
            # =================================================
            elif op == 0x02:
                self.setr(a, self.r(b) + self.alu_rhs(c))

            elif op == 0x03:
                self.setr(a, self.r(b) - self.alu_rhs(c))

            # =================================================
            # CMP
            # =================================================
            elif op == 0x04:
                r = self.r(a) - self.r(b)
                self.Z = (r == 0)
                self.N = (r < 0)

            # =================================================
            # BRANCH
            # =================================================
            elif op == 0x05:
                self.pc = (a << 8) | b

            elif op == 0x06:
                if self.Z:
                    self.pc = (a << 8) | b

            elif op == 0x07:
                if not self.Z:
                    self.pc = (a << 8) | b

            # =================================================
            # STACK
            # =================================================
            elif op == 0x10:
                self.push(self.r(a))

            elif op == 0x11:
                self.setr(a, self.pop())

            # =================================================
            # MEMORY
            # =================================================
            elif op in (0x20, 0x21, 0x22):  # LDB/LDH/LDW
                rd = a
                base = b

                offset = self.r(c & 0x1F) if (c & 0x80) else c
                addr = self.r(base) + offset

                if op == 0x20:
                    self.setr(rd, self.mem_read_u8(addr))
                elif op == 0x21:
                    self.setr(rd, self.mem_read_u16(addr))
                else:
                    self.setr(rd, self.mem_read_u32(addr))

            elif op in (0x23, 0x24, 0x25):  # STB/STH/STW
                rs = a
                base = b

                offset = self.r(c & 0x1F) if (c & 0x80) else c
                addr = self.r(base) + offset

                if op == 0x23:
                    self.mem_write_u8(addr, self.r(rs))
                    mem_write = (addr, self.r(rs) & 0xFF, 1)
                elif op == 0x24:
                    self.mem_write_u16(addr, self.r(rs))
                    mem_write = (addr, self.r(rs) & 0xFFFF, 2)
                else:
                    self.mem_write_u32(addr, self.r(rs))
                    mem_write = (addr, self.r(rs), 4)

            # =================================================
            # CALL / RET (FIXED STACK ABI)
            # =================================================
            elif op == 0x30:
                addr = (a << 8) | b

                self.setr(self.LR_REG, self.pc)
                self.pc = addr

            elif op == 0x31:
                self.pc = self.r(self.LR_REG)

            # =================================================
            # SYSCALL
            # =================================================
            elif op == 0x40:
                if a == 1:
                    syscall_message = "[SYSCALL] EXIT"
                    self.running = False

            # =================================================
            # HALT
            # =================================================
            elif op == 0xFF:
                self.running = False

            else:
                raise Exception(f"Unknown opcode {op}")

            if trace:
                print(
                    f"PC={instr_pc:08X}  {self.disasm(op, a, b, c):24} "
                    f"; {self.trace_changes(before_reg, before_sp, pc_before_exec, before_z, before_n, before_running, mem_write)} "
                    f"; OP=0x{op:02X} RAW=0x{instr:08X}"
                )
            if syscall_message:
                print(syscall_message)

        print("[CPU HALTED]")


# =========================================================
# MAIN
# =========================================================
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--trace", action="store_true", help="print each instruction")
    parser.add_argument("--dump", nargs=2, metavar=("ADDR", "SIZE"), help="dump memory after execution")
    args = parser.parse_args()

    print("=== KR32 BOOT ===")

    cpu = CPU()

    cpu.load_image("memory.img")

    print("[BOOT] Image loaded")
    print("[BOOT] Reset CPU state")
    print("[BOOT] Starting execution")

    cpu.run(0, trace=args.trace)

    if args.dump:
        addr = int(args.dump[0], 0)
        size = int(args.dump[1], 0)
        print(f"[MEM DUMP] addr=0x{addr:08X} size={size}")
        cpu.hexdump(addr, size)

    print("[BOOT] Done")


if __name__ == "__main__":
    main()
