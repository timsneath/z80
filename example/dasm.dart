import 'dart:io';

import 'package:dart_z80/dart_z80.dart';

void main(List<String> args) {
  if (args.length < 3) {
    print("dart dasm.dart filename [start-hex] [end-hex]");
    exit(1);
  }

  final rom = File(args[0]).readAsBytesSync();
  final start = int.parse(args[1]);
  final end = int.parse(args[2]);

  var idx = start;

  while (idx < end) {
    // We don't know whether the opcode is 1, 2, or 4 bytes long, so we just
    // pass the next four bytes to the disassembler. The disassembler itself
    // will tell us how many bytes were in the opcode, and we'll use that to
    // move the index forward.
    final dasm = Disassembler.disassembleInstruction(
        [rom[idx], rom[idx + 1], rom[idx + 2], rom[idx + 3]]);

    print('[${toHex32(idx)}]  ${dasm.byteCode}  ${dasm.disassembly}');
    idx += dasm.length;
  }
}
