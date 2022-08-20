[![pub package](https://img.shields.io/pub/v/dart_z80.svg)](https://pub.dev/packages/dart_z80)
[![Language](https://img.shields.io/badge/language-Dart-blue.svg)](https://dart.dev)
![Build](https://github.com/timsneath/z80/workflows/Build/badge.svg)
[![codecov](https://codecov.io/gh/timsneath/z80/branch/main/graph/badge.svg?token=zr4wE5pmay)](https://codecov.io/gh/timsneath/z80)

A functional Zilog Z80 microprocessor emulator written in Dart. Originally
intended for use with Cambridge, a ZX Spectrum emulator
(<https://github.com/timsneath/cambridge>).

The emulator passes the comprehensive FUSE test suite, which contains 1356 tests
that evaluate the correctness of both documented and undocumented instructions.
It also passes `ZEXDOC` (sometimes referred to as `zexlax` test suite).

Not all undocumented registers or flags are implemented (e.g. the `W` register
is not implemented).

The emulator itself is licensed under the MIT license (see LICENSE). The
`ZEXALL` and `ZEXDOC` test suites included with this emulator are licensed under
GPL, per the separate license in that folder.
