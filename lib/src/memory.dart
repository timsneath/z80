import 'dart:typed_data';

import 'package:dart_z80/dart_z80.dart';

/// Represents a contiguous memory space as used in a microcomputer like the ZX
/// Spectrum or TRS-80.
///
/// An actual computer implementation may extend this with a specific
/// implementation that includes a fixed memory space, and probably some notion
/// of a read-only ROM storage area.
class Memory {
  late final Uint8List memory;

  Memory(int sizeInBytes) : memory = Uint8List(sizeInBytes);

  /// Load a list of byte data into memory, starting at origin.
  void load(int origin, Iterable<int> data) =>
      memory.setRange(origin, origin + data.length, data);

  /// Read a single byte from the given memory location.
  int readByte(int address) => memory[address];

  /// Read a single word from the given memory location.
  int readWord(int address) => createWord(memory[address], memory[address + 1]);

  /// Resets or clears the memory address space.
  ///
  /// Read-only memory may be preserved after a reset.
  void reset() => memory.fillRange(0, memory.length, 0);

  /// Write a single byte to the given memory location.
  void writeByte(int address, int value) => memory[address] = value;

  /// Write a single word to the given memory location.
  void writeWord(int address, int value) {
    memory[address] = lowByte(value);
    memory[address + 1] = highByte(value);
  }
}
