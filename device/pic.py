class PIC:
    def __init__(self):
        self.pending = 0  # bitmask of pending IRQs
        self.enabled = 0  # bitmask of enabled IRQs
        self.irq_mask = 0xFF  # allow up to 8 IRQs for now

    def raise_irq(self, irq):
        if irq < 8:
            self.pending |= (1 << irq)

    def next_irq(self):
        # Return the lowest pending enabled IRQ, or None
        for i in range(8):
            if (self.pending & (1 << i)) and (self.enabled & (1 << i)):
                return i
        return None

    def ack(self, irq):
        if irq < 8:
            self.pending &= ~(1 << irq)

    def enable_irq(self, irq):
        if irq < 8:
            self.enabled |= (1 << irq)

    def disable_irq(self, irq):
        if irq < 8:
            self.enabled &= ~(1 << irq)