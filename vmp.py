import argparse
import time

from mmu import (
    MMU,
    MODE_KERNEL,
    PAGE_EXEC,
    PAGE_READ,
    PAGE_WRITE,
    PageFault,
)
from debug import dump_all, dump_short
from device.timer import PIT
from device.pic import PIC


# =========================================================
# TRAP/INTERRUPT VECTOR DEFINITIONS
# =========================================================
# IDT vector numbers for synchronous exceptions
TRAP_DIVIDE_BY_ZERO = 0
TRAP_INVALID_INSTR = 1
TRAP_PAGE_FAULT = 2
TRAP_SYSCALL = 3
TRAP_MISALIGNED = 4
TRAP_ILLEGAL_MEM = 5
TRAP_DEBUG = 6

# Vector for async interrupts (future use)
TRAP_IRQ = 16


class TrapDelivery(Exception):
    """Internal exception used to abort instruction execution when a trap is delivered."""
    pass


# =========================================================
# KR32-RISC CPU (FINAL STABLE VM)
# =========================================================
class CPU:
    ZERO_REG = 0
    SP_REG = 13
    FP_REG = 14
    LR_REG = 15
    MEM_SIZE = 8 * 1024 * 1024

    def __init__(self, mem_size=MEM_SIZE, page_size=4096, virtual_size=1024 * 1024 * 1024,
                 tlb_size=64,
        tracevirt = False,
        debug_mode = None,
    ):
        self.MEM_SIZE = mem_size

        # 32 general-purpose registers
        self.reg = [0] * 32

        self.pc = 0
        self.sp = 0xF000
        self.fp = 0xF000
        self.reg[self.SP_REG] = self.sp
        self.reg[self.FP_REG] = self.fp

        self.Z = 0
        self.N = 0
        self.C = 0
        self.V = 0

        self.running = True
        self.mode = MODE_KERNEL

        # byte-addressable physical memory
        self.physical_memory = bytearray(self.MEM_SIZE)
        self.mmu = MMU(page_size=page_size, virtual_size=virtual_size, tlb_size=tlb_size, physical_memory=self.physical_memory)
        # self.mmu.identity_map(0, self.MEM_SIZE, PAGE_READ | PAGE_WRITE | PAGE_EXEC)  # remove, do in guest
        self.mmu.enabled = False  # start disabled
        #trace virtaadd transl
        self.tracevirt = tracevirt
        self.debug_mode = debug_mode
        self.traceint = False
        self.trace_handler = False
        self.trace_fault = False
        self.current_instr_pc = None
        self.current_instr = None
        self.trap_return_pc = 0
        self.trap_saved_r1 = 0
        self.trap_saved_r2 = 0

        # =====================================================
        # TRAP / INTERRUPT STATE
        # =====================================================
        # IDT (Interrupt Descriptor Table) base address in physical memory
        self.idt_base_pa = 0

        # Interrupt enable flag (controls trap delivery)
        self.interrupt_enabled = False

        # Trap context: saved state when a trap occurs
        self.trap_epc = 0        # Exception PC (address of faulting instruction)
        self.trap_cause = 0      # Vector number or cause code
        self.trap_value = 0      # Additional info (e.g., fault address for page faults)

        # Flag to mark we are currently in a trap handler
        self.in_trap_handler = False

        # =====================================================
        # DEVICES
        # =====================================================
        self.timer = PIT(period_ms=100)  # tick every 1 second
        self.pic = PIC()
        self.pic.enable_irq(0)  # enable timer IRQ

    # -----------------------------------------------------
    # SAFE REGISTER ACCESS
    # -----------------------------------------------------
    def r(self, i):
        idx = i & 0x1F
        if idx == self.ZERO_REG:
            return 0
        return self.reg[idx]

    def setr(self, i, v):
        idx = i & 0x1F
        if idx == self.ZERO_REG:
            return
        self.reg[idx] = v & 0xFFFFFFFF
        if idx == self.SP_REG:
            self.sp = self.reg[idx]
        elif idx == self.FP_REG:
            self.fp = self.reg[idx]

    def get_sp(self):
        return self.r(self.SP_REG)

    def set_sp(self, v):
        self.setr(self.SP_REG, v)
        self.sp = self.r(self.SP_REG)

    def imm16(self, hi, lo):
        return ((hi & 0xFF) << 8) | (lo & 0xFF)

    def alu_rhs(self, c):
        if c & 0x80:
            return c & 0x7F
        return self.r(c)

    def signed32(self, v):
        v &= 0xFFFFFFFF
        return v - 0x100000000 if v & 0x80000000 else v

    def sign_extend(self, v, bits):
        sign = 1 << (bits - 1)
        mask = (1 << bits) - 1
        v &= mask
        return (v ^ sign) - sign

    def set_cmp_flags(self, lhs, rhs):
        lhs &= 0xFFFFFFFF
        rhs &= 0xFFFFFFFF
        result = (lhs - rhs) & 0xFFFFFFFF
        self.Z = (result == 0)
        self.N = bool(result & 0x80000000)
        self.C = (lhs >= rhs)
        self.V = bool(((lhs ^ rhs) & (lhs ^ result) & 0x80000000) != 0)

    def div_trunc(self, lhs, rhs):
        if rhs == 0:
            raise ZeroDivisionError("KR32 DIV by zero")
        negative = (lhs < 0) != (rhs < 0)
        quotient = abs(lhs) // abs(rhs)
        return -quotient if negative else quotient

    def reg_name(self, i):
        idx = i & 0x1F
        if idx == self.ZERO_REG:
            return "ZERO"
        if idx == self.SP_REG:
            return "SP"
        if idx == self.FP_REG:
            return "FP"
        if idx == self.LR_REG:
            return "LR"
        return f"R{idx}"

    def disasm(self, op, a, b, c, ext=None):
        target = ext if ext is not None else (a << 8) | b
        op_name = {
            0x01: "MOV",
            0x02: "ADD",
            0x03: "SUB",
            0x04: "CMP",
            0x05: "B",
            0x06: "BEQ",
            0x07: "BNE",
            0x08: "MUL",
            0x09: "AND",
            0x0A: "OR",
            0x0B: "XOR",
            0x0C: "SHL",
            0x0D: "SHR",
            0x0E: "SAR",
            0x0F: "LI",
            0x10: "PUSH",
            0x11: "POP",
            0x12: "BLT",
            0x13: "BLE",
            0x14: "BGT",
            0x15: "BGE",
            0x16: "DIV",
            0x17: "MOD",
            0x18: "DIVU",
            0x19: "MODU",
            0x1A: "BLTU",
            0x1B: "BLEU",
            0x1C: "BGTU",
            0x1D: "BGEU",
            0x20: "LDB",
            0x21: "LDH",
            0x22: "LDW",
            0x23: "STB",
            0x24: "STH",
            0x25: "STW",
            0x26: "LDBS",
            0x27: "LDHS",
            0x30: "BL",
            0x31: "RET",
            0x40: "SVC",
            0x50: "SETPTBR",
            0x51: "SETIDTR",
            0x52: "ENABLEMMU",
            0x53: "ENABLEINT",
            0x54: "DISABLEINT",
            0x55: "IRET",
            0x56: "DEBUG",
            0xFF: "HLT",
        }.get(op)

        if op == 0x01:
            if a & 0x80:
                return f"MOV {self.reg_name(a)}, {self.reg_name(b)}"
            return f"MOV {self.reg_name(a)}, 0x{self.imm16(b, c):04X}"
        if op in (0x02, 0x03, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E):
            rhs = f"#{c & 0x7F}" if c & 0x80 else self.reg_name(c)
            return f"{op_name} {self.reg_name(a)}, {self.reg_name(b)}, {rhs}"
        if op == 0x08:
            return f"MUL {self.reg_name(a)}, {self.reg_name(b)}, {self.reg_name(c)}"
        if op in (0x16, 0x17, 0x18, 0x19):
            return f"{op_name} {self.reg_name(a)}, {self.reg_name(b)}, {self.reg_name(c)}"
        if op == 0x0F:
            return f"LI {self.reg_name(a)}, 0x{target:08X}"
        if op == 0x04:
            rhs = f"#{c & 0x7F}" if c & 0x80 else self.reg_name(b)
            return f"CMP {self.reg_name(a)}, {rhs}"
        if op in (0x05, 0x06, 0x07, 0x12, 0x13, 0x14, 0x15, 0x1A, 0x1B, 0x1C, 0x1D, 0x30):
            return f"{op_name} 0x{target:08X}"
        if op == 0x10:
            return f"PUSH {self.reg_name(a)}"
        if op == 0x11:
            return f"POP {self.reg_name(a)}"
        if op in (0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27):
            offset = self.reg_name(c) if c & 0x80 else f"#{c}"
            return f"{op_name} {self.reg_name(a)}, [{self.reg_name(b)} + {offset}]"
        if op == 0x31:
            return "RET"
        if op == 0x40:
            return f"SVC {a}"
        if op == 0x50:
            return f"SETPTBR {self.reg_name(a)}"
        if op == 0x51:
            return f"SETIDTR {self.reg_name(a)}"
        if op == 0x52:
            return "ENABLEMMU"
        if op == 0x53:
            return "ENABLEINT"
        if op == 0x54:
            return "DISABLEINT"
        if op == 0x55:
            return "IRET"
        if op == 0x56:
            delay = (a << 16) | (b << 8) | c
            return f"DEBUG {delay}"
        if op == 0xFF:
            return "HLT"
        return f"UNKNOWN 0x{op:02X}"

    def trace_changes(self, before_reg, before_sp, before_pc, before_z, before_n, before_c, before_v, before_running, mem_write):
        changes = []

        for i, (old, new) in enumerate(zip(before_reg, self.reg)):
            if old != new:
                changes.append(f"{self.reg_name(i)}:0x{old:08X}->0x{new:08X}")

        if before_sp != self.sp and before_reg[self.SP_REG] == self.reg[self.SP_REG]:
            changes.append(f"SP:0x{before_sp:08X}->0x{self.sp:08X}")

        if before_pc != self.pc:
            changes.append(f"PC:0x{before_pc:04X}->0x{self.pc:04X}")

        if before_z != self.Z:
            changes.append(f"Z:{int(before_z)}->{int(self.Z)}")

        if before_n != self.N:
            changes.append(f"N:{int(before_n)}->{int(self.N)}")

        if before_c != self.C:
            changes.append(f"C:{int(before_c)}->{int(self.C)}")

        if before_v != self.V:
            changes.append(f"V:{int(before_v)}->{int(self.V)}")

        if before_running != self.running:
            changes.append(f"RUN:{int(before_running)}->{int(self.running)}")

        if mem_write is not None:
            addr, value, size = mem_write
            width = size * 2
            changes.append(f"MEM{size * 8}[0x{addr:08X}]=0x{value:0{width}X}")

        if not changes:
            return "no change"
        return " | ".join(changes)

    # -----------------------------------------------------
    # MEMORY SAFETY
    # -----------------------------------------------------
    def check_physical_mem(self, paddr, size):
        if paddr < 0 or paddr + size > len(self.physical_memory):
            raise Exception(f"PHYS MEM OOB paddr=0x{paddr:08X} size={size}")

    def translate(self, vaddr, access):
        try:
            paddr, _ = self.mmu.translate(vaddr, access, self.mode)
        except PageFault as exc:
            self.raise_trap(TRAP_PAGE_FAULT, vaddr)
            raise TrapDelivery()
        self.check_physical_mem(paddr, 1)
        return paddr

    def raise_trap(self, vector, value=0):
        """
        Deliver a synchronous trap/exception to the guest kernel.

        This is called when a fault occurs (divide-by-zero, page fault, etc).
        The CPU saves context and vectors through the IDT to the handler.

        Args:
            vector: trap vector number (TRAP_DIVIDE_BY_ZERO, TRAP_PAGE_FAULT, etc)
            value: optional extra info (e.g., faulting address for page faults)
        """
        fault_pc = self.current_instr_pc if self.current_instr_pc is not None else self.pc
        self.trap_epc = fault_pc
        self.trap_return_pc = self.pc
        self.trap_cause = vector
        self.trap_value = value

        # Preserve original register values that are used for trap arguments.
        # Guest trap handlers can save/restore R1/R2 themselves, but the VM
        # must restore the interrupted thread's original values on IRET.
        self.trap_saved_r1 = self.r(1)
        self.trap_saved_r2 = self.r(2)

        # Make trap arguments visible to the guest handler
        self.setr(1, value)
        self.setr(2, vector)

        if self.traceint or self.trace_fault:
            print(f"[TRAP] vector={vector} value=0x{value:08X} pc=0x{fault_pc:08X} handler_base=0x{self.idt_base_pa:08X}")
            if self.current_instr is not None:
                op = (self.current_instr >> 24) & 0xFF
                a  = (self.current_instr >> 16) & 0xFF
                b  = (self.current_instr >> 8) & 0xFF
                c  = self.current_instr & 0xFF
                if op in (0x05, 0x06, 0x07, 0x0F, 0x12, 0x13, 0x14, 0x15, 0x1A, 0x1B, 0x1C, 0x1D, 0x30):
                    target = self.mem_read_u32(fault_pc + 4)
                    print(f"[TRAP INST] {self.disasm(op, a, b, c, target)}")
                else:
                    print(f"[TRAP INST] {self.disasm(op, a, b, c)}")

        # Check if IDT base is set and interrupt delivery is enabled
        if self.idt_base_pa == 0:
            print(f"[TRAP FATAL] vector={vector} @ pc=0x{self.trap_epc:08X}, no IDT base set")
            self.running = False
            raise TrapDelivery()

        if not self.interrupt_enabled:
            print(f"[TRAP MASKED] vector={vector} @ pc=0x{self.trap_epc:08X}")
            raise TrapDelivery()

        handler_pa = self.idt_base_pa + vector * 4
        if handler_pa + 4 > len(self.physical_memory):
            print(f"[TRAP FATAL] IDT entry out of bounds: vector={vector}")
            self.running = False
            raise TrapDelivery()

        handler_pc_bytes = self.physical_memory[handler_pa:handler_pa+4]
        handler_pc = int.from_bytes(handler_pc_bytes, "little")

        self.in_trap_handler = True
        self.pc = handler_pc
        raise TrapDelivery()

    def physical_read_u8(self, paddr):
        self.check_physical_mem(paddr, 1)
        return self.physical_memory[paddr]

    def physical_write_u8(self, paddr, val):
        self.check_physical_mem(paddr, 1)
        self.physical_memory[paddr] = val & 0xFF
    #trace virt to physical translation
    def trace_virt(self, bl_type,addr,access):
        if self.tracevirt:
            access_name = {
                "r": "READ",
                "w": "WRITE",
                "x": "EXEC",
            }.get(access, access)

            if not self.mmu.enabled:
                print(f"[VIRT] {access_name:<5} [MMU OFF] {bl_type*8} bits VA=0x{addr:08X}->PA=0x{addr:08X} ")
                return

            try:
                paddr, tlb = self.mmu.translate(addr, access, self.mode)
            except PageFault:
                print(f"[VIRT] {access_name:<5} [PAGE FLT] {bl_type*8} bits VA=0x{addr:08X} ")
                self.raise_trap(TRAP_PAGE_FAULT, addr)
                raise TrapDelivery()

            if tlb is False:
                print(f"[VIRT] {access_name:<5} [TABLE] ", end="")
            else:
                print(f"[VIRT] {access_name:<5} [TLB] ", end="")
            print(f"{bl_type*8} bits VA=0x{addr:08X}->PA=0x{paddr:08X} ")

    #help read when not byte
    def mem_read_u8_hlp(self, addr, access="r"):
        value_u8 = self.physical_read_u8(self.translate(addr, access))
        return value_u8

    def mem_read_u8(self, addr, access="r"):
        self.trace_virt(1,addr,access)
        value_u8 = self.physical_read_u8(self.translate(addr, access))
        return value_u8

    def mem_read_u16(self, addr, access="r"):
        self.trace_virt(2, addr, access)
        return self.mem_read_u8_hlp(addr, access) | (self.mem_read_u8_hlp(addr + 1, access) << 8)

    def mem_read_u32(self, addr, access="r"):
        self.trace_virt(4, addr, access)
        return (
            self.mem_read_u8_hlp(addr, access)
            | (self.mem_read_u8_hlp(addr + 1, access) << 8)
            | (self.mem_read_u8_hlp(addr + 2, access) << 16)
            | (self.mem_read_u8_hlp(addr + 3, access) << 24)
        )

    def mem_write_u8_hlp(self, addr, val):
        self.physical_write_u8(self.translate(addr, "w"), val)

    def mem_write_u8(self, addr, val):
        self.trace_virt(1, addr, "w")
        self.physical_write_u8(self.translate(addr, "w"), val)

    def mem_write_u16(self, addr, val):
        self.trace_virt(2, addr, "w")
        self.mem_write_u8_hlp(addr, val)
        self.mem_write_u8_hlp(addr + 1, val >> 8)

    def mem_write_u32(self, addr, val):
        self.trace_virt(4, addr, "w")
        self.mem_write_u8_hlp(addr, val)
        self.mem_write_u8_hlp(addr + 1, val >> 8)
        self.mem_write_u8_hlp(addr + 2, val >> 16)
        self.mem_write_u8_hlp(addr + 3, val >> 24)

    def hexdump(self, addr, size, width=16):
        if size < 0:
            raise ValueError("hexdump size must be non-negative")
        for row in range(addr, addr + size, width):
            chunk = bytes(self.mem_read_u8(i, "r") for i in range(row, min(row + width, addr + size)))
            hex_part = " ".join(f"{b:02X}" for b in chunk)
            hex_part = hex_part.ljust(width * 3 - 1)
            ascii_part = "".join(chr(b) if 32 <= b <= 126 else "." for b in chunk)
            print(f"{row:08X}  {hex_part}  |{ascii_part}|")

    def physical_hexdump(self, paddr, size, width=16):
        self.check_physical_mem(paddr, size)
        for row in range(paddr, paddr + size, width):
            chunk = self.physical_memory[row:min(row + width, paddr + size)]
            hex_part = " ".join(f"{b:02X}" for b in chunk)
            hex_part = hex_part.ljust(width * 3 - 1)
            ascii_part = "".join(chr(b) if 32 <= b <= 126 else "." for b in chunk)
            print(f"{row:08X}  {hex_part}  |{ascii_part}|")

    # -----------------------------------------------------
    # STACK
    # -----------------------------------------------------
    def push(self, v):
        self.set_sp(self.get_sp() - 4)
        self.mem_write_u32(self.get_sp(), v)

    def pop(self):
        v = self.mem_read_u32(self.get_sp())
        self.set_sp(self.get_sp() + 4)
        return v

    # -----------------------------------------------------
    # LOAD IMAGE
    # -----------------------------------------------------
    def load_image(self, file):
        with open(file, "rb") as f:
            data = f.read()

        self.check_physical_mem(0, len(data))
        self.physical_memory[0:len(data)] = data

    # -----------------------------------------------------
    # FETCH
    # -----------------------------------------------------
    def fetch(self):
        instr = self.mem_read_u32(self.pc, access="x")
        self.pc += 4
        return instr

    # -----------------------------------------------------
    # RUN LOOP
    # -----------------------------------------------------
    def run(self, start=0, trace=False):
        self.pc = start
        self.running = True

        steps = 0
        MAX_STEPS = 1_000_000

        while self.running:

            steps += 1
            if steps > MAX_STEPS:
                print("[CPU] MAX STEPS REACHED -> STOP")
                break

            instr_pc = self.pc
            self.current_instr_pc = instr_pc
            self.current_instr = None

            try:
                # =================================================
                # DEVICE TICKING
                # =================================================
                if self.timer.tick():
                    print("[TIMER] tick")
                    self.pic.raise_irq(0)

                # Check for pending IRQs
                if self.interrupt_enabled and not self.in_trap_handler:
                    irq = self.pic.next_irq()
                    if irq is not None:
                        print(f"[IRQ] pending={irq}")
                        self.pic.ack(irq)  # Auto-ack for now
                        self.raise_trap(TRAP_IRQ, irq)

                instr = self.fetch()
                self.current_instr = instr

                op = (instr >> 24) & 0xFF
                a  = (instr >> 16) & 0xFF
                b  = (instr >> 8) & 0xFF
                c  = instr & 0xFF
                ext = None
                if op in (0x05, 0x06, 0x07, 0x0F, 0x12, 0x13, 0x14, 0x15, 0x1A, 0x1B, 0x1C, 0x1D, 0x30):
                    ext = self.fetch()
                pc_before_exec = self.pc
                before_reg = self.reg[:]
                before_sp = self.sp
                before_z = self.Z
                before_n = self.N
                before_c = self.C
                before_v = self.V
                before_running = self.running
                mem_write = None
                syscall_message = None

                # =================================================
                # MOV / LI
                # =================================================
                if op == 0x01:
                    if a & 0x80:
                        self.setr(a, self.r(b))
                    else:
                        self.setr(a, self.imm16(b, c))

                elif op == 0x0F:
                    self.setr(a, ext)

                # =================================================
                # ALU
                # =================================================
                elif op == 0x02:
                    self.setr(a, self.r(b) + self.alu_rhs(c))

                elif op == 0x03:
                    self.setr(a, self.r(b) - self.alu_rhs(c))

                elif op == 0x08:
                    self.setr(a, self.r(b) * self.r(c))

                elif op == 0x16:  # DIV (signed)
                    # Division by zero raises a trap
                    rhs = self.signed32(self.r(c))
                    if rhs == 0:
                        self.raise_trap(TRAP_DIVIDE_BY_ZERO, 0x16)
                    else:
                        self.setr(a, self.div_trunc(self.signed32(self.r(b)), rhs))

                elif op == 0x17:  # MOD (signed modulo)
                    lhs = self.signed32(self.r(b))
                    rhs = self.signed32(self.r(c))
                    if rhs == 0:
                        self.raise_trap(TRAP_DIVIDE_BY_ZERO, 0x17)
                    else:
                        self.setr(a, lhs - self.div_trunc(lhs, rhs) * rhs)

                elif op == 0x18:  # DIVU (unsigned)
                    rhs = self.r(c)
                    if rhs == 0:
                        self.raise_trap(TRAP_DIVIDE_BY_ZERO, 0x18)
                    else:
                        self.setr(a, self.r(b) // rhs)

                elif op == 0x19:  # MODU (unsigned modulo)
                    rhs = self.r(c)
                    if rhs == 0:
                        self.raise_trap(TRAP_DIVIDE_BY_ZERO, 0x19)
                    else:
                        self.setr(a, self.r(b) % rhs)

                elif op == 0x09:
                    self.setr(a, self.r(b) & self.alu_rhs(c))

                elif op == 0x0A:
                    self.setr(a, self.r(b) | self.alu_rhs(c))

                elif op == 0x0B:
                    self.setr(a, self.r(b) ^ self.alu_rhs(c))

                elif op == 0x0C:
                    self.setr(a, self.r(b) << (self.alu_rhs(c) & 0x1F))

                elif op == 0x0D:
                    self.setr(a, self.r(b) >> (self.alu_rhs(c) & 0x1F))

                elif op == 0x0E:
                    self.setr(a, self.signed32(self.r(b)) >> (self.alu_rhs(c) & 0x1F))

                # =================================================
                # CMP
                # =================================================
                elif op == 0x04:
                    self.set_cmp_flags(self.r(a), self.alu_rhs(c) if c & 0x80 else self.r(b))

                # =================================================
                # BRANCH
                # =================================================
                elif op == 0x05:
                    self.pc = ext

                elif op == 0x06:
                    if self.Z:
                        self.pc = ext

                elif op == 0x07:
                    if not self.Z:
                        self.pc = ext

                elif op == 0x12:
                    if self.N != self.V:
                        self.pc = ext

                elif op == 0x13:
                    if self.Z or self.N != self.V:
                        self.pc = ext

                elif op == 0x14:
                    if not self.Z and self.N == self.V:
                        self.pc = ext

                elif op == 0x15:
                    if self.N == self.V:
                        self.pc = ext

                elif op == 0x1A:
                    if not self.C:
                        self.pc = ext

                elif op == 0x1B:
                    if not self.C or self.Z:
                        self.pc = ext

                elif op == 0x1C:
                    if self.C and not self.Z:
                        self.pc = ext

                elif op == 0x1D:
                    if self.C:
                        self.pc = ext

                # =================================================
                # STACK
                # =================================================
                elif op == 0x10:
                    self.push(self.r(a))

                elif op == 0x11:
                    self.setr(a, self.pop())

                # =================================================
                # MEMORY
                # =================================================
                elif op in (0x20, 0x21, 0x22, 0x26, 0x27):  # LDB/LDH/LDW/LDBS/LDHS
                    rd = a
                    base = b

                    offset = self.r(c & 0x1F) if (c & 0x80) else c
                    addr = self.r(base) + offset

                    if op == 0x20:
                        self.setr(rd, self.mem_read_u8(addr))
                    elif op == 0x21:
                        self.setr(rd, self.mem_read_u16(addr))
                    elif op == 0x22:
                        self.setr(rd, self.mem_read_u32(addr))
                    elif op == 0x26:
                        self.setr(rd, self.sign_extend(self.mem_read_u8(addr), 8))
                    else:
                        self.setr(rd, self.sign_extend(self.mem_read_u16(addr), 16))

                elif op in (0x23, 0x24, 0x25):  # STB/STH/STW
                    rs = a
                    base = b

                    offset = self.r(c & 0x1F) if (c & 0x80) else c
                    addr = self.r(base) + offset

                    if op == 0x23:
                        self.mem_write_u8(addr, self.r(rs))
                        mem_write = (addr, self.r(rs) & 0xFF, 1)
                    elif op == 0x24:
                        self.mem_write_u16(addr, self.r(rs))
                        mem_write = (addr, self.r(rs) & 0xFFFF, 2)
                    else:
                        self.mem_write_u32(addr, self.r(rs))
                        mem_write = (addr, self.r(rs), 4)

                # =================================================
                # CALL / RET (FIXED STACK ABI)
                # =================================================
                elif op == 0x30:
                    self.setr(self.LR_REG, self.pc)
                    self.pc = ext

                elif op == 0x31:
                    self.pc = self.r(self.LR_REG)

                # =================================================
                # SYSCALL / SOFTWARE TRAP
                # =================================================
                elif op == 0x40:  # SVC (a = syscall number)
                    # Deliver SYSCALL trap with syscall number in trap_value
                    self.raise_trap(TRAP_SYSCALL, a)

                elif op == 0x56:  # DEBUG - user-visible debug trap
                    debug_delay = (a << 16) | (b << 8) | c
                    if self.debug_mode is not None:
                        if self.debug_mode == 0:
                            dump_short(self)
                        else:
                            dump_all(self)
                        if debug_delay:
                            time.sleep(debug_delay)
                        self.raise_trap(TRAP_DEBUG, debug_delay)
                    elif debug_delay:
                        time.sleep(debug_delay)

                # =================================================
                # MMU CONTROL
                # =================================================
                elif op == 0x50:  # SETPTBR Rn - set page table base register
                    self.mmu.ptbr_pa = self.r(a)

                elif op == 0x51:  # SETIDTR Rn - set IDT base register
                    # Guest kernel sets the IDT base physical address
                    self.idt_base_pa = self.r(a)

                elif op == 0x52:  # ENABLEMMU
                    self.mmu.enabled = True

                # =================================================
                # TRAP / INTERRUPT CONTROL
                # =================================================
                elif op == 0x53:  # ENABLEINT - enable interrupt delivery
                    # After this, traps can be delivered via IDT
                    self.interrupt_enabled = True

                elif op == 0x54:  # DISABLEINT - disable interrupt delivery
                    # Traps will be masked after this
                    self.interrupt_enabled = False

                elif op == 0x55:  # IRET - return from trap
                    # Restore PC and original trap-scratch registers. The guest
                    # handler may use R1/R2 for trap arguments, but the interrupted
                    # context must resume with the original register state.
                    self.setr(1, self.trap_saved_r1)
                    self.setr(2, self.trap_saved_r2)
                    self.in_trap_handler = False
                    self.pc = self.trap_return_pc

                # =================================================
                # HALT
                # =================================================
                elif op == 0xFF:
                    self.running = False

                else:
                    # Unknown instruction: deliver invalid instruction trap
                    self.raise_trap(TRAP_INVALID_INSTR, op)

                if trace or (self.trace_handler and self.in_trap_handler):
                    print(
                        f"PC={instr_pc:08X}  {self.disasm(op, a, b, c, ext):30} "
                        f"; {self.trace_changes(before_reg, before_sp, pc_before_exec, before_z, before_n, before_c, before_v, before_running, mem_write)} "
                        f"; OP=0x{op:02X} RAW=0x{instr:08X}"
                    )
                if syscall_message:
                    print(syscall_message)
            except TrapDelivery:
                if trace:
                    print(f"PC={instr_pc:08X}  [TRAP] vector={self.trap_cause} -> handler=0x{self.pc:08X}")
                continue
            finally:
                self.current_instr_pc = None

        print("[CPU HALTED]")


# =========================================================
# MAIN
# =========================================================
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--trace", action="store_true", help="print each instruction")
    parser.add_argument("--dump", nargs=2, metavar=("ADDR", "SIZE"), help="dump memory after execution")
    parser.add_argument("--pdump", nargs=2, metavar=("PADDR", "SIZE"), help="dump physical memory after execution")
    parser.add_argument("--mem-size", default=str(CPU.MEM_SIZE), help="physical memory size in bytes")
    parser.add_argument("--page-size", default="4096", help="MMU page size in bytes")
    parser.add_argument("--virtual-size", default=str(1024 * 1024 * 1024), help="virtual address space size in bytes")
    parser.add_argument("--tlb-size", default="64", help="TLB entry count")
    parser.add_argument("--no-mmu", action="store_true", help="disable address translation")
    parser.add_argument(
        "--tracevirt",
        action="store_true",
        help="trace virtual->physical address translations"
    )
    parser.add_argument(
        "--traceint",
        action="store_true",
        help="trace trap/interrupt delivery"
    )
    parser.add_argument(
        "--tracefault",
        action="store_true",
        help="also print the trap-faulting instruction when a trap is delivered"
    )
    parser.add_argument(
        "--tracehandler",
        action="store_true",
        help="trace instructions only while inside trap/interrupt handlers"
    )
    parser.add_argument(
        "--debug",
        type=int,
        choices=[0, 1],
        help="enable debug dumps: 0=short (regs+flags), 1=full"
    )
    args = parser.parse_args()

    print("=== KR32 BOOT ===")

    cpu = CPU(
        mem_size=int(args.mem_size, 0),
        page_size=int(args.page_size, 0),
        virtual_size=int(args.virtual_size, 0),
        tlb_size=int(args.tlb_size, 0),
        tracevirt=args.tracevirt,
        debug_mode=args.debug,
    )
    cpu.traceint = args.traceint
    cpu.trace_fault = args.tracefault
    cpu.trace_handler = args.tracehandler
    if args.no_mmu:
        cpu.mmu.enabled = False

    cpu.load_image("memory.img")

    print("[BOOT] Image loaded")
    print("[BOOT] Reset CPU state")
    print("[BOOT] Starting execution")

    cpu.run(0, trace=args.trace)

    if args.dump:
        addr = int(args.dump[0], 0)
        size = int(args.dump[1], 0)
        print(f"[VIRT MEM DUMP] addr=0x{addr:08X} size={size}")
        cpu.hexdump(addr, size)

    if args.pdump:
        paddr = int(args.pdump[0], 0)
        size = int(args.pdump[1], 0)
        print(f"[PHYS MEM DUMP] paddr=0x{paddr:08X} size={size}")
        cpu.physical_hexdump(paddr, size)

    print("[BOOT] Done")


if __name__ == "__main__":
    main()
