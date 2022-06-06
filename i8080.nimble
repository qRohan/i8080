# Package

version       = "0.1.0"
author        = "Rohan Jakhar"
description   = "Intel 8080 emulator"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 1.6.6"


task test, "Runs the test suite":
  exec "nim c -d:release -r tests/tester"