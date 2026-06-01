#!/usr/bin/env python3
"""Simple preprocessor to expand small C-like macros to KR32 assembly.

Supported directives (minimal):
- func NAME / endfunc
- arg1/arg2/arg3/arg4
- call NAME
- return [REG|IMM]
- alloc N / free N  (splits large immediates into <=127 chunks)
- decl_local NAME, SIZE  (emits .EQU NAME OFFSET, user must alloc)
- ifz/ifnz / else / endif
- whilez/whilenz / endwhile
- #define NAME VAL  -> .EQU
- load8/store8 helpers
- small explicit kernel assembly macros, e.g. GET_TASK_PTR R5, R2

This is intentionally small and conservative. It emits plain assembly
the existing assembler can consume.
wonderfull!
"""
import sys
import re


def split_chunks(n, maxv=127):
    chunks = []
    while n > 0:
        now = min(n, maxv)
        chunks.append(now)
        n -= now
    return chunks


TASK_FIELDS = {
    "KSP": "TASK_KSP",
    "USP": "TASK_USP",
    "PC": "TASK_PC",
    "STATE": "TASK_STATE",
    "PID": "TASK_PID",
    "PTBR": "TASK_PTBR",
    "FD_TABLE": "TASK_FD_TABLE",
    "WAIT": "TASK_WAIT",
    "RESUME": "TASK_RESUME",
    "KBUF_WR": "TASK_KBUF_WR_PTR",
    "KBUF_RD": "TASK_KBUF_RD_PTR",
}


class Preprocessor:
    def __init__(self):
        self.out = []
        self.in_func = False
        self.func = ""
        self.if_stack = []
        self.loop_stack = []
        self.counter = 0
        self.local_offset = 0

    def gen(self, tag):
        self.counter += 1
        # produce global-unique labels (no leading dot) to avoid local-label resolution issues
        if self.func:
            name = f"{self.func}${tag}_{self.counter:03d}"
        else:
            name = f"L_{tag}_{self.counter:03d}"
        return name

    def emit(self, line):
        self.out.append(line)

    def split_code_comment(self, line):
        code, sep, comment = line.partition(";")
        if not sep:
            return code.strip(), ""
        return code.strip(), ";" + comment.rstrip()

    def emit_macro_comment(self, source):
        text = source.strip()
        if text:
            self.emit(f"; macro: {text}")

    def emit_task_get(self, dst, task_ptr, field):
        self.emit(f"LDW {dst} [{task_ptr} + {field}]")

    def emit_task_set(self, task_ptr, field, value):
        if re.match(r"^(R\d+|SP|FP|LR)$", value, re.IGNORECASE):
            self.emit(f"STW {value.upper()} [{task_ptr} + {field}]")
        else:
            self.emit(f"LI R1 {value}")
            self.emit(f"STW R1 [{task_ptr} + {field}]")

    def handle_kernel_macro(self, code, source=None):
        m = re.match(r"^GET_CURR_TASK_IDX\s+(\w+)$", code, re.IGNORECASE)
        if m:
            if source:
                self.emit_macro_comment(source)
            dst = m.group(1).upper()
            self.emit("LI R1 CURRENT_TASK")
            self.emit(f"LDW {dst} [R1]")
            return True

        m = re.match(r"^SET_CURR_TASK_IDX\s+(\w+)$", code, re.IGNORECASE)
        if m:
            if source:
                self.emit_macro_comment(source)
            src = m.group(1).upper()
            self.emit("LI R1 CURRENT_TASK")
            self.emit(f"STW {src} [R1]")
            return True

        m = re.match(r"^GET_TASK_PTR\s+(\w+)\s*,\s*(\w+)$", code, re.IGNORECASE)
        if m:
            if source:
                self.emit_macro_comment(source)
            dst = m.group(1).upper()
            idx = m.group(2).upper()
            self.emit("LI R1 TASK_SIZE")
            self.emit(f"MUL R3 {idx} R1")
            self.emit(f"LI {dst} tasks")
            self.emit(f"ADD {dst} {dst} R3")
            return True

        m = re.match(r"^TASK_GET_([A-Z0-9_]+)\s+(\w+)\s*,\s*(\w+)$", code, re.IGNORECASE)
        if m:
            name = m.group(1).upper()
            dst = m.group(2).upper()
            task_ptr = m.group(3).upper()
            field = TASK_FIELDS.get(name)
            if field:
                if source:
                    self.emit_macro_comment(source)
                self.emit_task_get(dst, task_ptr, field)
                return True

        m = re.match(r"^TASK_SET_([A-Z0-9_]+)\s+(\w+)\s*,\s*([A-Za-z0-9_]+)$", code, re.IGNORECASE)
        if m:
            name = m.group(1).upper()
            task_ptr = m.group(2).upper()
            value = m.group(3).upper()
            field = TASK_FIELDS.get(name)
            if field:
                if source:
                    self.emit_macro_comment(source)
                self.emit_task_set(task_ptr, field, value)
                return True

        return False

    def handle(self, line):
        source = line.rstrip()
        code, comment = self.split_code_comment(line)
        if not code:
            if comment or not source:
                self.emit(source)
            return

        if self.handle_kernel_macro(code, source):
            return

        # simple directive matching
        m = re.match(r"^(func)\s+(\w+)$", code, re.IGNORECASE)
        if m:
            name = m.group(2).upper()
            self.in_func = True
            self.func = name
            self.local_offset = 0
            self.emit(f"{name}:")
            self.emit("FUNC_ENTER")
            return

        if re.match(r"^endfunc$", code, re.IGNORECASE):
            # close any open ifs/loops conservatively
            while self.if_stack:
                lbls = self.if_stack.pop()
                self.emit(f"{lbls['end']}:")
            while self.loop_stack:
                l = self.loop_stack.pop()
                self.emit(f"{l['end']}:")
            self.emit("FUNC_LEAVE")
            self.in_func = False
            self.func = ""
            return

        # argN
        m = re.match(r"^(arg[1-4])\s+(.+)$", code, re.IGNORECASE)
        if m:
            self.emit(f"{m.group(1).upper()} {m.group(2).strip()}")
            return

        # call
        m = re.match(r"^call\s+(.+)$", code, re.IGNORECASE)
        if m:
            self.emit(f"CALL {m.group(1).strip()}")
            return

        # return
        m = re.match(r"^return(?:\s+(.+))?$", code, re.IGNORECASE)
        if m:
            arg = m.group(1)
            if arg:
                a = arg.strip()
                # register?
                if re.match(r"^R\d+$", a, re.IGNORECASE):
                    self.emit(f"MOV R1, {a}")
                else:
                    self.emit(f"LI R1, {a}")
            self.emit("RETURN")
            return

        # alloc / free
        m = re.match(r"^(alloc|free)\s+(\d+)$", code, re.IGNORECASE)
        if m:
            cmd = m.group(1).lower()
            n = int(m.group(2), 0)
            chunks = split_chunks(n)
            if cmd == "alloc":
                for c in chunks:
                    self.emit(f"SUB SP, SP, {c}")
            else:
                for c in chunks:
                    self.emit(f"ADD SP, SP, {c}")
            return

        # decl_local NAME, SIZE
        m = re.match(r"^decl_local\s+(\w+)\s*,\s*(\d+)$", code, re.IGNORECASE)
        if m and self.in_func:
            name = m.group(1).upper()
            size = int(m.group(2), 0)
            offset = self.local_offset
            self.local_offset += size
            # Export as .EQU name <offset> (offset from FP)
            self.emit(f".EQU {name} {offset}")
            return

        # ifz / ifnz
        m = re.match(r"^(ifz|ifnz)\s+(.+)$", code, re.IGNORECASE)
        if m:
            kind = m.group(1).lower()
            reg = m.group(2).strip()
            else_lbl = self.gen("if_else")
            end_lbl = self.gen("if_end")
            # CMP reg, 0
            self.emit(f"CMP {reg}, 0")
            if kind == "ifz":
                # ifz -> if equal true; if not equal branch to else
                self.emit(f"BNE {else_lbl}")
            else:
                # ifnz -> if not zero true; if equal branch to else
                self.emit(f"BEQ {else_lbl}")

            # push frame with labels
            self.if_stack.append({"else": else_lbl, "end": end_lbl, "has_else": False})
            return

        if re.match(r"^else$", code, re.IGNORECASE):
            if not self.if_stack:
                raise SystemExit("else without if")
            top = self.if_stack.pop()
            # branch to end, emit else label
            self.emit(f"B {top['end']}")
            self.emit(f"{top['else']}:")
            # push back but mark that else already emitted
            top['has_else'] = True
            self.if_stack.append(top)
            return

        if re.match(r"^endif$", code, re.IGNORECASE):
            if not self.if_stack:
                raise SystemExit("endif without if")
            top = self.if_stack.pop()
            # if there was no explicit else, emit the else label as an alias
            if not top.get('has_else', False):
                self.emit(f"{top['else']}:")
            self.emit(f"{top['end']}:")
            return

        # whilez / whilenz
        m = re.match(r"^(whilez|whilenz)\s+(.+)$", code, re.IGNORECASE)
        if m:
            kind = m.group(1).lower()
            reg = m.group(2).strip()
            top = self.gen("loop_top")
            end = self.gen("loop_end")
            self.emit(f"{top}:")
            self.emit(f"CMP {reg}, 0")
            if kind == "whilez":
                # while (reg==0) -> if reg != 0 break
                self.emit(f"BNE {end}")
            else:
                # while non-zero -> if reg == 0 break
                self.emit(f"BEQ {end}")
            self.loop_stack.append({"top": top, "end": end})
            return

        if re.match(r"^endwhile$", code, re.IGNORECASE):
            if not self.loop_stack:
                raise SystemExit("endwhile without while")
            top = self.loop_stack.pop()
            self.emit(f"B {top['top']}")
            self.emit(f"{top['end']}:")
            return

        if re.match(r"^break$", code, re.IGNORECASE):
            if not self.loop_stack:
                raise SystemExit("break outside loop")
            self.emit(f"B {self.loop_stack[-1]['end']}")
            return

        if re.match(r"^continue$", code, re.IGNORECASE):
            if not self.loop_stack:
                raise SystemExit("continue outside loop")
            self.emit(f"B {self.loop_stack[-1]['top']}")
            return

        # defines
        m = re.match(r"^#define\s+(\w+)\s+(.+)$", code)
        if m:
            name = m.group(1).upper()
            val = m.group(2).strip()
            self.emit(f".EQU {name} {val}")
            return

        # load8/store8 helpers
        m = re.match(r"^load8\s+(\w+)\s*,\s*\[(.+)\]$", code, re.IGNORECASE)
        if m:
            dst = m.group(1)
            mem = m.group(2)
            self.emit(f"LDB {dst} [{mem}]")
            return

        m = re.match(r"^store8\s+(\w+)\s*,\s*\[(.+)\]$", code, re.IGNORECASE)
        if m:
            src = m.group(1)
            mem = m.group(2)
            self.emit(f"STB {src} [{mem}]")
            return

        # c-like call with named args: e.g. map_page(r2=0x1000, r3=SYM, r4=r5)
        m = re.match(r"^(\w+)\s*\(\s*(.*?)\s*\)$", code)
        if m:
            name = m.group(1).strip()
            args = m.group(2).strip()
            if args:
                parts = [a.strip() for a in args.split(',') if a.strip()]
                for part in parts:
                    mm = re.match(r"^(r\d+)\s*=\s*(.+)$", part, re.IGNORECASE)
                    if not mm:
                        # not a named-register arg, fall back to passthrough
                        self.emit(code)
                        return
                    dst = mm.group(1).upper()
                    val = mm.group(2).strip()
                    # if value is a register, use MOV, otherwise LI
                    if re.match(r"^R\d+$", val, re.IGNORECASE):
                        self.emit(f"MOV {dst} {val.upper()}")
                    else:
                        self.emit(f"LI {dst} {val}")
            # finally emit call
            self.emit(f"CALL {name}")
            return

        # passthrough for anything else (emit as-is)
        self.emit(source)

    def process(self, lines):
        for l in lines:
            self.handle(l.rstrip('\n'))
        return self.out


def main(argv):
    if len(argv) < 2:
        print("usage: preprocess_cmacros.py input.casm", file=sys.stderr)
        raise SystemExit(2)

    path = argv[1]
    with open(path, "r", encoding="utf-8") as f:
        src = f.readlines()

    p = Preprocessor()
    out = p.process(src)
    for line in out:
        print(line)


if __name__ == '__main__':
    main(sys.argv)
