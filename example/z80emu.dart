import 'dart:io';

import 'package:dart_z80/dart_z80.dart';

// Runs the ZEXDOC and ZEXALL test suites.

const cpuSpeed = 4000000;
const cyclesPerStep = (cpuSpeed ~/ 50);
const maxStringLength = 100;

final memory = Memory(64 * 1024);
final z80 =
    Z80(memory, portReadFunction: portRead, portWriteFunction: portWrite);

bool isDone = false;

/* Emulate CP/M bdos call 5 functions 2 (output character on screen) and 9
 * (output dollar-terminated string to screen).
 */

int portRead(int port) {
  if (z80.c == 2) {
    stdout.write(String.fromCharCode(z80.e));
  } else if (z80.c == 9) {
    var charCount = 0;

    for (var addr = z80.de;; addr++) {
      final char = String.fromCharCode(memory.readByte(addr));
      if (char == '\$' || ++charCount >= maxStringLength) break;

      stdout.write(String.fromCharCode(memory.readByte(addr)));
    }

    return 0;
  }

  return 0;
}

void portWrite(int addr, int value) {
  isDone = true;
}

void main() {
  final start = DateTime.now();
  emulate('testfiles/zexdoc.com');
  // emulate('testfiles/zexall.com');
  final stop = DateTime.now();
  final duration = stop.difference(start);
  print('Emulating zexdoc and zexall took a total of'
      ' ${duration.inSeconds} seconds');
}

void emulate(String filename) {
  var total = 0;

  print('Testing "$filename"...');

  final file = File(filename).readAsBytesSync();
  z80.pc = 0x100;
  memory.load(0x100, file);

  // Patch the memory of the program. Reset at 0x0000 is trapped by an OUT which
  // will stop emulation. CP/M bdos call 5 is trapped by an IN. See
  // Z80_INPUT_BYTE() and Z80_OUTPUT_BYTE() definitions in z80user.h.
  memory.writeByte(0, 0xd3); /* OUT N, A */
  memory.writeByte(1, 0x00);

  memory.writeByte(5, 0xdb); /* IN A, N */
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
