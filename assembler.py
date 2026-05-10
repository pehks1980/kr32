import struct

# =========================================================
# KR32-RISC OPCODES
# =========================================================
OP = {
    "MOV":  0x01,
    "ADD":  0x02,
    "SUB":  0x03,
    "CMP":  0x04,

    "B":    0x05,
    "BEQ":  0x06,
    "BNE":  0x07,

    "PUSH": 0x10,
    "POP":  0x11,

    "LDR":  0x20,
    "STR":  0x21,

    "BL":   0x30,
    "RET":  0x31,

    "SVC":  0x40,
    "HLT":  0xFF,
}


# =========================================================
# HELPERS
# =========================================================
def reg(x: str) -> int:
    """Convert Rn to int."""
    if isinstance(x, int):
        return x
    if not x.startswith("R"):
        raise ValueError(f"Expected register, got {x}")
    n = int(x[1:])
    if n < 0 or n > 31:
        raise ValueError(f"Register out of range: {x}")
    return n


def is_number(x: str) -> bool:
    try:
        int(x, 0)
        return True
    except ValueError:
        return False


# =========================================================
# ASSEMBLER
# =========================================================
class Assembler:
    def __init__(self):
        self.labels = {}
        self.lines = []
        self.out = []

    # -----------------------------------------------------
    # encode helper (32-bit instruction)
    # -----------------------------------------------------
    def encode(self, op, a=0, b=0, c=0):
        return (op << 24) | (a << 16) | (b << 8) | c

    def strip_comment(self, line):
        return line.split(";", 1)[0].strip()

    # -----------------------------------------------------
    # PASS 1: labels
    # -----------------------------------------------------
    def pass1(self, src):
        pc = 0

        for line in src:
            line = self.strip_comment(line)

            if not line or line.startswith(";"):
                continue

            if line.endswith(":"):
                self.labels[line[:-1]] = pc
            else:
                self.lines.append(line)
                pc += 1

    # -----------------------------------------------------
    # resolve operand
    # -----------------------------------------------------
    def resolve(self, x):
        if is_number(x):
            return int(x, 0)
        if x not in self.labels:
            raise KeyError(f"Unknown label: {x}")
        return self.labels[x]

    # -----------------------------------------------------
    # PASS 2: encode
    # -----------------------------------------------------
    def pass2(self):
        for line in self.lines:
            p = line.replace(",", "").split()
            op = p[0]

            # =================================================
            # MOV Rn IMM16
            # MOV Rn Rm
            # =================================================
            if op == "MOV":
                rd = reg(p[1])
                src = p[2]

                if src.startswith("R"):
                    self.out.append(self.encode(OP[op], 0x80 | rd, reg(src), 0))
                else:
                    imm = self.resolve(src) & 0xFFFF
                    self.out.append(
                        self.encode(OP[op], rd, (imm >> 8) & 0xFF, imm & 0xFF)
                    )

            # =================================================
            # ADD/SUB Rn Ra Rb
            # ADD/SUB Rn Ra IMM7
            # =================================================
            elif op in ("ADD", "SUB"):
                rd = reg(p[1])
                rs1 = reg(p[2])
                src2 = p[3]

                if src2.startswith("R"):
                    self.out.append(self.encode(OP[op], rd, rs1, reg(src2)))
                else:
                    imm = self.resolve(src2)
                    if imm < 0 or imm > 0x7F:
                        raise ValueError(f"{op} immediate out of range (0..127): {imm}")
                    self.out.append(self.encode(OP[op], rd, rs1, 0x80 | imm))

            # =================================================
            # CMP Ra Rb   (ONLY 2 operands)
            # =================================================
            elif op == "CMP":
                rs1 = reg(p[1])
                rs2 = reg(p[2])
                self.out.append(self.encode(OP[op], rs1, rs2, 0))

            # =================================================
            # BRANCHES (label)
            # =================================================
            elif op in ("B", "BEQ", "BNE", "BL"):
                target = self.resolve(p[1])
                self.out.append(
                    self.encode(
                        OP[op],
                        (target >> 8) & 0xFF,
                        target & 0xFF,
                        0
                    )
                )

            # =================================================
            # PUSH/POP Rn
            # =================================================
            elif op == "PUSH":
                self.out.append(self.encode(OP[op], reg(p[1])))

            elif op == "POP":
                self.out.append(self.encode(OP[op], reg(p[1])))

            # =================================================
            # MEMORY
            # LDR Rn Rbase offset
            # STR Rn Rbase offset
            # =================================================
            # =================================================
            # MEMORY (RISC addressing modes)
            # LDR Rn Rbase IMM
            # LDR Rn Rbase Roffset
            # STR Rn Rbase IMM
            # STR Rn Rbase Roffset
            # =================================================

            elif op == "LDR":
                rd = reg(p[1])
                base = reg(p[2])
                off = p[3]

                if off.startswith("R"):
                    off_reg = reg(off)
                    self.out.append(self.encode(OP[op], rd, base, 0x80 | off_reg))
                else:
                    self.out.append(self.encode(OP[op], rd, base, int(off) & 0x7F))


            elif op == "STR":
                rs = reg(p[1])
                base = reg(p[2])
                off = p[3]

                if off.startswith("R"):
                    off_reg = reg(off)
                    self.out.append(self.encode(OP[op], rs, base, 0x80 | off_reg))
                else:
                    self.out.append(self.encode(OP[op], rs, base, int(off) & 0x7F))

            # =================================================
            # SYSTEM
            # =================================================
            elif op == "RET":
                self.out.append(self.encode(OP[op]))

            elif op == "SVC":
                self.out.append(self.encode(OP[op], int(p[1])))

            elif op == "HLT":
                self.out.append(self.encode(OP[op]))

            else:
                raise Exception(f"[ASM] Unknown instruction: {line}")

    # -----------------------------------------------------
    # BUILD IMAGE
    # -----------------------------------------------------
    def build(self, src, out="memory.img"):
        self.labels = {}
        self.lines = []
        self.out = []

        self.pass1(src)
        self.pass2()

        with open(out, "wb") as f:
            for w in self.out:
                f.write(struct.pack("<I", w))

        print(f"[ASM] Built {out} ({len(self.out)} instructions)")
