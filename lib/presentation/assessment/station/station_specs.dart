/// The ordered list of vitals the station walks through for each protocol.
///
/// Order follows how a clinic room actually runs: the things that need a
/// calm child first (breathing), then the thermometer, then the scale and
/// tape, then the devices that may not be present (oximeter, Hb meter).
/// Display guidance only — see `vital_spec.dart`.
library;

import 'package:flutter/material.dart';

import '../../../domain/engines/measurement_safety_engine.dart';
import 'vital_spec.dart';

const _respiratoryRate = VitalSpec(
  key: 'respiratory_rate',
  label: 'Breathing rate',
  unit: '/min',
  decimals: 0,
  keypad: KeypadMode.integer,
  capture: CaptureMode.breathCounter,
  why:
      'Count for a full 60 seconds while calm. Fast breathing is the IMCI '
      'pneumonia sign.',
  icon: Icons.air_rounded,
  gaugeMin: 10,
  gaugeMax: 90,
  plausible: MeasurementKind.respiratoryRate,
  bands: respiratoryBands,
);

const _temperature = VitalSpec(
  key: 'temperature_celsius',
  label: 'Temperature',
  unit: '°C',
  decimals: 1,
  keypad: KeypadMode.decimal,
  why: 'Fever ≥37.5 · hypothermia <35.5.',
  icon: Icons.thermostat_rounded,
  gaugeMin: 34,
  gaugeMax: 41,
  plausible: MeasurementKind.temperatureC,
  bands: temperatureBands,
);

const _weightChild = VitalSpec(
  key: 'weight_kg',
  label: 'Weight',
  unit: 'kg',
  decimals: 1,
  keypad: KeypadMode.decimal,
  why: 'Saved to the growth series — the slope matters more than the point.',
  icon: Icons.monitor_weight_outlined,
  gaugeMin: 1,
  gaugeMax: 30,
  plausible: MeasurementKind.weightKg,
);

const _height = VitalSpec(
  key: 'height_cm',
  label: 'Length / height',
  unit: 'cm',
  decimals: 1,
  keypad: KeypadMode.decimal,
  why:
      'Lying down under 2 years, standing after. Needed for weight-for-height.',
  icon: Icons.height_rounded,
  gaugeMin: 40,
  gaugeMax: 130,
  plausible: MeasurementKind.heightCm,
);

const _muacMm = VitalSpec(
  key: 'muac_mm',
  label: 'MUAC',
  unit: 'mm',
  decimals: 0,
  keypad: KeypadMode.integer,
  why: 'Read straight off the GHS tape in millimetres, mid-upper left arm.',
  icon: Icons.straighten_outlined,
  gaugeMin: 90,
  gaugeMax: 170,
  showsMuacGauge: true,
  bands: muacMmBands,
);

const _spo2 = VitalSpec(
  key: 'oxygen_saturation',
  label: 'Oxygen saturation',
  unit: '%',
  decimals: 0,
  keypad: KeypadMode.integer,
  why:
      'Warm the hand, keep the probe out of bright light, wait for a steady '
      'trace.',
  icon: Icons.bloodtype_outlined,
  gaugeMin: 80,
  gaugeMax: 100,
  plausible: MeasurementKind.oxygenSaturation,
  bands: spo2Bands,
);

const _haemoglobin = VitalSpec(
  key: 'haemoglobin',
  label: 'Haemoglobin',
  unit: 'g/dL',
  decimals: 1,
  keypad: KeypadMode.decimal,
  why: 'Anaemia <11 · severe <7. Check the meter is in g/dL, not g/L.',
  icon: Icons.water_drop_outlined,
  gaugeMin: 4,
  gaugeMax: 16,
  plausible: MeasurementKind.haemoglobin,
  bands: haemoglobinBands,
);

/// Child protocols. The young-infant chart has no MUAC and no height; MUAC
/// applies from 6 months.
List<VitalSpec> childStationVitals({
  required bool isYoungInfant,
  required int? ageMonths,
}) {
  final muacApplies = !isYoungInfant && (ageMonths ?? 0) >= 6;
  return [
    _respiratoryRate,
    _temperature,
    _weightChild,
    if (!isYoungInfant) _height,
    if (muacApplies) _muacMm,
    _spo2,
    _haemoglobin,
  ];
}

const _diastolic = VitalSpec(
  key: 'diastolic',
  label: 'Diastolic',
  unit: 'mmHg',
  decimals: 0,
  keypad: KeypadMode.integer,
  why: 'High ≥90 · severe ≥110.',
  icon: Icons.favorite_border_rounded,
  gaugeMin: 40,
  gaugeMax: 130,
  plausible: MeasurementKind.diastolicBp,
  bands: diastolicBands,
);

const _bloodPressure = VitalSpec(
  key: 'systolic',
  label: 'Blood pressure',
  unit: 'mmHg',
  decimals: 0,
  keypad: KeypadMode.integer,
  why: 'Seated, after five minutes of rest. High ≥140/90 · severe ≥160/110.',
  icon: Icons.favorite_rounded,
  gaugeMin: 70,
  gaugeMax: 190,
  plausible: MeasurementKind.systolicBp,
  bands: systolicBands,
  pair: _diastolic,
);

const _muacCm = VitalSpec(
  key: 'muac_cm',
  label: 'MUAC',
  unit: 'cm',
  decimals: 1,
  keypad: KeypadMode.decimal,
  why: 'Undernutrition in pregnancy <23 cm.',
  icon: Icons.straighten_outlined,
  gaugeMin: 18,
  gaugeMax: 34,
  plausible: MeasurementKind.muacCm,
  bands: muacCmMaternalBands,
);

const _weightMaternal = VitalSpec(
  key: 'weight_kg',
  label: 'Weight',
  unit: 'kg',
  decimals: 1,
  keypad: KeypadMode.decimal,
  why: 'Gain over 1 kg in a week with high BP is a pre-eclampsia flag.',
  icon: Icons.monitor_weight_outlined,
  gaugeMin: 35,
  gaugeMax: 120,
  plausible: MeasurementKind.weightKg,
);

const _fundal = VitalSpec(
  key: 'fundal_height_cm',
  label: 'Fundal height',
  unit: 'cm',
  decimals: 0,
  keypad: KeypadMode.integer,
  why: 'Should roughly match the week from ~20 weeks.',
  icon: Icons.pregnant_woman_rounded,
  gaugeMin: 10,
  gaugeMax: 45,
  bands: fundalBands,
);

const _fhr = VitalSpec(
  key: 'foetal_heart_rate',
  label: 'Foetal heart rate',
  unit: 'bpm',
  decimals: 0,
  keypad: KeypadMode.integer,
  why: 'Listen for a full minute. Normal 110–160.',
  icon: Icons.child_care_rounded,
  gaugeMin: 80,
  gaugeMax: 200,
  plausible: MeasurementKind.heartRate,
  bands: foetalHeartBands,
);

/// Maternal protocols. Fundal height and foetal heart only while pregnant.
List<VitalSpec> maternalStationVitals({required bool isPregnant}) => [
  _bloodPressure,
  _haemoglobin,
  _muacCm,
  _weightMaternal,
  if (isPregnant) _fundal,
  if (isPregnant) _fhr,
];
