#!/usr/bin/env python3
"""Heuristic converter: turn top-level function labels in kernelshed.asm
into `func`/`endfunc` blocks and replace BL with call, RET with return.

This is conservative: it only converts labels that look like function
entries (no leading whitespace, all-caps/underscores) and not data labels
(no following directives like .SPACE/.WORD within a few lines). It leaves
inner labels and data alone.
"""
import re
import sys


def is_label(line):
    return re.match(r'^([A-Z0-9_]+):\s*$', line) is not None


def convert(lines):
    out = []
    i = 0
    n = len(lines)
    in_func = False
    while i < n:
        line = lines[i]
        if is_label(line):
            name = line.strip()[:-1]
            # lookahead few lines to detect data directives
            look = ''.join(lines[i+1:i+6]).upper()
            if '.SPACE' in look or '.WORD' in look or '.ORG' in look or ' .EQU ' in look:
                # treat as data label, emit as-is
                if in_func:
                    out.append('endfunc\n')
                    in_func = False
                out.append(line)
                i += 1
                continue

            # treat as function
            if in_func:
                out.append('endfunc\n')
            out.append(f'func {name}\n')
            in_func = True
            i += 1
            continue

        # replace BL <label> with call <label>
        m = re.match(r'\s*BL\s+(.+)$', line)
        if m:
            tgt = m.group(1).strip()
            out.append(f'  call {tgt}\n')
            i += 1
            continue

        # replace RET with return (but keep comments)
        if re.match(r'\s*RET\s*(;.*)?$', line):
            # preserve indentation
            indent = re.match(r'^(\s*)', line).group(1)
            out.append(f"{indent}return\n")
            i += 1
            continue

        out.append(line)
        i += 1

    if in_func:
        out.append('endfunc\n')
    return out


def main(argv):
    if len(argv) < 2:
        print('usage: convert_to_cmacros.py input.asm [output.casm]')
        raise SystemExit(2)
    inp = argv[1]
    outp = argv[2] if len(argv) > 2 else inp.replace('.asm', '.casm')
    with open(inp, 'r', encoding='utf-8') as f:
        src = f.readlines()
    dst = convert(src)
    with open(outp, 'w', encoding='utf-8') as f:
        f.writelines(dst)
    print('Wrote', outp)


if __name__ == '__main__':
    main(sys.argv)
