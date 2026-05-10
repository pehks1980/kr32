import struct
import argparse


# =========================================================
# KR32-RISC CPU (FINAL STABLE VM)
# =========================================================
class CPU:
    SP_REG = 13
    FP_REG = 14

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

        # memory
        self.mem = [0] * 65536

        # program image
        self.program = {}

    # -----------------------------------------------------
    # SAFE REGISTER ACCESS
    # -----------------------------------------------------
    def r(self, i):
        return self.reg[i & 0x1F]

    def setr(self, i, v):
        idx = i & 0x1F
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
            0x20: "LDR",
            0x21: "STR",
            0x30: "BL",
            0x31: "RET",
            0x40: "SVC",
            0xFF: "HLT",
        }.get(op)

        if op == 0x01:
            if a & 0x80:
                return f"MOV R{a & 0x1F}, R{b}"
            return f"MOV R{a}, 0x{self.imm16(b, c):04X}"
        if op in (0x02, 0x03):
            rhs = f"#{c & 0x7F}" if c & 0x80 else f"R{c}"
            return f"{op_name} R{a}, R{b}, {rhs}"
        if op == 0x04:
            return f"CMP R{a}, R{b}"
        if op in (0x05, 0x06, 0x07, 0x30):
            return f"{op_name} {target}"
        if op == 0x10:
            return f"PUSH R{a}"
        if op == 0x11:
            return f"POP R{a}"
        if op in (0x20, 0x21):
            offset = f"R{c & 0x1F}" if c & 0x80 else f"#{c}"
            return f"{op_name} R{a}, [R{b} + {offset}]"
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
                changes.append(f"R{i}:0x{old:08X}->0x{new:08X}")

        if before_sp != self.sp:
            changes.append(f"SP:0x{before_sp:04X}->0x{self.sp:04X}")

        if before_pc != self.pc:
            changes.append(f"PC:0x{before_pc:04X}->0x{self.pc:04X}")

        if before_z != self.Z:
            changes.append(f"Z:{int(before_z)}->{int(self.Z)}")

        if before_n != self.N:
            changes.append(f"N:{int(before_n)}->{int(self.N)}")

        if before_running != self.running:
            changes.append(f"RUN:{int(before_running)}->{int(self.running)}")

        if mem_write is not None:
            addr, value = mem_write
            changes.append(f"MEM[0x{addr:04X}]=0x{value:08X}")

        if not changes:
            return "no change"
        return " | ".join(changes)

    # -----------------------------------------------------
    # MEMORY SAFETY
    # -----------------------------------------------------
    def mem_read(self, addr):
        if addr < 0 or addr >= len(self.mem):
            raise Exception(f"MEM READ OOB {addr}")
        return self.mem[addr]

    def mem_write(self, addr, val):
        if addr < 0 or addr >= len(self.mem):
            raise Exception(f"MEM WRITE OOB {addr}")
        self.mem[addr] = val

    # -----------------------------------------------------
    # STACK
    # -----------------------------------------------------
    def push(self, v):
        self.set_sp(self.get_sp() - 1)
        self.mem_write(self.get_sp(), v)

    def pop(self):
        v = self.mem_read(self.get_sp())
        self.set_sp(self.get_sp() + 1)
        return v

    # -----------------------------------------------------
    # LOAD IMAGE
    # -----------------------------------------------------
    def load_image(self, file):
        with open(file, "rb") as f:
            data = f.read()

        for i, (w,) in enumerate(struct.iter_unpack("<I", data)):
            self.program[i] = w

    # -----------------------------------------------------
    # FETCH
    # -----------------------------------------------------
    def fetch(self):
        instr = self.program.get(self.pc)
        if instr is None:
            raise Exception(f"PC out of range: {self.pc}")
        self.pc += 1
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
            elif op == 0x20:  # LDR
                rd = a
                base = b

                offset = self.r(c & 0x1F) if (c & 0x80) else c
                addr = self.r(base) + offset

                self.setr(rd, self.mem_read(addr))

            elif op == 0x21:  # STR
                rs = a
                base = b

                offset = self.r(c & 0x1F) if (c & 0x80) else c
                addr = self.r(base) + offset

                self.mem_write(addr, self.r(rs))
                mem_write = (addr, self.r(rs))

            # =================================================
            # CALL / RET (FIXED STACK ABI)
            # =================================================
            elif op == 0x30:
                addr = (a << 8) | b

                self.push(self.pc)
                self.pc = addr

            elif op == 0x31:
                self.pc = self.pop()

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
                    f"PC={pc_before_exec - 1:04X}  {self.disasm(op, a, b, c):24} "
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
    args = parser.parse_args()

    print("=== KR32 BOOT ===")

    cpu = CPU()

    cpu.load_image("memory.img")

    print("[BOOT] Image loaded")
    print("[BOOT] Reset CPU state")
    print("[BOOT] Starting execution")

    cpu.run(0, trace=args.trace)

    print("[BOOT] Done")


if __name__ == "__main__":
    main()
