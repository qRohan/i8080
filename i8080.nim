import std/strformat
import i8080/cpu
import i8080/instructions
import i8080/memory
import i8080/registers


proc step*(cpu: var CPU) =
    if cpu.interrupt_pending and cpu.IME and (cpu.interrupt_delay == 0):
        cpu.interrupt_pending = false
        cpu.IME = false
        cpu.halted = false

        cpu.execute(cpu.interrupt_vector)
    
    elif not cpu.halted:
        cpu.execute(cpu.popPC())

proc interrupt*(cpu: var CPU, opcode: byte) =
    cpu.interrupt_pending = true
    cpu.interrupt_vector = opcode

proc debug_output*(cpu: var CPU) = 
    var debug_string = fmt"PC: {cpu.PC:04X}, AF: {cpu.reg.PSW:04X}, BC: {cpu.reg.BC:04X},"
    debug_string &= fmt" DE: {cpu.reg.DE:04X}, HL: {cpu.reg.HL:04X}, SP: {cpu.reg.SP:04X}, CYC: {cpu.cycles}"
    debug_string &= "\t"
    debug_string &= fmt"({(cpu.mem[cpu.PC]):02X} {(cpu.mem[cpu.PC+1]):02X} {(cpu.mem[cpu.PC+2]):02X} {(cpu.mem[cpu.PC+3]):02X})"
    echo debug_string

export cpu, memory, registers