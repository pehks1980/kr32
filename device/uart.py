import sys
import select

class UARTDevice:
    """Memory Mapped I/O (MMIO) UART Device for KR32.
    
    Exposes a standard serial interface mapped to memory:
      - Offset 0 (UART_DATA): Read to pop RX byte, Write to transmit TX byte.
      - Offset 4 (UART_STATUS): Status bits (Bit 0 = RX Ready, Bit 1 = TX Ready).
      - Offset 8 (UART_CTRL): Control bits (Bit 0 = RX Interrupt Enable, Bit 1 = TX Interrupt Enable).
    """

    def __init__(self):
        # FIFO buffer for received characters
        self.rx_fifo = []
        self.tx_fifo = []
        self.tx_output = []
        self.tx_capacity = 1024 #16
        self.tx_drain_period = 256
        self.tx_drain_counter = 0
        # Control register: Bit 0 = RX Interrupt Enable, Bit 1 = TX Interrupt Enable
        self.rx_tx_int_enable = 0
        self.tx_was_full = False

    def reset(self):
        """Reset the UART device state."""
        self.rx_fifo = []
        self.tx_fifo = []
        self.tx_output = []
        self.tx_drain_counter = 0
        self.rx_tx_int_enable = 0
        self.tx_was_full = False

    def read_reg(self, offset):
        """Read a register from the UART device based on byte offset."""
        if offset == 0:
            # UART_DATA: Read next byte from RX FIFO queue
            if self.rx_fifo:
                val = self.rx_fifo.pop(0)
                # Keep it within 8-bit unsigned boundary
                return val & 0xFF
            return 0
        elif offset == 4:
            # UART_STATUS: (R/O)
            # Bit 0 (1): RX Ready (FIFO has data)
            # Bit 1 (2): TX Ready (TX FIFO has space)
            status = 0
            if self.rx_fifo: #if atleast one byte in rx_queue
                status |= 1  # set RX 1 ready
            if len(self.tx_fifo) < self.tx_capacity: #if tx_fifo has a room limit is tx_capacity
                status |= 2 # good to TX
            else:
                self.tx_was_full = True
            return status
        elif offset == 8:
            # UART_CTRL: Return the current interrupt control mask
            return self.rx_tx_int_enable & 0xFF
        return 0

    def write_reg(self, offset, val):
        """Write a register to the UART device based on byte offset."""
        if offset == 0:
            # UART_DATA: Queue a byte for transmit if the TX FIFO has space.
            char_val = val & 0xFF
            if len(self.tx_fifo) < self.tx_capacity:
                self.tx_fifo.append(char_val)
                if len(self.tx_fifo) >= self.tx_capacity:

                    # set tx full if last possible byte is written to tx_fifo
                    self.tx_was_full = True #tx_fifo is full!

        elif offset == 8:
            # UART_CTRL: Update interrupt mask.
            self.rx_tx_int_enable = val & 0xFF

    def update(self):
        """Advance UART RX/TX state.
        
        Returns True if an enabled UART interrupt condition was raised.
        note runs by every machine cycle in vmp
        """
        irq = False
        try:
            # Verify stdin is a TTY and has data available to avoid blocking
            if sys.stdin.isatty():
                # select with timeout=0 is completely non-blocking
                r, _, _ = select.select([sys.stdin], [], [], 0)
                if r:
                    char = sys.stdin.read(1)
                    if char:
                        self.rx_fifo.append(ord(char))
                        #if uart not masked set fire irq
                        if self.rx_tx_int_enable & 1:
                            irq = True
        except Exception:
            pass

        if self.tx_fifo:
            self.tx_drain_counter += 1
            if self.tx_drain_counter >= self.tx_drain_period:
                self.tx_drain_counter = 0
                #after drain ctr we print one lettwe
                char_val = self.tx_fifo.pop(0)
                self.tx_output.append(char_val)
                try:
                    sys.stdout.write(chr(char_val))
                    sys.stdout.flush()
                except Exception:
                    pass
                if self.tx_was_full and len(self.tx_fifo) < self.tx_capacity:
                    self.tx_was_full = False
                    if self.rx_tx_int_enable & 2:
                        irq = True

        return irq
