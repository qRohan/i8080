import std/strformat
import std/strutils

import std/unittest
# import nimprof

import i8080

const MEMORY_SIZE = 0x10000


var
    test_finished: bool
    user_mem: array[0x10000, byte]

proc rb(address: uint16): byte =
    user_mem[address]

proc wb(address: uint16, value: byte) =
    user_mem[address] = value

proc port_in(cpu: var CPU, port: byte): byte =
    return 0x00

proc port_out(cpu: var CPU, port: byte, value: byte) =
    if port == 0:
        test_finished = true
    elif port == 1:
        let operation = cpu.reg.C

        if operation == 2:
            stdout.write chr(cpu.reg.E)
        elif operation == 9:
            var address = cpu.reg.DE

            while true:
                stdout.write chr(cpu.mem[address])
                inc(address)

                if chr(cpu.mem[address]) == '$':
                    break

proc load_file(filename: string, address: uint16) =
    var fp = open(filename)

    var size = fp.getFileSize()

    if size + int(address) > MEMORY_SIZE:
        stderr.write(fmt"error: file {filename} can't fit in memory.\n")
        raise newException(RangeDefect, fmt"file {filename} can't fit in memory")

    var read_bytes = fp.readBytes(user_mem, address, size)

    if read_bytes != size:
        stderr.write(fmt"error: while reading file {filename} \n")
        raise newException(AssertionDefect, fmt"error while reading file {filename}")

    fp.close()


proc run_test(cpu: var CPU, filename: string, cyc_expected: int64): bool =
    cpu.cycles = 0
    load_file(filename, 0x100)

    cpu.mem = Memory(read_byte: rb, write_byte: wb)
    cpu.port_in = port_in
    cpu.port_out = port_out

    echo(fmt"*** TEST: {filename.split('/')[^1]}")

    cpu.PC = 0x100

    # inject "out 0,a" at 0x0000 (signal to stop the test)
    cpu.mem[0x00] = 0xD3'u8;
    cpu.mem[0x01] = 0x00'u8;

    # inject "out 1,a" at 0x0005 (signal to output some characters)
    cpu.mem[0x05] = 0xD3'u8;
    cpu.mem[0x06] = 0x01'u8;
    cpu.mem[0x07] = 0xC9'u8;

    var nb_instructions = 0

    test_finished = false

    while not test_finished:
        nb_instructions += 1
        # cpu.debug_output()

        cpu.step()

    var diff = cyc_expected - cpu.cycles

    echo(fmt"{'\n'}*** {nb_instructions} instructions executed on {cpu.cycles} cycles (expected={cyc_expected}, diff={diff}){'\n'}");
    return diff == 0

var cpu = newCPU()

echo '\n'
test "TST8080.COM":
    check cpu.run_test("tests/roms/TST8080.COM", 4924)

echo '\n'
test "CPUTEST.COM":
    check cpu.run_test("tests/roms/CPUTEST.COM", 255653383)

echo '\n'
test "8080PRE.COM":
    check cpu.run_test("tests/roms/8080PRE.COM", 7817)

echo '\n'
test "8080EXM.COM":
    check cpu.run_test("tests/roms/8080EXM.COM", 23803381171)

