/// Input widgets shared by the four protocol forms.
///
/// These exist as one kit rather than four private copies for a clinical reason,
/// not a tidiness one: a danger-sign question must look and behave *identically*
/// in the ANC, PNC, young-infant and child charts. A CHO who learns that a red
/// tile means "this one refers" in one form must be able to rely on it in all of
/// them. Divergence between four hand-rolled copies is how a sign gets missed.
///
/// Two rules are enforced here rather than left to each caller:
///   * **A blank is not a "no".** Where a value can be unknown, [DangerSign] and
///     the numeric fields keep it null, and the engines are told. The engines
///     then downgrade their own confidence. Silently reading a blank as "no
///     danger sign" is the single most dangerous thing a form like this can do.
///   * **Every measurement states its cut-off** while it is being typed. The CHO
///     sees "SAM below 11.5" next to the MUAC box, so the number means something
///     before the engine has run.
///   * **A box scrolls itself into view when it is tapped.** The keyboard rises
///     and the field rises with it — a measurement the CHO cannot see while
///     typing is a measurement that gets guessed.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/engines/measurement_safety_engine.dart';
import '../shared/ui.dart';

/// A yes/no clinical question, with "not checked" as a first-class answer.
///
/// [danger] paints the Yes option red. It is set for signs where a Yes means
/// refer, so the form's colour tells the same story as the protocol.
class DangerSign extends StatelessWidget {
  const DangerSign({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.why,
    this.danger = true,
    this.allowUnknown = false,
  });

  final String label;
  final bool? value;
  final ValueChanged<bool?> onChanged;
  final String? why;
  final bool danger;
  final bool allowUnknown;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label, why: why),
        YesNoField(
          value: value,
          onChanged: onChanged,
          allowUnknown: allowUnknown,
          dangerOnYes: danger,
        ),
      ],
    ),
  );
}

/// A compact list of danger signs that share one heading.
///
/// Rendered as tappable rows rather than yes/no pairs because a chart section
/// with fourteen signs in it becomes unreadable as fourteen button pairs, and an
/// unreadable danger-sign list is a skipped one. Off means "asked and absent" —
/// which is why the heading says so out loud.
class SignChecklist extends StatelessWidget {
  const SignChecklist({
    super.key,
    required this.signs,
    required this.selected,
    required this.onToggle,
  });

  /// Label to storage-key pairs, in protocol order.
  final List<(String key, String label)> signs;
  final Set<String> selected;
  final void Function(String key, bool on) onToggle;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (key, label) in signs)
        _SignRow(
          label: label,
          on: selected.contains(key),
          onChanged: (v) => onToggle(key, v),
        ),
    ],
  );
}

class _SignRow extends StatelessWidget {
  const _SignRow({
    required this.label,
    required this.on,
    required this.onChanged,
  });

  final String label;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.sm),
    child: Material(
      color: on ? AppColors.triageRedBg : AppColors.canvas,
      borderRadius: BorderRadius.circular(Gap.radiusSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        onTap: () => onChanged(!on),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.md,
            vertical: Gap.sm,
          ),
          child: Row(
            children: [
              Icon(
                on
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 22,
                color: on ? AppColors.triageRed : AppColors.inkFaint,
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.3,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                    color: on ? AppColors.triageRed : AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A measurement box that shows its own clinical cut-off.
///
/// [cutoff] is printed under the field permanently — not in a tooltip, not
/// behind an info icon. The CHO reading "11.4" should see "SAM below 11.5" in
/// the same glance, because that is the moment the number becomes a decision.
///
/// [example] is a plain-language sample value shown as the hint while the box
/// is empty — "e.g. 120" — so a first-time user always knows what belongs in
/// the box before she asks.
class MeasureField extends StatefulWidget {
  const MeasureField({
    super.key,
    required this.label,
    required this.controller,
    this.unit,
    this.cutoff,
    this.why,
    this.decimal = false,
    this.width,
    this.onChanged,
    this.example,
  });

  final String label;
  final TextEditingController controller;
  final String? unit;
  final String? cutoff;
  final String? why;
  final bool decimal;
  final double? width;
  final ValueChanged<String>? onChanged;
  final String? example;

  @override
  State<MeasureField> createState() => _MeasureFieldState();
}

class _MeasureFieldState extends State<MeasureField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_scrollIntoView);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_scrollIntoView);
    _focusNode.dispose();
    super.dispose();
  }

  /// Bring the box above the keyboard the moment it gains focus. The short
  /// delay lets the keyboard animation settle first — scrolling against a
  /// still-rising keyboard lands the field under it again.
  void _scrollIntoView() {
    if (!_focusNode.hasFocus) return;
    Future<void>.delayed(const Duration(milliseconds: 320), () {
      if (!mounted || !_focusNode.hasFocus) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: 0.25,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      onChanged: widget.onChanged,
      keyboardType: widget.decimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          widget.decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
        ),
      ],
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.example ?? '—',
        suffixText: widget.unit,
        helperText: widget.cutoff,
        helperMaxLines: 3,
        helperStyle: const TextStyle(
          fontSize: 11.5,
          color: AppColors.inkMuted,
          height: 1.3,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(widget.label, why: widget.why),
          widget.width == null
              ? field
              : SizedBox(width: widget.width, child: field),
        ],
      ),
    );
  }
}

/// Two measurement boxes side by side — blood pressure, weight and height.
class MeasurePair extends StatelessWidget {
  const MeasurePair({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: left),
      const SizedBox(width: Gap.md),
      Expanded(child: right),
    ],
  );
}

/// Single-choice chips over an enum-like list.
class ChoiceChipsField<T> extends StatelessWidget {
  const ChoiceChipsField({
    super.key,
    required this.label,
    required this.options,
    required this.labelOf,
    required this.value,
    required this.onChanged,
    this.why,
    this.dangerIf,
  });

  final String label;
  final List<T> options;
  final String Function(T) labelOf;
  final T? value;
  final ValueChanged<T?> onChanged;
  final String? why;

  /// Marks an option as clinically concerning — an unattended delivery place,
  /// for example — so the record shows the risk at the moment it is entered.
  final bool Function(T)? dangerIf;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label, why: why),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final o in options)
              ChoiceChip(
                label: Text(labelOf(o)),
                selected: value == o,
                selectedColor: dangerIf?.call(o) == true
                    ? AppColors.triageAmberBg
                    : null,
                onSelected: (on) => onChanged(on ? o : null),
              ),
          ],
        ),
      ],
    ),
  );
}

/// A counter for small whole numbers — meals a day, breastfeeds, doses given.
///
/// Tapping beats typing here: these are asked while standing in a compound,
/// often one-handed, and a stepper cannot produce "77 meals" from a slipped
/// finger.
class CountField extends StatelessWidget {
  const CountField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.max = 12,
    this.why,
    this.target,
  });

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;
  final int max;
  final String? why;

  /// What the protocol expects, shown beside the count so a shortfall is
  /// visible before the engine says so.
  final String? target;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label, why: why),
        Row(
          children: [
            _StepButton(
              icon: Icons.remove_rounded,
              onTap: value == null || value == 0
                  ? null
                  : () => onChanged(value! - 1),
            ),
            Container(
              width: 56,
              alignment: Alignment.center,
              child: Text(
                value?.toString() ?? '—',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _StepButton(
              icon: Icons.add_rounded,
              onTap: (value ?? -1) >= max
                  ? null
                  : () => onChanged((value ?? 0) + 1),
            ),
            if (target != null) ...[
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(
                  target!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.inkMuted,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: onTap == null ? AppColors.canvas : AppColors.primaryLight,
    borderRadius: BorderRadius.circular(Gap.radiusSm),
    child: InkWell(
      borderRadius: BorderRadius.circular(Gap.radiusSm),
      onTap: onTap,
      child: SizedBox(
        height: 42,
        width: 42,
        child: Icon(
          icon,
          size: 20,
          color: onTap == null ? AppColors.inkFaint : AppColors.primary,
        ),
      ),
    ),
  );
}

/// The banner at the top of every protocol form.
///
/// States who is being assessed, which chart is running and the one age fact
/// the whole chart hinges on — gestational week, day after delivery, day of
/// life, month of age. If that number is wrong every threshold below it is
/// wrong, so it is shown large and early where it will be challenged.
class ProtocolHeader extends StatelessWidget {
  const ProtocolHeader({
    super.key,
    required this.name,
    required this.protocol,
    required this.anchor,
    this.caveat,
  });

  final String name;
  final String protocol;
  final String anchor;
  final String? caveat;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Gap.lg),
    decoration: BoxDecoration(
      color: AppColors.primaryLight,
      borderRadius: BorderRadius.circular(Gap.radius),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryDark,
          ),
        ),
        const SizedBox(height: Gap.xs),
        Text(
          protocol,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: Gap.md),
        Text(
          anchor,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
            height: 1.35,
          ),
        ),
        if (caveat != null) ...[
          const SizedBox(height: Gap.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 15,
                color: AppColors.triageAmber,
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  caveat!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.inkMuted,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

/// The bar that runs the protocol.
class RunBar extends StatelessWidget {
  const RunBar({
    super.key,
    required this.onRun,
    required this.busy,
    this.blocked,
  });

  final VoidCallback onRun;
  final bool busy;

  /// Why the protocol cannot run yet — a missing age anchor, nothing else. Every
  /// other field is allowed to be blank, and the engine will say so itself.
  final String? blocked;

  @override
  Widget build(BuildContext context) => SafeArea(
    minimum: const EdgeInsets.all(Gap.lg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (blocked != null) ...[
          Container(
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              color: AppColors.triageAmberBg,
              borderRadius: BorderRadius.circular(Gap.radiusSm),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: AppColors.triageAmber,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    blocked!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),
        ],
        FilledButton.icon(
          onPressed: busy || blocked != null ? null : onRun,
          icon: const Icon(Icons.psychology_outlined),
          label: Text(busy ? 'Working…' : 'Run assessment'),
        ),
      ],
    ),
  );
}

/// Parses a possibly-empty measurement box. Blank stays null, never zero.
double? parseDouble(TextEditingController c) {
  final t = c.text.trim();
  return t.isEmpty ? null : double.tryParse(t);
}

int? parseInt(TextEditingController c) {
  final t = c.text.trim();
  return t.isEmpty ? null : int.tryParse(t);
}

/// The pre-run safety gate for measurements.
///
/// Every clinical engine downstream is only as safe as the numbers fed into
/// it, so anything outside a plausible physiological range is surfaced here —
/// before a diagnosis is built on it — and the CHO is asked to re-check.
///
/// Returns `true` only when the CHO explicitly chooses to proceed with the
/// flagged values. Dismissing the dialog or choosing to re-measure returns
/// `false`, which sends them back to the form. The safe action is deliberately
/// the prominent one: a wrong number fed to a protocol engine produces a
/// confident, guideline-cited, wrong recommendation — the most dangerous kind
/// of error this app can make.
Future<bool> confirmImplausibleMeasurements(
  BuildContext context,
  List<PlausibilityFlag> flags,
) async {
  final proceed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(
        Icons.error_outline_rounded,
        color: AppColors.triageAmber,
      ),
      title: const Text('Check these readings'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text(
              'These values are outside the range a living person can '
              'produce. They are most likely a recording or device error, '
              'not the patient.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.inkMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: Gap.md),
            for (final f in flags) ...[
              Container(
                decoration: BoxDecoration(
                  color: AppColors.triageAmberBg,
                  borderRadius: BorderRadius.circular(Gap.radiusSm),
                ),
                child: AccentEdge(
                  accent: AppColors.triageAmber,
                  borderRadius: BorderRadius.circular(Gap.radiusSm),
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${f.kind.label}: ${f.value} ${f.kind.unit}',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: Gap.xs),
                        Text(
                          f.problem,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.inkMuted,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: Gap.xs),
                        Text(
                          f.advice,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Gap.sm),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Use anyway'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Re-measure'),
        ),
      ],
    ),
  );
  return proceed == true;
}
