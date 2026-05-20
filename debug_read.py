from assembler import Assembler
from pathlib import Path
from vmp import CPU

src = Path('kernelshed.asm').read_text().splitlines()
a = Assembler()
a.build(src, out='memory.img')

cpu = CPU()
cpu.load_image('memory.img')

labels = a.labels
breakpoints = {
    labels['SYSCALL_READ'],
    labels['DEV_CONSOLE_READ'],
    labels['COPY_TO_USER'],
}
orig_fetch = CPU.fetch

def fetch(self):
    if self.pc in breakpoints:
        print('BREAK', hex(self.pc), 'mode', self.mode)
        print('SP', hex(self.sp))
        print('R1..R6', [hex(self.r(i)) for i in range(1, 7)])
        if self.pc == labels['SYSCALL_READ']:
            print('caller', hex(self.r(1)), hex(self.r(2)), hex(self.r(3)), hex(self.r(6)), hex(self.r(7)), hex(self.r(9)))
        if self.pc == labels['DEV_CONSOLE_READ']:
            print('devread entry', hex(self.r(1)), hex(self.r(2)), hex(self.r(3)))
        if self.pc == labels['COPY_TO_USER']:
            print('copy_to_user entry', hex(self.r(1)), hex(self.r(2)), hex(self.r(4)))
        raise SystemExit('break')
    return orig_fetch(self)

CPU.fetch = fetch

try:
    cpu.run(0)
except SystemExit as e:
    print('stopped', e)
