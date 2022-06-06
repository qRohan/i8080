import std/bitops

type
    Registers* = object
        A: byte
        B: byte
        C: byte
        D: byte
        E: byte
        F: byte
        H: byte
        L: byte

        SP: uint16
        PC: uint16

proc `A`*(r: Registers): byte =
    r.A

proc `A=`*(r: var Registers, val: byte) =
    r.A = val

proc `B`*(r: Registers): byte =
    r.B

proc `B=`*(r: var Registers, val: byte) =
    r.B = val

proc `C`*(r: Registers): byte =
    r.C

proc `C=`*(r: var Registers, val: byte) =
    r.C = val

proc `D`*(r: Registers): byte =
    r.D

proc `D=`*(r: var Registers, val: byte) =
    r.D = val

proc `E`*(r: Registers): byte =
    r.E

proc `E=`*(r: var Registers, val: byte) =
    r.E = val

proc `F`*(r: Registers): byte =
    r.F

proc `F=`*(r: var Registers, val: byte) =
    r.F = (val and 0xD7'u8) or 0x02'u8

proc `H`*(r: Registers): byte =
    r.H

proc `H=`*(r: var Registers, val: byte) =
    r.H = val

proc `L`*(r: Registers): byte =
    r.L

proc `L=`*(r: var Registers, val: byte) =
    r.L = val


proc `SP`*(r: Registers): uint16 =
    r.SP

proc `SP=`*(r: var Registers, val: uint16) =
    r.SP = val

proc `PC`*(r: var Registers): uint16 =
    r.PC

proc `PC=`*(r: var Registers, val: uint16) =
    r.PC = val


proc `PSW`*(r: Registers): uint16 =
    result = (uint16(r.A) shl 8) or r.F

proc `PSW=`*(r: var Registers, val: uint16) =
    r.A = byte((val and 0xFF00) shr 8)
    r.`F=`byte(val and 0x00FF)

proc `BC`*(r: Registers): uint16 =
    result = (uint16(r.B) shl 8) or r.C

proc `BC=`*(r: var Registers, val: uint16) =
    r.B = byte((val and 0xFF00) shr 8)
    r.C = byte(val and 0x00FF)

proc `DE`*(r: Registers): uint16 =
    result = (uint16(r.D) shl 8) or r.E

proc `DE=`*(r: var Registers, val: uint16) =
    r.D = byte((val and 0xFF00) shr 8)
    r.E = byte(val and 0x00FF)

proc `HL`*(r: Registers): uint16 =
    result = (uint16(r.H) shl 8) or r.L

proc `HL=`*(r: var Registers, val: uint16) =
    r.H = byte((val and 0xFF00) shr 8)
    r.L = byte(val and 0x00FF)


# FLAGS
proc setFlag(r: var Registers, index: byte, `set`: bool) =
    if `set`:
        r.F.setBit(index)
    else:
        r.F.clearBit(index)

# Sign
proc `fS`*(r: Registers): bool =
    r.F.testBit(7)

proc `fS=`*(r: var Registers, `set`: bool) =
    r.setFlag(7, `set`)

# Zero
proc `fZ`*(r: Registers): bool =
    r.F.testBit(6)

proc `fZ=`*(r: var Registers, `set`: bool) =
    r.setFlag(6, `set`)

# Auxiliary Carry
proc `fH`*(r: Registers): bool =
    r.F.testBit(4)

proc `fH=`*(r: var Registers, `set`: bool) =
    r.setFlag(4, `set`)

# Parity
proc `fP`*(r: Registers): bool =
    r.F.testBit(2)

proc `fP=`*(r: var Registers, `set`: bool) =
    r.setFlag(2, `set`)

# Carry
proc `fC`*(r: Registers): bool =
    r.F.testBit(0)

proc `fC=`*(r: var Registers, `set`: bool) =
    r.setFlag(0, `set`)

proc newRegisters*(): Registers =
    result = Registers()
    result.F = result.F or 0x02
