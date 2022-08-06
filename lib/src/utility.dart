// utility.dart -- common methods for manipulating bytes and words

/// Extract the high byte of a 16-bit value.
int highByte(int value) => (value & 0xFF00) >> 8;

/// Extract the low byte of a 16-bit value.
int lowByte(int value) => value & 0x00FF;

/// Convert two bytes into a 16-bit word.
int createWord(int lowByte, int highByte) => (highByte << 8) + lowByte;

/// Format a byte as a hex string.
String toHex8(int value) => (value & 0xFF).toRadixString(16).padLeft(1, '0');

/// Format a word as a hex string.
String toHex16(int value) => (value & 0xFFFF).toRadixString(16).padLeft(2, '0');

/// Format a dword as a hex string.
String toHex32(int value) =>
    (value & 0xFFFFFFFF).toRadixString(16).padLeft(4, '0');

/// Format a byte as a binary string.
String toBin8(int value) => (value & 0xFF).toRadixString(2).padLeft(8, '0');

/// Format a word as a binary string.
String toBin16(int value) => (value & 0xFFFF).toRadixString(2).padLeft(16, '0');

/// Format a dword as a binary string.
String toBin32(int value) =>
    (value & 0xFFFFFFFF).toRadixString(2).padLeft(32, '0');

/// Calculates 2s complement of an 8-bit value.
int twocomp8(int value) => -(value & 0x80) + (value & ~0x80);

/// Calculates 2s complement of a 16-bit value.
int twocomp16(int value) => -(value & 0x8000) + (value & ~0x8000);

// Calculate 1s complement of an 8-bit value.
int onecomp8(int value) => (~value).toSigned(8) % 0x100;

// Calculate 1s complement of a 16-bit value.
int onecomp16(int value) => (~value).toSigned(16) % 0x10000;

/// Calculate parity of an arbitrary length integer.
bool isParity(int value) {
  // Algorithm for counting set bits taken from LLVM optimization proposal at:
  //    https://llvm.org/bugs/show_bug.cgi?id=1488
  var count = 0;

  for (var v = value; v != 0; count++) {
    v &= v - 1; // clear the least significant bit set
  }
  return count % 2 == 0;
}

/// Return true if a given bit is set in a binary integer of arbitrary length.
bool isBitSet(int value, int bit) => (value & (1 << bit)) == 1 << bit;

/// Set a given bit in a binary integer of arbitrary length.
int setBit(int value, int bit) => value | (1 << bit);

/// Reset a given bit in a binary integer of arbitrary length.
int resetBit(int value, int bit) => value & ~(1 << bit);

/// Return true if a signed byte is negative.
bool isSign8(int value) => (value & 0x80) == 0x80;

/// Return true if a signed word is negative.
bool isSign16(int value) => (value & 0x8000) == 0x8000;

/// Return true if a given value is zero.
bool isZero(int value) => value == 0;

/// Return true if a given value is odd.
bool isOdd(int value) => value & 0x01 == 0x01;

/// Return true if a given value is even.
bool isEven(int value) => ~value & 0x01 == 0x01;
