from collections import OrderedDict


class TLB:
    def __init__(self, capacity=64):
        if capacity <= 0:
            raise ValueError("TLB capacity must be positive")
        self.capacity = capacity
        self.entries = OrderedDict()

    def lookup(self, vpn):
        entry = self.entries.get(vpn)
        if entry is None:
            return None
        self.entries.move_to_end(vpn)
        return entry

    def insert(self, vpn, ppn, flags):
        self.entries[vpn] = (ppn, flags)
        self.entries.move_to_end(vpn)
        while len(self.entries) > self.capacity:
            self.entries.popitem(last=False)

    def flush(self, preserve_flag=0):
        """Flush cached translations, optionally keeping global entries."""
        if not preserve_flag:
            self.entries.clear()
            return

        self.entries = OrderedDict(
            (vpn, entry)
            for vpn, entry in self.entries.items()
            if entry[1] & preserve_flag
        )

    def flush_vpn(self, vpn):
        self.entries.pop(vpn, None)
