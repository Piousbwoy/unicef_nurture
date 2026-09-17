/// A 3×4 clinical keypad. No system keyboard: the keys are ≥64px so a nurse
/// wearing gloves or holding a baby can hit them, the decimal point only
/// appears when the vital allows one, and a long press on backspace clears.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
import '../../shared/ui.dart';

class ClinicalKeypad extends StatelessWidget {
  const ClinicalKeypad({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowDecimal = false,
    this.maxIntegerDigits = 3,
    this.maxDecimals = 1,
  });

  /// Current text of the readout, e.g. "38.1".
  final String value;
  final ValueChanged<String> onChanged;
  final bool allowDecimal;
  final int maxIntegerDigits;
  final int maxDecimals;

  static const double keyHeight = 64;

  void _digit(String d) {
    final dot = value.indexOf('.');
    if (dot < 0) {
      // A lone leading zero is replaced, not extended ("07" is never a vital).
      if (value == '0') {
        onChanged(d);
      } else if (value.length < maxIntegerDigits) {
        onChanged(value + d);
      } else {
        return;
      }
    } else {
      if (value.length - dot - 1 >= maxDecimals) return;
      onChanged(value + d);
    }
    HapticFeedback.selectionClick();
  }

  void _decimal() {
    if (!allowDecimal || value.contains('.')) return;
    onChanged(value.isEmpty ? '0.' : '$value.');
    HapticFeedback.selectionClick();
  }

  void _backspace() {
    if (value.isEmpty) return;
    onChanged(value.substring(0, value.length - 1));
    HapticFeedback.selectionClick();
  }

  void _clear() {
    if (value.isEmpty) return;
    onChanged('');
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    Widget key({
      required Widget child,
      required String label,
      VoidCallback? onTap,
      VoidCallback? onLongPress,
      bool enabled = true,
    }) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Semantics(
          button: true,
          enabled: enabled,
          label: label,
          child: PressScale(
            onTap: enabled ? onTap : null,
            onLongPress: enabled ? onLongPress : null,
            pressedScale: 0.94,
            radius: BorderRadius.circular(Gap.radiusSm),
            child: GlassSurface(
              tier: GlassTier.chip,
              blur: false,
              shadow: false,
              radius: BorderRadius.circular(Gap.radiusSm),
              child: SizedBox(
                height: keyHeight,
                child: Center(
                  child: DefaultTextStyle(
                    style: AppType.title.copyWith(
                      fontSize: 24,
                      color: enabled ? AppColors.ink : AppColors.inkFaint,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Widget digit(String d) =>
        key(label: d, onTap: () => _digit(d), child: Text(d));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(children: [for (final d in row) digit(d)]),
        Row(
          children: [
            key(
              label: allowDecimal
                  ? 'Decimal point'
                  : 'Decimal point unavailable',
              enabled: allowDecimal,
              onTap: _decimal,
              child: const Text('.'),
            ),
            digit('0'),
            key(
              label: 'Backspace. Hold to clear',
              onTap: _backspace,
              onLongPress: _clear,
              child: const Icon(
                Icons.backspace_outlined,
                size: 24,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
