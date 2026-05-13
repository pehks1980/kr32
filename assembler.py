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
    "MUL":  0x08,
    "AND":  0x09,
    "OR":   0x0A,
    "XOR":  0x0B,
    "SHL":  0x0C,
    "SHR":  0x0D,
    "SAR":  0x0E,
    "LI":   0x0F,

    "PUSH": 0x10,
    "POP":  0x11,
    "BLT":  0x12,
    "BLE":  0x13,
    "BGT":  0x14,
    "BGE":  0x15,
    "DIV":  0x16,
    "MOD":  0x17,
    "DIVU": 0x18,
    "MODU": 0x19,
    "BLTU": 0x1A,
    "BLEU": 0x1B,
    "BGTU": 0x1C,
    "BGEU": 0x1D,

    "LDB":  0x20,
    "LDH":  0x21,
    "LDW":  0x22,
    "STB":  0x23,
    "STH":  0x24,
    "STW":  0x25,
    "LDBS": 0x26,
    "LDHS": 0x27,

    "BL":   0x30,
    "RET":  0x31,

    "SVC":  0x40,
    "HLT":  0xFF,

    "SETPTBR": 0x50,
    "ENABLEMMU": 0x51,
}

REG_ALIAS = {
    "ZERO": 0,
    "SP": 13,
    "FP": 14,
    "LR": 15,
}


# =========================================================
# HELPERS
# =========================================================
def reg(x: str) -> int:
    """Convert Rn to int."""
    if isinstance(x, int):
        return x
    x = x.upper()
    if x in REG_ALIAS:
        return REG_ALIAS[x]
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


def is_reg_token(x: str) -> bool:
    x = x.upper()
    return x in REG_ALIAS or (x.startswith("R") and x[1:].isdigit())


def normalize_op(op: str) -> str:
    op = op.upper()
    aliases = {
        "LDR": "LDW",
        "STR": "STW",
        "ADDI": "ADD",
        "SUBI": "SUB",
        "ANDI": "AND",
        "ORI": "OR",
        "XORI": "XOR",
        "SHLI": "SHL",
        "SHRI": "SHR",
        "SARI": "SAR",
    }
    return aliases.get(op, op)


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

    def tokenize(self, line):
        return (
            line.replace(",", " ")
            .replace("[", " ")
            .replace("]", " ")
            .replace("+", " ")
            .split()
        )

    def instr_size(self, line):
        op = normalize_op(self.tokenize(line)[0])
        if op == "LI" or op in (
            "B", "BEQ", "BNE",
            "BLT", "BLE", "BGT", "BGE",
            "BLTU", "BLEU", "BGTU", "BGEU",
            "BL",
        ):
            return 8
        return 4

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
                pc += self.instr_size(line)

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
            p = self.tokenize(line)
            op = normalize_op(p[0])

            # =================================================
            # MOV Rn IMM16
            # MOV Rn Rm
            # =================================================
            if op == "MOV":
                rd = reg(p[1])
                src = p[2]

                if is_reg_token(src):
                    self.out.append(self.encode(OP[op], 0x80 | rd, reg(src), 0))
                else:
                    imm = self.resolve(src) & 0xFFFF
                    self.out.append(
                        self.encode(OP[op], rd, (imm >> 8) & 0xFF, imm & 0xFF)
                    )

            elif op == "LI":
                rd = reg(p[1])
                imm = self.resolve(p[2]) & 0xFFFFFFFF
                self.out.append(self.encode(OP[op], rd, 0, 0))
                self.out.append(imm)

            # =================================================
            # ALU Rn Ra Rb
            # ALU Rn Ra IMM7
            # =================================================
            elif op in ("ADD", "SUB", "AND", "OR", "XOR", "SHL", "SHR", "SAR"):
                rd = reg(p[1])
                rs1 = reg(p[2])
                src2 = p[3]

                if is_reg_token(src2):
                    self.out.append(self.encode(OP[op], rd, rs1, reg(src2)))
                else:
                    imm = self.resolve(src2)
                    if imm < 0 or imm > 0x7F:
                        raise ValueError(f"{op} immediate out of range (0..127): {imm}")
                    self.out.append(self.encode(OP[op], rd, rs1, 0x80 | imm))

            elif op in ("MUL", "DIV", "MOD", "DIVU", "MODU"):
                rd = reg(p[1])
                rs1 = reg(p[2])
                rs2 = reg(p[3])
                self.out.append(self.encode(OP[op], rd, rs1, rs2))

            # =================================================
            # CMP Ra Rb   (ONLY 2 operands)
            # =================================================
            elif op == "CMP":
                rs1 = reg(p[1])
                rhs = p[2]
                if is_reg_token(rhs):
                    self.out.append(self.encode(OP[op], rs1, reg(rhs), 0))
                else:
                    imm = self.resolve(rhs)
                    if imm < 0 or imm > 0x7F:
                        raise ValueError(f"{op} immediate out of range (0..127): {imm}")
                    self.out.append(self.encode(OP[op], rs1, 0, 0x80 | imm))

            # =================================================
            # BRANCHES (label)
            # =================================================
            elif op in (
                "B", "BEQ", "BNE",
                "BLT", "BLE", "BGT", "BGE",
                "BLTU", "BLEU", "BGTU", "BGEU",
                "BL",
            ):
                target = self.resolve(p[1]) & 0xFFFFFFFF
                self.out.append(self.encode(OP[op]))
                self.out.append(target)

            # =================================================
            # PUSH/POP Rn
            # =================================================
            elif op == "PUSH":
                self.out.append(self.encode(OP[op], reg(p[1])))

            elif op == "POP":
                self.out.append(self.encode(OP[op], reg(p[1])))

            # =================================================
            # MEMORY (byte-addressed)
            # LDB/LDH/LDW Rn Rbase offset
            # STB/STH/STW Rn Rbase offset
            # Also accepts bracket syntax: LDW Rn [Rbase + offset]
            # =================================================
            elif op in ("LDB", "LDH", "LDW", "LDBS", "LDHS"):
                rd = reg(p[1])
                base = reg(p[2])
                off = p[3] if len(p) > 3 else "0"

                if is_reg_token(off):
                    off_reg = reg(off)
                    self.out.append(self.encode(OP[op], rd, base, 0x80 | off_reg))
                else:
                    imm = self.resolve(off)
                    if imm < 0 or imm > 0x7F:
                        raise ValueError(f"{op} offset out of range (0..127): {imm}")
                    self.out.append(self.encode(OP[op], rd, base, imm))


            elif op in ("STB", "STH", "STW"):
                rs = reg(p[1])
                base = reg(p[2])
                off = p[3] if len(p) > 3 else "0"

                if is_reg_token(off):
                    off_reg = reg(off)
                    self.out.append(self.encode(OP[op], rs, base, 0x80 | off_reg))
                else:
                    imm = self.resolve(off)
                    if imm < 0 or imm > 0x7F:
                        raise ValueError(f"{op} offset out of range (0..127): {imm}")
                    self.out.append(self.encode(OP[op], rs, base, imm))

            # =================================================
            # MMU CONTROL
            # =================================================
            elif op == "SETPTBR":
                self.out.append(self.encode(OP[op], reg(p[1])))

            elif op == "ENABLEMMU":
                self.out.append(self.encode(OP[op]))

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
