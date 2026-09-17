/// Vitals Station — measurement specs.
///
/// **Display guidance only.** The bands here are the same cut-offs the
/// protocol forms already print beside their fields (IMCI fast-breathing by
/// age, fever / hypothermia, SpO₂, MUAC, haemoglobin, blood pressure, foetal
/// heart rate). They colour the live readout so a nurse sees the zone as the
/// number lands. They do **not** classify, refer or treat: the IMCI / ANC /
/// PNC engines remain the single source of truth and are unchanged. Nothing
/// on this screen can produce a verdict.
///
/// Colour rule carried over from the rest of the app: triage red / amber /
/// green appear only on the marker and the text, never as decoration.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/engines/measurement_safety_engine.dart';
import '../../../domain/enums.dart';

/// How a value sits against its band.
enum VitalTone {
  normal(AppColors.triageGreen, AppColors.triageGreenBg),
  watch(AppColors.triageAmber, AppColors.triageAmberBg),
  danger(AppColors.triageRed, AppColors.triageRedBg);

  const VitalTone(this.fg, this.bg);

  final Color fg;
  final Color bg;
}

/// A half-open range `[min, max)` with the tone it earns and a one-line note.
/// `null` bounds are open.
class VitalBand {
  const VitalBand({this.min, this.max, required this.tone, required this.note});

  final double? min;
  final double? max;
  final VitalTone tone;
  final String note;

  bool contains(double v) =>
      (min == null || v >= min!) && (max == null || v < max!);
}

/// What the bands need to know about the patient. All optional; a missing
/// anchor simply yields plausibility-only feedback.
class VitalContext {
  const VitalContext({
    required this.clientType,
    this.ageDays,
    this.ageMonths,
    this.gestationWeeks,
  });

  final ClientType clientType;
  final int? ageDays;
  final int? ageMonths;
  final int? gestationWeeks;
}

enum KeypadMode { integer, decimal }

/// How a vital is captured on the station.
enum CaptureMode {
  /// Custom clinical keypad.
  keypad,

  /// Tap pad with a 60-second ring; also exposes the keypad as fallback.
  breathCounter,
}

/// One vital on the station.
class VitalSpec {
  const VitalSpec({
    required this.key,
    required this.label,
    required this.unit,
    required this.decimals,
    required this.keypad,
    required this.why,
    required this.icon,
    required this.gaugeMin,
    required this.gaugeMax,
    this.plausible,
    this.capture = CaptureMode.keypad,
    this.showsMuacGauge = false,
    this.pair,
    List<VitalBand> Function(VitalContext ctx)? bands,
  }) : _bands = bands;

  /// Key in the assessment `inputs` map and the form controller it seeds.
  final String key;
  final String label;
  final String unit;
  final int decimals;
  final KeypadMode keypad;

  /// One line under the label saying why the nurse is taking this.
  final String why;
  final IconData icon;

  /// Visible range of the band gauge.
  final double gaugeMin;
  final double gaugeMax;

  /// Plausibility range from [MeasurementSafetyEngine]; used for the
  /// out-of-range hint and the maximum digits accepted.
  final MeasurementKind? plausible;

  final CaptureMode capture;

  /// Embed the existing semicircle MUAC gauge (mm is converted to cm).
  final bool showsMuacGauge;

  /// A second reading captured on the same card (diastolic under systolic).
  final VitalSpec? pair;

  final List<VitalBand> Function(VitalContext ctx)? _bands;

  List<VitalBand> bands(VitalContext ctx) =>
      _bands?.call(ctx) ?? const <VitalBand>[];

  /// The band a value lands in, or null when the spec has no bands or the
  /// value falls between them.
  VitalBand? bandFor(double value, VitalContext ctx) {
    for (final b in bands(ctx)) {
      if (b.contains(value)) return b;
    }
    return null;
  }

  /// True when the value is outside the engine's plausible range.
  bool implausible(double value) {
    final p = plausible;
    return p != null && (value < p.min || value > p.max);
  }

  /// Formats a value for the readout ("4.2", "38").
  String format(num value) => decimals == 0
      ? value.round().toString()
      : value.toDouble().toStringAsFixed(decimals);
}

// ─── Band tables ──────────────────────────────────────────────────────────

/// IMCI fast breathing: ≥60 under 2 months, ≥50 at 2–11 months, ≥40 at
/// 12–59 months. Mirrors the cut-off text on the form.
List<VitalBand> respiratoryBands(VitalContext ctx) {
  final months = ctx.ageMonths ?? ((ctx.ageDays ?? 0) / 30.4375).floor();
  final cutoff = months < 2 ? 60.0 : (months < 12 ? 50.0 : 40.0);
  final band = months < 2
      ? 'under 2 months'
      : (months < 12 ? '2–11 months' : '12–59 months');
  return [
    VitalBand(
      max: 20,
      tone: VitalTone.watch,
      note: 'Very slow breathing — check the child is not drowsy.',
    ),
    VitalBand(
      min: 20,
      max: cutoff,
      tone: VitalTone.normal,
      note:
          'Below the IMCI fast-breathing line (${cutoff.round()}/min for $band).',
    ),
    VitalBand(
      min: cutoff,
      tone: VitalTone.danger,
      note: 'Fast breathing for $band (IMCI ≥${cutoff.round()}/min).',
    ),
  ];
}

List<VitalBand> temperatureBands(VitalContext ctx) => const [
  VitalBand(
    max: 35.5,
    tone: VitalTone.danger,
    note: 'Hypothermia (<35.5 °C). Warm the child, re-check.',
  ),
  VitalBand(
    min: 35.5,
    max: 37.5,
    tone: VitalTone.normal,
    note: 'Normal range (35.5–37.4 °C).',
  ),
  VitalBand(
    min: 37.5,
    max: 39.0,
    tone: VitalTone.watch,
    note: 'Fever (≥37.5 °C).',
  ),
  VitalBand(min: 39.0, tone: VitalTone.danger, note: 'High fever (≥39 °C).'),
];

List<VitalBand> spo2Bands(VitalContext ctx) => const [
  VitalBand(
    max: 90,
    tone: VitalTone.danger,
    note: 'Below 90% — the form treats this as a referral sign.',
  ),
  VitalBand(
    min: 90,
    max: 94,
    tone: VitalTone.watch,
    note: 'Borderline (90–93%). Warm the hand and re-check.',
  ),
  VitalBand(min: 94, tone: VitalTone.normal, note: 'Normal (≥94%).'),
];

/// WHO / GHS tape in millimetres, 6–59 months only.
List<VitalBand> muacMmBands(VitalContext ctx) => const [
  VitalBand(
    max: 115,
    tone: VitalTone.danger,
    note: 'Red zone <115 mm — severe acute malnutrition.',
  ),
  VitalBand(
    min: 115,
    max: 125,
    tone: VitalTone.watch,
    note: 'Yellow zone 115–124 mm — moderate acute malnutrition.',
  ),
  VitalBand(min: 125, tone: VitalTone.normal, note: 'Green zone ≥125 mm.'),
];

/// Pregnancy MUAC in centimetres (undernutrition <23 cm on the ANC form).
List<VitalBand> muacCmMaternalBands(VitalContext ctx) => const [
  VitalBand(
    max: 23,
    tone: VitalTone.watch,
    note: 'Undernutrition in pregnancy (<23 cm).',
  ),
  VitalBand(min: 23, tone: VitalTone.normal, note: 'Adequate (≥23 cm).'),
];

List<VitalBand> haemoglobinBands(VitalContext ctx) => const [
  VitalBand(max: 7, tone: VitalTone.danger, note: 'Severe anaemia (<7 g/dL).'),
  VitalBand(
    min: 7,
    max: 11,
    tone: VitalTone.watch,
    note: 'Anaemia (<11 g/dL).',
  ),
  VitalBand(min: 11, tone: VitalTone.normal, note: 'Not anaemic (≥11 g/dL).'),
];

List<VitalBand> systolicBands(VitalContext ctx) => const [
  VitalBand(
    max: 90,
    tone: VitalTone.watch,
    note: 'Low systolic (<90). Re-take after rest.',
  ),
  VitalBand(
    min: 90,
    max: 140,
    tone: VitalTone.normal,
    note: 'Normal (90–139).',
  ),
  VitalBand(
    min: 140,
    max: 160,
    tone: VitalTone.watch,
    note: 'High (≥140). Check protein in urine.',
  ),
  VitalBand(min: 160, tone: VitalTone.danger, note: 'Severe (≥160).'),
];

List<VitalBand> diastolicBands(VitalContext ctx) => const [
  VitalBand(max: 90, tone: VitalTone.normal, note: 'Normal (<90).'),
  VitalBand(
    min: 90,
    max: 110,
    tone: VitalTone.watch,
    note: 'High (≥90). Check protein in urine.',
  ),
  VitalBand(min: 110, tone: VitalTone.danger, note: 'Severe (≥110).'),
];

List<VitalBand> foetalHeartBands(VitalContext ctx) => const [
  VitalBand(
    max: 110,
    tone: VitalTone.watch,
    note: 'Below 110 bpm — listen again for a full minute.',
  ),
  VitalBand(
    min: 110,
    max: 161,
    tone: VitalTone.normal,
    note: 'Normal (110–160).',
  ),
  VitalBand(
    min: 161,
    tone: VitalTone.watch,
    note: 'Above 160 bpm — listen again for a full minute.',
  ),
];

/// Fundal height should roughly match the gestational week from ~20 weeks.
List<VitalBand> fundalBands(VitalContext ctx) {
  final w = ctx.gestationWeeks;
  if (w == null || w < 20) {
    return const [
      VitalBand(
        tone: VitalTone.normal,
        note: 'Compared against the gestational week from ~20 weeks.',
      ),
    ];
  }
  return [
    VitalBand(
      max: w - 3.0,
      tone: VitalTone.watch,
      note: 'More than 3 cm below the week ($w wks) — check dates and growth.',
    ),
    VitalBand(
      min: w - 3.0,
      max: w + 4.0,
      tone: VitalTone.normal,
      note: 'Matches the gestational week ($w wks ±3 cm).',
    ),
    VitalBand(
      min: w + 4.0,
      tone: VitalTone.watch,
      note:
          'More than 3 cm above the week ($w wks) — check dates, twins, fluid.',
    ),
  ];
}
