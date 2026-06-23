import argparse
import sys
import time
from token import OP

from mmu import (
    MMU,
    MODE_KERNEL,
    MODE_USER,
    PAGE_EXEC,
    PAGE_GLOBAL,
    PAGE_READ,
    PAGE_USER,
    PAGE_WRITE,
    PageFault,
)
from debug import dump_all, dump_debug2, dump_short
from device.timer import PIT
from device.pic import PIC
from device.uart import UARTDevice

# KR32 REGS CONVENTION:
#   R0        = hardwired ZERO
#   R1-R4     = argument registers (arg0..arg3)
#   R1        = return value register
#   R5-R11    = caller-saved temporaries
#   R12       = callee-saved temporary (optional)
#   R13       = SP (stack pointer)
#   R14       = FP (frame pointer)
#   R15       = LR (return link)
#   Callees must preserve FP/LR/SP and may use R1-R11 freely.

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

CSR_SSTATUS = 0x00
CSR_STVEC = 0x01
CSR_SEPC = 0x02
CSR_SCAUSE = 0x03
CSR_STVAL = 0x04
CSR_SSCRATCH = 0x05
CSR_SFLAGS = 0x06

CSR_NAMES = {
    CSR_SSTATUS: "sstatus",
    CSR_STVEC: "stvec",
    CSR_SEPC: "sepc",
    CSR_SCAUSE: "scause",
    CSR_STVAL: "stval",
    CSR_SSCRATCH: "sscratch",
    CSR_SFLAGS: "sflags",
}

SSTATUS_SIE = 1 << 1
SSTATUS_SPIE = 1 << 5
SSTATUS_SPP = 1 << 8

SFLAGS_Z = 1 << 0
SFLAGS_N = 1 << 1
SFLAGS_C = 1 << 2
SFLAGS_V = 1 << 3


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
        trace = False,
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
        self.trace = trace
        self.traceint = False
        self.trace_handler = False
        self.trace_fault = False
        self.debug_dump_range = None
        self.current_instr_pc = None
        self.trace_output = True
        self.trace_events = False
        self.quiet = False
        self.current_instr = None
        self.trap_return_pc = 0
        self.trap_saved_r1 = 0
        self.trap_saved_r2 = 0

        self.scause = 0      # Cause of current trap
        self.sepc = 0        # Exception PC (you already have trap_epc)
        self.stval = 0       # Fault address (you already have trap_value)
        self.sstatus = 0
        self.stvec = 0
        self.sscratch = 0
        self.sflags = 0

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
        self.timer = PIT(period_ms=2000)  # tick every 2 seconds
        self.pic = PIC()
        self.pic.enable_irq(0)  # enable timer IRQ
        self.uart = UARTDevice()
       

        # -------------------------------------------------
        # DEBUGGER STATE
        # -------------------------------------------------
        self.breakpoints = set()
        self.watchpoints = []
        self.stop_reason = None
        self.stop_info = None
        self.image_path = None

    # -----------------------------------------------------
    # SAFE REGISTER ACCESS
    # -----------------------------------------------------
    def r(self, i):
        idx = i & 0x1F
        if idx == self.ZERO_REG:
            return 0
        return self.reg[idx]
    # -----------------------------------------------------
    # SAFE REGISTER WRITE (enforces ZERO_REG immutability and updates SP/FP aliases)
    # -----------------------------------------------------

    def setr(self, i, v):
        idx = i & 0x1F
        if idx == self.ZERO_REG:
            return
        self.reg[idx] = v & 0xFFFFFFFF
        if idx == self.SP_REG:
            self.sp = self.reg[idx]
        elif idx == self.FP_REG:
            self.fp = self.reg[idx]
    # -----------------------------------------------------
    # ALU HELPER FUNCTIONS
    # -----------------------------------------------------

    def get_sp(self):
        return self.r(self.SP_REG)

    def set_sp(self, v):
        self.setr(self.SP_REG, v)
        self.sp = self.r(self.SP_REG)

    def imm16(self, hi, lo):
        return ((hi & 0xFF) << 8) | (lo & 0xFF)
    # -----------------------------------------------------
    # alu_rhs: Helper to decode the flexible 3rd operand in ALU instructions, 
    # which can be either an immediate (if bit 7 is set) or a register value.
    # -----------------------------------------------------
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
    # -----------------------------------------------------
    # set_cmp_flags: Helper to compute and set the condition flags (Z, N, C, V) 
    # based on a subtraction of two 32-bit values.
    # -----------------------------------------------------

    def set_cmp_flags(self, lhs, rhs):
        lhs &= 0xFFFFFFFF
        rhs &= 0xFFFFFFFF
        result = (lhs - rhs) & 0xFFFFFFFF
        self.Z = (result == 0)
        self.N = bool(result & 0x80000000)
        self.C = (lhs >= rhs)
        self.V = bool(((lhs ^ rhs) & (lhs ^ result) & 0x80000000) != 0)

    def pack_flags(self):
        flags = 0
        if self.Z:
            flags |= SFLAGS_Z
        if self.N:
            flags |= SFLAGS_N
        if self.C:
            flags |= SFLAGS_C
        if self.V:
            flags |= SFLAGS_V
        return flags

    def unpack_flags(self, flags):
        self.sflags = flags & 0xFFFFFFFF
        self.Z = bool(flags & SFLAGS_Z)
        self.N = bool(flags & SFLAGS_N)
        self.C = bool(flags & SFLAGS_C)
        self.V = bool(flags & SFLAGS_V)
    # -----------------------------------------------------
    # csr_name - Helper to get human-readable names for CSRs (Control and Status Registers) used in trap handling.
    # csr_read and csr_write: Accessors for control and status registers (CSRs) used in trap handling.
    #------------------------------------------------------

    def csr_name(self, csr):
        return CSR_NAMES.get(csr, f"csr{csr}")

    def csr_read(self, csr):
        if csr == CSR_SSTATUS:
            return self.sstatus
        if csr == CSR_STVEC:
            return self.stvec
        if csr == CSR_SEPC:
            return self.sepc
        if csr == CSR_SCAUSE:
            return self.scause
        if csr == CSR_STVAL:
            return self.stval
        if csr == CSR_SSCRATCH:
            return self.sscratch
        if csr == CSR_SFLAGS:
            return self.pack_flags()
        raise ValueError(f"unknown CSR: {csr}")

    def csr_write(self, csr, value):
        value &= 0xFFFFFFFF
        if csr == CSR_SSTATUS:
            self.sstatus = value
            self.interrupt_enabled = bool(value & SSTATUS_SIE)
        elif csr == CSR_STVEC:
            self.stvec = value
            self.idt_base_pa = value
        elif csr == CSR_SEPC:
            self.sepc = value
            self.trap_return_pc = value
        elif csr == CSR_SCAUSE:
            self.scause = value
            self.trap_cause = value
        elif csr == CSR_STVAL:
            self.stval = value
            self.trap_value = value
        elif csr == CSR_SSCRATCH:
            self.sscratch = value
        elif csr == CSR_SFLAGS:
            self.unpack_flags(value)
        else:
            raise ValueError(f"unknown CSR: {csr}")

    # -----------------------------------------------------
    # DEBUGGER HELPERS
    # -----------------------------------------------------
    def add_breakpoint(self, addr):
        self.breakpoints.add(addr)

    def clear_breakpoint(self, addr):
        self.breakpoints.discard(addr)

    def clear_breakpoint_index(self, index):
        addrs = self.list_breakpoints()
        if 0 <= index < len(addrs):
            self.breakpoints.discard(addrs[index])

    def list_breakpoints(self):
        return sorted(self.breakpoints)

    def add_watchpoint_reg(self, reg):
        idx = reg & 0x1F
        self.watchpoints.append({
            "type": "reg",
            "reg": idx,
            "prev": self.r(idx),
        })
        return len(self.watchpoints) - 1

    def add_watchpoint_mem(self, addr, size=1):
        self.watchpoints.append({
            "type": "mem",
            "addr": addr,
            "size": size,
            "prev": bytes(self.mem_read_u8(addr + i, "r") for i in range(size)),
        })
        return len(self.watchpoints) - 1

    def clear_watchpoint(self, index):
        if 0 <= index < len(self.watchpoints):
            self.watchpoints.pop(index)

    def list_watchpoints(self):
        return list(self.watchpoints)

    def _watchpoint_current(self, watch):
        if watch["type"] == "reg":
            return self.r(watch["reg"])
        if watch["type"] == "mem":
            addr = watch["addr"]
            size = watch["size"]
            return bytes(self.mem_read_u8(addr + i, "r") for i in range(size))
        raise ValueError(f"unknown watchpoint type: {watch['type']}")

    def _check_watchpoints(self):
        for index, watch in enumerate(self.watchpoints):
            try:
                current = self._watchpoint_current(watch)
            except Exception:
                continue
            if current != watch["prev"]:
                watch["prev"] = current
                self.stop_reason = ("watchpoint", index)
                self.stop_info = {"index": index, "watch": watch, "current": current}
                return True
        return False
    # -----------------------------------------------------
    # div_trunc: Helper for integer division that truncates towards zero, consistent with C semantics.
    # This is used for the DIV and DIVU instructions to ensure correct behavior with negative operands.
    # -----------------------------------------------------

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
    # -----------------------------------------------------
    # disasm: Helper to convert a raw instruction (given by opcode and operands) into a human-readable assembly string.
    # This is used for debugging and trace output to show the executed instructions in a more understandable form.
    # -----------------------------------------------------

    def disasm(self, op, a, b, c, ext=None):
        target = ext if ext is not None else (a << 8) | b
        op_name = {
            0x00: "NOP",
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
            0x32: "JR",
            0x33: "JALR",
            0x40: "SVC",
            0x50: "SETPTBR",
            0x51: "SETIDTR",
            0x52: "ENABLEMMU",
            0x53: "ENABLEINT",
            0x54: "DISABLEINT",
            0x55: "IRET",
            0x56: "DEBUG",
            0x57: "GETCAUSE",
            0x58: "CSRR",
            0x59: "CSRW",
            0x5A: "CSRS",
            0x5B: "CSRC",
            0x5C: "SRET",
            0x5D: "CSRRW",
            0x5E: "EOI",
            0x5F: "TRACE",

            0xFF: "HLT",
        }.get(op)
        #-----------------------------------------------------------------------
        # op is the main opcode that determines the instruction type, while a, b, c 
        # are the operand fields that can represent registers, immediates, or offsets 
        # depending on the instruction format. 
        # The ext field is used for instructions that require a larger immediate value (like LI) 
        # and is passed in from the fetch-decode stage when needed.
        # ------------------------------------------------------------------------

        if op == 0x00:
            return "NOP"
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
        
        if op == 0x28:
            return f"NOT {self.reg_name(a)}; {self.reg_name(b)}"

        if op == 0x31:
            return "RET"

        if op == 0x32:
            return f"{op_name} {self.reg_name(a)}"
        if op == 0x33:
            return f"{op_name} {self.reg_name(a)}"

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
        if op == 0x57:
            return f"GETCAUSE {self.reg_name(a)}"
        if op == 0x58:
            return f"CSRR {self.reg_name(a)}, {self.csr_name(b)}"
        if op == 0x59:
            return f"CSRW {self.csr_name(b)}, {self.reg_name(a)}"
        if op == 0x5A:
            return f"CSRS {self.csr_name(b)}, {self.reg_name(a)}"
        if op == 0x5B:
            return f"CSRC {self.csr_name(b)}, {self.reg_name(a)}"
        if op == 0x5C:
            return "SRET"
        if op == 0x5D:
            return f"CSRRW {self.reg_name(a)}, {self.csr_name(b)}, {self.reg_name(c)}"
        if op == 0x5E:
            return f"EOI {self.reg_name(a)}"
        if op == 0x5F:
            return f"TRACE {c}"
        
        if op == 0xFF:
            return "HLT"
        #-------------------------------------------------------------
        # If the opcode is not recognized, return a default string indicating it's unknown, 
        # which can help with debugging or when encountering invalid instructions.
        #-------------------------------------------------------------
        return f"UNKNOWN 0x{op:02X}"
    # -----------------------------------------------------
    # trace_changes: Helper to generate a human-readable summary of all the changes to registers, 
    # flags, and memory that occurred during the execution of an instruction.
    # This is used for detailed trace output to understand the effects of each instruction on the CPU state.
    # -----------------------------------------------------

    def trace_changes(
        self,
        before_reg,
        before_sp,
        before_pc,
        before_z,
        before_n,
        before_c,
        before_v,
        before_running,
        mem_write,
        skip_regs=None,
        skip_sp=False,
        skip_mem=False,
        skip_flags=False,
    ):
        skip_regs = set() if skip_regs is None else {r & 0x1F for r in skip_regs}
        changes = []

        for i, (old, new) in enumerate(zip(before_reg, self.reg)):
            if i in skip_regs:
                continue
            if old != new:
                changes.append(f"{self.reg_name(i)}:0x{old:08X}->0x{new:08X}")

        if not skip_sp and before_sp != self.sp and before_reg[self.SP_REG] == self.reg[self.SP_REG]:
            changes.append(f"SP:0x{before_sp:08X}->0x{self.sp:08X}")

        if before_pc != self.pc:
            changes.append(f"PC:0x{before_pc:04X}->0x{self.pc:04X}")

        if not skip_flags and before_z != self.Z:
            changes.append(f"Z:{int(before_z)}->{int(self.Z)}")

        if not skip_flags and before_n != self.N:
            changes.append(f"N:{int(before_n)}->{int(self.N)}")

        if not skip_flags and before_c != self.C:
            changes.append(f"C:{int(before_c)}->{int(self.C)}")

        if not skip_flags and before_v != self.V:
            changes.append(f"V:{int(before_v)}->{int(self.V)}")

        if before_running != self.running:
            changes.append(f"RUN:{int(before_running)}->{int(self.running)}")

        if mem_write is not None and not skip_mem:
            addr, value, size = mem_write
            width = size * 2
            changes.append(f"MEM{size * 8}[0x{addr:08X}]=0x{value:0{width}X}")

        if not changes:
            return "no change"
        return " | ".join(changes)

    def trace_flags_full(self, before_z, before_n, before_c, before_v):
        return (
            f"FLAGS Z:{int(before_z)}->{int(self.Z)} "
            f"C:{int(before_c)}->{int(self.C)} "
            f"N:{int(before_n)}->{int(self.N)} "
            f"V:{int(before_v)}->{int(self.V)}"
        )

    def trace_shows_flags(self, op, b):
        return op == 0x04 or op == 0x5C or (op == 0x59 and b == CSR_SFLAGS)

    def trace_redundant_changes(self, op, a, b, c):
        skip_regs = set()
        skip_mem = False

        if op == 0x01:
            skip_regs.add(a & 0x1F)
        elif op in (0x02, 0x03, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x16, 0x17, 0x18, 0x19):
            skip_regs.add(a & 0x1F)
        elif op in (0x20, 0x21, 0x22, 0x26, 0x27):
            skip_regs.add(a & 0x1F)
        elif op in (0x23, 0x24, 0x25):
            skip_mem = True
        elif op == 0x11:
            skip_regs.add(a & 0x1F)
        elif op in (0x57, 0x58, 0x5D):
            skip_regs.add(a & 0x1F)

        return skip_regs, skip_mem

    def trace_reg_value(self, before_reg, idx):
        idx &= 0x1F
        if idx == self.ZERO_REG:
            return 0
        return before_reg[idx] & 0xFFFFFFFF

    def trace_operands(self, op, a, b, c, ext, before_reg, mem_write):
        def regv(idx):
            return self.trace_reg_value(before_reg, idx)

        def regfmt(idx):
            return f"{self.reg_name(idx)}=0x{regv(idx):08X}"

        def dstfmt(idx):
            old = regv(idx)
            new = self.r(idx)
            if old == new:
                return f"{self.reg_name(idx)}:0x{old:08X} unchanged"
            return f"{self.reg_name(idx)}:0x{old:08X}->0x{new:08X}"
        #-----------------------------------------------------------
        # op is the opcode that determines the instruction type, while a, b, c are the operand fields.
        # rd is the destination register index extracted from a, and regfmt(b) gives the source register value for b.
        # dstfmt(a) formats the destination register a by showing its old and new values,
        # while regfmt(b) and regfmt(c) format the source registers b and c similarly.
        # For memory instructions, it calculates the effective address and shows the old and new values of
        # the destination register or the memory location being accessed, along with the source register values and offsets.
        #-----------------------------------------------------------       

        if op == 0x01:
            if a & 0x80:
                rd = a & 0x1F
                return f"{dstfmt(rd)}; src {regfmt(b)}"
            return f"{dstfmt(a)}; imm=0x{self.imm16(b, c):08X}"

        if op == 0x0F:
            return "-"

        if op in (0x02, 0x03, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E):
            rhs = c & 0x7F if c & 0x80 else regv(c)
            rhs_name = f"#{rhs}" if c & 0x80 else f"{self.reg_name(c)}=0x{rhs:08X}"
            return f"{dstfmt(a)}; {regfmt(b)}, {rhs_name}"

        if op in (0x08, 0x16, 0x17, 0x18, 0x19):
            return f"{dstfmt(a)}; {regfmt(b)}, {regfmt(c)}"

        if op == 0x04:
            rhs = c & 0x7F if c & 0x80 else regv(b)
            rhs_name = f"#{rhs}" if c & 0x80 else f"{self.reg_name(b)}=0x{rhs:08X}"
            return f"{regfmt(a)}, {rhs_name}"

        if op in (0x05, 0x06, 0x07, 0x12, 0x13, 0x14, 0x15, 0x1A, 0x1B, 0x1C, 0x1D, 0x30):
            return f"target=0x{ext:08X}"

        if op == 0x10:
            return f"push {regfmt(a)}"

        if op == 0x11:
            return f"pop -> {dstfmt(a)}"

        if op in (0x20, 0x21, 0x22, 0x26, 0x27):
            off = regv(c & 0x1F) if c & 0x80 else c
            off_name = f"{self.reg_name(c & 0x1F)}=0x{off:08X}" if c & 0x80 else f"#{off}"
            addr = (regv(b) + off) & 0xFFFFFFFF
            return f"{dstfmt(a)}; addr=0x{addr:08X} ({regfmt(b)} + {off_name})"

        if op in (0x23, 0x24, 0x25):
            off = regv(c & 0x1F) if c & 0x80 else c
            off_name = f"{self.reg_name(c & 0x1F)}=0x{off:08X}" if c & 0x80 else f"#{off}"
            addr = (regv(b) + off) & 0xFFFFFFFF
            stored = ""
            if mem_write is not None:
                _, value, size = mem_write
                stored = f"; stored{size * 8}=0x{value:0{size * 2}X}"
            return f"src {regfmt(a)}; addr=0x{addr:08X} ({regfmt(b)} + {off_name}){stored}"

        if op in (0x32, 0x33):
            return regfmt(a)

        if op in (0x50, 0x51):
            return regfmt(a)

        if op == 0x57:
            return dstfmt(a)

        if op == 0x58:
            return f"{dstfmt(a)}; csr={self.csr_name(b)}"

        if op in (0x59, 0x5A, 0x5B):
            return f"csr={self.csr_name(b)}; src {regfmt(a)}"

        if op == 0x5D:
            return f"{dstfmt(a)}; csr={self.csr_name(b)}, src {regfmt(c)}"

        if op == 0x5E:
            return f"irq={regv(a) & 0xFF}; src {regfmt(a)}"

        return "-"

    # -----------------------------------------------------
    # MEMORY SAFETY
    # -----------------------------------------------------
    def check_physical_mem(self, paddr, size):
        if paddr < 0 or paddr + size > len(self.physical_memory):
            raise Exception(f"PHYS MEM OOB paddr=0x{paddr:08X} size={size}")
    #-----------------------------------------------------
    # translate: Helper to convert a virtual address to a physical address using the MMU, 
    # while handling page faults by raising traps.
    # This is used for all memory accesses that go through the MMU to ensure correct address
    # translation and trap handling for faults.
    #-----------------------------------------------------

    def translate(self, vaddr, access):
        try:
            paddr, _ = self.mmu.translate(vaddr, access, self.mode)
        except PageFault as exc:
            self.raise_trap(TRAP_PAGE_FAULT, vaddr)
            raise TrapDelivery()
        self.check_physical_mem(paddr, 1)
        return paddr
    #-----------------------------------------------------
    # require_supervisor: Helper to enforce that certain privileged instructions can only be executed in supervisor mode,
    # and to raise a trap if they are attempted in user mode.
    # This is used for instructions that should not be allowed in user mode, such as those
    # that manipulate the IDT or control registers, to ensure proper privilege separation and trap handling.
    #-----------------------------------------------------

    def require_supervisor(self, opname):
        """Reject privileged instructions while the CPU is in user mode."""
        if self.mode == MODE_USER:
            self.raise_trap(TRAP_ILLEGAL_MEM, 0)
            raise TrapDelivery()
    #-----------------------------------------------------  
    # raise_trap: Core helper to deliver a synchronous trap/exception to the guest kernel, 
    # saving all necessary context and state for the trap handler.
    # This is called whenever a fault occurs (e.g., divide-by-zero, 
    # page fault, illegal instruction) to transfer control to the appropriate 
    # trap handler in the guest kernel, while preserving the state of the interrupted thread 
    # and ensuring correct trap delivery semantics.
    #-----------------------------------------------------

    def raise_trap(self, vector, value=0, resume_pc=None):
        """
        Deliver a synchronous trap/exception to the guest kernel.

        This is called when a fault occurs (divide-by-zero, page fault, etc).
        The CPU saves context and vectors through the IDT to the handler.

        Args:
            vector: trap vector number (TRAP_DIVIDE_BY_ZERO, TRAP_PAGE_FAULT, etc)
            value: optional extra info (e.g., faulting address for page faults)
        """
        fault_pc = self.current_instr_pc if self.current_instr_pc is not None else self.pc
        was_interrupt_enabled = self.interrupt_enabled
        self.trap_epc = fault_pc
        return_pc = self.pc if resume_pc is None else resume_pc
        self.trap_return_pc = return_pc
        self.trap_cause = vector
        self.trap_value = value

        if self.mode == MODE_USER:
            self.sstatus &= ~SSTATUS_SPP
        else:
            self.sstatus |= SSTATUS_SPP
        self.mode = MODE_KERNEL

        # Save RISC-V-like supervisor trap state.
        self.sepc = fault_pc if resume_pc is None else resume_pc
        self.scause = vector
        self.stval = value
        self.sflags = self.pack_flags()
        if was_interrupt_enabled:
            self.sstatus |= SSTATUS_SPIE
        else:
            self.sstatus &= ~SSTATUS_SPIE
        self.sstatus &= ~SSTATUS_SIE
        self.interrupt_enabled = False

        # Preserve original register values that are used for trap arguments.
        # Guest trap handlers can save/restore R1/R2 themselves, but the VM
        # must restore the interrupted thread's original values on IRET.
        self.trap_saved_r1 = self.r(1)
        self.trap_saved_r2 = self.r(2)

        if self.traceint or self.trace_fault:
            if self.trace_output:
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
                else:
                    print("[TRAP INST] <no current instruction>")

        # Check if IDT base is set and interrupt delivery is enabled
        if self.idt_base_pa == 0:
            if self.trace_output:
                print(f"[TRAP FATAL] vector={vector} @ pc=0x{self.trap_epc:08X}, no IDT base set")
            self.running = False
            raise TrapDelivery()

        if not was_interrupt_enabled:
            if self.trace_output:
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

    # -----------------------------------------------------
    # MMIO INTERCEPTION
    # -----------------------------------------------------
    def is_mmio(self, paddr):
        # MMIO resides in pages 0x00100000 (UART), 0x00101000 (Timer/PIT), 0x00102000 (PIC)
        return 0x00100000 <= paddr < 0x00103000
    #-----------------------------------------------------
    # mmio_read and mmio_write: Helpers to handle memory-mapped I/O accesses by dispatching 
    # reads/writes to the appropriate device emulation based on the physical address.
    # These are called for any memory access that falls within the MMIO address range, 
    # allowing the emulator to simulate interactions with devices like the UART, timer, and PIC 
    # by intercepting reads/writes to their designated MMIO addresses and invoking the corresponding device methods.
    #-----------------------------------------------------
    def mmio_read(self, paddr):
        page = paddr & 0xFFFFF000
        offset = paddr & 0x00000FFF
        if page == 0x00100000:
            return self.uart.read_reg(offset)
        elif page == 0x00101000:
            return self.timer.read_reg(offset)
        elif page == 0x00102000:
            return self.pic.read_reg(offset)
        return 0

    def mmio_write(self, paddr, val):
        page = paddr & 0xFFFFF000
        offset = paddr & 0x00000FFF
        if page == 0x00100000:
            self.uart.write_reg(offset, val)
        elif page == 0x00101000:
            self.timer.write_reg(offset, val)
        elif page == 0x00102000:
            self.pic.write_reg(offset, val)
    #-----------------------------------------------------
    # physical_read_u8 and physical_write_u8: Helpers to perform byte-level reads/writes to physical memory,
    # while checking for MMIO and ensuring memory safety.
    # These are the core methods for accessing physical memory, 
    # and they first check if the address falls within the MMIO range to dispatch 
    # to device emulation, or if it's regular memory to perform the read/write while ensuring it does not go out of bounds.
    #-----------------------------------------------------

    def physical_read_u8(self, paddr):
        if self.is_mmio(paddr):
            return self.mmio_read(paddr) & 0xFF
        self.check_physical_mem(paddr, 1)
        return self.physical_memory[paddr]

    def physical_write_u8(self, paddr, val):
        if self.is_mmio(paddr):
            self.mmio_write(paddr, val)
            return
        self.check_physical_mem(paddr, 1)
        self.physical_memory[paddr] = val & 0xFF
    #trace virt to physical translation
    def trace_virt(self, bl_type,addr,access):
        if not self.trace_output:
            return
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

    # -----------------------------------------------------
    # PASSIVE MEMORY PEEKS (no traps, no tracing, no state mutation)
    # Used by debuggers/UIs to inspect memory around the current PC without
    # triggering raise_trap side effects when a virtual address is unmapped.
    # -----------------------------------------------------
    def _peek_paddr(self, vaddr, access="r"):
        if vaddr < 0:
            return None
        if not self.mmu.enabled:
            paddr = vaddr & 0xFFFFFFFF
        else:
            try:
                paddr, _ = self.mmu.translate(vaddr, access, self.mode)
            except PageFault:
                return None
        if 0 <= paddr < len(self.physical_memory) and not self.is_mmio(paddr):
            return paddr
        return None

    def mem_peek_u8(self, addr, access="r"):
        paddr = self._peek_paddr(addr, access)
        if paddr is None:
            return None
        return self.physical_memory[paddr]

    def mem_peek_u32(self, addr, access="r"):
        b0 = self.mem_peek_u8(addr, access)
        b1 = self.mem_peek_u8(addr + 1, access)
        b2 = self.mem_peek_u8(addr + 2, access)
        b3 = self.mem_peek_u8(addr + 3, access)
        if b0 is None or b1 is None or b2 is None or b3 is None:
            return None
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    #-----------------------------------------------------
    # hexdump and physical_hexdump: Helpers to display memory contents in a human
    # readable format, showing both hexadecimal byte values and their ASCII representation.
    # These are used for debugging and inspection purposes, allowing the user to visualize 
    # the contents of memory regions by showing the byte values in hex alongside their ASCII 
    # equivalents, which can help identify strings or
    # data structures in memory dumps.
    #----------------------------------------------------- 

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
        self.image_path = file
       
    #-----------------------------------------------------
    # reset: Helper to reset the CPU state to its initial conditions, with an option to 
    # preserve debugging state such as breakpoints and watchpoints.
    # This is used to restart the emulation from a clean state, while optionally 
    # keeping the debugging context intact, which can be useful for iterative testing and 
    # debugging without losing the configured breakpoints or watchpoints.
    #-----------------------------------------------------
    def reset(self, preserve_debug=True):
        preserve_breakpoints = set(self.breakpoints) if preserve_debug else set()
        preserve_watchpoints = [watch.copy() for watch in self.watchpoints] if preserve_debug else []
        preserve_tracevirt = self.tracevirt
        preserve_debug_mode = self.debug_mode
        preserve_trace = self.trace
        preserve_traceint = self.traceint
        preserve_trace_fault = self.trace_fault
        preserve_trace_handler = self.trace_handler
        preserve_debug_dump_range = self.debug_dump_range
        preserve_quiet = self.quiet
        image_path = self.image_path

        mem_size = self.MEM_SIZE
        page_size = self.mmu.page_size
        virtual_size = self.mmu.virtual_size
        tlb_size = self.mmu.tlb.capacity

        self.__init__(
            mem_size=mem_size,
            page_size=page_size,
            virtual_size=virtual_size,
            tlb_size=tlb_size,
            tracevirt=preserve_tracevirt,
            debug_mode=preserve_debug_mode,
            trace=preserve_trace,
        )
        self.traceint = preserve_traceint
        self.trace_fault = preserve_trace_fault
        self.trace_handler = preserve_trace_handler
        self.debug_dump_range = preserve_debug_dump_range
        self.quiet = preserve_quiet

        if image_path is not None:
            self.load_image(image_path)

        
        self.uart.reset()
        self.breakpoints = preserve_breakpoints
        self.watchpoints = []
        for watch in preserve_watchpoints:
            if watch["type"] == "reg":
                self.add_watchpoint_reg(watch["reg"])
            else:
                self.add_watchpoint_mem(watch["addr"], watch["size"])

        self.stop_reason = None
        self.stop_info = None
        self.running = True
        self.pc = 0

    # -----------------------------------------------------
    # FETCH
    # -----------------------------------------------------
    def fetch(self):
        instr = self.mem_read_u32(self.pc, access="x")
        self.pc += 4
        return instr
    #-----------------------------------------------------
    # _execute_instruction: Core method to execute a single instruction cycle, 
    # including fetching the instruction, decoding it, executing it, and handling 
    # all side effects such as updating registers, flags, memory, and checking for interrupts or traps.
    # This is the heart of the CPU emulation, where the instruction is processed 
    # according to its opcode and operands, and all the logic for each instruction 
    # type is implemented, along with the necessary checks for interrupts, traps, and device updates.
    #-----------------------------------------------------

    def _execute_instruction(self, trace=False):
        instr_pc = self.pc
        self.current_instr_pc = instr_pc
        self.current_instr = None
        try:
            #if self.pc in self.device_hooks:
            #    self.device_hooks[self.pc]()
            #    return
            # upon devices irg (tr/fals) raise pics irq bit 0 -timer tick bit 1 -uart event (TX/RX)
            if self.timer.tick():
                if self.trace_output and self.trace_events:
                    print("[TIMER tick]")
                self.pic.raise_irq(0)

            if self.uart.update():
                if self.trace_output and self.trace_events:
                    print("[UART RX/TX]")
                self.pic.raise_irq(1)
        # nesting/priority?
            if self.interrupt_enabled and not self.in_trap_handler:
                irq = self.pic.next_irq()
                if irq is not None:
                    if self.trace_output and self.trace_events:
                        print(f"[IRQ {irq}] pending..")
                    self.raise_trap(TRAP_IRQ, irq)

            instr = self.fetch()
            self.current_instr = instr

            op = (instr >> 24) & 0xFF
            a = (instr >> 16) & 0xFF
            b = (instr >> 8) & 0xFF
            c = instr & 0xFF
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
            # NOP
            # =================================================

            if op == 0x00:
                pass  # NOP
            # =================================================
            # ALU and MOV instructions
            # ================================================= 

            elif op == 0x01:
                if a & 0x80:
                    self.setr(a, self.r(b))
                else:
                    self.setr(a, self.imm16(b, c))

            elif op == 0x0F:
                self.setr(a, ext)

            elif op == 0x02:
                self.setr(a, self.r(b) + self.alu_rhs(c))

            elif op == 0x03:
                self.setr(a, self.r(b) - self.alu_rhs(c))

            elif op == 0x08:
                self.setr(a, self.r(b) * self.r(c))

            elif op == 0x16:
                rhs = self.signed32(self.r(c))
                if rhs == 0:
                    self.raise_trap(TRAP_DIVIDE_BY_ZERO, 0x16)
                else:
                    self.setr(a, self.div_trunc(self.signed32(self.r(b)), rhs))

            elif op == 0x17:
                lhs = self.signed32(self.r(b))
                rhs = self.signed32(self.r(c))
                if rhs == 0:
                    self.raise_trap(TRAP_DIVIDE_BY_ZERO, 0x17)
                else:
                    self.setr(a, lhs - self.div_trunc(lhs, rhs) * rhs)

            elif op == 0x18:
                rhs = self.r(c)
                if rhs == 0:
                    self.raise_trap(TRAP_DIVIDE_BY_ZERO, 0x18)
                else:
                    self.setr(a, self.r(b) // rhs)

            elif op == 0x19:
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

            elif op == 0x04:
                self.set_cmp_flags(self.r(a), self.alu_rhs(c) if c & 0x80 else self.r(b))

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

            elif op == 0x10:
                self.push(self.r(a))

            elif op == 0x11:
                self.setr(a, self.pop())
            #-------------------------------------------------
            # op is instructions like LOAD/STORE with register+offset addressing, 
            # where the effective address is calculated as the value in the base register 
            # plus an offset that can be either an immediate or another register.
            # For LOAD instructions (0x20-0x22, 0x26-0x27), it reads from the calculated 
            # memory address and stores the value in the destination register, 
            
            # while for STORE instructions (0x23-0x25), it writes the value from the 
            # source register to the calculated memory address. The offset can be 
            # a small immediate value (if the high bit of c is not set) or 
            # the value of another register (if the high bit of c is set), 
            # allowing for flexible addressing modes. 
            # The disassembly output for these instructions includes the effective address calculation 
            # and the source/destination register values, along with any offsets used in the address calculation.
            #-------------------------------------------------

            elif op in (0x20, 0x21, 0x22, 0x26, 0x27):
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

            elif op in (0x23, 0x24, 0x25):
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
            
            elif op == 0x28:
                self.setr(a, ~self.r(b))

            elif op == 0x30:
                self.setr(self.LR_REG, self.pc)
                self.pc = ext

            elif op == 0x31:
                self.pc = self.r(self.LR_REG)

            elif op == 0x32:
                self.pc = self.reg[a]

            elif op == 0x33:
                self.reg[15] = self.pc
                self.pc = self.reg[a]
            #----------------------------------------
            # op 0x40 is a special SYSCALL instruction that triggers a system call trap to the guest kernel,
            # passing the syscall number in register a. This allows the guest code to request 
            # services from the kernel, and the emulator raises a trap with the appropriate vector 
            # and arguments for the kernel to handle the system call.
            #----------------------------------------

            elif op == 0x40:
                self.raise_trap(TRAP_SYSCALL, a, resume_pc=self.pc)

            elif op == 0x56:
                debug_delay = (a << 16) | (b << 8) | c
                if self.debug_mode is not None:
                    if self.debug_mode == 0:
                        dump_short(self)
                    elif self.debug_mode == 1:
                        dump_all(self)
                    else:
                        dump_debug2(self, self.debug_dump_range)
                    if debug_delay:
                        time.sleep(debug_delay)
                    self.raise_trap(TRAP_DEBUG, debug_delay, resume_pc=self.pc)
                elif debug_delay:
                    time.sleep(debug_delay)

            elif op == 0x5F:
                trace_val = (a << 16) | (b << 8) | c
                if trace_val == 0:
                    self.trace = False
                    self.tracevirt = False
                elif trace_val == 1:
                    self.trace = True
                elif trace_val == 2:
                    self.trace = True
                    self.tracevirt = True

            elif op == 0x50:
                self.require_supervisor("SETPTBR")
                new_ptbr = self.r(a)
                if self.mmu.ptbr_pa != new_ptbr:
                    self.mmu.ptbr_pa = new_ptbr
                    self.mmu.flush_tlb(preserve_global=True)

            elif op == 0x51:
                self.require_supervisor("SETIDTR")
                self.idt_base_pa = self.r(a)
                self.stvec = self.r(a)

            elif op == 0x52:
                self.require_supervisor("ENABLEMMU")
                self.mmu.enabled = True

            elif op == 0x53:
                self.require_supervisor("ENABLEINT")
                self.interrupt_enabled = True
                self.sstatus |= SSTATUS_SIE

            elif op == 0x54:
                self.require_supervisor("DISABLEINT")
                self.interrupt_enabled = False
                self.sstatus &= ~SSTATUS_SIE

            elif op == 0x55:
                self.setr(1, self.trap_saved_r1)
                self.setr(2, self.trap_saved_r2)
                self.in_trap_handler = False
                self.pc = self.trap_return_pc

            elif op == 0x57:
                self.setr(a, self.scause)

            elif op == 0x58:
                self.setr(a, self.csr_read(b))

            elif op == 0x59:
                self.require_supervisor("CSRW")
                self.csr_write(b, self.r(a))

            elif op == 0x5A:
                self.require_supervisor("CSRS")
                self.csr_write(b, self.csr_read(b) | self.r(a))

            elif op == 0x5B:
                self.require_supervisor("CSRC")
                self.csr_write(b, self.csr_read(b) & ~self.r(a))
            #-------------------------------------------------------
            # op 0x5C is a special SRET instruction that returns from 
            # a trap handler back to the interrupted code,
            # restoring the CPU state from the saved trap context. This includes 
            # setting the program counter to the saved EPC, 
            # restoring the mode (user/kernel) based on the SPP bit, 
            # and restoring the interrupt enable state based on the SPIE bit.
            #  
            # This allows the guest kernel's trap handler to return control back 
            # to the user code that was interrupted, while ensuring that the CPU state 
            # is correctly restored to continue execution seamlessly.
            #-------------------------------------------------------

            elif op == 0x5C:
                self.require_supervisor("SRET")
                self.unpack_flags(self.sflags)
                self.mode = MODE_KERNEL if self.sstatus & SSTATUS_SPP else MODE_USER
                if self.sstatus & SSTATUS_SPIE:
                    self.sstatus |= SSTATUS_SIE
                    self.interrupt_enabled = True
                else:
                    self.sstatus &= ~SSTATUS_SIE
                    self.interrupt_enabled = False
                self.sstatus |= SSTATUS_SPIE
                self.sstatus &= ~SSTATUS_SPP
                self.in_trap_handler = False
                self.pc = self.sepc

            elif op == 0x5D:
                self.require_supervisor("CSRRW")
                old_csr = self.csr_read(b)
                new_csr = self.r(c)
                self.csr_write(b, new_csr)
                self.setr(a, old_csr)

            elif op == 0x5E:
                self.require_supervisor("EOI")
                self.pic.ack(self.r(a) & 0xFF)

            elif op == 0xFF:
                self.running = False

            else:
                self.raise_trap(TRAP_INVALID_INSTR, op)

            if self.trace_output and (self.trace or (self.trace_handler and self.in_trap_handler)):
                operands = self.trace_operands(op, a, b, c, ext, before_reg, mem_write)
                skip_regs, skip_mem = self.trace_redundant_changes(op, a, b, c)
                show_flags = self.trace_shows_flags(op, b)
                changes = self.trace_changes(
                    before_reg,
                    before_sp,
                    pc_before_exec,
                    before_z,
                    before_n,
                    before_c,
                    before_v,
                    before_running,
                    mem_write,
                    skip_regs=skip_regs,
                    skip_mem=skip_mem,
                    skip_flags=show_flags,
                )
                detail_parts = []
                if operands != "-":
                    detail_parts.append(operands)
                if show_flags:
                    detail_parts.append(self.trace_flags_full(before_z, before_n, before_c, before_v))
                if changes != "no change":
                    detail_parts.append(changes)
                if not detail_parts:
                    detail_parts.append("no change")
                details = " ; ".join(detail_parts)
                print(
                    f"PC:{instr_pc:08X}   {self.disasm(op, a, b, c, ext):19} "
                    f"; {details} "
                    f"; OP=0x{op:02X} (0x{instr:08X})"
                )
            if syscall_message and self.trace_output:
                print(syscall_message)
        finally:
            self.current_instr_pc = None
    #-----------------------------------------------------
    # step: Helper to execute a single instruction and return whether the CPU is still running,
    # while also handling traps and checking watchpoints. 
    # This is used for stepping through execution one instruction at a time, 
    # allowing for fine-grained debugging and inspection of the CPU state after each instruction, 
    # while also ensuring that any traps or watchpoints are properly handled to stop execution when necessary.
    # -----------------------------------------------------           

    def step(self, trace=False):
        self.stop_reason = None
        self.stop_info = None
        try:
            self._execute_instruction(trace=trace)
        except TrapDelivery:
            self.stop_reason = ("trap", self.trap_cause)
            self.stop_info = {"cause": self.trap_cause, "pc": self.pc}
            return False

        if self._check_watchpoints():
            return False

        return self.running

    # -----------------------------------------------------
    # RUN LOOP
    # -----------------------------------------------------
    def run(self, start=0, trace=False):
        self.pc = start
        self.running = True

        steps = 0
        MAX_STEPS = 10_000_000

        # If we're resuming AT a breakpoint, skip it on the first iteration so
        # 'continue' makes forward progress instead of immediately re-stopping.
        skip_initial_bp = self.pc in self.breakpoints

        while self.running:
            if self.pc in self.breakpoints and not skip_initial_bp:
                self.stop_reason = ("breakpoint", self.pc)
                self.stop_info = {"pc": self.pc}
                break
            skip_initial_bp = False

            steps += 1
            if steps > MAX_STEPS:
                if not self.quiet:
                    print("[CPU] MAX STEPS REACHED -> STOP")
                break

            try:
                self._execute_instruction(trace=trace)
            except TrapDelivery:
                # Trap delivery is part of normal guest execution: the trap
                # has been vectorized into the guest kernel. Continue running
                # until a real breakpoint/watchpoint/halt occurs.
                if not self.running:
                    self.stop_reason = ("trap", self.trap_cause)
                    self.stop_info = {"cause": self.trap_cause, "pc": self.pc}
                    break
                continue

            if self._check_watchpoints():
                break

        if not self.quiet:
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
        "--traceevents",
        action="store_true",
        help="print timer, UART, and pending IRQ event messages"
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="print VM boot and halt status messages"
    )

    parser.add_argument(
        "--debug",
        type=int,
        choices=[0, 1, 2],
        help="enable debug dumps: 0=short, 1=full, 2=MMU/process view"
    )
    args = parser.parse_args()

    cpu = CPU(
        mem_size=int(args.mem_size, 0),
        page_size=int(args.page_size, 0),
        virtual_size=int(args.virtual_size, 0),
        tlb_size=int(args.tlb_size, 0),
        tracevirt=args.tracevirt,
        debug_mode=args.debug,
        trace=args.trace,
       
    )
    cpu.traceint = args.traceint
    cpu.trace_fault = args.tracefault
    cpu.trace_handler = args.tracehandler
    cpu.trace_events = args.traceevents
    cpu.quiet = not args.verbose
    if args.dump and args.debug == 2:
        cpu.debug_dump_range = (int(args.dump[0], 0), int(args.dump[1], 0))
    if args.no_mmu:
        cpu.mmu.enabled = False

    cpu.load_image("memory.img")

    if args.verbose:
        print("=== KR32 BOOT ===")
        print("[BOOT] Image loaded")
        print("[BOOT] Reset CPU state")
        print("[BOOT] Starting execution")

    cpu.run(0)

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

    if args.verbose:
        print("[BOOT] Done")


if __name__ == "__main__":
    main()
