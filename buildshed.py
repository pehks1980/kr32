from assembler import Assembler

def load(f):
    with open(f) as x:
        return x.readlines()

asm = Assembler()
asm.build(load("kernelshed.asm"), "memory.img")
