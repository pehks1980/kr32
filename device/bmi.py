#=========================================================
# BMI - Block Message Interface
#
# Host mailbox device used by NSFS and future host services.
#
# KR32 writes a request into BMI_BUF_WRITE,
# rings the doorbell,
# VM processes the request,
# VM writes reply into BMI_BUF_READ,
# KR32 continues.
#=========================================================

# BMI MMIO registers

BMI_REG_BASE = 0x17000

BMI_STATUS    = BMI_REG_BASE + 0
BMI_DOORBELL  = BMI_REG_BASE + 4
BMI_REPLY     = BMI_REG_BASE + 8

BMI_TX_BUFFER = 0x15000
BMI_RX_BUFFER = 0x16000
BMI_BUF_WRITE = BMI_TX_BUFFER
BMI_BUF_READ = BMI_RX_BUFFER

BMI_HDR_OPCODE = 0
BMI_HDR_FLAGS = 2
BMI_HDR_NAMESPACE = 4
BMI_HDR_PAYLOAD_LEN = 8
BMI_HDR_SIZEOF = 12

BMI_IDLE  = 0
BMI_READY = 1
BMI_BUSY  = 2
BMI_DONE  = 3
BMI_ERROR = 4

class BMIDevice:

    def __init__(self, cpu):
        self.cpu = cpu

    def phys_read_u8(self, paddr):
        self.cpu.check_physical_mem(paddr, 1)
        return self.cpu.physical_memory[paddr]

    def phys_read_u16(self, paddr):
        lo = self.phys_read_u8(paddr)
        hi = self.phys_read_u8(paddr + 1)
        return lo | (hi << 8)

    def phys_read_u32(self, paddr):
        return (
            self.phys_read_u8(paddr)
            | (self.phys_read_u8(paddr + 1) << 8)
            | (self.phys_read_u8(paddr + 2) << 16)
            | (self.phys_read_u8(paddr + 3) << 24)
        )

    def phys_write_u8(self, paddr, value):
        self.cpu.check_physical_mem(paddr, 1)
        self.cpu.physical_memory[paddr] = value & 0xFF

    def phys_write_u16(self, paddr, value):
        self.phys_write_u8(paddr, value & 0xFF)
        self.phys_write_u8(paddr + 1, (value >> 8) & 0xFF)

    def phys_write_u32(self, paddr, value):
        self.phys_write_u8(paddr, value & 0xFF)
        self.phys_write_u8(paddr + 1, (value >> 8) & 0xFF)
        self.phys_write_u8(paddr + 2, (value >> 16) & 0xFF)
        self.phys_write_u8(paddr + 3, (value >> 24) & 0xFF)

    def read_reg(self, offset):
        addr = BMI_REG_BASE + offset
        return self.phys_read_u32(addr)

    def write_reg(self, offset, value):
        addr = BMI_REG_BASE + offset
        self.phys_write_u32(addr, value)

    def update(self):
        status = self.read_reg(0)

        if status != BMI_READY:
            return

        self.process()

    def process(self):
        self.write_reg(0, BMI_BUSY)

        try:
            packet = self.read_packet()
            reply = self.dispatch(packet)
            self.write_reply(reply)
            self.write_reg(0, BMI_DONE)

        except Exception as e:
            print("[BMI]", e)
            self.write_reg(0, BMI_ERROR)

        self.write_reg(4, 0)

    def read_packet(self):
        base = BMI_BUF_WRITE
        opcode = self.phys_read_u16(base + BMI_HDR_OPCODE)
        flags = self.phys_read_u16(base + BMI_HDR_FLAGS)
        namespace = self.phys_read_u32(base + BMI_HDR_NAMESPACE)
        length = self.phys_read_u32(base + BMI_HDR_PAYLOAD_LEN)
        payload = bytearray()

        for i in range(length):
            payload.append(self.phys_read_u8(base + BMI_HDR_SIZEOF + i))

        return {
            "opcode": opcode,
            "flags": flags,
            "namespace": namespace,
            "payload": bytes(payload)
        }

    def dispatch(self, packet):
        print()
        print("========= BMI =========")
        print("opcode    :", packet["opcode"])
        print("namespace :", packet["namespace"])
        print("payload   :", packet["payload"])
        print("=======================")
        return {
            "status": 0,
            "payload": b""
        }

    def write_reply(self, reply):
        base = BMI_BUF_READ
        self.phys_write_u16(base + BMI_HDR_OPCODE, 0)
        self.phys_write_u16(base + BMI_HDR_FLAGS, reply["status"])
        self.phys_write_u32(base + BMI_HDR_NAMESPACE, 0)
        payload = reply["payload"]
        self.phys_write_u32(base + BMI_HDR_PAYLOAD_LEN, len(payload))

        for i, b in enumerate(payload):
            self.phys_write_u8(base + BMI_HDR_SIZEOF + i, b)
