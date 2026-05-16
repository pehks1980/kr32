import struct

# =========================================================
# KR32-RISC OPCODES
# =========================================================
OP = {
    "NOP":  0x00,
    "MOV":  0x01,
    "ADD":  0x02,
    "SUB":  0x03,
    "CMP":  0x04,

    "B":    0x05, #Branch (unconditional)
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
    "BLT":  0x12, #branch if less than (signed)
    "BLE":  0x13,
    "BGT":  0x14,
    "BGE":  0x15,
    "DIV":  0x16,
    "MOD":  0x17,
    "DIVU": 0x18,
    "MODU": 0x19,
    "BLTU": 0x1A, #branch if less than (unsigned)
    "BLEU": 0x1B,
    "BGTU": 0x1C,
    "BGEU": 0x1D,

    "LDB":  0x20, #load byte
    "LDH":  0x21, #load halfword 16-bit unsigned
    "LDW":  0x22, 
    "STB":  0x23, #
    "STH":  0x24,
    "STW":  0x25,
    "LDBS": 0x26, #load byte signed
    "LDHS": 0x27,

    "BL":   0x30,   # branch link lr
    "RET":  0x31,   # return from subroutine pc from lr 
    
    "JR":   0x32,   # jump register
    "JALR": 0x33,   # jump and link register

    "SVC":  0x40,   # supervisor call (system call)
    "HLT":  0xFF,

    "SETPTBR": 0x50, # set page table base register for MMU
    "SETIDTR": 0x51, # set interrupt descriptor table base register for interrupt handling
    "ENABLEMMU": 0x52, # enable MMU with current page table
    "ENABLEINT": 0x53, # enable interrupts
    "DISABLEINT": 0x54, #  disable interrupts   
    "IRET": 0x55,   # return from interrupt (restore PC and flags)
    "DEBUG": 0x56,  
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
        #self.out = []
        self.pc = 0
        #self.memory = {}
        self.memory = bytearray(16 * 1024 * 1024)  # 16MB
        
        # constants for assembler (e.g. string literals)
        self.consts = {} 
        self.current_global = ""

    def emit8(self, v):
        self.memory[self.pc] = v & 0xFF
        self.pc += 1

    def emit16(self, v):
        self.emit8(v)
        self.emit8(v >> 8)

    def emit32(self, v):
        self.emit8(v)
        self.emit8(v >> 8)
        self.emit8(v >> 16)
        self.emit8(v >> 24)

    # -----------------------------------------------------
    # encode helper (32-bit instruction)
    # -----------------------------------------------------
    def encode(self, op, a=0, b=0, c=0):
        return (op << 24) | (a << 16) | (b << 8) | c

    def strip_comment(self, line):
        return line.split(";", 1)[0].strip()

    
    def tokenize(self, line):
        line = line.replace(",", " ").upper()

        out = []
        cur = ""
        bracket = 0

        for ch in line:
            if ch == "[":
                bracket += 1

            if ch == "]":
                bracket -= 1

            if ch.isspace() and bracket == 0:
                if cur:
                    out.append(cur.upper())
                    cur = ""
            else:
                cur += ch

        if cur:
            out.append(cur.upper())

        return out

        #line = line.replace(",", " ").upper()
        #return line.split()

    def instr_size(self, line):
        tokens = self.tokenize(line)
        op = normalize_op(tokens[0])
        if op == "LI" or op in (
            "B", "BEQ", "BNE",
            "BLT", "BLE", "BGT", "BGE",
            "BLTU", "BLEU", "BGTU", "BGEU",
            "BL", "CALL", "CALLEX",
        ):
            return 8
        if op in ("ARG1", "ARG2", "ARG3", "ARG4"):
            return 4
        if op in ("FUNC_ENTER", "FUNC_LEAVE"):
            return 12
        if op == "RETURN":
            return 16 if len(tokens) > 1 else 12
        return 4

    # -----------------------------------------------------
    # PASS 1: labels
    # -----------------------------------------------------
    def pass1(self, src):
        self.pc = 0

        for line in src:
            line = self.strip_comment(line).upper()

            if not line:
                continue

            tokens = self.tokenize(line)

            # label
            if line.endswith(":"):
                label = line[:-1]

                if label.startswith("."):
                    label = self.current_global + label
                else:
                    self.current_global = label

                self.labels[label] = self.pc
                continue

            # directives
            if tokens[0] == ".ORG":
                self.lines.append(line)
                self.pc = int(tokens[1], 0)
                continue

            elif tokens[0] == ".WORD":
                self.lines.append(line)
                count = len(tokens) - 1
                self.pc += count * 4
                continue

            elif tokens[0] == ".SPACE":
                self.lines.append(line)
                self.pc += self.resolve_expr(" ".join(tokens[1:]))
                continue

            elif tokens[0] == ".EQU":
                name = tokens[1]
                value = self.resolve_expr(" ".join(tokens[2:]))
                self.consts[name] = value
                self.lines.append(line)
                continue

            # instruction
            self.lines.append(line)
            self.pc += self.instr_size(line)
    
    # -----------------------------------------------------
    # parse memory operand like [Rbase + offset] or [Rbase]
    # -----------------------------------------------------

    def parse_mem_operand(self, s):
        s = s.strip() # remove whitespace

        if not (s.startswith("[") and s.endswith("]")):
            raise ValueError(f"Invalid memory operand: {s}")

        s = s[1:-1] # remove brackets

        if "+" in s:
            a, b = s.split("+", 1) # split into base and offset
            return a.strip(), b.strip()

        return s.strip(), "0" # +0 if no offset

    # -----------------------------------------------------
    # resolve operand
    # -----------------------------------------------------
    
    def resolve(self, x):
        x = x.strip().upper()


        if x in self.consts:
            return self.consts[x]

        if x in self.labels:
            return self.labels[x]
        
        if is_number(x):
            return int(x, 0)

        raise KeyError(f"Unknown symbol: {x}")
    
    # -----------------------------------------------------
    # resolve expression (supports +, -, *, parentheses)
    # -----------------------------------------------------
    
    def resolve_expr(self, expr):
        expr = expr.strip().upper()

        # parentheses later

        if "*" in expr:
            a, b = expr.split("*", 1)
            return self.resolve_expr(a) * self.resolve_expr(b)

        if "+" in expr:
            parts = expr.split("+")
            total = 0

            for p in parts:
                total += self.resolve_expr(p)

            return total

        if "-" in expr:
            a, b = expr.split("-", 1)
            return self.resolve_expr(a) - self.resolve_expr(b)

        return self.resolve(expr)

    # -----------------------------------------------------
    # PASS 2: encode
    # -----------------------------------------------------
    def pass2(self):
        self.pc = 0

        for line in self.lines:
            p = self.tokenize(line)
            op = normalize_op(p[0])

            if op == ".ORG":
                self.pc = int(p[1], 0)
                continue

            elif op == ".WORD":
                for item in p[1:]:
                    self.emit32(self.resolve_expr(item))
                continue

            elif op == ".SPACE":
                size = self.resolve_expr(" ".join(p[1:]))
                for _ in range(size):
                    self.emit8(0)
                continue

            elif op == ".EQU":
                continue

            # =================================================
            # MOV Rn IMM16
            # MOV Rn Rm
            # =================================================
            elif op == "MOV":
                rd = reg(p[1])
                src = p[2]

                if is_reg_token(src):
                    self.emit32(self.encode(OP[op], 0x80 | rd, reg(src), 0))
                else:
                    imm = self.resolve_expr(src) & 0xFFFF
                    self.emit32(
                        self.encode(OP[op], rd, (imm >> 8) & 0xFF, imm & 0xFF)
                    )

            elif op == "LI":
                rd = reg(p[1])
                imm = self.resolve_expr(p[2]) & 0xFFFFFFFF
                self.emit32(self.encode(OP[op], rd, 0, 0))
                self.emit32(imm)

            # =================================================
            # ALU Rn Ra Rb
            # ALU Rn Ra IMM7
            # =================================================
            elif op in ("ADD", "SUB", "AND", "OR", "XOR", "SHL", "SHR", "SAR"):
                rd = reg(p[1])
                rs1 = reg(p[2])
                src2 = p[3]

                if is_reg_token(src2):
                    self.emit32(self.encode(OP[op], rd, rs1, reg(src2)))
                else:
                    imm = self.resolve_expr(src2)
                    if imm < 0 or imm > 0x7F:
                        raise ValueError(f"{op} immediate out of range (0..127): {imm}")
                    self.emit32(self.encode(OP[op], rd, rs1, 0x80 | imm))

            elif op in ("MUL", "DIV", "MOD", "DIVU", "MODU"):
                rd = reg(p[1])
                rs1 = reg(p[2])
                rs2 = reg(p[3])
                self.emit32(self.encode(OP[op], rd, rs1, rs2))

            # =================================================
            # CMP Ra Rb   (ONLY 2 operands)
            # =================================================
            elif op == "CMP":
                rs1 = reg(p[1])
                rhs = p[2]
                if is_reg_token(rhs):
                    self.emit32(self.encode(OP[op], rs1, reg(rhs), 0))
                else:
                    imm = self.resolve_expr(rhs)
                    if imm < 0 or imm > 0x7F:
                        raise ValueError(f"{op} immediate out of range (0..127): {imm}")
                    self.emit32(self.encode(OP[op], rs1, 0, 0x80 | imm))

            elif op == "DEBUG":
                delay = 0
                if len(p) > 1:
                    delay = self.resolve_expr(p[1]) & 0xFFFFFF
                    if delay > 0xFFFFFF:
                        raise ValueError("DEBUG delay out of range (0..0xFFFFFF)")
                self.emit32(
                    self.encode(OP[op], (delay >> 16) & 0xFF, (delay >> 8) & 0xFF, delay & 0xFF)
                )

            # =================================================
            # BRANCHES (label)
            # =================================================
            elif op in (
                "B", "BEQ", "BNE",
                "BLT", "BLE", "BGT", "BGE",
                "BLTU", "BLEU", "BGTU", "BGEU",
                "BL",
            ):
                target = self.resolve_expr(p[1]) & 0xFFFFFFFF
                self.emit32(self.encode(OP[op]))
                self.emit32(target)

            # =================================================
            # PUSH/POP Rn
            # =================================================
            elif op == "PUSH":
                self.emit32(self.encode(OP[op], reg(p[1])))

            elif op == "POP":
                self.emit32(self.encode(OP[op], reg(p[1])))

            elif op == "FUNC_ENTER":
                self.emit32(self.encode(OP["PUSH"], reg("FP")))
                self.emit32(self.encode(OP["MOV"], 0x80 | reg("FP"), reg("SP"), 0))
                self.emit32(self.encode(OP["PUSH"], reg("LR")))

            elif op == "FUNC_LEAVE":
                self.emit32(self.encode(OP["POP"], reg("LR")))
                self.emit32(self.encode(OP["POP"], reg("FP")))
                self.emit32(self.encode(OP["RET"]))

            elif op == "RETURN":
                if len(p) == 1:
                    self.emit32(self.encode(OP["POP"], reg("LR")))
                    self.emit32(self.encode(OP["POP"], reg("FP")))
                    self.emit32(self.encode(OP["RET"]))
                else:
                    self.emit32(self.encode(OP["MOV"], 0x80 | reg("R1"), reg(p[1]), 0))
                    self.emit32(self.encode(OP["POP"], reg("LR")))
                    self.emit32(self.encode(OP["POP"], reg("FP")))
                    self.emit32(self.encode(OP["RET"]))

            elif op in ("CALL", "CALLEX"):
                target = self.resolve(p[1]) & 0xFFFFFFFF
                self.emit32(self.encode(OP["BL"]))
                self.emit32(target)

            elif op in ("ARG1", "ARG2", "ARG3", "ARG4"):
                dest = {"ARG1": "R1", "ARG2": "R2", "ARG3": "R3", "ARG4": "R4"}[op]
                self.emit32(self.encode(OP["MOV"], 0x80 | reg(dest), reg(p[1]), 0))

            # =================================================
            # MEMORY (byte-addressed)
            # LDB/LDH/LDW Rn Rbase offset
            # STB/STH/STW Rn Rbase offset
            # Also accepts bracket syntax: LDW Rn [Rbase + offset]
            # =================================================
            elif op in ("LDB", "LDH", "LDW", "LDBS", "LDHS"):
                rd = reg(p[1])

                mem = p[2]
                base, off = self.parse_mem_operand(mem)

                base = reg(base)

                if is_reg_token(off):
                    off_reg = reg(off)

                    self.emit32(
                        self.encode(OP[op], rd, base, 0x80 | off_reg)
                    )

                else:
                    imm = self.resolve_expr(off)

                    if imm < 0 or imm > 0x7F:
                        raise ValueError(
                            f"{op} offset out of range (0..127): {imm}"
                        )

                    self.emit32(
                        self.encode(OP[op], rd, base, imm)
                    )


            elif op in ("STB", "STH", "STW"):
                rs = reg(p[1])

                mem = p[2]
                base, off = self.parse_mem_operand(mem)

                base = reg(base)

                if is_reg_token(off):
                    off_reg = reg(off)

                    self.emit32(
                        self.encode(OP[op], rs, base, 0x80 | off_reg)
                    )

                else:
                    imm = self.resolve_expr(off)

                    if imm < 0 or imm > 0x7F:
                        raise ValueError(
                            f"{op} offset out of range (0..127): {imm}"
                        )

                    self.emit32(
                        self.encode(OP[op], rs, base, imm)
                    )

            # =================================================
            # MMU CONTROL
            # =================================================
            elif op == "SETPTBR":
                self.emit32(self.encode(OP[op], reg(p[1])))

            elif op == "ENABLEMMU":
                self.emit32(self.encode(OP[op]))

            # =================================================
            # SYSTEM
            # =================================================
            elif op == "RET":
                self.emit32(self.encode(OP[op]))

            elif op == "SVC":
                self.emit32(self.encode(OP[op], int(p[1])))

            elif op == "JR":
                self.emit32(self.encode(OP[op], reg(p[1])))

            elif op == "JALR":
                self.emit32(self.encode(OP[op], reg(p[1])))

            # =================================================
            # TRAP / INTERRUPT CONTROL
            # =================================================
            elif op == "SETIDTR":
                self.emit32(self.encode(OP[op], reg(p[1])))

            elif op == "ENABLEINT":
                self.emit32(self.encode(OP[op]))

            elif op == "DISABLEINT":
                self.emit32(self.encode(OP[op]))

            elif op == "IRET":
                self.emit32(self.encode(OP[op]))

            elif op == "HLT":
                self.emit32(self.encode(OP[op]))

            elif op == "GETCAUSE":
                self.emit32(self.encode(OP[op], reg(p[1])))

            else:
                raise Exception(f"[ASM] Unknown instruction: {line}")

    # -----------------------------------------------------
    # BUILD IMAGE
    # -----------------------------------------------------
    def build(self, src, out="memory.img"):
        self.labels = {}
        self.lines = []

        self.pass1(src)
        self.pass2()

        with open(out, "wb") as f:
            f.write(self.memory[:self.pc])

        print(f"[ASM] Built {out} ({self.pc} bytes)")