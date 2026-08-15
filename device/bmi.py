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

from device.nsfs import NSFSStore

# BMI MMIO registers

BMI_REG_BASE = 0x17000  #set the base address of BMI registers MMIO

BMI_STATUS    = BMI_REG_BASE + 0    #STATUS register - holds the current status of the BMI device   
BMI_DOORBELL  = BMI_REG_BASE + 4    #DOORBELL register - used to signal the VM that a request is ready to be processed
BMI_REPLY     = BMI_REG_BASE + 8    #REPLY register - holds the status of the last processed request

BMI_TX_BUFFER = 0x15000     #TX_BUFFER - holds the request data written by KR32 to be processed by the VM
BMI_RX_BUFFER = 0x16000     #RX_BUFFER - holds the reply data written by the VM to be read by KR32
BMI_BUF_WRITE = BMI_TX_BUFFER
BMI_BUF_READ = BMI_RX_BUFFER

BMI_HDR_OPCODE = 0  #BMI PACKET HEADER - OPCODE field - specifies the operation to be performed
BMI_HDR_FLAGS = 2   #BMI PACKET HEADER - FLAGS field - specifies additional information about the request
BMI_HDR_NAMESPACE = 4 #BMI PACKET HEADER - NAMESPACE field - specifies the namespace for the request
BMI_HDR_PAYLOAD_LEN = 8 #BMI PACKET HEADER - PAYLOAD_LEN field - specifies the length of the payload data
BMI_HDR_SIZEOF = 12

BMI_IDLE  = 0  #IDLE status - indicates the BMI device is idle
BMI_READY = 1  #READY status - indicates the BMI device is ready to receive a request
BMI_BUSY  = 2  #BUSY status - indicates the BMI device is processing a request
BMI_DONE  = 3  #DONE status - indicates the BMI device has finished processing a request
BMI_ERROR = 4  #ERROR status - indicates an error occurred while processing a request

class BMIDevice:

    def __init__(self, cpu, nsfs=None):
        self.cpu = cpu
        self.nsfs = nsfs if nsfs is not None else NSFSStore()

    # helpers to read/write physical memory, check bounds, and handle unaligned accesses
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

    # helpers to read/write BMI registers, check bounds, and handle unaligned accesses
    def read_reg(self, offset):
        aligned = offset & ~3
        addr = BMI_REG_BASE + aligned
        value = self.phys_read_u32(addr)
        if offset != aligned:
            return (value >> ((offset & 3) * 8)) & 0xFF
        return value

    def write_reg(self, offset, value):
        aligned = offset & ~3
        addr = BMI_REG_BASE + aligned
        if offset != aligned or value <= 0xFF:
            shift = (offset & 3) * 8
            old = self.phys_read_u32(addr)
            value = (old & ~(0xFF << shift)) | ((value & 0xFF) << shift)
        self.phys_write_u32(addr, value)

    # update: check if BMI is ready and process the request if it is
    # invoked in vmp.py's main loop to handle BMI requests from KR32
    def update(self):
        status = self.read_reg(0)
        doorbell = self.read_reg(4)

        if status != BMI_READY or doorbell == 0:
            return

        self.process()

    # Prosess bmi_call if BMI is ready and doorbell is rung, 
    # read the request packet, dispatch it to the appropriate handler, 
    # write the reply back to the buffer, and update the status registers accordingly. 
    # also Handle any exceptions that may occur during processing and set the error status if needed.   
    def process(self):
        self.write_reg(0, BMI_BUSY)

        try:
            packet = self.read_packet() #get data from bmi_call
            reply = self.dispatch(packet) #select the appropriate handler based on opcode and get the reply
            self.write_reply(reply) #answer the reply to bmi_call
            self.write_reg(BMI_REPLY - BMI_REG_BASE, reply["status"])
            self.write_reg(0, BMI_DONE) #set the status to DONE after processing the request

        except Exception as e:
            print("[BMI]", e)
            self.write_reg(BMI_REPLY - BMI_REG_BASE, BMI_ERROR)
            self.write_reg(0, BMI_ERROR)

        self.write_reg(4, 0) #clear the doorbell register to indicate that the request has been processed

    # read_packet: reads a packet from the BMI buffer, 
    # extracting the opcode, flags, namespace, payload length, and payload data.
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
    
    # debug: print the opcode, namespace, and payload of the packet,
    def dispatch(self, packet):
        print()
        print("========= BMI =========")
        print("opcode    :", packet["opcode"])
        print("namespace :", packet["namespace"])
        print("payload   :", packet["payload"])
        print("=======================")
        status, payload = self.nsfs.handle_packet(packet)
        return {
            "status": status,
            "payload": payload
        }
    # write_reply: to kernel 
    # writes a reply packet to the BMI buffer
    def write_reply(self, reply):
        base = BMI_BUF_READ #construct the reply packet in the BMI buffer
        self.phys_write_u16(base + BMI_HDR_OPCODE, 0)
        self.phys_write_u16(base + BMI_HDR_FLAGS, reply["status"])
        self.phys_write_u32(base + BMI_HDR_NAMESPACE, 0)
        payload = reply["payload"]
        self.phys_write_u32(base + BMI_HDR_PAYLOAD_LEN, len(payload))

        for i, b in enumerate(payload): #write the payload data to the BMI buffer, byte by byte
            self.phys_write_u8(base + BMI_HDR_SIZEOF + i, b)
