import std/tables
import std/bitops
import std/sugar

import cpu
import memory
import registers


const OPCODES_CYCLES = [
#   0  1   2   3   4   5   6   7   8  9   A   B   C   D   E  F
    4, 10, 7,  5,  5,  5,  7,  4,  4, 10, 7,  5,  5,  5,  7, 4,  # 0
    4, 10, 7,  5,  5,  5,  7,  4,  4, 10, 7,  5,  5,  5,  7, 4,  # 1
    4, 10, 16, 5,  5,  5,  7,  4,  4, 10, 16, 5,  5,  5,  7, 4,  # 2
    4, 10, 13, 5,  10, 10, 10, 4,  4, 10, 13, 5,  5,  5,  7, 4,  # 3
    5, 5,  5,  5,  5,  5,  7,  5,  5, 5,  5,  5,  5,  5,  7, 5,  # 4
    5, 5,  5,  5,  5,  5,  7,  5,  5, 5,  5,  5,  5,  5,  7, 5,  # 5
    5, 5,  5,  5,  5,  5,  7,  5,  5, 5,  5,  5,  5,  5,  7, 5,  # 6
    7, 7,  7,  7,  7,  7,  7,  7,  5, 5,  5,  5,  5,  5,  7, 5,  # 7
    4, 4,  4,  4,  4,  4,  7,  4,  4, 4,  4,  4,  4,  4,  7, 4,  # 8
    4, 4,  4,  4,  4,  4,  7,  4,  4, 4,  4,  4,  4,  4,  7, 4,  # 9
    4, 4,  4,  4,  4,  4,  7,  4,  4, 4,  4,  4,  4,  4,  7, 4,  # A
    4, 4,  4,  4,  4,  4,  7,  4,  4, 4,  4,  4,  4,  4,  7, 4,  # B
    5, 10, 10, 10, 11, 11, 7,  11, 5, 10, 10, 10, 11, 17, 7, 11, # C
    5, 10, 10, 10, 11, 11, 7,  11, 5, 10, 10, 10, 11, 17, 7, 11, # D
    5, 10, 10, 18, 11, 11, 7,  11, 5, 5,  10, 4,  11, 17, 7, 11, # E
    5, 10, 10, 4,  11, 11, 7,  11, 5, 5,  10, 4,  11, 17, 7, 11  # F
]


template flagsZSP(cpu: CPU, val: byte) =
    cpu.reg.fZ = val == 0
    cpu.reg.fS = val.testBit(7)
    cpu.reg.fP = not bool(parityBits(val))

proc instrXCHG(cpu: var CPU) =
    let de = cpu.reg.DE
    cpu.reg.DE = cpu.reg.HL
    cpu.reg.HL = de

proc instrXTHL(cpu: var CPU) =
    let stack_val = cpu.mem.read_word(cpu.reg.SP)
    cpu.mem[cpu.reg.SP] = cpu.reg.HL
    cpu.reg.HL = stack_val

proc instrDAD(cpu: var CPU, val: uint16) =
    var total = int32(cpu.reg.HL) + int32(val)
    cpu.reg.fC = total > 0xFFFF
    cpu.reg.HL = uint16(total)

proc instrADD(cpu: var CPU, val: byte, carry: bool) =
    var total = int16(cpu.reg.A) + int16(val) + int16(carry)

    cpu.reg.fC = total > 0xFF
    cpu.reg.fH = (cpu.reg.A and 0xF) + (val and 0xF) + byte(carry) > 0xF
    flagsZSP(cpu, byte(total))

    cpu.reg.A = byte(total)

proc instrSUB(cpu: var CPU, val: byte, carry: bool) =
    cpu.instrADD(not val, not carry)
    cpu.reg.fC = not cpu.reg.fC

proc instrANA(cpu: var CPU, val: byte) =
    let result = cpu.reg.A and val

    cpu.reg.fC = false
    cpu.reg.fH = ((cpu.reg.A or val) and 0x08) != 0
    flagsZSP(cpu, result)

    cpu.reg.A = result

proc instrXRA(cpu: var CPU, val: byte) =
    cpu.reg.A = cpu.reg.A xor val

    cpu.reg.fC = false
    cpu.reg.fH = false
    flagsZSP(cpu, cpu.reg.A)

proc instrORA(cpu: var CPU, val: byte) =
    cpu.reg.A = cpu.reg.A or val

    cpu.reg.fC = false
    cpu.reg.fH = false
    flagsZSP(cpu, cpu.reg.A)

proc instrCMP(cpu: var CPU, val: byte) =
    let result = cpu.reg.A - val

    cpu.reg.fC = val > cpu.reg.A
    cpu.reg.fH = bool((not (cpu.reg.A xor result xor val)) and 0x10)
    flagsZSP(cpu, result)

proc instrINR(cpu: var CPU, setter: proc(r: var Registers, val: byte), val: byte) =
    let total = val + 1

    cpu.reg.setter(total)

    cpu.reg.fH = (total and 0x0F) == 0
    flagsZSP(cpu, total)

proc instrDCR(cpu: var CPU, setter: proc(r: var Registers, val: byte), val: byte) =
    let total = val - 1

    cpu.reg.setter(total)

    cpu.reg.fH = not ((total and 0x0F) == 0x0F)
    flagsZSP(cpu, total)

proc instrRLC(cpu: var CPU) =
    cpu.reg.A = (cpu.reg.A shl 1) or (cpu.reg.A shr 7)

    cpu.reg.fC = cpu.reg.A.testBit(0)


proc instrRRC(cpu: var CPU) =
    cpu.reg.A = (cpu.reg.A shr 1) or (cpu.reg.A shl 7)

    cpu.reg.fC = cpu.reg.A.testBit(7)

proc instrRAL(cpu: var CPU) =
    let val = cpu.reg.A
    cpu.reg.A = (val shl 1) or byte(cpu.reg.fC)

    cpu.reg.fC = val.testBit(7)

proc instrRAR(cpu: var CPU) =
    let val = cpu.reg.A
    cpu.reg.A = (val shr 1) or (byte(cpu.reg.fC) shl 7)

    cpu.reg.fC = val.testBit(0)

proc instrDAA(cpu: var CPU) =
    var
        cy: bool = cpu.reg.fC
        correction: byte = 0

        lsb = cpu.reg.A and 0x0F
        msb = cpu.reg.A shr 4

    if cpu.reg.fH or (lsb > 9):
        correction += 0x06
    if cpu.reg.fC or (msb > 9) or ((msb >= 9) and (lsb > 9)):
        correction += 0x60
        cy = true

    cpu.instrADD(correction, false)
    cpu.reg.fC = cy

proc instrJMP(cpu: var CPU, next: uint16) =
    cpu.PC = next

proc instrCondJMP(cpu: var CPU, cond: bool) =
    let next = cpu.popPC16()
    if cond:
        cpu.instrJMP(next)

proc instrCALL(cpu: var CPU, next: uint16) =
    cpu.pushStack(cpu.PC)
    cpu.PC = next

proc instrCondCALL(cpu: var CPU, cond: bool) =
    let next = cpu.popPC16()
    if cond:
        cpu.instrCALL(next)
        cpu.cycles += 6

proc instrRET(cpu: var CPU) =
    cpu.PC = cpu.popStack()

proc instrCondRET(cpu: var CPU, cond: bool) =
    if cond:
        cpu.instrRET()
        cpu.cycles += 6



var ops = {
# ========== 8-bit load/store/move instructions ==========
    0x7F'u8: # MOV A, A
        Instruction((cpu: var CPU) => (cpu.reg.A = cpu.reg.A)),
    0x78'u8: # MOV A, B
        Instruction((cpu: var CPU) => (cpu.reg.A = cpu.reg.B)),
    0x79'u8: # MOV A, C
        Instruction((cpu: var CPU) => (cpu.reg.A = cpu.reg.C)),
    0x7A'u8: # MOV A, D
        Instruction((cpu: var CPU) => (cpu.reg.A = cpu.reg.D)),
    0x7B'u8: # MOV A, E
        Instruction((cpu: var CPU) => (cpu.reg.A = cpu.reg.E)),
    0x7C'u8: # MOV A, H
        Instruction((cpu: var CPU) => (cpu.reg.A = cpu.reg.H)),
    0x7D'u8: # MOV A, L
        Instruction((cpu: var CPU) => (cpu.reg.A = cpu.reg.L)),
    0x7E'u8: # MOV A, M
        Instruction((cpu: var CPU) => (cpu.reg.A = cpu.mem[cpu.reg.HL])),


    0x0A'u8: # LDAX B
        Instruction((cpu: var CPU) => (cpu.reg.A = cpu.mem[cpu.reg.BC])),
    0x1A'u8: # LDAX D
        Instruction((cpu: var CPU) => (cpu.reg.A = cpu.mem[cpu.reg.DE])),

    0x3A'u8: # LDA a16
        Instruction((cpu: var CPU) => (cpu.reg.A = cpu.mem[cpu.popPC16()])),


    0x47'u8: # MOV B, A
        Instruction((cpu: var CPU) => (cpu.reg.B = cpu.reg.A)),
    0x40'u8: # MOV B, B
        Instruction((cpu: var CPU) => (cpu.reg.B = cpu.reg.B)),
    0x41'u8: # MOV B, C
        Instruction((cpu: var CPU) => (cpu.reg.B = cpu.reg.C)),
    0x42'u8: # MOV B, D
        Instruction((cpu: var CPU) => (cpu.reg.B = cpu.reg.D)),
    0x43'u8: # MOV B, E
        Instruction((cpu: var CPU) => (cpu.reg.B = cpu.reg.E)),
    0x44'u8: # MOV B, H
        Instruction((cpu: var CPU) => (cpu.reg.B = cpu.reg.H)),
    0x45'u8: # MOV B, L
        Instruction((cpu: var CPU) => (cpu.reg.B = cpu.reg.L)),
    0x46'u8: # MOV B, M
        Instruction((cpu: var CPU) => (cpu.reg.B = cpu.mem[cpu.reg.HL])),


    0x4F'u8: # MOV C, A
        Instruction((cpu: var CPU) => (cpu.reg.C = cpu.reg.A)),
    0x48'u8: # MOV C, B
        Instruction((cpu: var CPU) => (cpu.reg.C = cpu.reg.B)),
    0x49'u8: # MOV C, C
        Instruction((cpu: var CPU) => (cpu.reg.C = cpu.reg.C)),
    0x4A'u8: # MOV C, D
        Instruction((cpu: var CPU) => (cpu.reg.C = cpu.reg.D)),
    0x4B'u8: # MOV C, E
        Instruction((cpu: var CPU) => (cpu.reg.C = cpu.reg.E)),
    0x4C'u8: # MOV C, H
        Instruction((cpu: var CPU) => (cpu.reg.C = cpu.reg.H)),
    0x4D'u8: # MOV C, L
        Instruction((cpu: var CPU) => (cpu.reg.C = cpu.reg.L)),
    0x4E'u8: # MOV C, M
        Instruction((cpu: var CPU) => (cpu.reg.C = cpu.mem[cpu.reg.HL])),



    0x57'u8: # MOV D, A
        Instruction((cpu: var CPU) => (cpu.reg.D = cpu.reg.A)),
    0x50'u8: # MOV D, B
        Instruction((cpu: var CPU) => (cpu.reg.D = cpu.reg.B)),
    0x51'u8: # MOV D, C
        Instruction((cpu: var CPU) => (cpu.reg.D = cpu.reg.C)),
    0x52'u8: # MOV D, D
        Instruction((cpu: var CPU) => (cpu.reg.D = cpu.reg.D)),
    0x53'u8: # MOV D, E
        Instruction((cpu: var CPU) => (cpu.reg.D = cpu.reg.E)),
    0x54'u8: # MOV D, H
        Instruction((cpu: var CPU) => (cpu.reg.D = cpu.reg.H)),
    0x55'u8: # MOV D, L
        Instruction((cpu: var CPU) => (cpu.reg.D = cpu.reg.L)),
    0x56'u8: # MOV D, M
        Instruction((cpu: var CPU) => (cpu.reg.D = cpu.mem[cpu.reg.HL])),


    0x5F'u8: # MOV E, A
        Instruction((cpu: var CPU) => (cpu.reg.E = cpu.reg.A)),
    0x58'u8: # MOV E, B
        Instruction((cpu: var CPU) => (cpu.reg.E = cpu.reg.B)),
    0x59'u8: # MOV E, C
        Instruction((cpu: var CPU) => (cpu.reg.E = cpu.reg.C)),
    0x5A'u8: # MOV E, D
        Instruction((cpu: var CPU) => (cpu.reg.E = cpu.reg.D)),
    0x5B'u8: # MOV E, E
        Instruction((cpu: var CPU) => (cpu.reg.E = cpu.reg.E)),
    0x5C'u8: # MOV E, H
        Instruction((cpu: var CPU) => (cpu.reg.E = cpu.reg.H)),
    0x5D'u8: # MOV E, L
        Instruction((cpu: var CPU) => (cpu.reg.E = cpu.reg.L)),
    0x5E'u8: # MOV E, M
        Instruction((cpu: var CPU) => (cpu.reg.E = cpu.mem[cpu.reg.HL])),


    0x67'u8: # MOV H, A
        Instruction((cpu: var CPU) => (cpu.reg.H = cpu.reg.A)),
    0x60'u8: # MOV H, B
        Instruction((cpu: var CPU) => (cpu.reg.H = cpu.reg.B)),
    0x61'u8: # MOV H, C
        Instruction((cpu: var CPU) => (cpu.reg.H = cpu.reg.C)),
    0x62'u8: # MOV H, D
        Instruction((cpu: var CPU) => (cpu.reg.H = cpu.reg.D)),
    0x63'u8: # MOV H, E
        Instruction((cpu: var CPU) => (cpu.reg.H = cpu.reg.E)),
    0x64'u8: # MOV H, H
        Instruction((cpu: var CPU) => (cpu.reg.H = cpu.reg.H)),
    0x65'u8: # MOV H, L
        Instruction((cpu: var CPU) => (cpu.reg.H = cpu.reg.L)),
    0x66'u8: # MOV H, M
        Instruction((cpu: var CPU) => (cpu.reg.H = cpu.mem[cpu.reg.HL])),


    0x6F'u8: # MOV L, A
        Instruction((cpu: var CPU) => (cpu.reg.L = cpu.reg.A)),
    0x68'u8: # MOV L, B
        Instruction((cpu: var CPU) => (cpu.reg.L = cpu.reg.B)),
    0x69'u8: # MOV L, C
        Instruction((cpu: var CPU) => (cpu.reg.L = cpu.reg.C)),
    0x6A'u8: # MOV L, D
        Instruction((cpu: var CPU) => (cpu.reg.L = cpu.reg.D)),
    0x6B'u8: # MOV L, E
        Instruction((cpu: var CPU) => (cpu.reg.L = cpu.reg.E)),
    0x6C'u8: # MOV L, H
        Instruction((cpu: var CPU) => (cpu.reg.L = cpu.reg.H)),
    0x6D'u8: # MOV L, L
        Instruction((cpu: var CPU) => (cpu.reg.L = cpu.reg.L)),
    0x6E'u8: # MOV L, M
        Instruction((cpu: var CPU) => (cpu.reg.L = cpu.mem[cpu.reg.HL])),


    0x77'u8: # MOV M, A
        Instruction((cpu: var CPU) => (cpu.mem[cpu.reg.HL] = cpu.reg.A)),
    0x70'u8: # MOV M, B
        Instruction((cpu: var CPU) => (cpu.mem[cpu.reg.HL] = cpu.reg.B)),
    0x71'u8: # MOV M, C
        Instruction((cpu: var CPU) => (cpu.mem[cpu.reg.HL] = cpu.reg.C)),
    0x72'u8: # MOV M, D
        Instruction((cpu: var CPU) => (cpu.mem[cpu.reg.HL] = cpu.reg.D)),
    0x73'u8: # MOV M, E
        Instruction((cpu: var CPU) => (cpu.mem[cpu.reg.HL] = cpu.reg.E)),
    0x74'u8: # MOV M, H
        Instruction((cpu: var CPU) => (cpu.mem[cpu.reg.HL] = cpu.reg.H)),
    0x75'u8: # MOV M, L
        Instruction((cpu: var CPU) => (cpu.mem[cpu.reg.HL] = cpu.reg.L)),



    0x3E'u8: # MVI A, d8
        Instruction((cpu: var CPU) => (cpu.reg.A = cpu.popPC())),
    0x06'u8: # MVI B, d8
        Instruction((cpu: var CPU) => (cpu.reg.B = cpu.popPC())),
    0x0E'u8: # MVI C, d8
        Instruction((cpu: var CPU) => (cpu.reg.C = cpu.popPC())),
    0x16'u8: # MVI D, d8
        Instruction((cpu: var CPU) => (cpu.reg.D = cpu.popPC())),
    0x1E'u8: # MVI E, d8
        Instruction((cpu: var CPU) => (cpu.reg.E = cpu.popPC())),
    0x26'u8: # MVI H, d8
        Instruction((cpu: var CPU) => (cpu.reg.H = cpu.popPC())),
    0x2E'u8: # MVI L, d8
        Instruction((cpu: var CPU) => (cpu.reg.L = cpu.popPC())),
    0x36'u8: # MVI M, d8
        Instruction((cpu: var CPU) => (cpu.mem[cpu.reg.HL] = cpu.popPC())),


    0x02'u8: # STAX B
        Instruction((cpu: var CPU) => (cpu.mem[cpu.reg.BC] = cpu.reg.A)),
    0x12'u8: # STAX D
        Instruction((cpu: var CPU) => (cpu.mem[cpu.reg.DE] = cpu.reg.A)),
    0x32'u8: # STAX (a16)
        Instruction((cpu: var CPU) => (cpu.mem[cpu.popPC16()] = cpu.reg.A)),





# ========== 16-bit load/store/move instructions ==========
    0x01'u8: # LXI B, d16
        Instruction((cpu: var CPU) => (cpu.reg.BC = cpu.popPC16())),
    0x11'u8: # LXI D, d16
        Instruction((cpu: var CPU) => (cpu.reg.DE = cpu.popPC16())),
    0x21'u8: # LXI H, d16
        Instruction((cpu: var CPU) => (cpu.reg.HL = cpu.popPC16())),
    0x31'u8: # LXI SP, d16
        Instruction((cpu: var CPU) => (cpu.reg.SP = cpu.popPC16())),


    0x2A'u8: # LHLD
        Instruction((cpu: var CPU) => (
            let address = cpu.popPC16()
            cpu.reg.HL = cpu.mem.read_word(address))),
    0x22'u8: # SHLD
        Instruction((cpu: var CPU) => (
            let address = cpu.popPC16()
            cpu.mem[address] = cpu.reg.HL)),
                    # call to overloaded `[]=` to write word

    0xF9'u8: # SPHL
        Instruction((cpu: var CPU) => (cpu.reg.SP = cpu.reg.HL)),

    0xEB'u8: # XCHG
        Instruction((cpu: var CPU) => (cpu.instrXCHG())),
    0xE3'u8: # XTHL
        Instruction((cpu: var CPU) => (cpu.instrXTHL())),


    0xF5'u8: # PUSH PSW
        Instruction((cpu: var CPU) => (cpu.pushStack(cpu.reg.PSW))),
    0xC5'u8: # PUSH B
        Instruction((cpu: var CPU) => (cpu.pushStack(cpu.reg.BC))),
    0xD5'u8: # PUSH D
        Instruction((cpu: var CPU) => (cpu.pushStack(cpu.reg.DE))),
    0xE5'u8: # PUSH H
        Instruction((cpu: var CPU) => (cpu.pushStack(cpu.reg.HL))),

    0xF1'u8: # POP PSW
        Instruction((cpu: var CPU) => (cpu.reg.PSW = cpu.popStack())),
    0xC1'u8: # POP B
        Instruction((cpu: var CPU) => (cpu.reg.BC = cpu.popStack())),
    0xD1'u8: # POP D
        Instruction((cpu: var CPU) => (cpu.reg.DE = cpu.popStack())),
    0xE1'u8: # POP H
        Instruction((cpu: var CPU) => (cpu.reg.HL = cpu.popStack())),





# ========== 8bit arithmetic/logical instructions ==========
    0x87'u8: # ADD A
        Instruction((cpu: var CPU) => (cpu.instrADD(cpu.reg.A, false))),
    0x80'u8: # ADD B
        Instruction((cpu: var CPU) => (cpu.instrADD(cpu.reg.B, false))),
    0x81'u8: # ADD C
        Instruction((cpu: var CPU) => (cpu.instrADD(cpu.reg.C, false))),
    0x82'u8: # ADD D
        Instruction((cpu: var CPU) => (cpu.instrADD(cpu.reg.D, false))),
    0x83'u8: # ADD E
        Instruction((cpu: var CPU) => (cpu.instrADD(cpu.reg.E, false))),
    0x84'u8: # ADD H
        Instruction((cpu: var CPU) => (cpu.instrADD(cpu.reg.H, false))),
    0x85'u8: # ADD L
        Instruction((cpu: var CPU) => (cpu.instrADD(cpu.reg.L, false))),
    0x86'u8: # ADD M
        Instruction((cpu: var CPU) => (cpu.instrADD(cpu.mem[cpu.reg.HL], false))),

    0xC6'u8: # ADI d8
        Instruction((cpu: var CPU) => (cpu.instrADD(cpu.popPC(), false))),


    0x8F'u8: # ADC A
        Instruction((cpu: var CPU) => (cpu.instrADD(cpu.reg.A, cpu.reg.fC))),
    0x88'u8: # ADC B
        Instruction((cpu: var CPU) => (cpu.instrADD(cpu.reg.B, cpu.reg.fC))),
    0x89'u8: # ADC C
        Instruction((cpu: var CPU) => (cpu.instrADD(cpu.reg.C, cpu.reg.fC))),
    0x8A'u8: # ADC D
        Instruction((cpu: var CPU) => (cpu.instrADD(cpu.reg.D, cpu.reg.fC))),
    0x8B'u8: # ADC E
        Instruction((cpu: var CPU) => (cpu.instrADD(cpu.reg.E, cpu.reg.fC))),
    0x8C'u8: # ADC H
        Instruction((cpu: var CPU) => (cpu.instrADD(cpu.reg.H, cpu.reg.fC))),
    0x8D'u8: # ADC L
        Instruction((cpu: var CPU) => (cpu.instrADD(cpu.reg.L, cpu.reg.fC))),
    0x8E'u8: # ADC M
        Instruction((cpu: var CPU) => (cpu.instrADD(cpu.mem[cpu.reg.HL], cpu.reg.fC))),

    0xCE'u8: # ACI d8
        Instruction((cpu: var CPU) => (cpu.instrADD(cpu.popPC(), cpu.reg.fC))),



    0x97'u8: # SUB A
        Instruction((cpu: var CPU) => (cpu.instrSUB(cpu.reg.A, false))),
    0x90'u8: # SUB B
        Instruction((cpu: var CPU) => (cpu.instrSUB(cpu.reg.B, false))),
    0x91'u8: # SUB C
        Instruction((cpu: var CPU) => (cpu.instrSUB(cpu.reg.C, false))),
    0x92'u8: # SUB D
        Instruction((cpu: var CPU) => (cpu.instrSUB(cpu.reg.D, false))),
    0x93'u8: # SUB E
        Instruction((cpu: var CPU) => (cpu.instrSUB(cpu.reg.E, false))),
    0x94'u8: # SUB H
        Instruction((cpu: var CPU) => (cpu.instrSUB(cpu.reg.H, false))),
    0x95'u8: # SUB L
        Instruction((cpu: var CPU) => (cpu.instrSUB(cpu.reg.L, false))),
    0x96'u8: # SUB M
        Instruction((cpu: var CPU) => (cpu.instrSUB(cpu.mem[cpu.reg.HL], false))),

    0xD6'u8: # SUI A, d8
        Instruction((cpu: var CPU) => (cpu.instrSUB(cpu.popPC(), false))),


    0x9F'u8: # SBB A
        Instruction((cpu: var CPU) => (cpu.instrSUB(cpu.reg.A, cpu.reg.fC))),
    0x98'u8: # SBB B
        Instruction((cpu: var CPU) => (cpu.instrSUB(cpu.reg.B, cpu.reg.fC))),
    0x99'u8: # SBB C
        Instruction((cpu: var CPU) => (cpu.instrSUB(cpu.reg.C, cpu.reg.fC))),
    0x9A'u8: # SBB D
        Instruction((cpu: var CPU) => (cpu.instrSUB(cpu.reg.D, cpu.reg.fC))),
    0x9B'u8: # SBB E
        Instruction((cpu: var CPU) => (cpu.instrSUB(cpu.reg.E, cpu.reg.fC))),
    0x9C'u8: # SBB H
        Instruction((cpu: var CPU) => (cpu.instrSUB(cpu.reg.H, cpu.reg.fC))),
    0x9D'u8: # SBB L
        Instruction((cpu: var CPU) => (cpu.instrSUB(cpu.reg.L, cpu.reg.fC))),
    0x9E'u8: # SBB M
        Instruction((cpu: var CPU) => (cpu.instrSUB(cpu.mem[cpu.reg.HL], cpu.reg.fC))),

    0xDE'u8: # SBI A, d8
        Instruction((cpu: var CPU) => (cpu.instrSUB(cpu.popPC(), cpu.reg.fC))),


    0xA7'u8: # ANA A
        Instruction((cpu: var CPU) => (cpu.instrANA(cpu.reg.A))),
    0xA0'u8: # ANA B
        Instruction((cpu: var CPU) => (cpu.instrANA(cpu.reg.B))),
    0xA1'u8: # ANA C
        Instruction((cpu: var CPU) => (cpu.instrANA(cpu.reg.C))),
    0xA2'u8: # ANA D
        Instruction((cpu: var CPU) => (cpu.instrANA(cpu.reg.D))),
    0xA3'u8: # ANA E
        Instruction((cpu: var CPU) => (cpu.instrANA(cpu.reg.E))),
    0xA4'u8: # ANA H
        Instruction((cpu: var CPU) => (cpu.instrANA(cpu.reg.H))),
    0xA5'u8: # ANA L
        Instruction((cpu: var CPU) => (cpu.instrANA(cpu.reg.L))),
    0xA6'u8: # ANA M
        Instruction((cpu: var CPU) => (cpu.instrANA(cpu.mem[cpu.reg.HL]))),

    0xE6'u8: # ANI d8
        Instruction((cpu: var CPU) => (cpu.instrANA(cpu.popPC()))),


    0xB7'u8: # ORA A
        Instruction((cpu: var CPU) => (cpu.instrORA(cpu.reg.A))),
    0xB0'u8: # ORA B
        Instruction((cpu: var CPU) => (cpu.instrORA(cpu.reg.B))),
    0xB1'u8: # ORA C
        Instruction((cpu: var CPU) => (cpu.instrORA(cpu.reg.C))),
    0xB2'u8: # ORA D
        Instruction((cpu: var CPU) => (cpu.instrORA(cpu.reg.D))),
    0xB3'u8: # ORA E
        Instruction((cpu: var CPU) => (cpu.instrORA(cpu.reg.E))),
    0xB4'u8: # ORA H
        Instruction((cpu: var CPU) => (cpu.instrORA(cpu.reg.H))),
    0xB5'u8: # ORA L
        Instruction((cpu: var CPU) => (cpu.instrORA(cpu.reg.L))),
    0xB6'u8: # ORA M
        Instruction((cpu: var CPU) => (cpu.instrORA(cpu.mem[cpu.reg.HL]))),

    0xF6'u8: # ORI d8
        Instruction((cpu: var CPU) => (cpu.instrORA(cpu.popPC()))),


    0xAF'u8: # XRA A
        Instruction((cpu: var CPU) => (cpu.instrXRA(cpu.reg.A))),
    0xA8'u8: # XRA B
        Instruction((cpu: var CPU) => (cpu.instrXRA(cpu.reg.B))),
    0xA9'u8: # XRA C
        Instruction((cpu: var CPU) => (cpu.instrXRA(cpu.reg.C))),
    0xAA'u8: # XRA D
        Instruction((cpu: var CPU) => (cpu.instrXRA(cpu.reg.D))),
    0xAB'u8: # XRA E
        Instruction((cpu: var CPU) => (cpu.instrXRA(cpu.reg.E))),
    0xAC'u8: # XRA H
        Instruction((cpu: var CPU) => (cpu.instrXRA(cpu.reg.H))),
    0xAD'u8: # XRA L
        Instruction((cpu: var CPU) => (cpu.instrXRA(cpu.reg.L))),
    0xAE'u8: # XRA M
        Instruction((cpu: var CPU) => (cpu.instrXRA(cpu.mem[cpu.reg.HL]))),

    0xEE'u8: # XRI d8
        Instruction((cpu: var CPU) => (cpu.instrXRA(cpu.popPC()))),


    0xBF'u8: # CMP A
        Instruction((cpu: var CPU) => (cpu.instrCMP(cpu.reg.A))),
    0xB8'u8: # CMP B
        Instruction((cpu: var CPU) => (cpu.instrCMP(cpu.reg.B))),
    0xB9'u8: # CMP C
        Instruction((cpu: var CPU) => (cpu.instrCMP(cpu.reg.C))),
    0xBA'u8: # CMP D
        Instruction((cpu: var CPU) => (cpu.instrCMP(cpu.reg.D))),
    0xBB'u8: # CMP E
        Instruction((cpu: var CPU) => (cpu.instrCMP(cpu.reg.E))),
    0xBC'u8: # CMP H
        Instruction((cpu: var CPU) => (cpu.instrCMP(cpu.reg.H))),
    0xBD'u8: # CMP L
        Instruction((cpu: var CPU) => (cpu.instrCMP(cpu.reg.L))),
    0xBE'u8: # CMP M
        Instruction((cpu: var CPU) => (cpu.instrCMP(cpu.mem[cpu.reg.HL]))),

    0xFE'u8: # CPI d8
        Instruction((cpu: var CPU) => (cpu.instrCMP(cpu.popPC()))),



    0x3C'u8: # INR A
        Instruction((cpu: var CPU) => (cpu.instrINR(`A=`, cpu.reg.A))),
    0x04'u8: # INR B
        Instruction((cpu: var CPU) => (cpu.instrINR(`B=`, cpu.reg.B))),
    0x0C'u8: # INR C
        Instruction((cpu: var CPU) => (cpu.instrINR(`C=`, cpu.reg.C))),
    0x14'u8: # INR D
        Instruction((cpu: var CPU) => (cpu.instrINR(`D=`, cpu.reg.D))),
    0x1C'u8: # INR E
        Instruction((cpu: var CPU) => (cpu.instrINR(`E=`, cpu.reg.E))),
    0x24'u8: # INR H
        Instruction((cpu: var CPU) => (cpu.instrINR(`H=`, cpu.reg.H))),
    0x2C'u8: # INR L
        Instruction((cpu: var CPU) => (cpu.instrINR(`L=`, cpu.reg.L))),

    0x34'u8: # INR M
        Instruction((cpu: var CPU) => (
        let
            val = cpu.mem[cpu.reg.HL]
            total = val + 1

        cpu.mem[cpu.reg.HL] = total

        cpu.reg.fH = (total and 0x0F) == 0
        flagsZSP(cpu, total))
        ),

    0x3D'u8: # DCR A
        Instruction((cpu: var CPU) => (cpu.instrDCR(`A=`, cpu.reg.A))),
    0x05'u8: # DCR B
        Instruction((cpu: var CPU) => (cpu.instrDCR(`B=`, cpu.reg.B))),
    0x0D'u8: # DCR C
        Instruction((cpu: var CPU) => (cpu.instrDCR(`C=`, cpu.reg.C))),
    0x15'u8: # DCR D
        Instruction((cpu: var CPU) => (cpu.instrDCR(`D=`, cpu.reg.D))),
    0x1D'u8: # DCR E
        Instruction((cpu: var CPU) => (cpu.instrDCR(`E=`, cpu.reg.E))),
    0x25'u8: # DCR H
        Instruction((cpu: var CPU) => (cpu.instrDCR(`H=`, cpu.reg.H))),
    0x2D'u8: # DCR L
        Instruction((cpu: var CPU) => (cpu.instrDCR(`L=`, cpu.reg.L))),

    0x35'u8: # DCR M
        Instruction((cpu: var CPU) => (
        let
            val = cpu.mem[cpu.reg.HL]
            total = val - 1

        cpu.mem[cpu.reg.HL] = total

        cpu.reg.fH = not ((total and 0x0F) == 0x0F)
        flagsZSP(cpu, total))
        ),


    0x07'u8: # RLC
        Instruction((cpu: var CPU) => (cpu.instrRLC())),
    0x0F'u8: # RRC
        Instruction((cpu: var CPU) => (cpu.instrRRC())),
    0x17'u8: # RAL
        Instruction((cpu: var CPU) => (cpu.instrRAL())),
    0x1F'u8: # RAR
        Instruction((cpu: var CPU) => (cpu.instrRAR())),

    0x27'u8: # DAA i.e Decimal Adjust Accumulator
        Instruction((cpu: var CPU) => (cpu.instrDAA())),
    0x2F'u8: # CMA
        Instruction((cpu: var CPU) => (cpu.reg.A = not cpu.reg.A)),
    0x37'u8: # STC
        Instruction((cpu: var CPU) => (cpu.reg.fC = true)),
    0x3F'u8: # CMC
        Instruction((cpu: var CPU) => (cpu.reg.fC = not cpu.reg.fC)),





# ========== 16bit arithmetic/logical instructions ==========
    0x09'u8: # DAD B
        Instruction((cpu: var CPU) => (cpu.instrDAD(cpu.reg.BC))),
    0x19'u8: # DAD D
        Instruction((cpu: var CPU) => (cpu.instrDAD(cpu.reg.DE))),
    0x29'u8: # DAD H
        Instruction((cpu: var CPU) => (cpu.instrDAD(cpu.reg.HL))),
    0x39'u8: # DAD SP
        Instruction((cpu: var CPU) => (cpu.instrDAD(cpu.reg.SP))),


    0x03'u8: # INX B
        Instruction((cpu: var CPU) => (cpu.reg.BC = cpu.reg.BC + 1)),
    0x13'u8: # INX D
        Instruction((cpu: var CPU) => (cpu.reg.DE = cpu.reg.DE + 1)),
    0x23'u8: # INX H
        Instruction((cpu: var CPU) => (cpu.reg.HL = cpu.reg.HL + 1)),
    0x33'u8: # INX SP
        Instruction((cpu: var CPU) => (cpu.reg.SP = cpu.reg.SP + 1)),

    0x0B'u8: # DCX B
        Instruction((cpu: var CPU) => (cpu.reg.BC = cpu.reg.BC - 1)),
    0x1B'u8: # DCX D
        Instruction((cpu: var CPU) => (cpu.reg.DE = cpu.reg.DE - 1)),
    0x2B'u8: # DCX H
        Instruction((cpu: var CPU) => (cpu.reg.HL = cpu.reg.HL - 1)),
    0x3B'u8: # DCX SP
        Instruction((cpu: var CPU) => (cpu.reg.SP = cpu.reg.SP - 1)),





# ========== Jumps/calls ==========
    0xC3'u8: # JMP
        Instruction((cpu: var CPU) => (cpu.instrJMP(cpu.popPC16()))),
    0xC2'u8: # JNZ
        Instruction((cpu: var CPU) => (cpu.instrCondJMP(not cpu.reg.fZ))),
    0xCA'u8: # JZ
        Instruction((cpu: var CPU) => (cpu.instrCondJMP(cpu.reg.fZ))),
    0xD2'u8: # JNC
        Instruction((cpu: var CPU) => (cpu.instrCondJMP(not cpu.reg.fC))),
    0xDA'u8: # JC
        Instruction((cpu: var CPU) => (cpu.instrCondJMP(cpu.reg.fC))),
    0xE2'u8: # JPO
        Instruction((cpu: var CPU) => (cpu.instrCondJMP(not cpu.reg.fP))),
    0xEA'u8: # JPE
        Instruction((cpu: var CPU) => (cpu.instrCondJMP(cpu.reg.fP))),
    0xF2'u8: # JP
        Instruction((cpu: var CPU) => (cpu.instrCondJMP(not cpu.reg.fS))),
    0xFA'u8: # JM
        Instruction((cpu: var CPU) => (cpu.instrCondJMP(cpu.reg.fS))),

    0xE9'u8: # PCHL
        Instruction((cpu: var CPU) => (cpu.instrJMP(cpu.reg.HL))),


    0xCD'u8: # CALL
        Instruction((cpu: var CPU) => (cpu.instrCALL(cpu.popPC16()))),
    0xC4'u8: # CNZ
        Instruction((cpu: var CPU) => (cpu.instrCondCALL(not cpu.reg.fZ))),
    0xCC'u8: # CZ
        Instruction((cpu: var CPU) => (cpu.instrCondCALL(cpu.reg.fZ))),
    0xD4'u8: # CNC
        Instruction((cpu: var CPU) => (cpu.instrCondCALL(not cpu.reg.fC))),
    0xDC'u8: # CC
        Instruction((cpu: var CPU) => (cpu.instrCondCALL(cpu.reg.fC))),
    0xE4'u8: # CPO
        Instruction((cpu: var CPU) => (cpu.instrCondCALL(not cpu.reg.fP))),
    0xEC'u8: # CPE
        Instruction((cpu: var CPU) => (cpu.instrCondCALL(cpu.reg.fP))),
    0xF4'u8: # CP
        Instruction((cpu: var CPU) => (cpu.instrCondCALL(not cpu.reg.fS))),
    0xFC'u8: # CM
        Instruction((cpu: var CPU) => (cpu.instrCondCALL(cpu.reg.fS))),


    0xC9'u8: # RET
        Instruction((cpu: var CPU) => (cpu.instrRET())),
    0xC0'u8: # RNZ
        Instruction((cpu: var CPU) => (cpu.instrCondRET(not cpu.reg.fZ))),
    0xC8'u8: # RZ
        Instruction((cpu: var CPU) => (cpu.instrCondRET(cpu.reg.fZ))),
    0xD0'u8: # RNC
        Instruction((cpu: var CPU) => (cpu.instrCondRET(not cpu.reg.fC))),
    0xD8'u8: # RC
        Instruction((cpu: var CPU) => (cpu.instrCondRET(cpu.reg.fC))),
    0xE0'u8: # RPO
        Instruction((cpu: var CPU) => (cpu.instrCondRET(not cpu.reg.fP))),
    0xE8'u8: # RPE
        Instruction((cpu: var CPU) => (cpu.instrCondRET(cpu.reg.fP))),
    0xF0'u8: # RP
        Instruction((cpu: var CPU) => (cpu.instrCondRET(not cpu.reg.fS))),
    0xF8'u8: # RM
        Instruction((cpu: var CPU) => (cpu.instrCondRET(cpu.reg.fS))),


    0xC7'u8: # RST 0
        Instruction((cpu: var CPU) => (cpu.instrCALL(0x00))),
    0xCF'u8: # RST 1
        Instruction((cpu: var CPU) => (cpu.instrCALL(0x08))),
    0xD7'u8: # RST 2
        Instruction((cpu: var CPU) => (cpu.instrCALL(0x10))),
    0xDF'u8: # RST 3
        Instruction((cpu: var CPU) => (cpu.instrCALL(0x18))),
    0xE7'u8: # RST 4
        Instruction((cpu: var CPU) => (cpu.instrCALL(0x20))),
    0xEF'u8: # RST 5
        Instruction((cpu: var CPU) => (cpu.instrCALL(0x28))),
    0xF7'u8: # RST 6
        Instruction((cpu: var CPU) => (cpu.instrCALL(0x30))),
    0xFF'u8: # RST 7
        Instruction((cpu: var CPU) => (cpu.instrCALL(0x38))),


    # ====== Undocumented ======
    0xCB'u8: # Undocumented JMP
        Instruction((cpu: var CPU) => (cpu.instrJMP(cpu.popPC16()))),

    0xD9'u8: # Undocumented RET
        Instruction((cpu: var CPU) => (cpu.instrRET())),

    0xDD'u8: # Undocumented CALLs
        Instruction((cpu: var CPU) => (cpu.instrCALL(cpu.popPC16()))),
    0xED'u8:
        Instruction((cpu: var CPU) => (cpu.instrCALL(cpu.popPC16()))),
    0xFD'u8:
        Instruction((cpu: var CPU) => (cpu.instrCALL(cpu.popPC16()))),





# ========== Misc/control instructions ==========
    0x00'u8: # NOP
        Instruction((cpu: var CPU) => (discard)),
    0x76'u8: # HLT
        Instruction((cpu: var CPU) => (cpu.halted = true)),

    0xD3'u8: # OUT d8
        Instruction((cpu: var CPU) => (cpu.port_out(cpu, cpu.popPC(), cpu.reg.A))),
    0xDD'u8: # IN d8
        Instruction((cpu: var CPU) => (cpu.reg.A = cpu.port_in(cpu, cpu.popPC()))),

    0xF3'u8: # DI
        Instruction((cpu: var CPU) => (cpu.IME = false)),
    0xFB'u8: # EI
        Instruction((cpu: var CPU) => (cpu.IME = true; cpu.interrupt_delay = 1)),

    # ====== Undocumented ======
    0x08'u8: # Undocumented NOPs
        Instruction((cpu: var CPU) => (discard)),
    0x10'u8: # NOP
        Instruction((cpu: var CPU) => (discard)),
    0x18'u8: # NOP
        Instruction((cpu: var CPU) => (discard)),
    0x20'u8: # NOP
        Instruction((cpu: var CPU) => (discard)),
    0x28'u8: # NOP
        Instruction((cpu: var CPU) => (discard)),
    0x30'u8: # NOP
        Instruction((cpu: var CPU) => (discard)),
    0x38'u8: # NOP
        Instruction((cpu: var CPU) => (discard)),



    }.toTable

# proc ExecuteNextOpcode*(cpu: var CPU): byte =
#     let
#         opcode = cpu.popPC()
#         next_inst = ops[opcode]
#     cpu.owed_cycles += next_inst.cycles
#     next_inst.exec(cpu)
#     return opcode

proc execute*(cpu: var CPU, opcode: byte) =
    let
        next_inst = ops[opcode]


    cpu.cycles += OPCODES_CYCLES[opcode]

    if cpu.interrupt_delay > 0:
        cpu.interrupt_delay -= 1

    cpu.next_inst()


