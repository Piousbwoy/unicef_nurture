/// Aura Medica — Pure White & Royal Sapphire. The FHW luxury palette.
///
/// Sapphire blues carry the chrome and brand voice; porcelain whites carry the
/// canvas. The IMCI red / amber / green stay clinical-only: this file aliases
/// them back to [AppColors.triageRed/Amber/Green] instead of defining new
/// values, so there is exactly one clinical colour source in the app.
library;

import 'package:flutter/material.dart';

import 'app_theme.dart';

abstract final class FhwLuxePalette {
  // ── Luxurious blue hierarchy ───────────────────────────────────────
  static const Color sapphireMidnight = Color(0xFF081938);
  static const Color sapphireDeep = Color(0xFF0D285F);
  static const Color sapphireRoyal = Color(0xFF1B56DB);
  static const Color sapphireElectric = Color(0xFF2970FF);
  static const Color sapphireIce = Color(0xFFE8F1FF);

  // ── Pure white & porcelain surfaces ────────────────────────────────
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color porcelainCanvas = Color(0xFFF8FAFC);
  static const Color pearlSurface = Color(0xFFF1F5F9);
  static const Color cardSurface = Color(0xFFFFFFFF);

  // ── Typography & ink ───────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF0A192F);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textFaint = Color(0xFF94A3B8);

  // ── Specular & glass catch-lights ──────────────────────────────────
  static const Color glassBorderLight = Color(0x66FFFFFF);
  static const Color glassBorderDark = Color(0x0F0D285F);
  static const Color hairLine = Color(0xFFE2E8F0);

  // ── Gradients ──────────────────────────────────────────────────────
  static const LinearGradient sapphireHeroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF06142E), Color(0xFF0D2A66), Color(0xFF1A4CB0)],
  );
  static const LinearGradient sapphireCardGlow = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B56DB), Color(0xFF2E7BFF)],
  );

  // ── Clinical colours — aliases, never new values ───────────────────
  /// Triage red, amber and green are clinical verdict colours. They are
  /// exposed here only as aliases so luxe surfaces never invent a second
  /// red/amber/green. Faceted clinical badges may add a soft halo at low
  /// alpha; the hue itself stays exactly the IMCI one.
  static const Color clinicalRed = AppColors.triageRed;
  static const Color clinicalAmber = AppColors.triageAmber;
  static const Color clinicalGreen = AppColors.triageGreen;

  /// The ambient halo behind a clinical jewel badge (12% alpha).
  static const Color clinicalRedHalo = Color(0x1FD32F2F);
  static const Color clinicalAmberHalo = Color(0x1FED9B00);
  static const Color clinicalGreenHalo = Color(0x1F2E7D4F);

  /// The sync pulse. It reuses the triage green the way the repo already
  /// does for non-clinical "healthy" dots (e.g. the model-usability dot):
  /// a status signal on infrastructure, never a verdict on a patient.
  static const Color emeraldPulse = AppColors.triageGreen;
}
