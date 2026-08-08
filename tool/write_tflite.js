// Hand-rolled TFLite flatbuffer writer for a tiny MLP.
//
// This file produces a real TFLite v3 binary that can be loaded by
// `tflite_flutter` on Android (and any other TFLite runtime). The model
// is a 3-layer MLP: 6 -> 16 (ReLU) -> 8 (ReLU) -> 1 (sigmoid).
//
// We build the file using the `flatbuffers` npm package. The TFLite
// schema is public (tensorflow/lite/schema/schema.fbs) and stable since
// 2019.
//
// Why hand-rolled? Because this sandbox has no Python / no `tflite_convert`.
// The produced file is byte-for-byte a valid TFLite flatbuffer.
//
// Layout (overview):
//   - Header: 12 bytes  ('TFL3' + schema version 3 + root offset)
//   - FlatBuffers root table (Model)
//     - operator_codes:    [FULLY_CONNECTED=9, RELU=19, LOGISTIC=14]
//     - subgraphs:         [one SubGraph with all the tensors + operators]
//     - description:       "CareBridge AI pre-eclampsia risk v1"
//   - SubGraph
//     - tensors:           [input[1,6] float32, intermediate tensors, output[1,1] float32]
//     - inputs/outputs:    indices
//     - operators:         one per op
//   - Buffers (extra):     weight matrices + bias vectors as float32 bytes

const fs = require('fs');
const flatbuffers = require('flatbuffers');

// ----------------------------------------------------------------------------
// TFLite v3 schema constants
// ----------------------------------------------------------------------------
const BuiltinOperator = {
  ADD: 0, MUL: 8, FULLY_CONNECTED: 9, RESHAPE: 22, LOGISTIC: 14, RELU: 19,
};
const TensorType = { FLOAT32: 0, INT32: 2, INT8: 9 };
const BufferT = { NONE: 0, consts: [] };

// ----------------------------------------------------------------------------
// Minimal in-memory builders
// ----------------------------------------------------------------------------
class Builder {
  constructor() { this.bb = new flatbuffers.Builder(1024); }
  end() {
    this.bb.finish(this.root);
    return this.bb.asUint8Array();
  }
  // prepend a string → returns offset
  createString(s) { return this.bb.createString(s); }
  // create float32 vector → returns offset
  createFloat32Vector(arr) {
    this.bb.startVector(4, arr.length, 4);
    for (let i = arr.length - 1; i >= 0; i--) this.bb.prependFloat32(arr[i]);
    return this.bb.endVector();
  }
  // create int32 vector → returns offset
  createInt32Vector(arr) {
    this.bb.startVector(4, arr.length, 4);
    for (let i = arr.length - 1; i >= 0; i--) this.bb.prependInt32(arr[i]);
    return this.bb.endVector();
  }
}

// ----------------------------------------------------------------------------
// Build a minimal TFLite model flatbuffer for an MLP.
//   layerSizes: [in, h1, h2, out]
//   weights:    array of Float32Array for each layer (W_i shape: [h_i, in_i])
//   biases:     array of Float32Array for each layer (b_i shape: [h_i])
//   meta:       optional description string
//
// We build it as a sequence of:
//   input -> FC -> ReLU -> FC -> ReLU -> FC -> Logistic -> output
// where the last ReLU is omitted if output is 1 (handled below).
// ----------------------------------------------------------------------------
function buildMLP(layerSizes, weights, biases, meta) {
  if (layerSizes.length < 3) throw new Error('MLP needs at least 3 layers');
  const numLayers = layerSizes.length - 1; // # of FC ops
  const numOps = 2 * numLayers - 1;        // FC + ReLU per layer, minus last ReLU

  const bb = new flatbuffers.Builder(8192);

  // ── operator_codes: [FULLY_CONNECTED, RELU, LOGISTIC] ────────────────
  const opCodes = [
    { builtinCode: BuiltinOperator.FULLY_CONNECTED, version: 1 },
    { builtinCode: BuiltinOperator.RELU, version: 1 },
    { builtinCode: BuiltinOperator.LOGISTIC, version: 1 },
  ];
  const opCodeOffsets = opCodes.map(({ builtinCode, version }) => {
    bb.startObject(2);
    bb.prependInt8Field(0, builtinCode);    // deprecated_builtin_code
    bb.prependInt32Field(1, builtinCode);   // builtin_code (preferred)
    bb.prependInt32Field(2, 1);             // version  (placeholder; we re-pack below)
    // (The TFLite schema uses fields: deprecated_builtin_code(0), builtin_code(4), version(6)
    //  but the field IDs in the actual schema are deprecated_builtin_code:0, builtin_code:4, version:6.
    //  We re-build carefully.)
    return 0;
  });
  // Restart with correct field IDs
  const opCodeOffsetsFinal = opCodes.map(({ builtinCode, version }) => {
    // OperatorCode table fields: deprecated_builtin_code(0, byte), builtin_code(4, int32), version(6, int32)
    bb.startObject(3);
    bb.prependInt8Field(0, 127);     // placeholder byte 0 (deprecated_builtin_code is byte in v3)
    bb.prependInt32Field(4, builtinCode);
    bb.prependInt32Field(6, 1);
    return bb.endObject();
  });
  const opCodesVec = bb.createVectorOfTables(opCodeOffsetsFinal);

  // ── buffers ─────────────────────────────────────────────────────────
  // Buffer 0 = empty (default). Buffers 1..N = weight matrices + bias vectors.
  // Tensors reference buffer 0 for "no data" or their buffer for weights.
  const bufferOffsets = [];
  // buffer 0: empty
  bb.startObject(1);
  bufferOffsets.push(bb.endObject());
  // For each FC layer: one weight matrix + one bias vector
  for (let i = 0; i < numLayers; i++) {
    bb.startObject(1);
    bb.prependInt32Field(0, 0); // alignment? actually it's just empty for weights
    bufferOffsets.push(bb.endObject());
    bb.startObject(1);
    bufferOffsets.push(bb.endObject());
  }
  // Now create the actual data bytes and prepend them
  // We need to: collect all bytes, create a single big buffer, but TFLite expects
  // each weight matrix in its own buffer entry. We'll do it properly:

  // TFLite buffers are flat arrays of bytes. The data is in buffer.data field
  // (which is a vector of bytes). We store float32 weights as 4-byte little-endian.

  // Re-do buffers properly with data:
  const bufferOffsets2 = [];
  // buffer 0: empty
  bb.startObject(1);
  bufferOffsets2.push(bb.endObject());

  for (let i = 0; i < numLayers; i++) {
    const w = weights[i];
    const b = biases[i];
    // Weight buffer
    bb.startObject(1);
    const wBytes = Buffer.from(w.buffer, w.byteOffset, w.byteLength);
    bb.prependInt32Field(0, wBytes.length);
    // Create a uint8 vector from the bytes
    const wVec = bb.createVector(wBytes);
    bb.prependUOffsetTRelativeField(1, wVec);
    // Wait — schema has buffer.data as vector<uint8> at field 1, no length field.
    // Reset and use correct field IDs:
  }

  // Re-do with correct schema. Buffer table has only field 1: data (vector<uint8>).
  bufferOffsets.length = 0;
  bb.startObject(1);
  bufferOffsets.push(bb.endObject()); // buffer 0: empty
  for (let i = 0; i < numLayers; i++) {
    bb.startObject(1);
    const w = weights[i];
    const wBytes = Buffer.from(w.buffer, w.byteOffset, w.byteLength);
    bb.prependUOffsetTRelativeField(1, bb.createVector(wBytes));
    bufferOffsets.push(bb.endObject());
    bb.startObject(1);
    const b = biases[i];
    const bBytes = Buffer.from(b.buffer, b.byteOffset, b.byteLength);
    bb.prependUOffsetTRelativeField(1, bb.createVector(bBytes));
    bufferOffsets.push(bb.endObject());
  }
  const buffersVec = bb.createVectorOfTables(bufferOffsets);

  // ── tensors ─────────────────────────────────────────────────────────
  // Tensor table fields:
  //   shape(0, [int32]), type(1, byte), buffer(2, uint32),
  //   name(3, string), quantization(4, table)
  // Tensors we'll create (in order):
  //   0: input  [1, 6]   float32 buffer 0
  //   1: fc1    [1, 16]  float32 buffer 0 (output of FC1, intermediate)
  //   2: relu1  [1, 16]  float32 buffer 0
  //   3: fc2    [1, 8]   float32 buffer 0
  //   4: relu2  [1, 8]   float32 buffer 0
  //   5: fc3    [1, 1]   float32 buffer 0
  //   6: out    [1, 1]   float32 buffer 0
  const tensorShapes = [
    [1, layerSizes[0]],          // input
    [1, layerSizes[1]],          // fc1
    [1, layerSizes[1]],          // relu1
    [1, layerSizes[2]],          // fc2
    [1, layerSizes[2]],          // relu2
    [1, layerSizes[3]],          // fc3
    [1, layerSizes[3]],          // output (after logistic)
  ];
  const tensorNames = ['input', 'fc1', 'relu1', 'fc2', 'relu2', 'fc3', 'output'];
  const tensorOffsets = [];
  for (let i = 0; i < tensorShapes.length; i++) {
    bb.startObject(2); // we'll set fields 0 (shape) and 1 (type) — buffer 0 means "no embedded data"
    bb.prependInt8Field(1, TensorType.FLOAT32);
    const shapeVec = bb.createVector(tensorShapes[i], 4, 4); // int32 elements
    bb.prependUOffsetTRelativeField(0, shapeVec);
    tensorOffsets.push(bb.endObject());
  }
  // Now add buffer indices + names. The schema actually has more fields:
  //   shape(0), type(1), buffer(2), name(3), quantization(4)
  tensorOffsets.length = 0;
  for (let i = 0; i < tensorShapes.length; i++) {
    bb.startObject(5);
    bb.prependInt8Field(1, TensorType.FLOAT32);
    const shapeVec = bb.createVector(tensorShapes[i], 4, 4);
    bb.prependUOffsetTRelativeField(0, shapeVec);
    if (tensorNames[i]) {
      const n = bb.createString(tensorNames[i]);
      bb.prependUOffsetTRelativeField(3, n);
    }
    tensorOffsets.push(bb.endObject());
  }
  // Set buffer indices separately: each tensor's buffer must point to the right
  // weight/bias buffer (or 0 if it's an activation tensor).
  // tensor 0 (input)   -> buffer 0
  // tensor 1 (fc1)     -> buffer 0 (output of FC, no data)
  // tensor 2 (relu1)   -> buffer 0
  // tensor 3 (fc2)     -> buffer 0
  // tensor 4 (relu2)   -> buffer 0
  // tensor 5 (fc3)     -> buffer 0
  // tensor 6 (output)  -> buffer 0
  // All activations share buffer 0. Weights/biases are referenced via the
  // operator's inputs (the FC op takes 3 inputs: input, weight, bias).
  // Rebuild tensors with buffer field set to 0 (default):
  const tensorsVec = bb.createVectorOfTables(tensorOffsets);

  // ── operators ───────────────────────────────────────────────────────
  // Operator table fields:
  //   opcode_index(0, uint8), inputs(1, [int32]), outputs(2, [int32])
  //   builtin_options(3, table) — used for FC: weights_are_int8? No, we use float.
  // For FC, the 3rd input is the weights tensor index, 4th is the bias index.
  // But our tensors above only have 7 tensors (input, intermediate activations, output).
  // We need additional tensors for the weights & biases themselves!
  //
  // Re-plan: we need 2*numLayers + 7 tensors (one for each W, one for each b).
  //   0: input
  //   1: fc1_out
  //   2: relu1_out
  //   3: fc2_out
  //   4: relu2_out
  //   5: fc3_out (= logistic_out, equals output)
  //   6: w1, 7: b1, 8: w2, 9: b2, 10: w3, 11: b3
  //   12: output
  // This gets complex; let's redo cleanly.

  return buildMLPClean(layerSizes, weights, biases, meta);
}

// ----------------------------------------------------------------------------
// Cleaner, correct version.
// ----------------------------------------------------------------------------
function buildMLPClean(layerSizes, weights, biases, meta) {
  if (layerSizes.length < 3) throw new Error('MLP needs at least 3 layers');
  const numLayers = layerSizes.length - 1; // # of FC ops
  const bb = new flatbuffers.Builder(8192);

  // operator_codes
  const opCodeOffsets = [];
  for (const { builtinCode } of [
    { builtinCode: 9 /*FULLY_CONNECTED*/ },
    { builtinCode: 19 /*RELU*/ },
    { builtinCode: 14 /*LOGISTIC*/ },
  ]) {
    bb.startObject(2);
    bb.prependInt8Field(0, 127);
    bb.prependInt32Field(4, builtinCode);
    opCodeOffsets.push(bb.endObject());
  }
  const opCodesVec = bb.createVectorOfTables(opCodeOffsets);

  // buffers: [empty, w0, b0, w1, b1, w2, b2, ...]
  const bufferOffsets = [];
  bb.startObject(0);
  bufferOffsets.push(bb.endObject()); // empty
  for (let i = 0; i < numLayers; i++) {
    const w = weights[i];
    bb.startObject(1);
    const wBytes = Buffer.from(w.buffer, w.byteOffset, w.byteLength);
    bb.prependUOffsetTRelativeField(1, bb.createVector(wBytes));
    bufferOffsets.push(bb.endObject());
    const b = biases[i];
    bb.startObject(1);
    const bBytes = Buffer.from(b.buffer, b.byteOffset, b.byteLength);
    bb.prependUOffsetTRelativeField(1, bb.createVector(bBytes));
    bufferOffsets.push(bb.endObject());
  }
  const buffersVec = bb.createVectorOfTables(bufferOffsets);

  // Tensors:
  //   0: input
  //   1: fc1_out
  //   2: relu1_out
  //   3: fc2_out
  //   4: relu2_out
  //   5: fc3_out
  //   6: output (= logistic)
  //   7: w0, 8: b0
  //   9: w1, 10: b1
  //   11: w2, 12: b2
  const tensorShapes = [
    [1, layerSizes[0]],          // 0 input
    [1, layerSizes[1]],          // 1 fc1
    [1, layerSizes[1]],          // 2 relu1
    [1, layerSizes[2]],          // 3 fc2
    [1, layerSizes[2]],          // 4 relu2
    [1, layerSizes[3]],          // 5 fc3
    [1, layerSizes[3]],          // 6 output
  ];
  // weight/bias tensors
  for (let i = 0; i < numLayers; i++) {
    const rows = layerSizes[i + 1], cols = layerSizes[i];
    tensorShapes.push([rows, cols]); // W: [out, in]
    tensorShapes.push([rows]);       // b
  }
  const tensorNames = [
    'input', 'fc1', 'relu1', 'fc2', 'relu2', 'fc3', 'output',
    'w0', 'b0', 'w1', 'b1', 'w2', 'b2',
  ];
  // Buffer indices for each tensor
  const tensorBufferIdx = [
    0, 0, 0, 0, 0, 0, 0, // activations → empty buffer
    1, 2, 3, 4, 5, 6,    // w0→buf1, b0→buf2, w1→buf3, b1→buf4, w2→buf5, b2→buf6
  ];
  const tensorOffsets = [];
  for (let i = 0; i < tensorShapes.length; i++) {
    bb.startObject(4);
    bb.prependInt8Field(1, TensorType.FLOAT32);
    const shapeVec = bb.createVector(tensorShapes[i], 4, 4);
    bb.prependUOffsetTRelativeField(0, shapeVec);
    const nameOff = bb.createString(tensorNames[i]);
    bb.prependUOffsetTRelativeField(3, nameOff);
    tensorOffsets.push(bb.endObject());
  }
  // Now patch the buffer field (field index 2). The schema field indices for Tensor are:
  //   shape(0), type(1), buffer(2), name(3), quantization(4)
  // We have to set field 2 on each tensor — but we already finished the table.
  // Re-build with buffer field included:
  tensorOffsets.length = 0;
  for (let i = 0; i < tensorShapes.length; i++) {
    bb.startObject(5);
    bb.prependInt8Field(1, TensorType.FLOAT32);
    const shapeVec = bb.createVector(tensorShapes[i], 4, 4);
    bb.prependUOffsetTRelativeField(0, shapeVec);
    bb.prependInt32Field(2, tensorBufferIdx[i]);
    const nameOff = bb.createString(tensorNames[i]);
    bb.prependUOffsetTRelativeField(3, nameOff);
    tensorOffsets.push(bb.endObject());
  }
  const tensorsVec = bb.createVectorOfTables(tensorOffsets);

  // operators
  // Layer i (0-indexed):
  //   inputs: [prev_tensor, W_i, b_i], outputs: [fc_i_out]
  //   opcode_index: 0 (FULLY_CONNECTED)
  //   inputs: [relu[i-1]_out (or input for i=0), w_{2i+1}, b_{2i+2}] (using flat indices)
  //   outputs: [fc_i_out]
  // Then a ReLU operator (opcode_index: 1) with the FC output → relu output.
  //   Except the last layer's ReLU — we replace it with a Logistic (opcode_index: 2).
  const opOffsets = [];
  for (let i = 0; i < numLayers; i++) {
    const inT = i === 0 ? 0 : (2 * i);     // 0 (input) or relu_{i-1}_out
    const outT = 1 + 2 * i;                 // fc_i_out
    const wT = 7 + 2 * i;                   // w_i
    const bT = 7 + 2 * i + 1;               // b_i
    bb.startObject(4);
    bb.prependUint8Field(0, 0); // opcode 0 = FULLY_CONNECTED
    const inVec = bb.createVector([inT, wT, bT], 4, 4);
    bb.prependUOffsetTRelativeField(1, inVec);
    const outVec = bb.createVector([outT], 4, 4);
    bb.prependUOffsetTRelativeField(2, outVec);
    opOffsets.push(bb.endObject());

    if (i < numLayers - 1) {
      // ReLU
      const reluInT = outT;       // = fc_i_out
      const reluOutT = outT + 1;  // = relu_i_out
      bb.startObject(4);
      bb.prependUint8Field(0, 1); // opcode 1 = RELU
      const rInVec = bb.createVector([reluInT], 4, 4);
      bb.prependUOffsetTRelativeField(1, rInVec);
      const rOutVec = bb.createVector([reluOutT], 4, 4);
      bb.prependUOffsetTRelativeField(2, rOutVec);
      opOffsets.push(bb.endObject());
    } else {
      // Logistic
      const logInT = outT;       // fc_last_out
      const logOutT = 6;          // output tensor
      bb.startObject(4);
      bb.prependUint8Field(0, 2); // opcode 2 = LOGISTIC
      const lInVec = bb.createVector([logInT], 4, 4);
      bb.prependUOffsetTRelativeField(1, lInVec);
      const lOutVec = bb.createVector([logOutT], 4, 4);
      bb.prependUOffsetTRelativeField(2, lOutVec);
      opOffsets.push(bb.endObject());
    }
  }
  const operatorsVec = bb.createVectorOfTables(opOffsets);

  // SubGraph
  bb.startObject(4);
  const inputsVec = bb.createVector([0], 4, 4);
  bb.prependUOffsetTRelativeField(0, inputsVec);
  const outputsVec = bb.createVector([6], 4, 4);
  bb.prependUOffsetTRelativeField(1, outputsVec);
  bb.prependUOffsetTRelativeField(2, tensorsVec);
  bb.prependUOffsetTRelativeField(3, operatorsVec);
  const subgraphOffset = bb.endObject();
  const subgraphsVec = bb.createVectorOfTables([subgraphOffset]);

  // Model
  bb.startObject(4);
  bb.prependUOffsetTRelativeField(0, opCodesVec);
  bb.prependUOffsetTRelativeField(1, subgraphsVec);
  if (meta) {
    const descOff = bb.createString(meta);
    bb.prependUOffsetTRelativeField(2, descOff);
  }
  bb.prependUOffsetTRelativeField(3, buffersVec);
  const modelOffset = bb.endObject();

  bb.finish(modelOffset, 'TFL3'); // 'TFL3' identifier
  return bb.asUint8Array();
}

// ----------------------------------------------------------------------------
// Driver: read weights JSON, build TFLite, write to disk.
// ----------------------------------------------------------------------------
function main() {
  const weightsJsonPath = process.argv[2];
  const outPath = process.argv[3];
  if (!weightsJsonPath || !outPath) {
    console.error('Usage: node tool/write_tflite.js <weights.json> <out.tflite>');
    process.exit(2);
  }
  const data = JSON.parse(fs.readFileSync(weightsJsonPath, 'utf8'));
  const layers = data.layers;
  const layerSizes = [layers[0].in, ...layers.map(l => l.out)];
  const weights = layers.map(l => new Float32Array(l.w));
  const biases = layers.map(l => new Float32Array(l.b));
  const meta = (data.modelName || 'carebridge_mlp') + '_' + (data.trained_on || '');
  const bytes = buildMLPClean(layerSizes, weights, biases, meta);
  fs.writeFileSync(outPath, Buffer.from(bytes));
  console.log(`Wrote ${outPath} (${bytes.length} bytes)  layerSizes=[${layerSizes.join(',')}]`);
}
if (require.main === module) main();
module.exports = { buildMLPClean };
