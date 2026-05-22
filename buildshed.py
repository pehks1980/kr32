import subprocess
from assembler import Assembler

def load(f):
    with open(f) as x:
        return x.readlines()

# 1. Preprocess the kernelshed.asm (C-like macros) to kernelshed_pre.asm (pure assembly)
print("[BUILD] Preprocessing kernelshed.asm using preprocess_cmacros.py...")
subprocess.run("python3 tools/preprocess_cmacros.py kernelshed.asm > kernelshed_pre.asm", shell=True, check=True)

# 2. Build the preprocessed assembly into memory.img
print("[BUILD] Assembling kernelshed_pre.asm to memory.img...")
asm = Assembler()
asm.build(load("kernelshed_pre.asm"), "memory.img")
print("[BUILD] Build successful! Created memory.img")
