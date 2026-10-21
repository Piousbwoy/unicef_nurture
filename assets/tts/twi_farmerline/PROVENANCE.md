# Farmerline Twi — auditioned, not shipped

`FarmerlineML/main_twi_TTS`, **CC-BY-4.0** — the only Twi voice in this repo with a
licence that lets us ship it commercially. Exported to the app's `piper-v1`
contract and verified speaking through the app's own engine.

Measured on this machine, 2 CPU threads, same Dart engine as every other voice:

| voice | size | synth of 1.78 s audio | RTF |
| --- | --- | --- | --- |
| `twi_piper` (Stable-Twi twi-6, fp32) | 80 MB | ~0.5 s | ~0.3 |
| `twi_farmerline` (int8) | 38 MB | **4.6 s** | **2.6** |

So it is 38 MB smaller and eight times slower. On a caregiver's phone that is a
two-to-four second stall before every Twi answer begins, which is a worse
outcome than the licence problem it solves. It stays exported and tested as the
A/B candidate, and it becomes the right choice if a **fp32** export is produced
(estimated ~150 MB, RTF near 0.9) and pack delivery through
`VOICE_PACK_BASE_URL` is accepted — that trades bundle size for both licence
cleanliness and speed, and it is the only version worth switching to.

Audition clips: `C:/Users/Alhaji_stunner/nlp_upgrade/packs/twi_farmerline/`.
