import 'dart:typed_data';

import 'package:dart_z80/dart_z80.dart';

/// Represents a contiguous memory space as used in a microcomputer like the ZX
/// Spectrum or TRS-80.
///
/// An actual computer implementation may extend this with a specific
/// implementation that includes a fixed memory space, and probably some notion
/// of a read-only ROM storage area.
class Memory {
  late final Uint8List _memory;

  Memory(int? sizeInBytes) : _memory = Uint8List(sizeInBytes ?? 0x10000);

  /// Load a list of byte data into memory, starting at origin.
  void load(int origin, Iterable<int> data) =>
      _memory.setRange(origin, origin + data.length, data);

  /// Read a single byte from the given memory location.
  int readByte(int address) => _memory[address];

  /// Read a single word from the given memory location.
  int readWord(int address) =>
      createWord(_memory[address], _memory[address + 1]);

  /// Resets or clears the memory address space.
  ///
  /// Read-only memory may be preserved after a reset.
  void reset() => _memory.fillRange(0, _memory.length, 0);

  /// Write a single byte to the given memory location.
  void writeByte(int address, int value) => _memory[address] = value;

  /// Write a single word to the given memory location.
  void writeWord(int address, int value) {
    _memory[address] = lowByte(value);
    _memory[address + 1] = highByte(value);
  }
}
