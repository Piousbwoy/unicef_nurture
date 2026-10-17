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

  /// The recessed seat cut into a sapphire surface — progress tracks and
  /// clinical jewel wells — so a recess reads as depth carved into the blue,
  /// never a new hue. Held below [commandNavy] in luminance, or a well stops
  /// reading as a cut and becomes a bump.
  static const Color sapphireGroove = Color(0xFF071838);

  /// Midnight sapphire: the deep brand surface for chrome and ledgers. Flat —
  /// no gradient, no sheen — but carrying real chroma, so the header band and
  /// the register read as dyed depth rather than charcoal next to the lacquer
  /// panels. A navy without blue in it turns grey the moment a saturated blue
  /// is placed beside it.
  static const Color commandNavy = Color(0xFF0B2354);

  /// Royal lacquer: the data-panel fill. One hue, two stops — a lit corner and
  /// a shadow corner — so a panel reads as a material with depth the way
  /// lacquered wood does. This is deliberately *not* the old [sapphireCardGlow]:
  /// no second hue arriving at the edge, no bloom, no sheen overlay. Depth of
  /// substance, not atmosphere.
  static const LinearGradient sapphireLacquer = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E4D9F), Color(0xFF0E2E66)],
  );

  /// The polished edge a lacquered panel catches the light on: a single
  /// hairline across the top, brighter where the fill is lit. Structural, not
  /// a glow — it is one pixel, and it is why the surface reads made rather
  /// than printed.
  static const LinearGradient lacquerEdge = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0x40FFFFFF), Color(0x0AFFFFFF)],
  );

  // ── Pure white & porcelain surfaces ────────────────────────────────
  static const Color pureWhite = Color(0xFFFFFFFF);

  /// The FHW desk canvas — a clean, cool white. The desk reads as a sheet of
  /// bright paper: the royal-lacquer panels carry the colour and lift off the
  /// white on their own blue bloom, while the porcelain working cards separate
  /// with a hairline edge and a soft drop rather than a tone gap.
  static const Color porcelainCanvas = Color(0xFFFFFFFF);
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

  // ── Ink & rules on a lacquer panel ─────────────────────────────────
  /// The body ink on a royal-lacquer panel. It is the pale end of the pearl
  /// sheen rather than a fourth blue: the light that runs across a white card
  /// and the ink on a blue panel are the *same* cold light, so the desk cannot
  /// split into two products. Plain white is too bright to read as ink and
  /// vanishes at 13px next to a lit title.
  static const Color lacquerInk = Color(0xFFDCE9FF);

  /// The header rule inside a lacquer panel — a cut in the same material, so
  /// white carrying a little blue rather than a grey sticker on the blue.
  static const Color lacquerRule = Color(0x24FFFFFF);

  /// The quieter rule between two rows of a panel's register.
  static const Color lacquerRuleQuiet = Color(0x14FFFFFF);

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
