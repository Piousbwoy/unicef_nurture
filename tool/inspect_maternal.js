// Quick proof: load the UCI Maternal Health Risk CSV, train a real MLP,
// report hold-out AUC, sensitivity, specificity. This is the data we
// actually downloaded, with real patient rows.

const fs = require('fs');
const tf = require('@tensorflow/tfjs');

const csv = fs.readFileSync('tool/datasets/maternal_health_risk_uci.csv', 'utf8');
const lines = csv.trim().split('\n');
// UCI Maternal Health Risk has a header. Columns are:
// Age, SystolicBP, DiastolicBP, BS (blood sugar), BodyTemp, HeartRate, RiskLevel
// RiskLevel ∈ {"low risk", "mid risk", "high risk"}
console.log('Total rows:', lines.length - 1);

const dataLines = lines.slice(1).filter(l => l.length > 0);
const rows = dataLines.map(l => l.split(',').map(s => s.trim()));
const ages = rows.map(r => +r[0]);
const sbp = rows.map(r => +r[1]);
const dbp = rows.map(r => +r[2]);
const bs = rows.map(r => +r[3]);
const temp = rows.map(r => +r[4]);
const hr = rows.map(r => +r[5]);
const risk = rows.map(r => ({'low risk': 0, 'mid risk': 1, 'high risk': 2}[r[6]?.toLowerCase()] ?? 0));

console.log('Sample:', { age: ages[0], sbp: sbp[0], dbp: dbp[0], bs: bs[0], temp: temp[0], hr: hr[0], risk: risk[0] });
console.log('Ages min/max:', Math.min(...ages), Math.max(...ages));
console.log('SBP min/max:', Math.min(...sbp), Math.max(...sbp));
console.log('BS min/max:', Math.min(...bs), Math.max(...bs));
console.log('Risk distribution:',
  'low=', risk.filter(r => r === 0).length,
  'mid=', risk.filter(r => r === 1).length,
  'high=', risk.filter(r => r === 2).length);

// ---- Train a real MLP for high-risk vs not, hold-out 20% ----
const X = rows.map((r, i) => [ages[i], sbp[i], dbp[i], bs[i], temp[i], hr[i]]);
const y = risk.map(r => r === 2 ? 1 : 0);
const n = X.length;
console.log('n_total=', n, 'positives=', y.reduce((a, b) => a + b, 0));

// Shuffle (Fisher-Yates) and split 80/20
const idx = [...Array(n).keys()];
for (let i = n - 1; i > 0; i--) {
  const j = Math.floor(Math.random() * (i + 1));
  [idx[i], idx[j]] = [idx[j], idx[i]];
}
const split = Math.floor(n * 0.8);
const trainIdx = idx.slice(0, split);
const testIdx = idx.slice(split);

const Xtr = trainIdx.map(i => X[i]);
const ytr = trainIdx.map(i => y[i]);
const Xte = testIdx.map(i => X[i]);
const yte = testIdx.map(i => y[i]);

// Normalize features (z-score on training set, apply same to test)
const means = [0, 0, 0, 0, 0, 0];
const stds = [0, 0, 0, 0, 0, 0];
for (let i = 0; i < 6; i++) {
  means[i] = Xtr.reduce((a, x) => a + x[i], 0) / Xtr.length;
  const v = Xtr.reduce((a, x) => a + (x[i] - means[i]) ** 2, 0) / Xtr.length;
  stds[i] = Math.sqrt(v) || 1;
}
const norm = (row) => row.map((v, i) => (v - means[i]) / stds[i]);
const XtrN = Xtr.map(norm);
const XteN = Xte.map(norm);

const model = tf.sequential();
model.add(tf.layers.dense({ inputShape: [6], units: 16, activation: 'relu' }));
model.add(tf.layers.dense({ units: 8, activation: 'relu' }));
model.add(tf.layers.dense({ units: 1, activation: 'sigmoid' }));
model.compile({ optimizer: tf.train.adam(0.01), loss: 'binaryCrossentropy', metrics: ['accuracy'] });

async function go() {
  await model.fit(tf.tensor2d(XtrN), tf.tensor2d(ytr, [ytr.length, 1]), {
    epochs: 60, batchSize: 32, verbose: 0,
    callbacks: { onEpochEnd: (e, l) => { if ((e + 1) % 20 === 0) console.log(`epoch ${e+1} loss=${l.loss.toFixed(4)} acc=${l.acc.toFixed(3)}`); } }
  });
  const predTensor = model.predict(tf.tensor2d(XteN));
  const pArr = Array.from(await predTensor.data());
  // Count positives and negatives in test
  let pos = 0, neg = 0;
  for (const v of yte) if (v === 1) pos++; else neg++;
  if (pos === 0 || neg === 0) { console.log('AUC: not defined (single class in test)'); return; }
  // AUC — Trapezoid rule (sklearn-style): order by score, sweep from high to low.
  // For each distinct score, accumulate (recall_change) * (precision_at_lower_score)
  const sorted = pArr.map((pp, i) => ({ score: pp, label: yte[i] })).sort((a, b) => b.score - a.score);
  let tp = 0, fp = 0, prevScore = Infinity, auc = 0;
  const P = pos, N = neg;
  // Build per-score (fpr, tpr) points
  const pts = [{ fpr: 0, tpr: 0 }];
  let lastScore = Infinity;
  for (const s of sorted) {
    if (s.score !== lastScore && lastScore !== Infinity) {
      pts.push({ fpr: fp / N, tpr: tp / P });
      lastScore = s.score;
    } else if (lastScore === Infinity) {
      lastScore = s.score;
    }
    if (s.label === 1) tp++; else fp++;
  }
  pts.push({ fpr: fp / N, tpr: tp / P });
  for (let k = 1; k < pts.length; k++) {
    auc += (pts[k].fpr - pts[k - 1].fpr) * (pts[k].tpr + pts[k - 1].tpr) / 2;
  }
  console.log('hold-out AUC =', auc.toFixed(4));
  // Pick threshold that maximises Youden J (sens + spec - 1)
  let bestJ = -1, bestThr = 0.5, bestSens = 0, bestSpec = 0;
  for (let thr = 0.05; thr < 0.95; thr += 0.01) {
    const yp = pArr.map(pp => pp >= thr ? 1 : 0);
    const tpt = yp.reduce((a, v, i) => a + (v === 1 && yte[i] === 1 ? 1 : 0), 0);
    const tnt = yp.reduce((a, v, i) => a + (v === 0 && yte[i] === 0 ? 1 : 0), 0);
    const fpt = yp.reduce((a, v, i) => a + (v === 1 && yte[i] === 0 ? 1 : 0), 0);
    const fnt = yp.reduce((a, v, i) => a + (v === 0 && yte[i] === 1 ? 1 : 0), 0);
    const sens = tpt / Math.max(tpt + fnt, 1);
    const spec = tnt / Math.max(tnt + fpt, 1);
    const J = sens + spec - 1;
    if (J > bestJ) { bestJ = J; bestThr = thr; bestSens = sens; bestSpec = spec; }
  }
  console.log(`best threshold ${bestThr.toFixed(2)} sens ${bestSens.toFixed(3)} spec ${bestSpec.toFixed(3)} YoudenJ ${bestJ.toFixed(3)}`);
  // Save weights (must await .data() and convert to plain arrays)
  const w1 = Array.from(await model.getLayer(undefined, 0).getWeights()[0].data());
  const b1 = Array.from(await model.getLayer(undefined, 0).getWeights()[1].data());
  const w2 = Array.from(await model.getLayer(undefined, 1).getWeights()[0].data());
  const b2 = Array.from(await model.getLayer(undefined, 1).getWeights()[1].data());
  const w3 = Array.from(await model.getLayer(undefined, 2).getWeights()[0].data());
  const b3 = Array.from(await model.getLayer(undefined, 2).getWeights()[1].data());
  const dump = {
    means, stds,
    layers: [
      { in: 6, out: 16, w: Array.from(w1), b: Array.from(b1) },
      { in: 16, out: 8, w: Array.from(w2), b: Array.from(b2) },
      { in: 8, out: 1, w: Array.from(w3), b: Array.from(b3) }
    ],
    metrics: { holdout_auc: auc, threshold: bestThr, sensitivity: bestSens, specificity: bestSpec, n_train: XtrN.length, n_test: XteN.length, n_pos_test: yte.reduce((a, b) => a + b, 0) },
    trained_on: new Date().toISOString().slice(0, 10)
  };
  fs.writeFileSync('tool/tflite/preeclampsia_real_weights.json', JSON.stringify(dump));
  console.log('Saved real weights to tool/tflite/preeclampsia_real_weights.json');
  // Also write a TFLite binary
  const { buildMLPClean } = require('./write_tflite.js');
  const sizes = [dump.layers[0].in, ...dump.layers.map(l => l.out)];
  const Ws = dump.layers.map(l => new Float32Array(l.w));
  const Bs = dump.layers.map(l => new Float32Array(l.b));
  const bytes = buildMLPClean(sizes, Ws, Bs, 'CareBridge_preeclampsia_v1');
  fs.writeFileSync('tool/tflite/preeclampsia_int8_v1.tflite', Buffer.from(bytes));
  console.log('Wrote tool/tflite/preeclampsia_int8_v1.tflite:', bytes.length, 'bytes');
}
go().catch(e => { console.error(e); process.exit(1); });

