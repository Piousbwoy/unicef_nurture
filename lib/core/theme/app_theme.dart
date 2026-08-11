import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// CareBridge AI visual system — "Clinical Luxe".
///
/// White air, royal blue authority. The idiom is premium product design:
/// pure white surfaces, a single saturated royal-blue brand voice, bold
/// geometric headlines in **Sora**, warm humanist body text in **Manrope**,
/// soft blue-tinted shadows and generous radii. Every screen should feel like
/// a flagship banking app that happens to save children's lives.
///
/// One rule is load-bearing and must never be relaxed: **the IMCI triage
/// red / amber / green belong to clinical safety and nothing else.** They are
/// the colours a Ghanaian CHO already trusts from the IMCI chart booklet, so
/// they are kept exactly as trained and are never re-purposed for decoration.
/// The blue luxury palette applies to chrome, surfaces, brand and typography.
abstract final class AppColors {
  // ── White & blue neutrals ──────────────────────────────────────────
  /// Dominant background — pure, clean white.
  static const Color canvas = Color(0xFFFFFFFF);

  /// Raised surfaces — a breath of blue-grey so cards read on white.
  static const Color surface = Color(0xFFF6F9FE);

  /// Tinted hero surfaces (dashboard headers, image scrims).
  static const Color surfaceTint = Color(0xFFEAF1FD);

  /// Primary text — a deep navy ink, never pure black.
  static const Color ink = Color(0xFF0B1B33);
  static const Color inkMuted = Color(0xFF4A5B76);
  static const Color inkFaint = Color(0xFF8494AD);

  /// Borders — cool and quiet.
  static const Color line = Color(0xFFE3EAF5);
  static const Color lineStrong = Color(0xFFCBD8EC);

  // ── Brand — royal blue ─────────────────────────────────────────────
  static const Color primary = Color(0xFF1B56DB);
  static const Color primaryDark = Color(0xFF123FA8);
  static const Color primaryDeep = Color(0xFF0C2B73);
  static const Color primaryLight = Color(0xFFE8EFFD);
  static const Color primaryGlow = Color(0xFF4D82F3);

  /// Kept as an alias — older screens read `accent`.
  static const Color accent = primary;

  /// The signature brand gradient: deep royal into bright azure.
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFF1240C4), Color(0xFF3B76F6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF0C2B73), Color(0xFF1B56DB), Color(0xFF3B76F6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── IMCI triage bands — clinical safety, never decoration ─────────
  static const Color triageRed = Color(0xFFD32F2F);
  static const Color triageRedBg = Color(0xFFFDECEA);
  static const Color triageAmber = Color(0xFFED9B00);
  static const Color triageAmberBg = Color(0xFFFFF6E5);
  static const Color triageGreen = Color(0xFF2E7D4F);
  static const Color triageGreenBg = Color(0xFFE9F6EE);

  // ── Semantic ───────────────────────────────────────────────────────
  static const Color offline = Color(0xFF6B4FA8);
  static const Color offlineBg = Color(0xFFF1EDF8);
  static const Color info = Color(0xFF1B56DB);
}

/// Strict 8px baseline grid with generous premium radii.
abstract final class Gap {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;

  /// Minimum interactive height — thumb-first field design.
  static const double tapTarget = 54;

  /// Premium radii — soft, expensive, never bubble-shaped.
  static const double radius = 18;
  static const double radiusSm = 12;
  static const double radiusXs = 8;

  /// Hairline stroke weight.
  static const double hairline = 1;
}

/// Motion language: smooth, eased, deliberate.
abstract final class AppMotion {
  static const Duration duration = Duration(milliseconds: 450);
  static const Duration fast = Duration(milliseconds: 220);
  static const Curve curve = Curves.easeOutCubic;

  /// A fade + subtle upward-translate reveal, used on scroll/enter.
  static Widget reveal(
    Widget child, {
    Duration duration = AppMotion.duration,
    Curve curve = AppMotion.curve,
    double distance = 10,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: curve,
      builder: (context, t, _) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, distance * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Soft, diffuse, blue-tinted shadows — the signature of the premium finish.
abstract final class AppShadows {
  static const BoxShadow soft = BoxShadow(
    color: Color(0x14194DBF), // royal blue at ~8%
    blurRadius: 32,
    offset: Offset(0, 10),
  );
  static const BoxShadow card = BoxShadow(
    color: Color(0x0F1B56DB),
    blurRadius: 28,
    offset: Offset(0, 8),
  );
  static const BoxShadow glow = BoxShadow(
    color: Color(0x381B56DB),
    blurRadius: 24,
    offset: Offset(0, 8),
  );
}

/// The type system. **Sora** carries the voice — bold geometric headlines that
/// feel like a flagship product. **Manrope** carries the information — warm,
/// legible, confident body text.
abstract final class AppType {
  static TextStyle get display => GoogleFonts.sora(
    fontSize: 40,
    fontWeight: FontWeight.w800,
    height: 1.12,
    letterSpacing: -0.8,
    color: AppColors.ink,
  );

  static TextStyle get headline => GoogleFonts.sora(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.5,
    color: AppColors.ink,
  );

  static TextStyle get title => GoogleFonts.sora(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.2,
    color: AppColors.ink,
  );

  /// Uppercase micro-label. Callers are expected to uppercase the text.
  static TextStyle get eyebrow => GoogleFonts.manrope(
    fontSize: 11.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.4, // ~0.12em
    color: AppColors.inkMuted,
  );

  static TextStyle get bodyLarge => GoogleFonts.manrope(
    fontSize: 17,
    fontWeight: FontWeight.w500,
    height: 1.6,
    color: AppColors.ink,
  );

  static TextStyle get body => GoogleFonts.manrope(
    fontSize: 15.5,
    fontWeight: FontWeight.w500,
    height: 1.6,
    color: AppColors.ink,
  );

  static TextStyle get label => GoogleFonts.manrope(
    fontSize: 13.5,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  static TextStyle get caption => GoogleFonts.manrope(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    height: 1.5,
    color: AppColors.inkMuted,
  );
}

abstract final class AppTheme {
  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Color(0xFFFFFFFF),
      secondary: AppColors.primaryGlow,
      onSecondary: Color(0xFFFFFFFF),
      error: AppColors.triageRed,
      onError: Color(0xFFFFFFFF),
      surface: AppColors.canvas,
      onSurface: AppColors.ink,
      outline: AppColors.line,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.canvas,
      visualDensity: VisualDensity.standard,
    );

    // Manrope everywhere, then Sora for the display/headline/title voices.
    final manrope = GoogleFonts.manropeTextTheme(base.textTheme);
    final textTheme = manrope.copyWith(
      displayLarge: AppType.display,
      displayMedium: AppType.display.copyWith(fontSize: 34),
      displaySmall: AppType.display.copyWith(fontSize: 30),
      headlineLarge: AppType.headline,
      headlineMedium: AppType.headline.copyWith(fontSize: 24),
      headlineSmall: AppType.title,
      titleLarge: AppType.title,
      titleMedium: GoogleFonts.manrope(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      bodyLarge: AppType.bodyLarge,
      bodyMedium: AppType.body,
      labelLarge: AppType.label,
      bodySmall: AppType.caption,
    );

    return base.copyWith(
      textTheme: textTheme,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.canvas,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.canvas,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Gap.radius),
          side: const BorderSide(color: AppColors.line, width: Gap.hairline),
        ),
      ),
      // Primary CTA: the signature royal-blue gradient with a soft glow.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(Gap.tapTarget),
          backgroundColor: AppColors.primary,
          foregroundColor: const Color(0xFFFFFFFF),
          elevation: 0,
          textStyle: GoogleFonts.manrope(
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Gap.radiusSm),
          ),
        ).copyWith(
          overlayColor: const WidgetStatePropertyAll(Color(0x14FFFFFF)),
        ),
      ),
      // Secondary: a confident 1.5px royal outline.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(Gap.tapTarget),
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          textStyle: GoogleFonts.manrope(
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Gap.radiusSm),
          ),
        ),
      ),
      // Tertiary: ghost blue.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
          padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
        ),
      ),
      // Rounded filled inputs — soft blue-grey at rest, royal when focused.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Gap.md,
          vertical: Gap.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Gap.radiusSm),
          borderSide: const BorderSide(color: AppColors.line, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Gap.radiusSm),
          borderSide: const BorderSide(color: AppColors.line, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Gap.radiusSm),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Gap.radiusSm),
          borderSide: const BorderSide(color: AppColors.triageRed, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Gap.radiusSm),
          borderSide: const BorderSide(color: AppColors.triageRed, width: 1.6),
        ),
        labelStyle: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.inkMuted,
        ),
        hintStyle: GoogleFonts.manrope(
          fontSize: 14.5,
          fontWeight: FontWeight.w500,
          color: AppColors.inkFaint,
        ),
        prefixIconColor: AppColors.inkFaint,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.primaryLight,
        side: BorderSide.none,
        labelStyle: GoogleFonts.manrope(
          fontSize: 12.5,
          color: AppColors.primaryDark,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Gap.radiusXs),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.line,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: Gap.md,
        iconColor: AppColors.inkMuted,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.canvas,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.inkFaint,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: GoogleFonts.manrope(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelStyle: GoogleFonts.manrope(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A brand-gradient CTA button — the signature premium element.
///
/// Use for THE single most important action on a screen ("Start visit",
/// "Get started", "Save assessment"). Everything else stays flat.
class GradientButton extends StatefulWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final onPressed = widget.onPressed;
    final enabled = onPressed != null;
    // A 0.985 dip on press is the difference between a button that
    // *responds* and a button that *activates*. Felt, not seen.
    final scale = _down ? 0.985 : 1.0;
    final button = AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 110),
      curve: AppMotion.curve,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(Gap.radiusSm),
          onTap: onPressed,
          onTapDown: onPressed == null
              ? null
              : (_) => setState(() => _down = true),
          onTapCancel: onPressed == null
              ? null
              : () => setState(() => _down = false),
          onTapUp: onPressed == null
              ? null
              : (_) => setState(() => _down = false),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.curve,
            decoration: BoxDecoration(
              gradient: enabled
                  ? AppColors.brandGradient
                  : const LinearGradient(
                      colors: [AppColors.lineStrong, AppColors.line],
                    ),
              borderRadius: BorderRadius.circular(Gap.radiusSm),
              boxShadow: enabled
                  ? const [AppShadows.glow]
                  : const <BoxShadow>[],
            ),
            child: Container(
              height: Gap.tapTarget,
              padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize:
                    widget.expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(
                      widget.icon,
                      color: enabled ? Colors.white : AppColors.inkFaint,
                      size: 20,
                    ),
                    const SizedBox(width: Gap.sm),
                  ],
                  // Flexible + maxLines so a long primary label can never
                  // push the button off-screen on a narrow phone; it wraps
                  // to a second line and the row centers it.
                  Flexible(
                    child: Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        color: enabled ? Colors.white : AppColors.inkFaint,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return widget.expand
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}
