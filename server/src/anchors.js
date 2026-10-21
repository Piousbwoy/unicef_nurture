// Chain anchors: does the trail the district holds still agree with what each
// device admitted at the time?
//
// ### What this adds to the hash chain
//
// The chain is verified on the handset, with a key that never leaves it. That is
// what makes it tamper-evident locally, and it is also the limit: nobody else can
// recompute those hashes, so on the server the trail was a pile of rows the device
// happened to send. A device that rewrote its own history consistently — entirely
// possible, since it holds the key — would produce a server copy that was just as
// consistent and quietly shorter.
//
// An anchor is the device committing, every tenth entry, to the head hash and the
// number of entries at that point, sent out of band and stored append-only. History
// that is truncated afterwards now contradicts a statement the device already made
// and cannot withdraw.
//
// ### What it does not claim
//
// This is the sentence to say out loud rather than let people assume: an anchor
// proves nothing was *removed* after it was sent. It does not prove the anchored
// entries were ever true. A device determined to falsify from its very first entry
// can anchor a fiction, because the same key that signs honest entries signs those.
// Closing that needs a commitment the device cannot make alone — a district signing
// key or a published timestamp — which is a PKI decision for the health service,
// not something to invent in a sync server.
//
// ### Checks performed
//
// For each anchor, in the trail the server holds for that device:
//   entry_missing     the anchored position is no longer there at all
//   hash_mismatch     the row at that position is not the row that was anchored
//   history_shortened fewer rows exist up to that position than were declared
//
// `history_shortened` compares against rows *up to the anchor's seq*, not the
// device's total: a device that legitimately keeps working will always grow past
// its last anchor, and comparing to the total would report that as tampering.
'use strict';

const { pool } = require('./db');

async function auditAnchors(client = pool) {
  const [anchors] = await client.query(
    'SELECT device_id, seq, entry_hash, entry_count, anchored_at ' +
      'FROM ledger_anchors ORDER BY device_id, seq'
  );
  if (anchors.length === 0) {
    return { anchors: 0, devices: 0, problems: [] };
  }

  const [rows] = await client.query(
    'SELECT device_id, seq, entry_hash FROM access_ledger'
  );

  const byDevice = new Map();
  for (const r of rows) {
    const device = r.device_id || '(no device recorded)';
    if (!byDevice.has(device)) byDevice.set(device, []);
    byDevice.get(device).push(r);
  }
  for (const list of byDevice.values()) {
    list.sort((a, b) => Number(a.seq) - Number(b.seq));
  }

  const problems = [];
  for (const a of anchors) {
    const device = a.device_id || '(no device recorded)';
    const seq = Number(a.seq);
    const list = byDevice.get(device) || [];
    const entry = list.find((r) => Number(r.seq) === seq);

    if (!entry) {
      problems.push({
        device_id: device,
        seq,
        kind: 'entry_missing',
        detail:
          `anchor at seq ${seq} declares ${a.entry_count} entr(ies); that ` +
          'position is no longer in the trail the district holds',
      });
      continue;
    }
    if (entry.entry_hash !== a.entry_hash) {
      problems.push({
        device_id: device,
        seq,
        kind: 'hash_mismatch',
        detail:
          'the row at the anchored position does not carry the hash that was ' +
          'committed when it was sent',
      });
    }
    const upTo = list.filter((r) => Number(r.seq) <= seq).length;
    if (Number(a.entry_count) > upTo) {
      problems.push({
        device_id: device,
        seq,
        kind: 'history_shortened',
        detail:
          `anchor at seq ${seq} declared ${a.entry_count} entries; only ${upTo} ` +
          'remain at or before that position',
      });
    }
  }

  return { anchors: anchors.length, devices: byDevice.size, problems };
}

module.exports = { auditAnchors };
