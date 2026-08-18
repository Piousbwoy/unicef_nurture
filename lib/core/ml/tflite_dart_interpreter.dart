library;

// A minimal, dependency-free TensorFlow Lite interpreter in pure Dart.
//
// Why this exists
// ───────────────
// The native `tflite_flutter` runtime is the PRIMARY inference path on
// Android/iOS/Windows (see tflite_runner_io.dart). But it relies on
// dart:ffi + a platform C library, which the browser cannot provide. This
// interpreter executes the exact same SHA-verified `.tflite` assets —
// parsed straight from their FlatBuffers bytes — so a web demo runs the
// genuine trained weights on-device instead of the deterministic fallback.
//
// Scope: the ops our model pack uses (FULLY_CONNECTED with fused ReLU,
// QUANTIZE, DEQUANTIZE), float32/int8/int32 tensors, per-channel affine
// quantization. Anything outside that scope throws, and the caller falls
// back exactly as it would for a native interpreter failure.

import 'dart:math' as math;
import 'dart:typed_data';

// TFLite v3 schema enum values (tensorflow/lite/schema/schema.fbs).
class _Op {
  static const add = 0;
  static const dequantize = 6;
  static const fullyConnected = 9;
  static const logistic = 14;
  static const relu = 19;
  static const quantize = 114;
}

class _TensorType {
  static const float32 = 0;
  static const int32 = 2;
  static const int8 = 9;
}

class _BuiltinOptions {
  static const fullyConnectedOptions = 8;
}

class _Activation {
  static const none = 0;
  static const relu = 1;
}

/// Minimal FlatBuffers reader over the TFLite v3 schema.
class _Fb {
  _Fb(this.bytes) : bd = bytes.buffer.asByteData(bytes.offsetInBytes);

  final Uint8List bytes;
  final ByteData bd;

  int u32(int pos) => bd.getUint32(pos, Endian.little);
  int i32(int pos) => bd.getInt32(pos, Endian.little);
  int u16(int pos) => bd.getUint16(pos, Endian.little);
  int i64(int pos) => bd.getInt64(pos, Endian.little);
  double f32(int pos) => bd.getFloat32(pos, Endian.little);

  int root() => u32(0);

  int _vtable(int table) => table - i32(table);

  /// Offset of field [id] within the table, or 0 when the field is absent.
  int field(int table, int id) {
    final vt = _vtable(table);
    final slot = 4 + 2 * id;
    if (slot >= u16(vt)) return 0;
    return u16(vt + slot);
  }

  int byteField(int table, int id) {
    final fo = field(table, id);
    return fo == 0 ? 0 : bytes[table + fo];
  }

  int intField(int table, int id) {
    final fo = field(table, id);
    return fo == 0 ? 0 : i32(table + fo);
  }

  /// Vector field → (contents position, length), or null when absent.
  (int, int)? vec(int table, int id) {
    final fo = field(table, id);
    if (fo == 0) return null;
    final rel = table + fo;
    final target = rel + u32(rel);
    return (target + 4, u32(target));
  }

  List<int> intVec(int table, int id) {
    final v = vec(table, id);
    if (v == null) return const [];
    return [for (var j = 0; j < v.$2; j++) i32(v.$1 + 4 * j)];
  }

  List<double> floatVec(int table, int id) {
    final v = vec(table, id);
    if (v == null) return const [];
    return [for (var j = 0; j < v.$2; j++) f32(v.$1 + 4 * j)];
  }

  /// Position of the [index]-th table inside a vector of tables.
  int tableAt(int contentsPos, int index) {
    final p = contentsPos + 4 * index;
    return p + u32(p);
  }
}

class _Tensor {
  _Tensor({
    required this.shape,
    required this.type,
    required this.data,
    required this.scales,
    required this.zeroPoints,
  });

  final List<int> shape;
  final int type;

  /// Raw storage, one of Float32List / Int32List / Int8List.
  TypedData data;

  final List<double> scales;
  final List<int> zeroPoints;

  int get count => shape.isEmpty ? 1 : shape.reduce((a, b) => a * b);

  double scale(int channel) =>
      scales.isEmpty ? 1.0 : scales[channel < scales.length ? channel : 0];

  int zeroPoint(int channel) => zeroPoints.isEmpty
      ? 0
      : zeroPoints[channel < zeroPoints.length ? channel : 0];

  double realAt(int index, int channel) {
    final d = data;
    if (d is Float32List) return d[index];
    if (d is Int8List) return (d[index] - zeroPoint(channel)) * scale(channel);
    if (d is Int32List) return (d[index] - zeroPoint(channel)) * scale(channel);
    throw StateError('Unsupported tensor storage');
  }

  void setReal(int index, int channel, double value) {
    final d = data;
    if (d is Float32List) {
      d[index] = value;
    } else if (d is Int8List) {
      final q = (value / scale(channel) + zeroPoint(channel)).round();
      d[index] = q.clamp(-128, 127).toInt();
    } else if (d is Int32List) {
      final q = (value / scale(channel) + zeroPoint(channel)).round();
      d[index] = q;
    } else {
      throw StateError('Unsupported tensor storage');
    }
  }

  int quantizedAt(int index) {
    final d = data;
    if (d is Int8List) return d[index];
    if (d is Int32List) return d[index];
    throw StateError('Tensor is not quantized storage');
  }
}

class _Operator {
  _Operator({
    required this.builtinCode,
    required this.inputs,
    required this.outputs,
    required this.fusedActivation,
  });

  final int builtinCode;
  final List<int> inputs;
  final List<int> outputs;
  final int fusedActivation;
}

/// A parsed model graph, ready to run.
class TfliteDartModel {
  TfliteDartModel._(this._tensors, this._ops, this._inputs, this._outputs);

  final List<_Tensor> _tensors;
  final List<_Operator> _ops;
  final List<int> _inputs;
  final List<int> _outputs;

  /// Parses a `.tflite` flatbuffer. Throws [FormatException] on anything
  /// this minimal interpreter cannot honour.
  factory TfliteDartModel.fromBytes(Uint8List bytes) {
    final fb = _Fb(bytes);
    final model = fb.root();
    if (bytes.length < 8 ||
        bytes[4] != 0x54 || bytes[5] != 0x46 || bytes[6] != 0x4C) {
      throw const FormatException('Not a TFLite flatbuffer');
    }

    // Operator codes.
    final codes = <int>[];
    final oc = fb.vec(model, 1);
    if (oc != null) {
      for (var i = 0; i < oc.$2; i++) {
        final t = fb.tableAt(oc.$1, i);
        // deprecated_builtin_code when < 127, else the extended int32 field.
        final dep = fb.byteField(t, 0);
        codes.add(dep != 127 ? dep : fb.intField(t, 1));
      }
    }

    // Buffers.
    final buffers = <Uint8List>[];
    final bv = fb.vec(model, 4);
    if (bv != null) {
      for (var i = 0; i < bv.$2; i++) {
        final b = fb.tableAt(bv.$1, i);
        final d = fb.vec(b, 0);
        if (d == null) {
          buffers.add(Uint8List(0));
        } else {
          buffers.add(Uint8List.fromList(
              bytes.sublist(d.$1, d.$1 + d.$2)));
        }
      }
    }

    // First subgraph only — every model in the pack ships exactly one.
    final sgv = fb.vec(model, 2);
    if (sgv == null || sgv.$2 == 0) {
      throw const FormatException('Model has no subgraphs');
    }
    final sub = fb.tableAt(sgv.$1, 0);

    final tensors = <_Tensor>[];
    final tv = fb.vec(sub, 0);
    if (tv != null) {
      for (var i = 0; i < tv.$2; i++) {
        final t = fb.tableAt(tv.$1, i);
        final shape = fb.intVec(t, 0);
        final type = fb.byteField(t, 1);
        final bufferIdx = fb.intField(t, 2);
        var count = shape.isEmpty ? 1 : shape.reduce((a, b) => a * b);
        if (count < 0) count = 0;

        // QuantizationParameters (field 4): scale(2), zero_point(3).
        List<double> scales = const [];
        List<int> zps = const [];
        final qfo = fb.field(t, 4);
        if (qfo != 0) {
          final rel = t + qfo;
          final q = rel + fb.u32(rel);
          scales = fb.floatVec(q, 2);
          final zpv = fb.vec(q, 3);
          if (zpv != null) {
            zps = [for (var j = 0; j < zpv.$2; j++) fb.i64(zpv.$1 + 8 * j)];
          }
        }

        final raw = bufferIdx < buffers.length ? buffers[bufferIdx] : Uint8List(0);
        final TypedData data;
        switch (type) {
          case _TensorType.float32:
            final f = Float32List(count);
            final view = ByteData.sublistView(raw);
            for (var j = 0; j < count && (j + 1) * 4 <= raw.length; j++) {
              f[j] = view.getFloat32(j * 4, Endian.little);
            }
            data = f;
          case _TensorType.int32:
            final f = Int32List(count);
            final view = ByteData.sublistView(raw);
            for (var j = 0; j < count && (j + 1) * 4 <= raw.length; j++) {
              f[j] = view.getInt32(j * 4, Endian.little);
            }
            data = f;
          case _TensorType.int8:
            final f = Int8List(count);
            for (var j = 0; j < count && j < raw.length; j++) {
              f[j] = raw[j] > 127 ? raw[j] - 256 : raw[j];
            }
            data = f;
          default:
            throw FormatException('Unsupported tensor type $type');
        }
        tensors.add(_Tensor(
          shape: shape,
          type: type,
          data: data,
          scales: scales,
          zeroPoints: zps,
        ));
      }
    }

    final ops = <_Operator>[];
    final ov = fb.vec(sub, 3);
    if (ov != null) {
      for (var i = 0; i < ov.$2; i++) {
        final o = fb.tableAt(ov.$1, i);
        final opcodeIndex = fb.intField(o, 0);
        if (opcodeIndex >= codes.length) {
          throw FormatException('Bad opcode index $opcodeIndex');
        }
        var fused = _Activation.none;
        final optType = fb.byteField(o, 3);
        if (optType == _BuiltinOptions.fullyConnectedOptions) {
          final rel = o + fb.field(o, 4);
          final opts = rel + fb.u32(rel);
          fused = fb.byteField(opts, 0);
        }
        ops.add(_Operator(
          builtinCode: codes[opcodeIndex],
          inputs: fb.intVec(o, 1),
          outputs: fb.intVec(o, 2),
          fusedActivation: fused,
        ));
      }
    }

    return TfliteDartModel._(
      tensors,
      ops,
      fb.intVec(sub, 1),
      fb.intVec(sub, 2),
    );
  }

  int get inputCount => _tensors[_inputs.first].count;

  /// Runs the graph on [input] (already feature-ordered by the caller) and
  /// returns the first output value — for the risk models, a probability.
  double run(Float32List input) {
    final inT = _tensors[_inputs.first];
    if (input.length < inT.count) {
      throw ArgumentError('Input has ${input.length} values, '
          'model expects ${inT.count}');
    }
    for (var i = 0; i < inT.count; i++) {
      inT.setReal(i, 0, input[i]);
    }

    for (final op in _ops) {
      _dispatch(op);
    }

    final outT = _tensors[_outputs.first];
    return outT.realAt(0, 0);
  }

  void _dispatch(_Operator op) {
    switch (op.builtinCode) {
      case _Op.fullyConnected:
        _fullyConnected(op);
      case _Op.relu:
        _relu(op);
      case _Op.logistic:
        _logistic(op);
      case _Op.add:
        _add(op);
      case _Op.quantize:
      case _Op.dequantize:
        _requantize(op);
      default:
        throw FormatException('Unsupported op ${op.builtinCode}');
    }
  }

  /// y = W·x + b, W stored as [rows, cols] (TFLite convention).
  void _fullyConnected(_Operator op) {
    final x = _tensors[op.inputs[0]];
    final w = _tensors[op.inputs[1]];
    final b = op.inputs.length > 2 && op.inputs[2] >= 0
        ? _tensors[op.inputs[2]]
        : null;
    final y = _tensors[op.outputs[0]];

    final rows = w.shape.isNotEmpty ? w.shape.first : 1;
    final cols = w.count ~/ math.max(rows, 1);
    final wPerChannel = w.scales.length > 1;

    for (var r = 0; r < rows; r++) {
      var acc = b != null ? b.realAt(r, b.scales.length > 1 ? r : 0) : 0.0;
      if (x.type == _TensorType.int8 && w.type == _TensorType.int8) {
        // Integer fast path, mirroring the reference kernel:
        // sum (xq - xzp) * (wq - wzp), dequantized once at the end.
        final xzp = x.zeroPoint(0);
        final wzp = w.zeroPoint(wPerChannel ? r : 0);
        var isum = 0;
        for (var c = 0; c < cols; c++) {
          isum +=
              (x.quantizedAt(c) - xzp) *
              (w.quantizedAt(r * cols + c) - wzp);
        }
        acc += isum * x.scale(0) * w.scale(wPerChannel ? r : 0);
      } else {
        for (var c = 0; c < cols; c++) {
          acc += x.realAt(c, 0) * w.realAt(r * cols + c, wPerChannel ? r : 0);
        }
      }
      if (op.fusedActivation == _Activation.relu && acc < 0) acc = 0;
      y.setReal(r, 0, acc);
    }
  }

  void _relu(_Operator op) {
    final x = _tensors[op.inputs[0]];
    final y = _tensors[op.outputs[0]];
    for (var i = 0; i < x.count; i++) {
      final v = x.realAt(i, 0);
      y.setReal(i, 0, v < 0 ? 0 : v);
    }
  }

  void _logistic(_Operator op) {
    final x = _tensors[op.inputs[0]];
    final y = _tensors[op.outputs[0]];
    for (var i = 0; i < x.count; i++) {
      final v = x.realAt(i, 0);
      y.setReal(i, 0, 1.0 / (1.0 + math.exp(-v)));
    }
  }

  void _add(_Operator op) {
    final a = _tensors[op.inputs[0]];
    final b = _tensors[op.inputs[1]];
    final y = _tensors[op.outputs[0]];
    final n = math.max(a.count, b.count);
    for (var i = 0; i < n; i++) {
      y.setReal(i, 0, a.realAt(i % a.count, 0) + b.realAt(i % b.count, 0));
    }
  }

  /// QUANTIZE / DEQUANTIZE between differently-typed tensors: copy values
  /// through their real representation.
  void _requantize(_Operator op) {
    final x = _tensors[op.inputs[0]];
    final y = _tensors[op.outputs[0]];
    for (var i = 0; i < y.count; i++) {
      y.setReal(i, 0, x.realAt(i, 0));
    }
  }
}
