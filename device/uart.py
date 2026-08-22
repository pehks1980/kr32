import os
import sys
import select
import termios

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
        self.tx_drain_period = 1 #256
        self.tx_drain_counter = 0
        self.last_rx_char = None
        # Control register: Bit 0 = RX Interrupt Enable, Bit 1 = TX Interrupt Enable
        self.rx_tx_int_enable = 0
        self.tx_was_full = False
        self._stdin_fd = None
        self._stdin_termios = None
        self._stdin_cbreak = False
        self._host_fd = None

    def attach_host_fd(self, fd):
        """Use an externally managed terminal fd for debugger I/O."""
        self._host_fd = fd

    def reset(self):
        """Reset the UART device state."""
        self.rx_fifo = []
        self.tx_fifo = []
        self.tx_output = []
        self.tx_drain_counter = 0
        self.rx_tx_int_enable = 0
        self.tx_was_full = False
        self.last_rx_char = None

    def _prepare_stdin(self):
        """Disable canonical line buffering while keeping terminal echo enabled."""
        if not hasattr(sys.stdin, "fileno"):
            return
        try:
            fd = sys.stdin.fileno()
            if self._stdin_fd is None:
                self._stdin_fd = fd
            if not self._stdin_cbreak:
                self._stdin_termios = termios.tcgetattr(fd)
                attrs = list(self._stdin_termios)
                attrs[3] &= ~(termios.ICANON | termios.IEXTEN | termios.ECHOCTL)
                attrs[3] |= termios.ECHO
                attrs[6][termios.VMIN] = 1
                attrs[6][termios.VTIME] = 0
                termios.tcsetattr(fd, termios.TCSANOW, attrs)
                self._stdin_cbreak = True
        except Exception:
            pass

    def _restore_stdin(self):
        if self._stdin_fd is not None and self._stdin_termios is not None and self._stdin_cbreak:
            try:
                termios.tcsetattr(self._stdin_fd, termios.TCSADRAIN, self._stdin_termios)
            except Exception:
                pass
            self._stdin_cbreak = False

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
            # Verify the input fd is ready before reading so the VM never blocks.
            if self._host_fd is not None or sys.stdin.isatty():
                fd = self._host_fd
                if fd is None:
                    self._prepare_stdin()
                    fd = self._stdin_fd if self._stdin_fd is not None else sys.stdin.fileno()
                # select with timeout=0 is completely non-blocking
                r, _, _ = select.select([fd], [], [], 0)
                if r:
                    char = os.read(fd, 1)
                    if char:
                        char = char.decode("utf-8", errors="replace")

                        if char in ('\x7f', '\b'):
                            # Normalize DEL/backspace to a single backspace byte so the guest console
                            # can treat it as line editing without emitting caret-style control noise.
                            char = '\b'
                            try:
                                if self._host_fd is None:
                                    sys.stdout.write('\b \b')
                                    sys.stdout.flush()
                            except Exception:
                                pass

                        if char == '\r':
                            # Normalize Enter to a single LF terminator so the guest sees one line end.
                            char = '\n'
                            self.rx_fifo.append(ord(char))
                            self.last_rx_char = '\r'
                        elif char == '\n' and self.last_rx_char == '\r':
                            # The terminal may emit CRLF; drop the duplicated LF and keep only one line end.
                            self.last_rx_char = '\n'
                        else:
                            self.rx_fifo.append(ord(char))
                            self.last_rx_char = char

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
                    if self._host_fd is None:
                        sys.stdout.write(chr(char_val))
                        sys.stdout.flush()
                    else:
                        os.write(self._host_fd, bytes((char_val,)))
                except Exception:
                    pass
                if self.tx_was_full and len(self.tx_fifo) < self.tx_capacity:
                    self.tx_was_full = False
                    if self.rx_tx_int_enable & 2:
                        irq = True

        return irq
