import memory
import registers

type
    CPU* = object
        mem*: Memory
        reg*: Registers

        halted*: bool

        IME*: bool # Interrupt Master Enable
        interrupt_pending*: bool
        interrupt_vector*: byte
        interrupt_delay*: byte

        cycles*: int

        port_in*: proc(cpu: var CPU, port: byte): byte
        port_out*: proc(cpu: var CPU, port: byte, value: byte)


    Instruction* = proc(cpu: var CPU)
        # opcode : byte
        # mnemonic : string
        # cycles*: byte



proc newCPU*(): CPU =
    result = CPU()
    result.reg = newRegisters()

proc `PC`*(cpu: var CPU): uint16 {.inline.} = # time reduced from 64s to 59s after making inline
    return cpu.reg.PC

proc `PC=`*(cpu: var CPU, val: uint16) {.inline.} =
    cpu.reg.PC = val


proc popPC*(cpu: var CPU): byte {.inline.} =
    result = cpu.mem[cpu.PC]
    cpu.PC = cpu.PC + 1

proc popPC16*(cpu: var CPU): uint16 {.inline.} =
    let
        lo = cpu.popPC()
        hi = uint16(cpu.popPC())

    result = (hi shl 8) or lo

proc popStack*(self: var CPU): uint16 =
    let
        lo = self.mem[self.reg.SP]
        hi = uint16(self.mem[self.reg.SP + 1])

    self.reg.SP = self.reg.SP + 2
    result = (hi shl 8) or lo


proc pushStack*(self: var CPU, val: uint16) =
    self.mem[self.reg.SP - 1] = byte(val shr 8)
    self.mem[self.reg.SP - 2] = byte(val and 0x00FF'u16)
    self.reg.SP = self.reg.SP - 2
