class PIC:
    """Memory Mapped I/O (MMIO) Programmable Interrupt Controller (PIC) for KR32.
    
    Exposes interrupt routing control mapped to memory:
      - Offset 0 (PIC_MASK): Enabled IRQs bitmask (R/W).
      - Offset 4 (PIC_PENDING): Pending IRQs bitmask (R).
      - Offset 8 (PIC_ACK): Write IRQ number to acknowledge/EOI that interrupt (W).
    """
    def __init__(self):
        self.pending = 0  # bitmask of pending IRQs
        self.enabled = 0  # bitmask of enabled IRQs
        self.irq_mask = 0xFF  # allow up to 8 IRQs for now

    def raise_irq(self, irq):
        """Signal that an IRQ has been asserted by a device."""
        if irq < 8:
            self.pending |= (1 << irq)

    def next_irq(self):
        """Return the lowest pending enabled IRQ, or None."""
        for i in range(8):
            if (self.pending & (1 << i)) and (self.enabled & (1 << i)):
                return i
        return None

    def ack(self, irq):
        """Acknowledge (clear) a pending interrupt."""
        if irq < 8:
            self.pending &= ~(1 << irq)

    def enable_irq(self, irq):
        """Enable a specific IRQ vector (for compatibility)."""
        if irq < 8:
            self.enabled |= (1 << irq)

    def disable_irq(self, irq):
        """Disable a specific IRQ vector (for compatibility)."""
        if irq < 8:
            self.enabled &= ~(1 << irq)

    def read_reg(self, offset):
        """Read a register from the PIC based on byte offset."""
        if offset == 0:
            # PIC_MASK: Return enabled IRQ mask
            return self.enabled & 0xFF
        elif offset == 4:
            # PIC_PENDING: Return pending IRQ mask
            return self.pending & 0xFF
        return 0

    def write_reg(self, offset, val):
        """Write a register to the PIC based on byte offset."""
        if offset == 0:
            # PIC_MASK: Write enabled IRQ mask
            self.enabled = val & 0xFF
        elif offset == 8:
            # PIC_ACK: Acknowledge the given IRQ vector
            self.ack(val & 0xFF)