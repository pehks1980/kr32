class PIT:
    def __init__(self, frequency):
        self.frequency = frequency
        self.counter = 0        
    def tick(self):
        self.counter += 1
        if self.counter >= self.frequency:
            self.counter = 0
            return True
        return False    