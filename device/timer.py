import time

class PIT:
    def __init__(self, period_ms=1):
        self.period_ms = period_ms
        self.last_tick = time.time()
        
    def tick(self):
        now = time.time()
        if (now - self.last_tick) * 1000 >= self.period_ms:
            self.last_tick = now
            return True
        return False
        
    def reset(self):
        self.last_tick = time.time()
        
    def set_frequency(self, freq):
        # For compatibility, interpret freq as period in ms
        self.period_ms = freq
        self.reset()    