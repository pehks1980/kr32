from assembler import Assembler

def load(f):
    with open(f) as x:
        return x.readlines()

asm = Assembler()
asm.build(load("kernel.asm") + load("user.asm"), "memory.img")