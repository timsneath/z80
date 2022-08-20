import 'dart:io';

import 'package:dart_z80/dart_z80.dart';

// Runs the ZEXDOC and ZEXALL test suites.

const cpuSpeed = 3500000; // Zilog Z80A used in ZX Spectrum clocked at 3.5MHz
const cyclesPerStep = (cpuSpeed ~/ 50);
const maxStringLength = 100;

// The test suite uses two CP/M BDOS calls, which we emulate here. Per
// https://www.seasip.info/Cpm/bdos.html, to make a CP/M system call, you load C
// with the chosen function, DE with a parameter, and then CALL 5.
//
// The function that is set below calls IN, which is trapped by this function.
// - function 2: print ASCII character in E to screen
// - function 9: print dollar-terminated string pointed to by DE to screen
int portRead(int port) {
  switch (z80.c) {
    case 2:
      stdout.write(String.fromCharCode(z80.e));
      return 0;
    case 9:
      var charCount = 0;

      for (var addr = z80.de;; addr++) {
        final char = String.fromCharCode(memory.readByte(addr));
        if (char == '\$' || ++charCount >= maxStringLength) break;

        stdout.write(String.fromCharCode(memory.readByte(addr)));
      }

      return 0;
    default:
      return 0;
  }
}

void portWrite(int addr, int value) => isDone = true;

void emulate(File file) {
  var total = 0;

  print('Testing "${file.path}"...');
  z80.pc = 0x100;
  memory.load(0x100, file.readAsBytesSync());

  // Patch memory locations to handle CP/M BDOS calls.
  // Reset at 0x0000 (RST 0h) is trapped by an OUT which will stop emulation.
  // CALL 5 is trapped by an IN.
  memory.writeByte(0, 0xd3); /* OUT (00h), A */
  memory.writeByte(1, 0x00);

  memory.writeByte(5, 0xdb); /* IN A, (00h) */
  memory.writeByte(6, 0x00);
  memory.writeByte(7, 0xc9); /* RET */

  // First member of ZEXTEST is state, so this is safe.
  do {
    z80.executeNextInstruction();
    total++;
  } while (!isDone);
  print('\n$total cycle(s) emulated.\n'
      'For a Z80 running at ${cpuSpeed / 1000000}MHz, '
      'that would be ${total / cpuSpeed} seconds '
      'or ${total / (3600 * cpuSpeed)} hour(s).');
}

final memory = RAM(64 * 1024); // 64KB
final z80 = Z80(memory, onPortRead: portRead, onPortWrite: portWrite);
bool isDone = false;

void main() {
  final start = DateTime.now();
  emulate(File('example/testfiles/zexdoc.com'));
  // emulate(File('example/testfiles/zexall.com'));
  final stop = DateTime.now();
  final duration = stop.difference(start);
  print('Emulating zexdoc took a total of'
      ' ${duration.inSeconds} seconds');
}
