// z80.dart -- implements the Zilog Z80 processor core
//
// Reference notes:
// The Z80 microprocessor user manual can be downloaded from Zilog:
//    http://tinyurl.com/z80manual
//
// Other useful details of the Z80 architecture can be found here:
//    http://landley.net/history/mirror/cpm/z80.html
// and here:
//    http://z80.info/z80code.htm

import 'memory.dart';
import 'utility.dart';

// We use register names for the fields and we don't fuss too much about this.
// ignore_for_file: non_constant_identifier_names

typedef PortReadCallback = int Function(int);
typedef PortWriteCallback = void Function(int, int);

int defaultPortReadFunction(int port) => highByte(port);
void defaultPortWriteFunction(int addr, int value) {}

// Opcodes that can be prefixed with DD or FD, but are the same as the
// unprefixed versions (albeit slower).
const _extendedCodes = [
  0x04, 0x05, 0x06, 0x0c, 0x0d, 0x0e,
  0x14, 0x15, 0x16, 0x1c, 0x1d, 0x1e,
  0x3c, 0x3d, 0x3e, // inc/dec
  0x40, 0x41, 0x42, 0x43, 0x47, 0x48, 0x49, 0x4a, 0x4b, 0x4f,
  0x50, 0x51, 0x52, 0x53, 0x57, 0x58, 0x59, 0x5a, 0x5b, 0x5f, // ld
  0x78, 0x79, 0x7a, 0x7b, 0x7f,
  0x80, 0x81, 0x82, 0x83, 0x87, 0x88, 0x89, 0x8a, 0x8b, 0x8f,
  0x90, 0x91, 0x92, 0x93, 0x97, 0x98, 0x99, 0x9a, 0x9b, 0x9f,
  0xa0, 0xa1, 0xa2, 0xa3, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xaf,
  0xb0, 0xb1, 0xb2, 0xb3, 0xb7, 0xb8, 0xb9, 0xba, 0xbb, 0xbf // add/sub/and/or
];

class Z80 {
  final Memory memory;
  bool cpuSuspended;
  int tStates;

  late final PortReadCallback onPortRead;
  late final PortWriteCallback onPortWrite;

  Z80(
    this.memory, {
    int startAddress = 0,
    this.onPortRead = defaultPortReadFunction,
    this.onPortWrite = defaultPortWriteFunction,
  })  : af = 0xFFFF,
        bc = 0xFFFF,
        de = 0xFFFF,
        hl = 0xFFFF,
        a_ = 0xFF,
        f_ = 0xFF,
        b_ = 0xFF,
        c_ = 0xFF,
        d_ = 0xFF,
        e_ = 0xFF,
        h_ = 0xFF,
        l_ = 0xFF,
        ix = 0xFFFF,
        iy = 0xFFFF,
        sp = 0xFFFF,
        pc = startAddress,
        iff1 = false,
        iff2 = false,
        im = 0,
        i = 0xFF,
        r = 0xFF,
        tStates = 0,
        cpuSuspended = false;

  void reset() {
    // Initial register states are set per section 2.4 of
    //  http://www.myquest.nl/z80undocumented/z80-documented-v0.91.pdf
    af = 0xFFFF;
    bc = 0xFFFF;
    de = 0xFFFF;
    hl = 0xFFFF;
    ix = 0xFFFF;
    iy = 0xFFFF;
    sp = 0xFFFF;
    pc = 0x0000;
    a_ = 0xFF;
    f_ = 0xFF;
    b_ = 0xFF;
    c_ = 0xFF;
    d_ = 0xFF;
    e_ = 0xFF;
    h_ = 0xFF;
    l_ = 0xFF;

    iff1 = iff2 = false;
    im = 0;
    i = r = 0xFF;

    tStates = 0;
    cpuSuspended = false;
  }

  void interrupt({bool nonMaskable = false}) {
    if (nonMaskable) {
      pc = 0x0066;
    } else {
      if (iff1) {
        // Interrupts enabled
        switch (im) {
          case 0:
            // Not used on the ZX Spectrum
            break;
          case 1:
            iff1 = false;

            PUSH(pc);
            pc = 0x0038;
            break;
          case 2:
            // TODO: Implement IM2
            break;
        }
      }
    }
  }

  // *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
  // REGISTERS
  // *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***

  // Flags: SZ5H3PNC
  final flags = const {
    'C': 0x01, // carry flag (bit 0)
    'N': 0x02, // add/subtract flag (bit 1)
    'P': 0x04, // parity/overflow flag (bit 2)
    'F3': 0x08, // undocumented flag
    'H': 0x10, // half carry flag (bit 4)
    'F5': 0x20, // undocumented flag
    'Z': 0x40, // zero flag (bit 6)
    'S': 0x80 // sign flag (bit 7)
  };

  // Core registers
  int af, bc, de, hl, ix, iy;

  // The alternate register set (A', F', B', C', D', E', H', L')
  int a_, f_, b_, c_, d_, e_, h_, l_;

  int i; // Interrupt Page Address register
  int r; // Memory Refresh register

  int pc; // Program Counter
  int sp; // Stack pointer

  bool iff1;
  bool iff2;

  int im; // Interrupt Mode

  int get a => highByte(af);
  set a(int value) => af = createWord(value, f);

  int get f => lowByte(af);
  set f(int value) => af = createWord(a, value);

  int get b => highByte(bc);
  set b(int value) => bc = createWord(value, c);

  int get c => lowByte(bc);
  set c(int value) => bc = createWord(b, value);

  int get d => highByte(de);
  set d(int value) => de = createWord(value, e);

  int get e => lowByte(de);
  set e(int value) => de = createWord(d, value);

  int get h => highByte(hl);
  set h(int value) => hl = createWord(value, l);

  int get l => lowByte(hl);
  set l(int value) => hl = createWord(h, value);

  int get af_ => createWord(a_, f_);
  set af_(int value) {
    a_ = highByte(value);
    f_ = lowByte(value);
  }

  int get bc_ => createWord(b_, c_);
  set bc_(int value) {
    b_ = highByte(value);
    c_ = lowByte(value);
  }

  int get de_ => createWord(d_, e_);
  set de_(int value) {
    d_ = highByte(value);
    e_ = lowByte(value);
  }

  int get hl_ => createWord(h_, l_);
  set hl_(int value) {
    h_ = highByte(value);
    l_ = lowByte(value);
  }

  int get ixh => (ix & 0xFF00) >> 8;
  int get ixl => ix & 0x00FF;

  set ixh(int value) {
    final lo = lowByte(ix);
    ix = ((value & 0xFF) << 8) + lo;
  }

  set ixl(int value) {
    final hi = highByte(ix);
    ix = (hi << 8) + (value & 0xFF);
  }

  int get iyh => (iy & 0xFF00) >> 8;
  int get iyl => iy & 0x00FF;
  set iyh(int value) {
    final lo = lowByte(iy);
    iy = ((value & 0xFF) << 8) + lo;
  }

  set iyl(int value) {
    final hi = highByte(iy);
    iy = (hi << 8) + (value & 0xFF);
  }

  bool get fC => f & flags['C']! == flags['C'];
  bool get fN => f & flags['N']! == flags['N'];
  bool get fPV => f & flags['P']! == flags['P'];
  bool get f3 => f & flags['F3']! == flags['F3'];
  bool get fH => f & flags['H']! == flags['H'];
  bool get f5 => f & flags['F5']! == flags['F5'];
  bool get fZ => f & flags['Z']! == flags['Z'];
  bool get fS => f & flags['S']! == flags['S'];

  set fC(bool value) => f = value ? (f | flags['C']!) : (f & ~flags['C']!);
  set fN(bool value) => f = value ? (f | flags['N']!) : (f & ~flags['N']!);
  set fPV(bool value) => f = value ? (f | flags['P']!) : (f & ~flags['P']!);
  set f3(bool value) => f = value ? (f | flags['F3']!) : (f & ~flags['F3']!);
  set fH(bool value) => f = value ? (f | flags['H']!) : (f & ~flags['H']!);
  set f5(bool value) => f = value ? (f | flags['F5']!) : (f & ~flags['F5']!);
  set fZ(bool value) => f = value ? (f | flags['Z']!) : (f & ~flags['Z']!);
  set fS(bool value) => f = value ? (f | flags['S']!) : (f & ~flags['S']!);

  // *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
  // INSTRUCTIONS
  // *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***

  void LDI() {
    final byteRead = memory.readByte(hl);
    memory.writeByte(de, byteRead);

    fPV = (bc - 1) != 0;

    de = (de + 1) % 0x10000;
    hl = (hl + 1) % 0x10000;
    bc = (bc - 1) % 0x10000;

    fH = false;
    fN = false;
    f5 = isBitSet((byteRead + a) & 0xFF, 1);
    f3 = isBitSet((byteRead + a) & 0xFF, 3);

    tStates += 16;
  }

  void LDD() {
    final byteRead = memory.readByte(hl);
    memory.writeByte(de, byteRead);

    de = (de - 1) % 0x10000;
    hl = (hl - 1) % 0x10000;
    bc = (bc - 1) % 0x10000;
    fH = false;
    fN = false;
    fPV = bc != 0;
    f5 = isBitSet((byteRead + a) & 0xFF, 1);
    f3 = isBitSet((byteRead + a) & 0xFF, 3);

    tStates += 16;
  }

  void LDIR() {
    final byteRead = memory.readByte(hl);
    memory.writeByte(de, byteRead);

    de = (de + 1) % 0x10000;
    hl = (hl + 1) % 0x10000;
    bc = (bc - 1) % 0x10000;

    if (bc != 0) {
      pc = (pc - 2) % 0x10000;
      tStates += 21;
    } else {
      f5 = isBitSet((byteRead + a) & 0xFF, 1);
      f3 = isBitSet((byteRead + a) & 0xFF, 3);
      fH = false;
      fPV = false;
      fN = false;

      tStates += 16;
    }
  }

  void LDDR() {
    final byteRead = memory.readByte(hl);
    memory.writeByte(de, byteRead);

    de = (de - 1) % 0x10000;
    hl = (hl - 1) % 0x10000;
    bc = (bc - 1) % 0x10000;
    if (bc > 0) {
      pc = (pc - 2) % 0x10000;
      tStates += 21;
    } else {
      f5 = isBitSet((byteRead + a) & 0xFF, 1);
      f3 = isBitSet((byteRead + a) & 0xFF, 3);
      fH = false;
      fPV = false;
      fN = false;

      tStates += 16;
    }
  }

  // Arithmetic operations
  int INC(int reg) {
    final oldReg = reg;
    fPV = reg == 0x7F;
    reg = (reg + 1) % 0x100;
    fH = isBitSet(reg, 4) != isBitSet(oldReg, 4);
    fZ = isZero(reg);
    fS = isSign8(reg);
    f5 = isBitSet(reg, 5);
    f3 = isBitSet(reg, 3);
    fN = false;

    tStates += 4;

    return reg;
  }

  int DEC(int reg) {
    final oldReg = reg;
    fPV = reg == 0x80;
    reg = (reg - 1) % 0x100;
    fH = isBitSet(reg, 4) != isBitSet(oldReg, 4);
    fZ = isZero(reg);
    fS = isSign8(reg);
    f5 = isBitSet(reg, 5);
    f3 = isBitSet(reg, 3);
    fN = true;

    tStates += 4;

    return reg;
  }

  /// Add with carry (8-bit)
  int ADC8(int x, int y) => ADD8(x, y, withCarry: fC);

  /// Add with carry (16-bit)
  int ADC16(int xx, int yy) {
    // overflow in add only occurs when operand polarities are the same
    final overflowCheck = isSign16(xx) == isSign16(yy);

    xx = ADD16(xx, yy, withCarry: fC);

    // if polarity is now different then add caused an overflow
    if (overflowCheck) {
      fPV = isSign16(xx) != isSign16(yy);
    } else {
      fPV = false;
    }
    fS = isSign16(xx);
    fZ = isZero(xx);
    return xx;
  }

  int ADD8(int x, int y, {bool withCarry = false}) {
    final carry = withCarry ? 1 : 0;
    fH = (((x & 0x0F) + (y & 0x0F) + carry) & 0x10) == 0x10;

    // overflow in add only occurs when operand polarities are the same
    final overflowCheck = isSign8(x) == isSign8(y);

    fC = x + y + carry > 0xFF;
    x = (x + y + carry) % 0x100;
    fS = isSign8(x);

    // if polarity is now different then add caused an overflow
    if (overflowCheck) {
      fPV = fS != isSign8(y);
    } else {
      fPV = false;
    }

    f5 = isBitSet(x, 5);
    f3 = isBitSet(x, 3);
    fZ = isZero(x);
    fN = false;

    tStates += 4;

    return x;
  }

  int ADD16(int xx, int yy, {bool withCarry = false}) {
    final carry = withCarry ? 1 : 0;

    fH = (xx & 0x0FFF) + (yy & 0x0FFF) + carry > 0x0FFF;
    fC = xx + yy + carry > 0xFFFF;
    xx = (xx + yy + carry) % 0x10000;
    f5 = isBitSet(xx, 13);
    f3 = isBitSet(xx, 11);
    fN = false;

    tStates += 11;

    return xx;
  }

  int SBC8(int x, int y) => SUB8(x, y, withCarry: fC);

  int SBC16(int xx, int yy) {
    final carry = fC ? 1 : 0;

    fC = xx < (yy + carry);
    fH = (xx & 0xFFF) < ((yy & 0xFFF) + carry);
    fS = isSign16(xx);

    // overflow in subtract only occurs when operand signs are different
    final overflowCheck = isSign16(xx) != isSign16(yy);

    xx = (xx - yy - carry) % 0x10000;
    f5 = isBitSet(xx, 13);
    f3 = isBitSet(xx, 11);
    fZ = isZero(xx);
    fN = true;

    // if x changed polarity then subtract caused an overflow
    if (overflowCheck) {
      fPV = fS != isSign16(xx);
    } else {
      fPV = false;
    }
    fS = isSign16(xx);

    tStates += 15;

    return xx;
  }

  int SUB8(int x, int y, {bool withCarry = false}) {
    final carry = withCarry ? 1 : 0;

    fC = x < (y + carry);
    fH = (x & 0x0F) < ((y & 0x0F) + carry);

    fS = isSign8(x);

    // overflow in subtract only occurs when operand signs are different
    final overflowCheck = isSign8(x) != isSign8(y);

    x = (x - y - carry) % 0x100;
    f5 = isBitSet(x, 5);
    f3 = isBitSet(x, 3);

    // if x changed polarity then subtract caused an overflow
    if (overflowCheck) {
      fPV = fS != isSign8(x);
    } else {
      fPV = false;
    }

    fS = isSign8(x);
    fZ = isZero(x);
    fN = true;

    tStates += 4;

    return x;
  }

  void CP(int x) {
    SUB8(a, x);
    f5 = isBitSet(x, 5);
    f3 = isBitSet(x, 3);
  }

  // algorithm from http://worldofspectrum.org/faq/reference/z80reference.htm
  void DAA() {
    var correctionFactor = 0;
    final oldA = a;

    if ((a > 0x99) || fC) {
      correctionFactor |= 0x60;
      fC = true;
    } else {
      fC = false;
    }

    if (((a & 0x0F) > 0x09) || fH) {
      correctionFactor |= 0x06;
    }

    if (!fN) {
      a = (a + correctionFactor) % 0x100;
    } else {
      a = (a - correctionFactor) % 0x100;
    }

    fH = ((oldA & 0x10) ^ (a & 0x10)) == 0x10;
    f5 = isBitSet(a, 5);
    f3 = isBitSet(a, 3);

    fS = isSign8(a);
    fZ = isZero(a);
    fPV = isParity(a);

    tStates += 4;
  }

  // Flow operations
  void CALL() {
    final callAddr = getNextWord();

    PUSH(pc);

    pc = callAddr;

    tStates += 17;
  }

  void JR(int jump) {
    // jump is treated as signed byte from -128 to 127
    jump = twocomp8(jump);
    pc = (pc + jump) % 0x10000;

    tStates += 12;
  }

  void DJNZ(int jump) {
    b = (b - 1) % 0x100;
    if (b != 0) {
      JR(jump);
      tStates++; // JR is 12 tStates
    } else {
      tStates += 8;
    }
  }

  void RST(int addr) {
    PUSH(pc);
    pc = addr;
    tStates += 11;
  }

  // Stack operations
  void PUSH(int val) {
    sp = (sp - 1) % 0x10000;
    memory.writeByte(sp, highByte(val));
    sp = (sp - 1) % 0x10000;
    memory.writeByte(sp, lowByte(val));
  }

  int POP() {
    final lo = memory.readByte(sp);
    sp = (sp + 1) % 0x10000;
    final hi = memory.readByte(sp);
    sp = (sp + 1) % 0x10000;
    return (hi << 8) + lo;
  }

  void EX_AFAFPrime() {
    int temp;

    temp = a;
    a = a_;
    a_ = temp;

    temp = f;
    f = f_;
    f_ = temp;

    tStates += 4;
  }

  // Logic operations

  void CPD() {
    final val = memory.readByte(hl);
    fH = (a & 0x0F) < (val & 0x0F);
    fS = isSign8(a - val);
    fZ = a == val;
    f5 = isBitSet((a - val - (fH == true ? 1 : 0)) & 0xFF, 1);
    f3 = isBitSet((a - val - (fH == true ? 1 : 0)) & 0xFF, 3);
    fN = true;
    fPV = bc - 1 != 0;
    hl = (hl - 1) % 0x10000;
    bc = (bc - 1) % 0x10000;

    tStates += 16;
  }

  void CPDR() {
    final val = memory.readByte(hl);
    fH = (a & 0x0F) < (val & 0x0F);
    fS = isSign8(a - val);
    fZ = a == val;
    f5 = isBitSet((a - val - (fH == true ? 1 : 0)) & 0xFF, 1);
    f3 = isBitSet((a - val - (fH == true ? 1 : 0)) & 0xFF, 3);
    fN = true;
    fPV = bc - 1 != 0;
    hl = (hl - 1) % 0x10000;
    bc = (bc - 1) % 0x10000;

    if ((bc != 0) && (a != val)) {
      pc = (pc - 2) % 0x10000;
      tStates += 21;
    } else {
      tStates += 16;
    }
  }

  void CPI() {
    final val = memory.readByte(hl);
    fH = (a & 0x0F) < (val & 0x0F);
    fS = isSign8(a - val);
    fZ = a == val;
    f5 = isBitSet((a - val - (fH == true ? 1 : 0)) & 0xFF, 1);
    f3 = isBitSet((a - val - (fH == true ? 1 : 0)) & 0xFF, 3);
    fN = true;
    fPV = bc - 1 != 0;
    hl = (hl + 1) % 0x10000;
    bc = (bc - 1) % 0x10000;

    tStates += 16;
  }

  void CPIR() {
    final val = memory.readByte(hl);
    fH = (a & 0x0F) < (val & 0x0F);
    fS = isSign8(a - val);
    fZ = a == val;
    f5 = isBitSet((a - val - (fH == true ? 1 : 0)) & 0xFF, 1);
    f3 = isBitSet((a - val - (fH == true ? 1 : 0)) & 0xFF, 3);
    fN = true;
    fPV = bc - 1 != 0;

    hl = (hl + 1) % 0x10000;
    bc = (bc - 1) % 0x10000;

    if ((bc != 0) && (a != val)) {
      pc = (pc - 2) % 0x10000;
      tStates += 21;
    } else {
      tStates += 16;
    }
  }

  int OR(int a, int reg) {
    a |= reg;
    fS = isSign8(a);
    fZ = isZero(a);
    fH = false;
    f5 = isBitSet(a, 5);
    f3 = isBitSet(a, 3);

    fPV = isParity(a);
    fN = false;
    fC = false;

    tStates += 4;

    return a;
  }

  int XOR(int a, int reg) {
    a ^= reg;
    fS = isSign8(a);
    fZ = isZero(a);
    fH = false;
    f5 = isBitSet(a, 5);
    f3 = isBitSet(a, 3);

    fPV = isParity(a);
    fN = false;
    fC = false;

    tStates += 4;

    return a;
  }

  int AND(int a, int reg) {
    a &= reg;
    fS = isSign8(a);
    fZ = isZero(a);
    fH = true;
    f5 = isBitSet(a, 5);
    f3 = isBitSet(a, 3);
    fPV = isParity(a);
    fN = false;
    fC = false;

    tStates += 4;

    return a;
  }

  int NEG(int a) {
    // returns two's complement of a
    fPV = a == 0x80;
    fC = a != 0x00;

    a = ~a;
    a = (a + 1) % 0x100;
    f5 = isBitSet(a, 5);
    f3 = isBitSet(a, 3);

    fS = isSign8(a);
    fZ = isZero(a);
    fH = a & 0x0F != 0;
    fN = true;

    tStates += 8;

    return a;
  }

  // TODO: Organize these into the same groups as the Z80 manual
  void CPL() {
    a = onecomp8(a);
    f5 = isBitSet(a, 5);
    f3 = isBitSet(a, 3);
    fH = true;
    fN = true;

    tStates += 4;
  }

  void SCF() {
    f5 = isBitSet(a, 5);
    f3 = isBitSet(a, 3);
    fH = false;
    fN = false;
    fC = true;
  }

  void CCF() {
    f5 = isBitSet(a, 5);
    f3 = isBitSet(a, 3);
    fH = fC;
    fN = false;
    fC = !fC;

    tStates += 4;
  }

  int RLC(int reg) {
    // rotates register r to the left
    // bit 7 is copied to carry and to bit 0
    fC = isSign8(reg);
    reg = (reg << 1) % 0x100;
    if (fC) reg = setBit(reg, 0);

    f5 = isBitSet(reg, 5);
    f3 = isBitSet(reg, 3);
    fS = isSign8(reg);
    fZ = isZero(reg);
    fH = false;
    fPV = isParity(reg);
    fN = false;

    return reg;
  }

  void RLCA() {
    // rotates register A to the left
    // bit 7 is copied to carry and to bit 0
    fC = isSign8(a);
    a = (a << 1) % 0x100;
    if (fC) a = setBit(a, 0);
    f5 = isBitSet(a, 5);
    f3 = isBitSet(a, 3);

    fH = false;
    fN = false;

    tStates += 4;
  }

  int RRC(int reg) {
    fC = isBitSet(reg, 0);
    reg >>= 1;
    if (fC) reg = setBit(reg, 7);

    f5 = isBitSet(reg, 5);
    f3 = isBitSet(reg, 3);
    fS = isSign8(reg);
    fZ = isZero(reg);
    fH = false;
    fPV = isParity(reg);
    fN = false;

    return reg;
  }

  void RRCA() {
    fC = isBitSet(a, 0);
    a >>= 1;
    if (fC) a = setBit(a, 7);

    f5 = isBitSet(a, 5);
    f3 = isBitSet(a, 3);

    fH = false;
    fN = false;

    tStates += 4;
  }

  int RL(int reg) {
    // rotates register r to the left, through carry.
    // carry becomes the LSB of the new r
    final bit0 = fC;

    fC = isSign8(reg);
    reg = (reg << 1) % 0x100;

    if (bit0) reg = setBit(reg, 0);

    fS = isSign8(reg);
    fZ = isZero(reg);
    fH = false;
    f5 = isBitSet(reg, 5);
    f3 = isBitSet(reg, 3);
    fPV = isParity(reg);
    fN = false;

    return reg;
  }

  void RLA() {
    // rotates register r to the left, through carry.
    // carry becomes the LSB of the new r
    final bit0 = fC;

    fC = isSign8(a);
    a = (a << 1) % 0x100;

    if (bit0) a = setBit(a, 0);

    f5 = isBitSet(a, 5);
    f3 = isBitSet(a, 3);

    fH = false;
    fN = false;

    tStates += 4;
  }

  int RR(int reg) {
    final bit7 = fC;

    fC = isBitSet(reg, 0);
    reg >>= 1;

    if (bit7) reg = setBit(reg, 7);

    fS = isSign8(reg);
    fZ = isZero(reg);
    fH = false;
    f5 = isBitSet(reg, 5);
    f3 = isBitSet(reg, 3);
    fPV = isParity(reg);
    fN = false;

    return reg;
  }

  void RRA() {
    final bit7 = fC;

    fC = isBitSet(a, 0);
    a >>= 1;

    if (bit7) {
      a = setBit(a, 7);
    }

    f5 = isBitSet(a, 5);
    f3 = isBitSet(a, 3);

    fH = false;
    fN = false;

    tStates += 4;
  }

  int SLA(int reg) {
    fC = isSign8(reg);
    reg = (reg << 1) % 0x100;

    f5 = isBitSet(reg, 5);
    f3 = isBitSet(reg, 3);

    fS = isSign8(reg);
    fZ = isZero(reg);
    fH = false;
    fPV = isParity(reg);
    fN = false;

    return reg;
  }

  int SRA(int reg) {
    final bit7 = isSign8(reg);

    fC = isBitSet(reg, 0);
    reg >>= 1;

    if (bit7) reg = setBit(reg, 7);

    f5 = isBitSet(reg, 5);
    f3 = isBitSet(reg, 3);

    fS = isSign8(reg);
    fZ = isZero(reg);
    fH = false;
    fPV = isParity(reg);
    fN = false;

    return reg;
  }

  int SLL(int reg) {
    // technically, SLL is undocumented
    fC = isBitSet(reg, 7);
    reg = (reg << 1) % 0x100;
    reg = setBit(reg, 0);

    f5 = isBitSet(reg, 5);
    f3 = isBitSet(reg, 3);

    fS = isSign8(reg);
    fZ = isZero(reg);
    fH = false;
    fPV = isParity(reg);
    fN = false;

    return reg;
  }

  int SRL(int reg) {
    fC = isBitSet(reg, 0);
    reg >>= 1;
    reg = resetBit(reg, 7);

    f5 = isBitSet(reg, 5);
    f3 = isBitSet(reg, 3);

    fS = isSign8(reg);
    fZ = isZero(reg);
    fH = false;
    fPV = isParity(reg);
    fN = false;

    return reg;
  }

  void RLD() {
    // TODO: Overflow condition for this and RRD
    final old_pHL = memory.readByte(hl);

    var new_pHL = (old_pHL & 0x0F) << 4;
    new_pHL += a & 0x0F;

    a = a & 0xF0;
    a += (old_pHL & 0xF0) >> 4;

    memory.writeByte(hl, new_pHL);

    f5 = isBitSet(a, 5);
    f3 = isBitSet(a, 3);

    fS = isSign8(a);
    fZ = isZero(a);
    fH = false;
    fPV = isParity(a);
    fN = false;

    tStates += 18;
  }

  void RRD() {
    final old_pHL = memory.readByte(hl);

    var new_pHL = (a & 0x0F) << 4;
    new_pHL += (old_pHL & 0xF0) >> 4;

    a = a & 0xF0;
    a += old_pHL & 0x0F;

    memory.writeByte(hl, new_pHL);

    f5 = isBitSet(a, 5);
    f3 = isBitSet(a, 3);

    fS = isSign8(a);
    fZ = isZero(a);
    fH = false;
    fPV = isParity(a);
    fN = false;

    tStates += 18;
  }

  // Bitwise operations
  void BIT(int bitToTest, int reg) {
    switch (reg) {
      case 0x0:
        fZ = !isBitSet(b, bitToTest);
        f3 = isBitSet(b, 3);
        f5 = isBitSet(b, 5);
        fPV = fZ;
        break;
      case 0x1:
        fZ = !isBitSet(c, bitToTest);
        f3 = isBitSet(c, 3);
        f5 = isBitSet(c, 5);
        fPV = fZ;
        break;
      case 0x2:
        fZ = !isBitSet(d, bitToTest);
        f3 = isBitSet(d, 3);
        f5 = isBitSet(d, 5);
        fPV = fZ;
        break;
      case 0x3:
        fZ = !isBitSet(e, bitToTest);
        f3 = isBitSet(e, 3);
        f5 = isBitSet(e, 5);
        fPV = fZ;
        break;
      case 0x4:
        fZ = !isBitSet(h, bitToTest);
        f3 = isBitSet(h, 3);
        f5 = isBitSet(h, 5);
        fPV = fZ;
        break;
      case 0x5:
        fZ = !isBitSet(l, bitToTest);
        f3 = isBitSet(l, 3);
        f5 = isBitSet(l, 5);
        fPV = fZ;
        break;
      case 0x6:
        final val = memory.readByte(hl);
        fZ = !isBitSet(val, bitToTest);
        // NOTE: undocumented bits 3 and 5 for this instruction come from an
        // internal register 'W' that is highly undocumented. This really
        // doesn't matter too much, I don't think. See the following for more:
        //   http://www.omnimaga.org/asm-language/bit-n-(hl)-flags/
        f3 = false;
        f5 = false;
        fPV = fZ;
        break;
      case 0x7:
        fZ = !isBitSet(a, bitToTest);
        f3 = isBitSet(a, 3);
        f5 = isBitSet(a, 5);
        fPV = fZ;
        break;
      default:
        throw Exception(
            "Field register $reg must map to a valid Z80 register.");
    }

    // undocumented behavior from
    //   http://worldofspectrum.org/faq/reference/z80reference.htm
    fS = (bitToTest == 7) && (!fZ);
    fH = true;
    fN = false;
  }

  void RES(int bitToReset, int reg) {
    switch (reg) {
      case 0x0:
        b = resetBit(b, bitToReset);
        break;
      case 0x1:
        c = resetBit(c, bitToReset);
        break;
      case 0x2:
        d = resetBit(d, bitToReset);
        break;
      case 0x3:
        e = resetBit(e, bitToReset);
        break;
      case 0x4:
        h = resetBit(h, bitToReset);
        break;
      case 0x5:
        l = resetBit(l, bitToReset);
        break;
      case 0x6:
        memory.writeByte(hl, resetBit(memory.readByte(hl), bitToReset));
        break;
      case 0x7:
        a = resetBit(a, bitToReset);
        break;
      default:
        throw Exception(
            "Field register $reg must map to a valid Z80 register.");
    }
  }

  void SET(int bitToSet, int reg) {
    switch (reg) {
      case 0x0:
        b = setBit(b, bitToSet);
        break;
      case 0x1:
        c = setBit(c, bitToSet);
        break;
      case 0x2:
        d = setBit(d, bitToSet);
        break;
      case 0x3:
        e = setBit(e, bitToSet);
        break;
      case 0x4:
        h = setBit(h, bitToSet);
        break;
      case 0x5:
        l = setBit(l, bitToSet);
        break;
      case 0x6:
        memory.writeByte(hl, setBit(memory.readByte(hl), bitToSet));
        break;
      case 0x7:
        a = setBit(a, bitToSet);
        break;
      default:
        throw Exception(
            "Field register $reg must map to a valid Z80 register.");
    }
  }

  // Port operations and interrupts
  int IN(int reg, int portNumber) {
    final readByte = portRead(bc);

    fS = isSign8(reg);
    fZ = isZero(reg);
    fH = false;
    fPV = isParity(reg);
    fN = false;
    f5 = isBitSet(reg, 5);
    f3 = isBitSet(reg, 3);

    return readByte;
  }

  void OUT(int portNumber, int value) {
    portWrite(portNumber, value);
  }

  void OUTA(int portNumber, int value) {
    portWrite(portNumber, value);
  }

  int INA(int portNumber) => portRead(portNumber);

  void INI() {
    final memval = portRead(bc);
    memory.writeByte(hl, memval);
    hl = (hl + 1) % 0x10000;
    b = (b - 1) % 0x100;

    fN = isBitSet(memval, 7);
    fZ = b == 0;
    fS = isSign8(b);
    f3 = isBitSet(b, 3);
    f5 = isBitSet(b, 5);

    fC = fH = memval + ((c + 1) & 0xFF) > 0xFF;
    fPV = isParity(((memval + ((c + 1) & 0xFF)) & 0x07) ^ b);

    tStates += 16;
  }

  void OUTI() {
    final memval = memory.readByte(hl);
    portWrite(c, memval);
    hl = (hl + 1) % 0x10000;
    b = (b - 1) % 0x100;

    fN = isBitSet(memval, 7);
    fZ = b == 0;
    fS = isSign8(b);
    f3 = isBitSet(b, 3);
    f5 = isBitSet(b, 5);

    fC = fH = memval + l > 0xFF;
    fPV = isParity(((memval + l) & 0x07) ^ b);

    tStates += 16;
  }

  void IND() {
    final memval = portRead(bc);
    memory.writeByte(hl, memval);
    hl = (hl - 1) % 0x10000;
    b = (b - 1) % 0x100;

    fN = isBitSet(memval, 7);
    fZ = b == 0;
    fS = isSign8(b);
    f3 = isBitSet(b, 3);
    f5 = isBitSet(b, 5);

    fC = fH = memval + ((c - 1) & 0xFF) > 0xFF;
    fPV = isParity(((memval + ((c - 1) & 0xFF)) & 0x07) ^ b);
    tStates += 16;
  }

  void OUTD() {
    final memval = memory.readByte(hl);
    portWrite(c, memval);
    hl = (hl - 1) % 0x10000;
    b = (b - 1) % 0x100;

    fN = true;
    fN = isBitSet(memval, 7);
    fZ = b == 0;
    fS = isSign8(b);
    f3 = isBitSet(b, 3);
    f5 = isBitSet(b, 5);

    fC = fH = memval + l > 0xFF;
    fPV = isParity(((memval + l) & 0x07) ^ b);

    tStates += 16;
  }

  void INIR() {
    final memval = portRead(bc);
    memory.writeByte(hl, memval);
    hl = (hl + 1) % 0x10000;
    b = (b - 1) % 0x100;

    fN = isBitSet(memval, 7);
    fZ = b == 0;
    fS = isSign8(b);
    f3 = isBitSet(b, 3);
    f5 = isBitSet(b, 5);

    fC = fH = memval + ((c + 1) & 0xFF) > 0xFF;
    fPV = isParity(((memval + ((c + 1) & 0xFF)) & 0x07) ^ b);

    if (b != 0) {
      pc = (pc - 2) % 0x10000;
      tStates += 21;
    } else {
      tStates += 16;
    }
  }

  void OTIR() {
    final memval = memory.readByte(hl);
    portWrite(c, memval);

    hl = (hl + 1) % 0x10000;
    b = (b - 1) % 0x100;

    fN = true;
    fN = isBitSet(memval, 7);
    fZ = b == 0;
    fS = isSign8(b);
    f3 = isBitSet(b, 3);
    f5 = isBitSet(b, 5);

    fC = fH = memval + l > 0xFF;
    fPV = isParity(((memval + l) & 0x07) ^ b);

    if (b != 0) {
      pc = (pc - 2) % 0x10000;
      tStates += 21;
    } else {
      tStates += 16;
    }
  }

  void INDR() {
    final memval = portRead(bc);
    memory.writeByte(hl, memval);
    hl = (hl - 1) % 0x10000;
    b = (b - 1) % 0x100;

    fN = isBitSet(memval, 7);
    fZ = b == 0;
    fS = isSign8(b);
    f3 = isBitSet(b, 3);
    f5 = isBitSet(b, 5);

    fC = fH = memval + ((c - 1) & 0xFF) > 0xFF;
    fPV = isParity(((memval + ((c - 1) & 0xFF)) & 0x07) ^ b);

    if (b != 0) {
      pc = (pc - 2) % 0x10000;
      tStates += 21;
    } else {
      tStates += 16;
    }
  }

  void OTDR() {
    final memval = memory.readByte(hl);
    portWrite(c, memval);

    hl = (hl - 1) % 0x10000;
    b = (b - 1) % 0x100;

    fN = true;
    fN = isBitSet(memval, 7);
    fZ = b == 0;
    fS = isSign8(b);
    f3 = isBitSet(b, 3);
    f5 = isBitSet(b, 5);

    fC = fH = memval + l > 0xFF;
    fPV = isParity(((memval + l) & 0x07) ^ b);

    if (b != 0) {
      pc = (pc - 2) % 0x10000;
      tStates += 21;
    } else {
      tStates += 16;
    }
  }

  // *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
  // OPCODE DECODING
  // *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***

  // Use for debugging, where we want to be able to see what's coming without
  // affecting PC
  int previewByte(int displ) => memory.readByte(pc + displ);
  int previewWord(int displ) => memory.readWord(pc + displ);

  // Use for execution, where we want to move through the program
  int getNextByte() {
    final byteRead = memory.readByte(pc);
    pc = (pc + 1) % 0x10000;
    return byteRead;
  }

  int getNextWord() {
    final wordRead = memory.readWord(pc);
    pc = (pc + 2) % 0x10000;
    return wordRead;
  }

  int displacedIX() {
    final displ = getNextByte();
    if (displ > 0x7F) {
      return (ix + twocomp8(displ)) % 0x10000;
    } else {
      return (ix + displ) % 0x10000;
    }
  }

  int displacedIY() {
    final displ = getNextByte();
    if (displ > 0x7F) {
      return (iy + twocomp8(displ)) % 0x10000;
    } else {
      return (iy + displ) % 0x10000;
    }
  }

  int portRead(int port) => onPortRead(port);

  void portWrite(int addr, int value) => onPortWrite(addr, value);

  void rot(int operation, int register) {
    int Function(int) rotFunction;

    switch (operation) {
      case 0x00:
        rotFunction = RLC;
        break;
      case 0x01:
        rotFunction = RRC;
        break;
      case 0x02:
        rotFunction = RL;
        break;
      case 0x03:
        rotFunction = RR;
        break;
      case 0x04:
        rotFunction = SLA;
        break;
      case 0x05:
        rotFunction = SRA;
        break;
      case 0x06:
        rotFunction = SLL;
        break;
      case 0x07:
        rotFunction = SRL;
        break;
      default:
        throw Exception(
            "Operation $operation must map to a valid rotation operation.");
    }

    switch (register) {
      case 0x00:
        b = rotFunction(b);
        break;
      case 0x01:
        c = rotFunction(c);
        break;
      case 0x02:
        d = rotFunction(d);
        break;
      case 0x03:
        e = rotFunction(e);
        break;
      case 0x04:
        h = rotFunction(h);
        break;
      case 0x05:
        l = rotFunction(l);
        break;
      case 0x06:
        memory.writeByte(hl, rotFunction(memory.readByte(hl)));
        break;
      case 0x07:
        a = rotFunction(a);
        break;
      default:
        throw Exception(
            "Field register $register must map to a valid Z80 register.");
    }
  }

  void DecodeCBOpcode() {
    final opCode = getNextByte();
    r++;

    // first two bits of opCode determine function:
    switch (opCode >> 6) {
      // 00 = rot [y], r[z]
      case 0:
        rot((opCode & 0x38) >> 3, opCode & 0x07);
        break;

      // 01 = BIT y, r[z]
      case 1:
        BIT((opCode & 0x38) >> 3, opCode & 0x07);
        break;

      // 02 = RES y, r[z]
      case 2:
        RES((opCode & 0x38) >> 3, opCode & 0x07);
        break;

      // 03 = SET y, r[z]
      case 3:
        SET((opCode & 0x38) >> 3, opCode & 0x07);
        break;
    }

    // Set T-States
    if ((opCode & 0x7) == 0x6) {
      if ((opCode > 0x40) && (opCode < 0x7F)) {
        // BIT n, (HL)
        tStates += 12;
      } else {
        // all the other instructions involving (HL)
        tStates += 15;
      }
    } else {
      // straight register bitwise operation
      tStates += 8;
    }
  }

  void DecodeDDCBOpCode() {
    // format is DDCB[addr][opcode]
    final addr = displacedIX();
    final opCode = getNextByte();

    // BIT
    if ((opCode >= 0x40) && (opCode <= 0x7F)) {
      final val = memory.readByte(addr);
      final bit = (opCode & 0x38) >> 3;
      fZ = !isBitSet(val, bit);
      fPV = !isBitSet(val, bit); // undocumented, but same as fZ
      fH = true;
      fN = false;
      f5 = isBitSet(addr >> 8, 5);
      f3 = isBitSet(addr >> 8, 3);
      if (bit == 7) {
        fS = isSign8(val);
      } else {
        fS = false;
      }
      tStates += 20;
      return;
    } else {
      // Here follows a double-pass switch statement to determine the opcode
      // results. Firstly, we determine which kind of operation is being
      // requested, and then we identify where the result should be placed.
      var opResult = 0;

      final opCodeType = (opCode & 0xF8) >> 3;
      switch (opCodeType) {
        // RLC (IX+*)
        case 0x00:
          opResult = RLC(memory.readByte(addr));
          break;

        // RRC (IX+*)
        case 0x01:
          opResult = RRC(memory.readByte(addr));
          break;

        // RL (IX+*)
        case 0x02:
          opResult = RL(memory.readByte(addr));
          break;

        // RR (IX+*)
        case 0x03:
          opResult = RR(memory.readByte(addr));
          break;

        // SLA (IX+*)
        case 0x04:
          opResult = SLA(memory.readByte(addr));
          break;

        // SRA (IX+*)
        case 0x05:
          opResult = SRA(memory.readByte(addr));
          break;

        // SLL (IX+*)
        case 0x06:
          opResult = SLL(memory.readByte(addr));
          break;

        // SRL (IX+*)
        case 0x07:
          opResult = SRL(memory.readByte(addr));
          break;

        // RES n, (IX+*)
        case 0x10:
        case 0x11:
        case 0x12:
        case 0x13:
        case 0x14:
        case 0x15:
        case 0x16:
        case 0x17:
          opResult = resetBit(memory.readByte(addr), (opCode & 0x38) >> 3);
          break;

        // SET n, (IX+*)
        case 0x18:
        case 0x19:
        case 0x1A:
        case 0x1B:
        case 0x1C:
        case 0x1D:
        case 0x1E:
        case 0x1F:
          opResult = setBit(memory.readByte(addr), (opCode & 0x38) >> 3);
          break;
      }
      memory.writeByte(addr, opResult);

      final opCodeTarget = opCode & 0x07;
      switch (opCodeTarget) {
        case 0x00: // b
          b = opResult;
          break;
        case 0x01: // c
          c = opResult;
          break;
        case 0x02: // d
          d = opResult;
          break;
        case 0x03: // e
          e = opResult;
          break;
        case 0x04: // h
          h = opResult;
          break;
        case 0x05: // l
          l = opResult;
          break;
        case 0x06: // no register
          break;
        case 0x07: // a
          a = opResult;
          break;
      }

      tStates += 23;
    }
  }

  void DecodeDDOpcode() {
    final opCode = getNextByte();
    r++;

    int addr;

    switch (opCode) {
      // NOP
      case 0x00:
        tStates += 8;
        break;

      // ADD IX, BC
      case 0x09:
        ix = ADD16(ix, bc);
        tStates += 4;
        break;

      // ADD IX, DE
      case 0x19:
        ix = ADD16(ix, de);
        tStates += 4;
        break;

      // LD IX, **
      case 0x21:
        ix = getNextWord();
        tStates += 14;
        break;

      // LD (**), IX
      case 0x22:
        memory.writeWord(getNextWord(), ix);
        tStates += 20;
        break;

      // INC IX
      case 0x23:
        ix = (ix + 1) % 0x10000;
        tStates += 10;
        break;

      // INC IXH
      case 0x24:
        ixh = INC(ixh);
        tStates += 4;
        break;

      // DEC IXH
      case 0x25:
        ixh = DEC(ixh);
        tStates += 4;
        break;

      // LD IXH, *
      case 0x26:
        ixh = getNextByte();
        tStates += 11;
        break;

      // ADD IX, IX
      case 0x29:
        ix = ADD16(ix, ix);
        tStates += 4;
        break;

      // LD IX, (**)
      case 0x2A:
        ix = memory.readWord(getNextWord());
        tStates += 20;
        break;

      // DEC IX
      case 0x2B:
        ix = (ix - 1) % 0x10000;
        tStates += 10;
        break;

      // INC IXL
      case 0x2C:
        ixl = INC(ixl);
        tStates += 4;
        break;

      // DEC IXL
      case 0x2D:
        ixl = DEC(ixl);
        tStates += 4;
        break;

      // LD IXH, *
      case 0x2E:
        ixl = getNextByte();
        tStates += 11;
        break;

      // INC (IX+*)
      case 0x34:
        addr = displacedIX();
        memory.writeByte(addr, INC(memory.readByte(addr)));
        tStates += 19;
        break;

      // DEC (IX+*)
      case 0x35:
        addr = displacedIX();
        memory.writeByte(addr, DEC(memory.readByte(addr)));
        tStates += 19;
        break;

      // LD (IX+*), *
      case 0x36:
        memory.writeByte(displacedIX(), getNextByte());
        tStates += 19;
        break;

      // ADD IX, SP
      case 0x39:
        ix = ADD16(ix, sp);
        tStates += 4;
        break;

      // LD B, IXH
      case 0x44:
        b = ixh;
        tStates += 8;
        break;

      // LD B, IXL
      case 0x45:
        b = ixl;
        tStates += 8;
        break;

      // LD B, (IX+*)
      case 0x46:
        b = memory.readByte(displacedIX());
        tStates += 19;
        break;

      // LD C, IXH
      case 0x4C:
        c = ixh;
        tStates += 8;
        break;

      // LD C, IXL
      case 0x4D:
        c = ixl;
        tStates += 8;
        break;

      // LD C, (IX+*)
      case 0x4E:
        c = memory.readByte(displacedIX());
        tStates += 19;
        break;

      // LD D, IXH
      case 0x54:
        d = ixh;
        tStates += 8;
        break;

      // LD D, IXL
      case 0x55:
        d = ixl;
        tStates += 8;
        break;

      // LD D, (IX+*)
      case 0x56:
        d = memory.readByte(displacedIX());
        tStates += 19;
        break;

      // LD E, IXH
      case 0x5C:
        e = ixh;
        tStates += 8;
        break;

      // LD E, IXL
      case 0x5D:
        e = ixl;
        tStates += 8;
        break;

      // LD E, (IX+*)
      case 0x5E:
        e = memory.readByte(displacedIX());
        tStates += 19;
        break;

      // LD IXH, B
      case 0x60:
        ixh = b;
        tStates += 8;
        break;

      // LD IXH, C
      case 0x61:
        ixh = c;
        tStates += 8;
        break;

      // LD IXH, D
      case 0x62:
        ixh = d;
        tStates += 8;
        break;

      // LD IXH, E
      case 0x63:
        ixh = e;
        tStates += 8;
        break;

      // LD IXH, IXH
      case 0x64:
        tStates += 8;
        break;

      // LD IXH, IXL
      case 0x65:
        ixh = ixl;
        tStates += 8;
        break;

      // LD H, (IX+*)
      case 0x66:
        h = memory.readByte(displacedIX());
        tStates += 19;
        break;

      // LD IXH, A
      case 0x67:
        ixh = a;
        tStates += 8;
        break;

      // LD IXL, B
      case 0x68:
        ixl = b;
        tStates += 8;
        break;

      // LD IXL, C
      case 0x69:
        ixl = c;
        tStates += 8;
        break;

      // LD IXL, D
      case 0x6A:
        ixl = d;
        tStates += 8;
        break;

      // LD IXL, E
      case 0x6B:
        ixl = e;
        tStates += 8;
        break;

      // LD IXL, IXH
      case 0x6C:
        ixl = ixh;
        tStates += 8;
        break;

      // LD IXL, IXL
      case 0x6D:
        tStates += 8;
        break;

      // LD L, (IX+*)
      case 0x6E:
        l = memory.readByte(displacedIX());
        tStates += 19;
        break;

      // LD IXL, A
      case 0x6F:
        ixl = a;
        tStates += 8;
        break;

      // LD (IX+*), B
      case 0x70:
        memory.writeByte(displacedIX(), b);
        tStates += 19;
        break;

      // LD (IX+*), C
      case 0x71:
        memory.writeByte(displacedIX(), c);
        tStates += 19;
        break;

      // LD (IX+*), D
      case 0x72:
        memory.writeByte(displacedIX(), d);
        tStates += 19;
        break;

      // LD (IX+*), E
      case 0x73:
        memory.writeByte(displacedIX(), e);
        tStates += 19;
        break;

      // LD (IX+*), H
      case 0x74:
        memory.writeByte(displacedIX(), h);
        tStates += 19;
        break;

      // LD (IX+*), L
      case 0x75:
        memory.writeByte(displacedIX(), l);
        tStates += 19;
        break;

      // LD (IX+*), A
      case 0x77:
        memory.writeByte(displacedIX(), a);
        tStates += 19;
        break;

      // LD A, IXH
      case 0x7C:
        a = ixh;
        tStates += 8;
        break;

      // LD A, IXL
      case 0x7D:
        a = ixl;
        tStates += 8;
        break;

      // LD A, (IX+*)
      case 0x7E:
        a = memory.readByte(displacedIX());
        tStates += 19;
        break;

      // ADD A, IXH
      case 0x84:
        a = ADD8(a, ixh);
        tStates += 4;
        break;

      // ADD A, IXL
      case 0x85:
        a = ADD8(a, ixl);
        tStates += 4;
        break;

      // ADD A, (IX+*)
      case 0x86:
        a = ADD8(a, memory.readByte(displacedIX()));
        tStates += 15;
        break;

      // ADC A, IXH
      case 0x8C:
        a = ADC8(a, ixh);
        tStates += 4;
        break;

      // ADC A, IXL
      case 0x8D:
        a = ADC8(a, ixl);
        tStates += 4;
        break;

      // ADC A, (IX+*)
      case 0x8E:
        a = ADC8(a, memory.readByte(displacedIX()));
        tStates += 15;
        break;

      // SUB IXH
      case 0x94:
        a = SUB8(a, ixh);
        tStates += 4;
        break;

      // SUB IXL
      case 0x95:
        a = SUB8(a, ixl);
        tStates += 4;
        break;

      // SUB (IX+*)
      case 0x96:
        a = SUB8(a, memory.readByte(displacedIX()));
        tStates += 15;
        break;

      // SBC A, IXH
      case 0x9C:
        a = SBC8(a, ixh);
        tStates += 4;
        break;

      // SBC A, IXL
      case 0x9D:
        a = SBC8(a, ixl);
        tStates += 4;
        break;

      // SBC A, (IX+*)
      case 0x9E:
        a = SBC8(a, memory.readByte(displacedIX()));
        tStates += 15;
        break;

      // AND IXH
      case 0xA4:
        a = AND(a, ixh);
        tStates += 4;
        break;

      // AND IXL
      case 0xA5:
        a = AND(a, ixl);
        tStates += 4;
        break;

      // AND (IX+*)
      case 0xA6:
        a = AND(a, memory.readByte(displacedIX()));
        tStates += 15;
        break;

      // XOR (IX+*)
      case 0xAE:
        a = XOR(a, memory.readByte(displacedIX()));
        tStates += 15;
        break;

      // XOR IXH
      case 0xAC:
        a = XOR(a, ixh);
        tStates += 4;
        break;

      // XOR IXL
      case 0xAD:
        a = XOR(a, ixl);
        tStates += 4;
        break;

      // OR IXH
      case 0xB4:
        a = OR(a, ixh);
        tStates += 4;
        break;

      // OR IXL
      case 0xB5:
        a = OR(a, ixl);
        tStates += 4;
        break;

      // OR (IX+*)
      case 0xB6:
        a = OR(a, memory.readByte(displacedIX()));
        tStates += 15;
        break;

      // CP IXH
      case 0xBC:
        CP(ixh);
        tStates += 4;
        break;

      // CP IXL
      case 0xBD:
        CP(ixl);
        tStates += 4;
        break;

      // CP (IX+*)
      case 0xBE:
        CP(memory.readByte(displacedIX()));
        tStates += 15;
        break;

      // bitwise instructions
      case 0xCB:
        DecodeDDCBOpCode();
        break;

      // POP IX
      case 0xE1:
        ix = POP();
        tStates += 14;
        break;

      // EX (SP), IX
      case 0xE3:
        final temp = memory.readWord(sp);
        memory.writeWord(sp, ix);
        ix = temp;
        tStates += 23;
        break;

      // PUSH IX
      case 0xE5:
        PUSH(ix);
        tStates += 15;
        break;

      // JP (IX)
      // note that the brackets in the instruction are an eccentricity, the result
      // should be ix rather than the contents of addr(ix)
      case 0xE9:
        pc = ix;
        tStates += 8;
        break;

      // Undocumented, but per §3.7 of:
      //    http://www.myquest.nl/z80undocumented/z80-documented-v0.91.pdf
      case 0xFD:
        tStates += 8;
        break;

      // LD SP, IX
      case 0xF9:
        sp = ix;
        tStates += 10;
        break;

      default:
        if (_extendedCodes.contains(opCode)) {
          tStates += 4;
          pc--; // go back one
          executeNextInstruction();
        } else {
          throw Exception("Opcode DD${toHex16(opCode)} not understood. ");
        }
    }
  }

  void DecodeEDOpcode() {
    final opCode = getNextByte();
    r++;

    switch (opCode) {
      // IN B, (C)
      case 0x40:
        IN(b, c);
        tStates += 12;
        break;

      // OUT (C), B
      case 0x41:
        OUT(c, b);
        tStates += 12;
        break;

      // SBC HL, BC
      case 0x42:
        hl = SBC16(hl, bc);
        break;

      // LD (**), BC
      case 0x43:
        memory.writeWord(getNextWord(), bc);
        tStates += 20;
        break;

      // NEG
      case 0x44:
      case 0x4C:
      case 0x54:
      case 0x5C:
      case 0x64:
      case 0x6C:
      case 0x74:
      case 0x7C:
        a = NEG(a);
        break;

      // RETN
      case 0x45:
      case 0x55:
      case 0x5D:
      case 0x65:
      case 0x6D:
      case 0x75:
      case 0x7D:
        pc = POP();
        iff1 = iff2;
        tStates += 14;
        break;

      // IM 0
      case 0x46:
      case 0x66:
        im = 0;
        // print('IM 0');
        tStates += 8;
        break;

      // LD I, A
      case 0x47:
        i = a;
        tStates += 9;
        break;

      // IN C, (C)
      case 0x48:
        c = IN(c, c);
        tStates += 12;
        break;

      // OUT C, (C)
      case 0x49:
        OUT(c, c);
        tStates += 12;
        break;

      // ADC HL, BC
      case 0x4A:
        hl = ADC16(hl, bc);
        tStates += 4;
        break;

      // LD BC, (**)
      case 0x4B:
        bc = memory.readWord(getNextWord());
        tStates += 20;
        break;

      // RETI
      case 0x4D:
        pc = POP();
        tStates += 14;
        break;

      // LD R, A
      case 0x4F:
        r = a;
        tStates += 9;
        break;

      // IN D, (C)
      case 0x50:
        d = IN(d, c);
        tStates += 12;
        break;

      // OUT (C), D
      case 0x51:
        OUT(c, d);
        tStates += 12;
        break;

      // SBC HL, DE
      case 0x52:
        hl = SBC16(hl, de);
        break;

      // LD (**), DE
      case 0x53:
        memory.writeWord(getNextWord(), de);
        tStates += 20;
        break;

      // IM 1
      case 0x4E:
      case 0x56:
      case 0x6E:
      case 0x76:
        im = 1;
        // print('IM 1');
        tStates += 8;
        break;

      // LD A, I
      case 0x57:
        a = i;
        fS = isSign8(i);
        fZ = isZero(i);
        f5 = isBitSet(i, 5);
        fH = false;
        f3 = isBitSet(i, 3);
        fPV = iff2;
        fN = false;
        tStates += 9;
        break;

      // IN E, (C)
      case 0x58:
        e = IN(e, c);
        tStates += 12;
        break;

      // OUT (C), E
      case 0x59:
        OUT(c, e);
        tStates += 12;
        break;

      // ADC HL, DE
      case 0x5A:
        hl = ADC16(hl, de);
        tStates += 4;
        break;

      // LD DE, (**)
      case 0x5B:
        de = memory.readWord(getNextWord());
        tStates += 20;
        break;

      // IM 2
      case 0x5E:
      case 0x7E:
        im = 2;
        // print('IM 2');
        tStates += 8;
        break;

      // LD A, R
      case 0x5F:
        a = r;
        fS = isSign8(r);
        fZ = isZero(r);
        fH = false;
        fPV = iff2;
        fN = false;
        tStates += 9;
        break;

      // IN H, (C)
      case 0x60:
        h = IN(h, c);
        tStates += 12;
        break;

      // OUT (C), H
      case 0x61:
        OUT(c, h);
        tStates += 12;
        break;

      // SBC HL, HL
      case 0x62:
        hl = SBC16(hl, hl);
        break;

      // LD (**), HL
      case 0x63:
        memory.writeWord(getNextWord(), hl);
        tStates += 20;
        break;

      // RRD
      case 0x67:
        RRD();
        break;

      // IN L, (C)
      case 0x68:
        l = IN(l, c);
        tStates += 12;
        break;

      // OUT (C), L
      case 0x69:
        OUT(c, l);
        tStates += 12;
        break;

      // ADC HL, HL
      case 0x6A:
        hl = ADC16(hl, hl);
        tStates += 4;
        break;

      // LD HL, (**)
      case 0x6B:
        hl = memory.readWord(getNextWord());
        tStates += 20;
        break;

      // RLD
      case 0x6F:
        RLD();
        break;

      // IN (C)
      case 0x70:
        IN(c, c);
        tStates += 12;
        break;

      // OUT (C), 0
      case 0x71:
        OUT(c, 0);
        tStates += 12;
        break;

      // SBC HL, SP
      case 0x72:
        hl = SBC16(hl, sp);
        break;

      // LD (**), SP
      case 0x73:
        memory.writeWord(getNextWord(), sp);
        tStates += 20;
        break;

      // IN A, (C)
      case 0x78:
        a = IN(a, c);
        tStates += 12;
        break;

      // OUT (C), A
      case 0x79:
        OUT(c, a);
        tStates += 12;
        break;

      // ADC HL, SP
      case 0x7A:
        hl = ADC16(hl, sp);
        tStates += 4;
        break;

      // LD SP, (**)
      case 0x7B:
        sp = memory.readWord(getNextWord());
        tStates += 20;
        break;

      // LDI
      case 0xA0:
        LDI();
        break;

      // CPI
      case 0xA1:
        CPI();
        break;

      // INI
      case 0xA2:
        INI();
        break;

      // OUTI
      case 0xA3:
        OUTI();
        break;

      // LDD
      case 0xA8:
        LDD();
        break;

      // CPD
      case 0xA9:
        CPD();
        break;

      // IND
      case 0xAA:
        IND();
        break;

      // OUTD
      case 0xAB:
        OUTD();
        break;

      // LDIR
      case 0xB0:
        LDIR();
        break;

      // CPIR
      case 0xB1:
        CPIR();
        break;

      // INIR
      case 0xB2:
        INIR();
        break;

      // OTIR
      case 0xB3:
        OTIR();
        break;

      // LDDR
      case 0xB8:
        LDDR();
        break;

      // CPDR
      case 0xB9:
        CPDR();
        break;

      // INDR
      case 0xBA:
        INDR();
        break;

      // OTDR
      case 0xBB:
        OTDR();
        break;

      default:
        throw Exception("Opcode ED${toHex16(opCode)} not understood. ");
    }
  }

  void DecodeFDCBOpCode() {
    // format is FDCB[addr][opcode]
    final addr = displacedIY();
    final opCode = getNextByte();

    // BIT
    if ((opCode >= 0x40) && (opCode <= 0x7F)) {
      final val = memory.readByte(addr);
      final bit = (opCode & 0x38) >> 3;
      fZ = !isBitSet(val, bit);
      fPV = !isBitSet(val, bit); // undocumented, but same as fZ
      fH = true;
      fN = false;
      f5 = isBitSet(addr >> 8, 5);
      f3 = isBitSet(addr >> 8, 3);
      if (bit == 7) {
        fS = isSign8(val);
      } else {
        fS = false;
      }
      tStates += 20;
      return;
    } else {
      // Here follows a double-pass switch statement to determine the opcode
      // results. Firstly, we determine which kind of operation is being
      // requested, and then we identify where the result should be placed.
      var opResult = 0;

      final opCodeType = (opCode & 0xF8) >> 3;
      switch (opCodeType) {
        // RLC (IY+*)
        case 0x00:
          opResult = RLC(memory.readByte(addr));
          break;

        // RRC (IY+*)
        case 0x01:
          opResult = RRC(memory.readByte(addr));
          break;

        // RL (IY+*)
        case 0x02:
          opResult = RL(memory.readByte(addr));
          break;

        // RR (IY+*)
        case 0x03:
          opResult = RR(memory.readByte(addr));
          break;

        // SLA (IY+*)
        case 0x04:
          opResult = SLA(memory.readByte(addr));
          break;

        // SRA (IY+*)
        case 0x05:
          opResult = SRA(memory.readByte(addr));
          break;

        // SLL (IY+*)
        case 0x06:
          opResult = SLL(memory.readByte(addr));
          break;

        // SRL (IY+*)
        case 0x07:
          opResult = SRL(memory.readByte(addr));
          break;

        // RES n, (IY+*)
        case 0x10:
        case 0x11:
        case 0x12:
        case 0x13:
        case 0x14:
        case 0x15:
        case 0x16:
        case 0x17:
          opResult = resetBit(memory.readByte(addr), (opCode & 0x38) >> 3);
          break;

        // SET n, (IY+*)
        case 0x18:
        case 0x19:
        case 0x1A:
        case 0x1B:
        case 0x1C:
        case 0x1D:
        case 0x1E:
        case 0x1F:
          opResult = setBit(memory.readByte(addr), (opCode & 0x38) >> 3);
          break;
      }
      memory.writeByte(addr, opResult);

      final opCodeTarget = opCode & 0x07;
      switch (opCodeTarget) {
        case 0x00: // b
          b = opResult;
          break;
        case 0x01: // c
          c = opResult;
          break;
        case 0x02: // d
          d = opResult;
          break;
        case 0x03: // e
          e = opResult;
          break;
        case 0x04: // h
          h = opResult;
          break;
        case 0x05: // l
          l = opResult;
          break;
        case 0x06: // no register
          break;
        case 0x07: // a
          a = opResult;
          break;
      }

      tStates += 23;
    }
  }

  void DecodeFDOpcode() {
    final opCode = getNextByte();
    r++;

    int addr;

    switch (opCode) {
      // NOP
      case 0x00:
        tStates += 8;
        break; // T-State is a guess - I can't find this documented

      // ADD IY, BC
      case 0x09:
        iy = ADD16(iy, bc);
        tStates += 4;
        break;

      // ADD IY, DE
      case 0x19:
        iy = ADD16(iy, de);
        tStates += 4;
        break;

      // LD IY, **
      case 0x21:
        iy = getNextWord();
        tStates += 14;
        break;

      // LD (**), IY
      case 0x22:
        memory.writeWord(getNextWord(), iy);
        tStates += 20;
        break;

      // INC IY
      case 0x23:
        iy = (iy + 1) % 0x10000;
        tStates += 10;
        break;

      // INC IYH
      case 0x24:
        iyh = INC(iyh);
        tStates += 4;
        break;

      // DEC IYH
      case 0x25:
        iyh = DEC(iyh);
        tStates += 4;
        break;

      // LD IYH, *
      case 0x26:
        iyh = getNextByte();
        tStates += 11;
        break;

      // ADD IY, IY
      case 0x29:
        iy = ADD16(iy, iy);
        tStates += 4;
        break;

      // LD IY, (**)
      case 0x2A:
        iy = memory.readWord(getNextWord());
        tStates += 20;
        break;

      // DEC IY
      case 0x2B:
        iy = (iy - 1) % 0x10000;
        tStates += 10;
        break;

      // INC IYL
      case 0x2C:
        iyl = INC(iyl);
        tStates += 4;
        break;

      // DEC IYL
      case 0x2D:
        iyl = DEC(iyl);
        tStates += 4;
        break;

      // LD IYH, *
      case 0x2E:
        iyl = getNextByte();
        tStates += 11;
        break;

      // INC (IY+*)
      case 0x34:
        addr = displacedIY();
        memory.writeByte(addr, INC(memory.readByte(addr)));
        tStates += 19;
        break;

      // DEC (IY+*)
      case 0x35:
        addr = displacedIY();
        memory.writeByte(addr, DEC(memory.readByte(addr)));
        tStates += 19;
        break;

      // LD (IY+*), *
      case 0x36:
        memory.writeByte(displacedIY(), getNextByte());
        tStates += 19;
        break;

      // ADD IY, SP
      case 0x39:
        iy = ADD16(iy, sp);
        tStates += 4;
        break;

      // LD B, IYH
      case 0x44:
        b = iyh;
        tStates += 8;
        break;

      // LD B, IYL
      case 0x45:
        b = iyl;
        tStates += 8;
        break;

      // LD B, (IY+*)
      case 0x46:
        b = memory.readByte(displacedIY());
        tStates += 19;
        break;

      // LD C, IYH
      case 0x4C:
        c = iyh;
        tStates += 8;
        break;

      // LD C, IYL
      case 0x4D:
        c = iyl;
        tStates += 8;
        break;

      // LD C, (IY+*)
      case 0x4E:
        c = memory.readByte(displacedIY());
        tStates += 19;
        break;

      // LD D, IYH
      case 0x54:
        d = iyh;
        tStates += 8;
        break;

      // LD D, IYL
      case 0x55:
        d = iyl;
        tStates += 8;
        break;

      // LD D, (IY+*)
      case 0x56:
        d = memory.readByte(displacedIY());
        tStates += 19;
        break;

      // LD E, IYH
      case 0x5C:
        e = iyh;
        tStates += 8;
        break;

      // LD E, IYL
      case 0x5D:
        e = iyl;
        tStates += 8;
        break;

      // LD E, (IY+*)
      case 0x5E:
        e = memory.readByte(displacedIY());
        tStates += 19;
        break;

      // LD IYH, B
      case 0x60:
        iyh = b;
        tStates += 8;
        break;

      // LD IYH, C
      case 0x61:
        iyh = c;
        tStates += 8;
        break;

      // LD IYH, D
      case 0x62:
        iyh = d;
        tStates += 8;
        break;

      // LD IYH, E
      case 0x63:
        iyh = e;
        tStates += 8;
        break;

      // LD IYH, IYH
      case 0x64:
        tStates += 8;
        break;

      // LD IYH, IYL
      case 0x65:
        iyh = iyl;
        tStates += 8;
        break;

      // LD H, (IY+*)
      case 0x66:
        h = memory.readByte(displacedIY());
        tStates += 19;
        break;

      // LD IYH, A
      case 0x67:
        iyh = a;
        tStates += 8;
        break;

      // LD IYL, B
      case 0x68:
        iyl = b;
        tStates += 8;
        break;

      // LD IYL, C
      case 0x69:
        iyl = c;
        tStates += 8;
        break;

      // LD IYL, D
      case 0x6A:
        iyl = d;
        tStates += 8;
        break;

      // LD IYL, E
      case 0x6B:
        iyl = e;
        tStates += 8;
        break;

      // LD IYL, IYH
      case 0x6C:
        iyl = iyh;
        tStates += 8;
        break;

      // LD IYL, IYL
      case 0x6D:
        tStates += 8;
        break;

      // LD L, (IY+*)
      case 0x6E:
        l = memory.readByte(displacedIY());
        tStates += 19;
        break;

      // LD IYL, A
      case 0x6F:
        iyl = a;
        tStates += 8;
        break;

      // LD (IY+*), B
      case 0x70:
        memory.writeByte(displacedIY(), b);
        tStates += 19;
        break;

      // LD (IY+*), C
      case 0x71:
        memory.writeByte(displacedIY(), c);
        tStates += 19;
        break;

      // LD (IY+*), D
      case 0x72:
        memory.writeByte(displacedIY(), d);
        tStates += 19;
        break;

      // LD (IY+*), E
      case 0x73:
        memory.writeByte(displacedIY(), e);
        tStates += 19;
        break;

      // LD (IY+*), H
      case 0x74:
        memory.writeByte(displacedIY(), h);
        tStates += 19;
        break;

      // LD (IY+*), L
      case 0x75:
        memory.writeByte(displacedIY(), l);
        tStates += 19;
        break;

      // LD (IY+*), A
      case 0x77:
        memory.writeByte(displacedIY(), a);
        tStates += 19;
        break;

      // LD A, IYH
      case 0x7C:
        a = iyh;
        tStates += 8;
        break;

      // LD A, IYL
      case 0x7D:
        a = iyl;
        tStates += 8;
        break;

      // LD A, (IY+*)
      case 0x7E:
        a = memory.readByte(displacedIY());
        tStates += 19;
        break;

      // ADD A, IYH
      case 0x84:
        a = ADD8(a, iyh);
        tStates += 4;
        break;

      // ADD A, IYL
      case 0x85:
        a = ADD8(a, iyl);
        tStates += 4;
        break;

      // ADD A, (IY+*)
      case 0x86:
        a = ADD8(a, memory.readByte(displacedIY()));
        tStates += 15;
        break;

      // ADC A, IYH
      case 0x8C:
        a = ADC8(a, iyh);
        tStates += 4;
        break;

      // ADC A, IYL
      case 0x8D:
        a = ADC8(a, iyl);
        tStates += 4;
        break;

      // ADC A, (IY+*)
      case 0x8E:
        a = ADC8(a, memory.readByte(displacedIY()));
        tStates += 15;
        break;

      // SUB IYH
      case 0x94:
        a = SUB8(a, iyh);
        tStates += 4;
        break;

      // SUB IYL
      case 0x95:
        a = SUB8(a, iyl);
        tStates += 4;
        break;

      // SUB (IY+*)
      case 0x96:
        a = SUB8(a, memory.readByte(displacedIY()));
        tStates += 15;
        break;

      // SBC A, IYH
      case 0x9C:
        a = SBC8(a, iyh);
        tStates += 4;
        break;

      // SBC A, IYL
      case 0x9D:
        a = SBC8(a, iyl);
        tStates += 4;
        break;

      // SBC A, (IY+*)
      case 0x9E:
        a = SBC8(a, memory.readByte(displacedIY()));
        tStates += 15;
        break;

      // AND IYH
      case 0xA4:
        a = AND(a, iyh);
        tStates += 4;
        break;

      // AND IYL
      case 0xA5:
        a = AND(a, iyl);
        tStates += 4;
        break;

      // AND (IY+*)
      case 0xA6:
        a = AND(a, memory.readByte(displacedIY()));
        tStates += 15;
        break;

      // XOR (IY+*)
      case 0xAE:
        a = XOR(a, memory.readByte(displacedIY()));
        tStates += 15;
        break;

      // XOR IYH
      case 0xAC:
        a = XOR(a, iyh);
        tStates += 4;
        break;

      // XOR IYL
      case 0xAD:
        a = XOR(a, iyl);
        tStates += 4;
        break;

      // OR IYH
      case 0xB4:
        a = OR(a, iyh);
        tStates += 4;
        break;

      // OR IYL
      case 0xB5:
        a = OR(a, iyl);
        tStates += 4;
        break;

      // OR (IY+*)
      case 0xB6:
        a = OR(a, memory.readByte(displacedIY()));
        tStates += 15;
        break;

      // CP IYH
      case 0xBC:
        CP(iyh);
        tStates += 4;
        break;

      // CP IYL
      case 0xBD:
        CP(iyl);
        tStates += 4;
        break;

      // CP (IY+*)
      case 0xBE:
        CP(memory.readByte(displacedIY()));
        tStates += 15;
        break;

      // bitwise instructions
      case 0xCB:
        DecodeFDCBOpCode();
        break;

      // POP IY
      case 0xE1:
        iy = POP();
        tStates += 14;
        break;

      // EX (SP), IY
      case 0xE3:
        final temp = memory.readWord(sp);
        memory.writeWord(sp, iy);
        iy = temp;
        tStates += 23;
        break;

      // PUSH IY
      case 0xE5:
        PUSH(iy);
        tStates += 15;
        break;

      // JP (IY)
      // note that the brackets in the instruction are an eccentricity, the result
      // should be iy rather than the contents of addr(iy)
      case 0xE9:
        pc = iy;
        tStates += 8;
        break;

      // LD SP, IY
      case 0xF9:
        sp = iy;
        tStates += 10;
        break;

      default:
        if (_extendedCodes.contains(opCode)) {
          tStates += 4; // instructions take an extra 4 bytes over unprefixed
          pc--; // go back one
          executeNextInstruction();
        } else {
          throw Exception("Opcode FD${toHex16(opCode)} not understood. ");
        }
    }
  }

  bool executeNextInstruction() {
    final opCode = getNextByte();

    r = (r + 1) % 0x100;

    switch (opCode) {
      // NOP
      case 0x00:
        tStates += 4;
        break;

      // LD BC, **
      case 0x01:
        bc = getNextWord();
        tStates += 10;
        break;

      // LD (BC), A
      case 0x02:
        memory.writeByte(bc, a);
        tStates += 7;
        break;

      // INC BC
      case 0x03:
        bc = (bc + 1) % 0x10000;
        tStates += 6;
        break;

      // INC B
      case 0x04:
        b = INC(b);
        break;

      // DEC B
      case 0x05:
        b = DEC(b);
        break;

      // LD B, *
      case 0x06:
        b = getNextByte();
        tStates += 7;
        break;

      // RLCA
      case 0x07:
        RLCA();
        break;

      // EX AF, AF'
      case 0x08:
        EX_AFAFPrime();
        break;

      // ADD HL, BC
      case 0x09:
        hl = ADD16(hl, bc);
        break;

      // LD A, (BC)
      case 0x0A:
        a = memory.readByte(bc);
        tStates += 7;
        break;

      // DEC BC
      case 0x0B:
        bc = (bc - 1) % 0x10000;
        tStates += 6;
        break;

      // INC C
      case 0x0C:
        c = INC(c);
        break;

      // DEC C
      case 0x0D:
        c = DEC(c);
        break;

      // LD C, *
      case 0x0E:
        c = getNextByte();
        tStates += 7;
        break;

      // RRCA
      case 0x0F:
        RRCA();
        break;

      // DJNZ *
      case 0x10:
        DJNZ(getNextByte());
        break;

      // LD DE, **
      case 0x11:
        de = getNextWord();
        tStates += 10;
        break;

      // LD (DE), A
      case 0x12:
        memory.writeByte(de, a);
        tStates += 7;
        break;

      // INC DE
      case 0x13:
        de = (de + 1) % 0x10000;
        tStates += 6;
        break;

      // INC D
      case 0x14:
        d = INC(d);
        break;

      // DEC D
      case 0x15:
        d = DEC(d);
        break;

      // LD D, *
      case 0x16:
        d = getNextByte();
        tStates += 7;
        break;

      // RLA
      case 0x17:
        RLA();
        break;

      // JR *
      case 0x18:
        JR(getNextByte());
        break;

      // ADD HL, DE
      case 0x19:
        hl = ADD16(hl, de);
        break;

      // LD A, (DE)
      case 0x1A:
        a = memory.readByte(de);
        tStates += 7;
        break;

      // DEC DE
      case 0x1B:
        de = (de - 1) % 0x10000;
        tStates += 6;
        break;

      // INC E
      case 0x1C:
        e = INC(e);
        break;

      // DEC E
      case 0x1D:
        e = DEC(e);
        break;

      // LD E, *
      case 0x1E:
        e = getNextByte();
        tStates += 7;
        break;

      // RRA
      case 0x1F:
        RRA();
        break;

      // JR NZ, *
      case 0x20:
        if (!fZ) {
          JR(getNextByte());
        } else {
          pc = (pc + 1) % 0x10000;
          tStates += 7;
        }
        break;

      // LD HL, **
      case 0x21:
        hl = getNextWord();
        tStates += 10;
        break;

      // LD (**), HL
      case 0x22:
        memory.writeWord(getNextWord(), hl);
        tStates += 16;
        break;

      // INC HL
      case 0x23:
        hl = (hl + 1) % 0x10000;
        tStates += 6;
        break;

      // INC H
      case 0x24:
        h = INC(h);
        break;

      // DEC H
      case 0x25:
        h = DEC(h);
        break;

      // LD H, *
      case 0x26:
        h = getNextByte();
        tStates += 7;
        break;

      // DAA
      case 0x27:
        DAA();
        break;

      // JR Z, *
      case 0x28:
        if (fZ) {
          JR(getNextByte());
        } else {
          pc = (pc + 1) % 0x10000;
          tStates += 7;
        }
        break;

      // ADD HL, HL
      case 0x29:
        hl = ADD16(hl, hl);
        break;

      // LD HL, (**)
      case 0x2A:
        hl = memory.readWord(getNextWord());
        tStates += 16;
        break;

      // DEC HL
      case 0x2B:
        hl = (hl - 1) % 0x10000;
        tStates += 6;
        break;

      // INC L
      case 0x2C:
        l = INC(l);
        break;

      // DEC L
      case 0x2D:
        l = DEC(l);
        break;

      // LD L, *
      case 0x2E:
        l = getNextByte();
        tStates += 7;
        break;

      // CPL
      case 0x2F:
        CPL();
        break;

      // JR NC, *
      case 0x30:
        if (!fC) {
          JR(getNextByte());
        } else {
          pc = (pc + 1) % 0x10000;
          tStates += 7;
        }
        break;

      // LD SP, **
      case 0x31:
        sp = getNextWord();
        tStates += 10;
        break;

      // LD (**), A
      case 0x32:
        memory.writeByte(getNextWord(), a);
        tStates += 13;
        break;

      // INC SP
      case 0x33:
        sp = (sp + 1) % 0x10000;
        tStates += 6;
        break;

      // INC (HL)
      case 0x34:
        memory.writeByte(hl, INC(memory.readByte(hl)));
        tStates += 7;
        break;

      // DEC (HL)
      case 0x35:
        memory.writeByte(hl, DEC(memory.readByte(hl)));
        tStates += 7;
        break;

      // LD (HL), *
      case 0x36:
        memory.writeByte(hl, getNextByte());
        tStates += 10;
        break;

      // SCF
      case 0x37:
        SCF();
        tStates += 4;
        break;

      // JR C, *
      case 0x38:
        if (fC) {
          JR(getNextByte());
        } else {
          pc = (pc + 1) % 0x10000;
          tStates += 7;
        }
        break;

      // ADD HL, SP
      case 0x39:
        hl = ADD16(hl, sp);
        break;

      // LD A, (**)
      case 0x3A:
        a = memory.readByte(getNextWord());
        tStates += 13;
        break;

      // DEC SP
      case 0x3B:
        sp = (sp - 1) % 0x10000;
        tStates += 6;
        break;

      // INC A
      case 0x3C:
        a = INC(a);
        break;

      // DEC A
      case 0x3D:
        a = DEC(a);
        break;

      // LD A, *
      case 0x3E:
        a = getNextByte();
        tStates += 7;
        break;

      // CCF
      case 0x3F:
        CCF();
        break;

      // LD B, B
      case 0x40:
        tStates += 4;
        break;

      // LD B, C
      case 0x41:
        b = c;
        tStates += 4;
        break;

      // LD B, D
      case 0x42:
        b = d;
        tStates += 4;
        break;

      // LD B, E
      case 0x43:
        b = e;
        tStates += 4;
        break;

      // LD B, H
      case 0x44:
        b = h;
        tStates += 4;
        break;

      // LD B, L
      case 0x45:
        b = l;
        tStates += 4;
        break;

      // LD B, (HL)
      case 0x46:
        b = memory.readByte(hl);
        tStates += 7;
        break;

      // LD B, A
      case 0x47:
        b = a;
        tStates += 4;
        break;

      // LD C, B
      case 0x48:
        c = b;
        tStates += 4;
        break;

      // LD C, C
      case 0x49:
        tStates += 4;
        break;

      // LD C, D
      case 0x4A:
        c = d;
        tStates += 4;
        break;

      // LD C, E
      case 0x4B:
        c = e;
        tStates += 4;
        break;

      // LD C, H
      case 0x4C:
        c = h;
        tStates += 4;
        break;

      // LD C, L
      case 0x4D:
        c = l;
        tStates += 4;
        break;

      // LD C, (HL)
      case 0x4E:
        c = memory.readByte(hl);
        tStates += 7;
        break;

      // LD C, A
      case 0x4F:
        c = a;
        tStates += 4;
        break;

      // LD D, B
      case 0x50:
        d = b;
        tStates += 4;
        break;

      // LD D, C
      case 0x51:
        d = c;
        tStates += 4;
        break;

      // LD D, D
      case 0x52:
        tStates += 4;
        break;

      // LD D, E
      case 0x53:
        d = e;
        tStates += 4;
        break;

      // LD D, H
      case 0x54:
        d = h;
        tStates += 4;
        break;

      // LD D, L
      case 0x55:
        d = l;
        tStates += 4;
        break;

      // LD D, (HL)
      case 0x56:
        d = memory.readByte(hl);
        tStates += 7;
        break;

      // LD D, A
      case 0x57:
        d = a;
        tStates += 4;
        break;

      // LD E, B
      case 0x58:
        e = b;
        tStates += 4;
        break;

      // LD E, C
      case 0x59:
        e = c;
        tStates += 4;
        break;

      // LD E, D
      case 0x5A:
        e = d;
        tStates += 4;
        break;

      // LD E, E
      case 0x5B:
        tStates += 4;
        break;

      // LD E, H
      case 0x5C:
        e = h;
        tStates += 4;
        break;

      // LD E, L
      case 0x5D:
        e = l;
        tStates += 4;
        break;

      // LD E, (HL)
      case 0x5E:
        e = memory.readByte(hl);
        tStates += 7;
        break;

      // LD E, A
      case 0x5F:
        e = a;
        tStates += 4;
        break;

      // LD H, B
      case 0x60:
        h = b;
        tStates += 4;
        break;

      // LD H, C
      case 0x61:
        h = c;
        tStates += 4;
        break;

      // LD H, D
      case 0x62:
        h = d;
        tStates += 4;
        break;

      // LD H, E
      case 0x63:
        h = e;
        tStates += 4;
        break;

      // LD H, H
      case 0x64:
        tStates += 4;
        break;

      // LD H, L
      case 0x65:
        h = l;
        tStates += 4;
        break;

      // LD H, (HL)
      case 0x66:
        h = memory.readByte(hl);
        tStates += 7;
        break;

      // LD H, A
      case 0x67:
        h = a;
        tStates += 4;
        break;

      // LD L, B
      case 0x68:
        l = b;
        tStates += 4;
        break;

      // LD L, C
      case 0x69:
        l = c;
        tStates += 4;
        break;

      // LD L, D
      case 0x6A:
        l = d;
        tStates += 4;
        break;

      // LD L, E
      case 0x6B:
        l = e;
        tStates += 4;
        break;

      // LD L, H
      case 0x6C:
        l = h;
        tStates += 4;
        break;

      // LD L, L
      case 0x6D:
        tStates += 4;
        break;

      // LD L, (HL)
      case 0x6E:
        l = memory.readByte(hl);
        tStates += 7;
        break;

      // LD L, A
      case 0x6F:
        l = a;
        tStates += 4;
        break;

      // LD (HL), B
      case 0x70:
        memory.writeByte(hl, b);
        tStates += 7;
        break;

      // LD (HL), C
      case 0x71:
        memory.writeByte(hl, c);
        tStates += 7;
        break;

      // LD (HL), D
      case 0x72:
        memory.writeByte(hl, d);
        tStates += 7;
        break;

      // LD (HL), E
      case 0x73:
        memory.writeByte(hl, e);
        tStates += 7;
        break;

      // LD (HL), H
      case 0x74:
        memory.writeByte(hl, h);
        tStates += 7;
        break;

      // LD (HL), L
      case 0x75:
        memory.writeByte(hl, l);
        tStates += 7;
        break;

      // HALT
      case 0x76:
        tStates += 4;
        pc = (pc - 1) % 0x10000;
        cpuSuspended = true;
        break;

      // LD (HL), A
      case 0x77:
        memory.writeByte(hl, a);
        tStates += 7;
        break;

      // LD A, B
      case 0x78:
        a = b;
        tStates += 4;
        break;

      // LD A, C
      case 0x79:
        a = c;
        tStates += 4;
        break;

      // LD A, D
      case 0x7A:
        a = d;
        tStates += 4;
        break;

      // LD A, E
      case 0x7B:
        a = e;
        tStates += 4;
        break;

      // LD A, H
      case 0x7C:
        a = h;
        tStates += 4;
        break;

      // LD A, L
      case 0x7D:
        a = l;
        tStates += 4;
        break;

      // LD A, (HL)
      case 0x7E:
        a = memory.readByte(hl);
        tStates += 7;
        break;

      // LD A, A
      case 0x7F:
        tStates += 4;
        break;

      // ADD A, B
      case 0x80:
        a = ADD8(a, b);
        break;

      // ADD A, C
      case 0x81:
        a = ADD8(a, c);
        break;

      // ADD A, D
      case 0x82:
        a = ADD8(a, d);
        break;

      // ADD A, E
      case 0x83:
        a = ADD8(a, e);
        break;

      // ADD A, H
      case 0x84:
        a = ADD8(a, h);
        break;

      // ADD A, L
      case 0x85:
        a = ADD8(a, l);
        break;

      // ADD A, (HL)
      case 0x86:
        a = ADD8(a, memory.readByte(hl));
        tStates += 3;
        break;

      // ADD A, A
      case 0x87:
        a = ADD8(a, a);
        break;

      // ADC A, B
      case 0x88:
        a = ADC8(a, b);
        break;

      // ADC A, C
      case 0x89:
        a = ADC8(a, c);
        break;

      // ADC A, D
      case 0x8A:
        a = ADC8(a, d);
        break;

      // ADC A, E
      case 0x8B:
        a = ADC8(a, e);
        break;

      // ADC A, H
      case 0x8C:
        a = ADC8(a, h);
        break;

      // ADC A, L
      case 0x8D:
        a = ADC8(a, l);
        break;

      // ADC A, (HL)
      case 0x8E:
        a = ADC8(a, memory.readByte(hl));
        tStates += 3;
        break;

      // ADC A, A
      case 0x8F:
        a = ADC8(a, a);
        break;

      // SUB B
      case 0x90:
        a = SUB8(a, b);
        break;

      // SUB C
      case 0x91:
        a = SUB8(a, c);
        break;

      // SUB D
      case 0x92:
        a = SUB8(a, d);
        break;

      // SUB E
      case 0x93:
        a = SUB8(a, e);
        break;

      // SUB H
      case 0x94:
        a = SUB8(a, h);
        break;

      // SUB L
      case 0x95:
        a = SUB8(a, l);
        break;

      // SUB (HL)
      case 0x96:
        a = SUB8(a, memory.readByte(hl));
        tStates += 3;
        break;

      // SUB A
      case 0x97:
        a = SUB8(a, a);
        break;

      // SBC A, B
      case 0x98:
        a = SBC8(a, b);
        break;

      // SBC A, C
      case 0x99:
        a = SBC8(a, c);
        break;

      // SBC A, D
      case 0x9A:
        a = SBC8(a, d);
        break;

      // SBC A, E
      case 0x9B:
        a = SBC8(a, e);
        break;

      // SBC A, H
      case 0x9C:
        a = SBC8(a, h);
        break;

      // SBC A, L
      case 0x9D:
        a = SBC8(a, l);
        break;

      // SBC A, (HL)
      case 0x9E:
        a = SBC8(a, memory.readByte(hl));
        tStates += 3;
        break;

      // SBC A, A
      case 0x9F:
        a = SBC8(a, a);
        break;

      // AND B
      case 0xA0:
        a = AND(a, b);
        break;

      // AND C
      case 0xA1:
        a = AND(a, c);
        break;

      // AND D
      case 0xA2:
        a = AND(a, d);
        break;

      // AND E
      case 0xA3:
        a = AND(a, e);
        break;

      // AND H
      case 0xA4:
        a = AND(a, h);
        break;

      // AND L
      case 0xA5:
        a = AND(a, l);
        break;

      // AND (HL)
      case 0xA6:
        a = AND(a, memory.readByte(hl));
        tStates += 3;
        break;

      // AND A
      case 0xA7:
        a = AND(a, a);
        break;

      // XOR B
      case 0xA8:
        a = XOR(a, b);
        break;

      // XOR C
      case 0xA9:
        a = XOR(a, c);
        break;

      // XOR D
      case 0xAA:
        a = XOR(a, d);
        break;

      // XOR E
      case 0xAB:
        a = XOR(a, e);
        break;

      // XOR H
      case 0xAC:
        a = XOR(a, h);
        break;

      // XOR L
      case 0xAD:
        a = XOR(a, l);
        break;

      // XOR (HL)
      case 0xAE:
        a = XOR(a, memory.readByte(hl));
        tStates += 3;
        break;

      // XOR A
      case 0xAF:
        a = XOR(a, a);
        break;

      // OR B
      case 0xB0:
        a = OR(a, b);
        break;

      // OR C
      case 0xB1:
        a = OR(a, c);
        break;

      // OR D
      case 0xB2:
        a = OR(a, d);
        break;

      // OR E
      case 0xB3:
        a = OR(a, e);
        break;

      // OR H
      case 0xB4:
        a = OR(a, h);
        break;

      // OR L
      case 0xB5:
        a = OR(a, l);
        break;

      // OR (HL)
      case 0xB6:
        a = OR(a, memory.readByte(hl));
        tStates += 3;
        break;

      // OR A
      case 0xB7:
        a = OR(a, a);
        break;

      // CP B
      case 0xB8:
        CP(b);
        break;

      // CP C
      case 0xB9:
        CP(c);
        break;

      // CP D
      case 0xBA:
        CP(d);
        break;

      // CP E
      case 0xBB:
        CP(e);
        break;

      // CP H
      case 0xBC:
        CP(h);
        break;

      // CP L
      case 0xBD:
        CP(l);
        break;

      // CP (HL)
      case 0xBE:
        CP(memory.readByte(hl));
        tStates += 3;
        break;

      // CP A
      case 0xBF:
        CP(a);
        break;

      // RET NZ
      case 0xC0:
        if (!fZ) {
          pc = POP();
          tStates += 11;
        } else {
          tStates += 5;
        }
        break;

      // POP BC
      case 0xC1:
        bc = POP();
        tStates += 10;
        break;

      // JP NZ, **
      case 0xC2:
        if (!fZ) {
          pc = getNextWord();
        } else {
          pc = (pc + 2) % 0x10000;
        }
        tStates += 10;
        break;

      // JP **
      case 0xC3:
        pc = getNextWord();
        tStates += 10;
        break;

      // CALL NZ, **
      case 0xC4:
        if (!fZ) {
          CALL();
        } else {
          pc = (pc + 2) % 0x10000;
          tStates += 10;
        }
        break;

      // PUSH BC
      case 0xC5:
        PUSH(bc);
        tStates += 11;
        break;

      // ADD A, *
      case 0xC6:
        a = ADD8(a, getNextByte());
        tStates += 3;
        break;

      // RST 00h
      case 0xC7:
        RST(0x00);
        break;

      // RET Z
      case 0xC8:
        if (fZ) {
          pc = POP();
          tStates += 11;
        } else {
          tStates += 5;
        }
        break;

      // RET
      case 0xC9:
        pc = POP();
        tStates += 10;
        break;

      // JP Z, **
      case 0xCA:
        if (fZ) {
          pc = getNextWord();
        } else {
          pc = (pc + 2) % 0x10000;
        }
        tStates += 10;
        break;

      // BITWISE INSTRUCTIONS
      case 0xCB:
        DecodeCBOpcode();
        break;

      // CALL Z, **
      case 0xCC:
        if (fZ) {
          CALL();
        } else {
          pc = (pc + 2) % 0x10000;
          tStates += 10;
        }
        break;

      // CALL **
      case 0xCD:
        CALL();
        break;

      // ADC A, *
      case 0xCE:
        a = ADC8(a, getNextByte());
        tStates += 3;
        break;

      // RST 08h
      case 0xCF:
        RST(0x08);
        break;

      // RET NC
      case 0xD0:
        if (!fC) {
          pc = POP();
          tStates += 11;
        } else {
          tStates += 5;
        }
        break;

      // POP DE
      case 0xD1:
        de = POP();
        tStates += 10;
        break;

      // JP NC, **
      case 0xD2:
        if (!fC) {
          pc = getNextWord();
        } else {
          pc = (pc + 2) % 0x10000;
        }
        tStates += 10;
        break;

      // OUT (*), A
      case 0xD3:
        OUTA(getNextByte(), a);
        tStates += 11;
        break;

      // CALL NC, **
      case 0xD4:
        if (!fC) {
          CALL();
        } else {
          pc = (pc + 2) % 0x10000;
          tStates += 10;
        }
        break;

      // PUSH DE
      case 0xD5:
        PUSH(de);
        tStates += 11;
        break;

      // SUB *
      case 0xD6:
        a = SUB8(a, getNextByte());
        tStates += 3;
        break;

      // RST 10h
      case 0xD7:
        RST(0x10);
        break;

      // RET C
      case 0xD8:
        if (fC) {
          pc = POP();
          tStates += 11;
        } else {
          tStates += 5;
        }
        break;

      // EXX
      case 0xD9:
        final oldB = b, oldC = c, oldD = d, oldE = e, oldH = h, oldL = l;
        b = b_;
        c = c_;
        d = d_;
        e = e_;
        h = h_;
        l = l_;
        b_ = oldB;
        c_ = oldC;
        d_ = oldD;
        e_ = oldE;
        h_ = oldH;
        l_ = oldL;
        tStates += 4;
        break;

      // JP C, **
      case 0xDA:
        if (fC) {
          pc = getNextWord();
        } else {
          pc = (pc + 2) % 0x10000;
        }
        tStates += 10;
        break;

      // IN A, (*)
      case 0xDB:
        INA(getNextByte());
        tStates += 11;
        break;

      // CALL C, **
      case 0xDC:
        if (fC) {
          CALL();
        } else {
          pc = (pc + 2) % 0x10000;
          tStates += 10;
        }
        break;

      // IX OPERATIONS
      case 0xDD:
        DecodeDDOpcode();
        break;

      // SBC A, *
      case 0xDE:
        a = SBC8(a, getNextByte());
        tStates += 3;
        break;

      // RST 18h
      case 0xDF:
        RST(0x18);
        break;

      // RET PO
      case 0xE0:
        if (!fPV) {
          pc = POP();
          tStates += 11;
        } else {
          tStates += 5;
        }
        break;

      // POP HL
      case 0xE1:
        hl = POP();
        tStates += 10;
        break;

      // JP PO, **
      case 0xE2:
        if (!fPV) {
          pc = getNextWord();
        } else {
          pc = (pc + 2) % 0x10000;
        }
        tStates += 10;
        break;

      // EX (SP), HL
      case 0xE3:
        final temp = hl;
        hl = memory.readWord(sp);
        memory.writeWord(sp, temp);
        tStates += 19;
        break;

      // CALL PO, **
      case 0xE4:
        if (!fPV) {
          CALL();
        } else {
          pc = (pc + 2) % 0x10000;
          tStates += 10;
        }
        break;

      // PUSH HL
      case 0xE5:
        PUSH(hl);
        tStates += 11;
        break;

      // AND *
      case 0xE6:
        a = AND(a, getNextByte());
        tStates += 3;
        break;

      // RST 20h
      case 0xE7:
        RST(0x20);
        break;

      // RET PE
      case 0xE8:
        if (fPV) {
          pc = POP();
          tStates += 11;
        } else {
          tStates += 5;
        }
        break;

      // JP (HL)
      // note that the brackets in the instruction are an eccentricity, the result
      // should be hl rather than the contents of addr(hl)
      case 0xE9:
        pc = hl;
        tStates += 4;
        break;

      // JP PE, **
      case 0xEA:
        if (fPV) {
          pc = getNextWord();
        } else {
          pc = (pc + 2) % 0x10000;
        }
        tStates += 10;
        break;

      // EX DE, HL
      case 0xEB:
        final oldD = d, oldE = e;
        d = h;
        e = l;
        h = oldD;
        l = oldE;
        tStates += 4;
        break;

      // CALL PE, **
      case 0xEC:
        if (fPV) {
          CALL();
        } else {
          pc = (pc + 2) % 0x10000;
          tStates += 10;
        }
        break;

      // EXTD INSTRUCTIONS
      case 0xED:
        DecodeEDOpcode();
        break;

      // XOR *
      case 0xEE:
        a = XOR(a, getNextByte());
        tStates += 3;
        break;

      // RST 28h
      case 0xEF:
        RST(0x28);
        break;

      // RET P
      case 0xF0:
        if (!fS) {
          pc = POP();
          tStates += 11;
        } else {
          tStates += 5;
        }
        break;

      // POP AF
      case 0xF1:
        af = POP();
        tStates += 10;
        break;

      // JP P, **
      case 0xF2:
        if (!fS) {
          pc = getNextWord();
        } else {
          pc = (pc + 2) % 0x10000;
        }
        tStates += 10;
        break;

      // DI
      case 0xF3:
        iff1 = false;
        iff2 = false;
        tStates += 4;
        break;

      // CALL P, **
      case 0xF4:
        if (!fS) {
          CALL();
        } else {
          pc = (pc + 2) % 0x10000;
          tStates += 10;
        }
        break;

      // PUSH AF
      case 0xF5:
        PUSH(af);
        tStates += 11;
        break;

      // OR *
      case 0xF6:
        a = OR(a, getNextByte());
        tStates += 3;
        break;

      // RST 30h
      case 0xF7:
        RST(0x30);
        break;

      // RET M
      case 0xF8:
        if (fS) {
          pc = POP();
          tStates += 11;
        } else {
          tStates += 5;
        }
        break;

      // LD SP, HL
      case 0xF9:
        sp = hl;
        tStates += 6;
        break;

      // JP M, **
      case 0xFA:
        if (fS) {
          pc = getNextWord();
        } else {
          pc = (pc + 2) % 0x10000;
        }
        tStates += 10;
        break;

      // EI
      case 0xFB:
        iff1 = true;
        iff2 = true;
        tStates += 4;
        break;

      // CALL M, **
      case 0xFC:
        if (fS) {
          CALL();
        } else {
          pc = (pc + 2) % 0x10000;
          tStates += 10;
        }
        break;

      // IY INSTRUCTIONS
      case 0xFD:
        DecodeFDOpcode();
        break;

      // CP *
      case 0xFE:
        CP(getNextByte());
        tStates += 3;
        break;

      // RST 38h
      case 0xFF:
        RST(0x38);
        break;
    }

    return true;
  }
}
