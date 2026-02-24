python3 -c "
import struct, zlib

# struct bootloader_control layout (32 bytes, packed)
# slot_suffix[4]: '_a\0\0'    
# magic (uint32): 0x42414342
# version (uint8): 1
# nb_slot:3 + recovery_tries:3 packed into 1 byte -> 0x02 (nb_slot=2)
# reserved0[2]: 0x00 0x00
# slot_info[4] x 2 bytes each:
#   byte0: priority(4bits)=15, tries_remaining(3bits)=7, successful_boot(1bit)=0
#          = 0xF | (7<<4) | 0 = 0x7F
#   byte1: verity_corrupted(1bit)=0, reserved(7bits)=0 = 0x00
# reserved1[8]: all zeros
# crc32_le (uint32): CRC32 of preceding 28 bytes

slot_a = bytes([0x7F, 0x00])  # priority=15, tries=7, success=0
slot_b = bytes([0x7F, 0x00])  # same
slot_cd = b'\x00\x00' * 2    # unbootable

data = (
    b'_a\x00\x00'               # slot_suffix
    + struct.pack('<I', 0x42414342)  # magic
    + bytes([0x01, 0x02])        # version=1, nb_slot=2
    + b'\x00\x00'               # reserved0
    + slot_a + slot_b + slot_cd  # slot_info[4]
    + b'\x00' * 8               # reserved1
)
assert len(data) == 28, f'got {len(data)}'
crc = zlib.crc32(data) & 0xFFFFFFFF
full = data + struct.pack('<I', crc)
assert len(full) == 32
print(full.hex())
print(f'CRC32: 0x{crc:08X}')

# Actually write to misc partition at offset 2048
import os
dev = '/dev/sdc9'
with open(dev, 'r+b') as f:
    f.seek(2048)
    f.write(full)
    f.flush()
    os.fsync(f.fileno())
print(f'Written 32 bytes to {dev} at offset 2048')
"
sync
