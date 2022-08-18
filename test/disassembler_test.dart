import 'package:test/test.dart';
import 'package:dart_z80/dart_z80.dart';

void main() {
  test('Single byte instruction', () {
    final instruction = Disassembler.disassembleInstruction([0xF3]);
    expect(instruction.byteCode, equals('f3         '));
    expect(instruction.disassembly, equals('DI'));
    expect(instruction.length, equals(1));
  });

  test('Single byte instruction 2', () {
    final instruction = Disassembler.disassembleInstruction([0xAF]);
    expect(instruction.byteCode, equals('af         '));
    expect(instruction.disassembly, equals('XOR A'));
    expect(instruction.length, equals(1));
  });

  test('Double byte instruction', () {
    final instruction = Disassembler.disassembleInstruction([0xDB, 0x01]);
    expect(instruction.byteCode, equals('db 01      '));
    expect(instruction.disassembly, equals('IN A, (01h)'));
    expect(instruction.length, equals(2));
  });

  test('Double byte instruction 2', () {
    final instruction = Disassembler.disassembleInstruction([0xD3, 0xFE]);
    expect(instruction.byteCode, equals('d3 fe      '));
    expect(instruction.disassembly, equals('OUT (FEh), A'));
    expect(instruction.length, equals(2));
  });

  test('Triple byte instruction', () {
    final instruction = Disassembler.disassembleInstruction([0x11, 0xFF, 0xFF]);
    expect(instruction.byteCode, equals('11 ff ff   '));
    expect(instruction.disassembly, equals('LD DE, FFFFh'));
    expect(instruction.length, equals(3));
  });

  test('Triple byte instruction 2', () {
    final instruction = Disassembler.disassembleInstruction([0xC3, 0xCB, 0x11]);
    expect(instruction.byteCode, equals('c3 cb 11   '));
    expect(instruction.disassembly, equals('JP 11CBh'));
    expect(instruction.length, equals(3));
  });
}
