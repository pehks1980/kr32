
"""
    Simple direct-mapped cache for KR32.

    CPU talks to the cache.
    Cache talks to main memory.
    """

class Cache:
    def __init__(self, memory, lines=16, line_size=16):
        self.memory = memory
        self.lines = lines
        self.line_size = line_size

        self.data = [
            bytearray(line_size)
            for _ in range(lines)
        ]

        self.tags = [0] * lines
        self.valid = [False] * lines

        self.hits = 0
        self.misses = 0

    def read_u8(self, address):
        """Read one 32-bit word."""
        line = (address // self.line_size) % self.lines
        tag = address // (self.line_size * self.lines)
        offset = address % self.line_size

        if self.valid[line] and self.tags[line] == tag:
            self.hits += 1
            return self.data[line][offset]

        self.misses += 1

        base = address - offset

        for i in range(self.line_size):
            self.data[line][i] = self.memory[base + i]

        self.tags[line] = tag
        self.valid[line] = True

        return self.data[line][offset]

    def write_u8(self, address, value):
        """Write one 32-bit word."""
        line = (address // self.line_size) % self.lines
        tag = address // (self.line_size * self.lines)
        offset = address % self.line_size

        if self.valid[line] and self.tags[line] == tag:
            self.hits += 1
            self.data[line][offset] = value & 0xFF
        else:
            self.misses += 1

            base = address - offset

            for i in range(self.line_size):
                self.data[line][i] = self.memory[base + i]

            self.tags[line] = tag
            self.valid[line] = True
            self.data[line][offset] = value & 0xFF

        self.memory[address] = value & 0xFF


    def _line_index(self, address):
        return (address // self.words_per_line) % self.lines

    def _offset(self, address):
        return address % self.words_per_line

    def _tag(self, address):
        return address // (self.words_per_line * self.lines)

    def _load_line(self, address, line, tag):
        """Load an entire cache line from RAM."""

        base = address - (address % self.words_per_line)

        for i in range(self.words_per_line):
            self.data[line][i] = self.memory[base + i]

        self.tags[line] = tag
        self.valid[line] = True

    def stats(self):
        total = self.hits + self.misses

        hit_rate = (
            self.hits / total * 100
            if total
            else 0
        )

        return {
            "accesses": total,
            "hits": self.hits,
            "misses": self.misses,
            "hit_rate": hit_rate,
        }