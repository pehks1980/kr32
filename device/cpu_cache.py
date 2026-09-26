
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

    # read byte from cache
    def read_u8(self, address):
        """Read one byte"""
        line = (address // self.line_size) % self.lines
        tag = address // (self.line_size * self.lines)
        offset = address % self.line_size

        # if data is in this cache line is actual get byte from cache
        if self.valid[line] and self.tags[line] == tag:
            self.hits += 1
            return self.data[line][offset]

        self.misses += 1

        base = address - offset #get start address of line of the block (tag)

        for i in range(self.line_size): #load fresh block to cache from memory
            self.data[line][i] = self.memory[base + i]

        self.tags[line] = tag  #put a tag on it (for this cache line)
        self.valid[line] = True #make this line valid (it has actual memory read now)

        return self.data[line][offset] #we read data to cache (its actual) - so return it from cache also
    
    #write a byte to memory and update cache
    def write_u8(self, address, value):
        """Write one byte"""
        line = (address // self.line_size) % self.lines
        tag = address // (self.line_size * self.lines)
        offset = address % self.line_size

        # if this write can be written (valid,block okay) to cache 
        # - write to it (we found block is in cache and its valid 
        # so we - update current valid cache line)
        if self.valid[line] and self.tags[line] == tag:
            self.hits += 1
            self.data[line][offset] = value & 0xFF
        else:
            self.misses += 1

            base = address - offset #get start of this line in this block (tag)

            for i in range(self.line_size):
                self.data[line][i] = self.memory[base + i] #read this line of this block

            self.tags[line] = tag
            self.valid[line] = True
            self.data[line][offset] = value & 0xFF #put byte into this line of this block into cache 
            # we update cache with new data byte here 

        self.memory[address] = value & 0xFF #write also it to physical memory as we do write op here
        # cache line is updted with new value,block, made valid (has actual memory in this line)
        # at exit: cache is valid and memory is written! greeat! all happy!


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