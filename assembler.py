import argparse
import ast
import struct
import sys

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
    "GETCAUSE": 0x57,
    "CSRR": 0x58,
    "CSRW": 0x59,
    "CSRS": 0x5A,
    "CSRC": 0x5B,
    "SRET": 0x5C,
    "CSRRW": 0x5D,
    "EOI": 0x5E,
    "TRACE": 0x5F,
}

REG_ALIAS = {
    "ZERO": 0,
    "SP": 13,
    "FP": 14,
    "LR": 15,
}

CSR_ALIAS = {
    "SSTATUS": 0x00,
    "STVEC": 0x01,
    "SEPC": 0x02,
    "SCAUSE": 0x03,
    "STVAL": 0x04,
    "SSCRATCH": 0x05,
    "SFLAGS": 0x06,
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


def csr(x: str) -> int:
    x = x.upper()
    if x in CSR_ALIAS:
        return CSR_ALIAS[x]
    if x.startswith("CSR") and x[3:].isdigit():
        n = int(x[3:])
    else:
        n = int(x, 0)
    if n < 0 or n > 0xFF:
        raise ValueError(f"CSR out of range: {x}")
    return n


# =========================================================
# ASSEMBLER
# =========================================================
class AssemblerError(Exception):
    def __init__(self, phase, message, lineno=None, addr=None, source=None):
        super().__init__(message)
        self.phase = phase
        self.message = message
        self.lineno = lineno
        self.addr = addr
        self.source = source

    def __str__(self):
        parts = [f"[ASM] {self.phase} error"]
        if self.lineno is not None:
            parts.append(f"line {self.lineno}")
        if self.addr is not None:
            parts.append(f"addr 0x{self.addr:08X}")

        header = ": ".join((" ".join(parts), self.message))
        if self.source:
            return f"{header}\n    {self.source}"
        return header


class Assembler:
    def __init__(self):
        self.labels = {}
        self.lines = []
        self.listing = []
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
        if not tokens:
            return 0
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

        self.listing = []
        for lineno, raw_line in enumerate(src, 1):
            source = raw_line.rstrip("\n")
            line = self.strip_comment(raw_line).upper()

            if not line:
                self.listing.append({"type": "comment", "source": source})
                continue

            try:
                tokens = self.tokenize(line)
                addr = self.pc

                # label
                if line.endswith(":"):
                    label = line[:-1]

                    if label.startswith("."):
                        label = self.current_global + label
                    else:
                        self.current_global = label

                    if label in self.labels:
                        raise ValueError(f"duplicate label: {label}")
                    self.labels[label] = self.pc
                    self.listing.append({"type": "label", "source": source, "addr": addr})
                    continue

                entry = {
                    "text": line,
                    "source": source,
                    "lineno": lineno,
                    "addr": addr,
                }

                # directives
                if tokens[0] == ".ORG":
                    if len(tokens) != 2:
                        raise ValueError(".ORG expects exactly one address")
                    self.lines.append(entry)
                    self.listing.append({"type": "directive", **entry})
                    self.pc = int(tokens[1], 0)
                    continue

                elif tokens[0] == ".WORD":
                    if len(tokens) < 2:
                        raise ValueError(".WORD expects at least one value")
                    self.lines.append(entry)
                    self.listing.append({"type": "directive", **entry})
                    count = len(tokens) - 1
                    self.pc += count * 4
                    continue

                elif tokens[0] == ".SPACE":
                    if len(tokens) < 2:
                        raise ValueError(".SPACE expects a size")
                    self.lines.append(entry)
                    self.listing.append({"type": "directive", **entry})
                    self.pc += self.resolve_expr(" ".join(tokens[1:]))
                    continue

                elif tokens[0] == ".EQU":
                    if len(tokens) < 3:
                        raise ValueError(".EQU expects a name and value")
                    name = tokens[1]
                    value = self.resolve_expr(" ".join(tokens[2:]))
                    self.consts[name] = value
                    self.lines.append(entry)
                    self.listing.append({"type": "directive", **entry})
                    continue

                elif tokens[0] == ".ASCIIZ":
                    text = ast.literal_eval(source.split(None, 1)[1])

                    self.lines.append(entry)
                    self.listing.append({"type": "directive", **entry})

                    self.pc += len(text) + 1
                    continue

                # instruction
                self.lines.append(entry)
                self.listing.append({"type": "instruction", **entry})
                self.pc += self.instr_size(line)
            except AssemblerError:
                raise
            except Exception as exc:
                raise AssemblerError("pass1", str(exc), lineno, self.pc, source) from exc
    
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
        if expr.startswith("-"):
            return -self.resolve_expr(expr[1:])

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

        for entry in self.lines:
            start_pc = self.pc
            try:
                self.encode_line(entry)
            except AssemblerError:
                raise
            except Exception as exc:
                raise AssemblerError(
                    "pass2",
                    str(exc),
                    entry["lineno"],
                    start_pc,
                    entry["source"],
                ) from exc

    def encode_line(self, entry):
        line = entry["text"]
        p = self.tokenize(line)
        if not p:
            return
        op = normalize_op(p[0])

        if op == ".ORG":
            self.pc = int(p[1], 0)
            return

        elif op == ".WORD":
            for item in p[1:]:
                self.emit32(self.resolve_expr(item))
            return

        elif op == ".SPACE":
            size = self.resolve_expr(" ".join(p[1:]))
            for _ in range(size):
                self.emit8(0)
            return

        elif op == ".EQU":
            return

        elif op == ".ASCIIZ":
            text = ast.literal_eval(entry["source"].split(None, 1)[1])

            for ch in text:
                self.emit8(ord(ch))

            self.emit8(0)
            return

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
        elif op == "TRACE":
            # TRACE n: n=0 -> disable per-instruction trace, n=1 -> enable per-instruction trace
            val = 0
            if len(p) > 1:
                val = self.resolve_expr(p[1]) & 0xFFFFFF
            self.emit32(self.encode(OP[op], (val >> 16) & 0xFF, (val >> 8) & 0xFF, val & 0xFF))

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
            imm = self.resolve_expr(p[1])
            if imm < 0 or imm > 0xFF:
                raise ValueError(f"SVC immediate out of range (0..255): {imm}")
            self.emit32(self.encode(OP[op], imm))

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

        elif op == "CSRR":
            self.emit32(self.encode(OP[op], reg(p[1]), csr(p[2]), 0))

        elif op in ("CSRW", "CSRS", "CSRC"):
            self.emit32(self.encode(OP[op], reg(p[2]), csr(p[1]), 0))

        elif op == "SRET":
            self.emit32(self.encode(OP[op]))

        elif op == "CSRRW":
            self.emit32(self.encode(OP[op], reg(p[1]), csr(p[2]), reg(p[3])))

        elif op == "EOI":
            self.emit32(self.encode(OP[op], reg(p[1])))

        else:
            raise Exception(f"unknown instruction: {line}")

    # -----------------------------------------------------
    # BUILD IMAGE
    # -----------------------------------------------------
    def print_listing(self):
        for entry in self.listing:
            if entry["type"] == "label":
                print(entry["source"])
            elif entry["type"] == "comment":
                print(entry["source"])
            elif entry["type"] == "instruction":
                addr = entry["addr"]
                print(f"0x{addr:08X}   {entry['source']}")
            else:
                print(entry["source"])

    def build(self, src, out="memory.img", list_listing=False, write_output=True):
        self.labels = {}
        self.lines = []
        self.consts = {}
        self.current_global = ""
        self.pc = 0
        self.memory = bytearray(16 * 1024 * 1024)

        try:
            self.pass1(src)
            self.pass2()
        except AssemblerError as exc:
            print(exc, file=sys.stderr)
            raise SystemExit(1)

        if write_output:
            with open(out, "wb") as f:
                f.write(self.memory[:self.pc])

        if list_listing:
            self.print_listing()

        if write_output:
            print(f"[ASM] Built {out} ({self.pc} bytes)")
        else:
            print(f"[ASM] Listing generated, binary output skipped")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="KR32 assembler")
    parser.add_argument("src", nargs="?", default="kernel.asm",
                        help="source assembly file")
    parser.add_argument("-o", "--output", default="memory.img",
                        help="output binary image file")
    parser.add_argument("--list", action="store_true",
                        help="print a physical-address assembly listing to stdout")
    parser.add_argument("--list-only", action="store_true",
                        help="print the listing without writing the binary image")
    args = parser.parse_args()

    with open(args.src, "r", encoding="utf-8") as f:
        source_lines = f.readlines()

    assembler = Assembler()
    assembler.build(
        source_lines,
        out=args.output,
        list_listing=args.list or args.list_only,
        write_output=not args.list_only,
    )
