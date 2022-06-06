type
    Memory* = object
        read_byte*: proc(address: uint16): byte
        write_byte*: proc(address: uint16, value: byte)


proc `[]`*(self: Memory, address: uint16): byte {.inline.} = #making both inline takes execution of tests from 72s to 64s
    self.read_byte(address)

proc `[]=`*(self: var Memory, address: uint16, value: byte) {.inline.} =
    self.write_byte(address, value)

# write word
template `[]=`*(self: var Memory, address: uint16, value: uint16) =
    self[address] = byte(value and 0x00FF)
    self[address + 1] = byte(value shr 8)

template read_word*(self: Memory, address: uint16): uint16 =
    (uint16(self[address + 1]) shl 8) or self[address]
