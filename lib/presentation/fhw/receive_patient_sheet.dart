/// Receiving a patient — the front door of the clinic flow.
///
/// WHO's ETAT rule for a sick child is *look before you log*: three quick
/// observations decide whether this child is waiting for paperwork or needs
/// treatment now. This sheet asks exactly those three — can the child sit
/// quietly, is the breathing hard, is the child drowsy or convulsing — with
/// thumb-sized targets, and routes a yes straight into the registration-free
/// [EmergencyTunnelScreen]. A no continues into records with nobody rushed.
///
/// The sheet deliberately stores nothing. It is a triage glance, not a form.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/core.dart';
import '../assessment/emergency_tunnel.dart';
import '../registration/patient_intake_screen.dart';

/// Shows the receiving sheet. [knownHouseholds] is forwarded to intake so the
/// household search is warm when the nurse gets there.
Future<void> showReceivePatientSheet(
  BuildContext context, {
  List<Household> knownHouseholds = const [],
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ReceivePatientSheet(knownHouseholds: knownHouseholds),
  );
}

class ReceivePatientSheet extends StatefulWidget {
  const ReceivePatientSheet({super.key, this.knownHouseholds = const []});

  final List<Household> knownHouseholds;

  @override
  State<ReceivePatientSheet> createState() => _ReceivePatientSheetState();
}

class _ReceivePatientSheetState extends State<ReceivePatientSheet> {
  // A triage observation is a yes/no glance, kept only for this visit to the
  // sheet — nothing here is written to any record.
  final Map<int, bool> _answered = {};

  static const _signs = <(String, String)>[
    ('Cannot sit quietly', 'Waking poorly, limp, or too weak to settle.'),
    ('Breathing is hard', 'Fast, laboured, or the chest pulling in.'),
    ('Drowsy or convulsing', 'Not fully alert, or having a fit.'),
  ];

  bool get _anyYes => _answered.values.contains(true);

  void _go(Widget screen) {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute(builder: (_) => screen));
  }

  void _openEmergency() => _go(const EmergencyTunnelScreen());

  void _openRecords() {
    _go(
      PatientIntakeScreen(
        knownHouseholds: widget.knownHouseholds,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'First, look — don\'t log',
            style: AppType.title.copyWith(color: AppColors.ink),
          ),
          const SizedBox(height: 6),
          Text(
            'Three quick observations before any record is opened. If any is '
            'true, this child is treated first and paperwork comes after.',
            style: AppType.caption,
          ),
          const SizedBox(height: 16),
          for (final (i, sign) in _signs.indexed)
            _SignRow(
              index: i,
              headline: sign.$1,
              detail: sign.$2,
              answer: _answered[i],
              onAnswer: (yes) => setState(() => _answered[i] = yes),
            ),
          const SizedBox(height: 8),
          if (_anyYes)
            FilledButton.icon(
              key: const ValueKey('receive-emergency'),
              onPressed: _openEmergency,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.triageRed,
                minimumSize: const Size.fromHeight(Gap.tapTarget),
              ),
              icon: const Icon(Icons.emergency_rounded),
              label: const Text('This is an emergency — start quick check'),
            )
          else
            FilledButton.icon(
              key: const ValueKey('receive-records'),
              onPressed: _openRecords,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(Gap.tapTarget),
              ),
              icon: const Icon(Icons.assignment_ind_outlined),
              label: const Text('No danger sign now — receive and record'),
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _anyYes ? _openRecords : _openEmergency,
            child: Text(
              _anyYes
                  ? 'No — record the arrival instead'
                  : 'Looks unwell — start the emergency quick check',
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'The emergency quick check needs no registration and works '
            'without internet.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _SignRow extends StatelessWidget {
  const _SignRow({
    required this.index,
    required this.headline,
    required this.detail,
    required this.answer,
    required this.onAnswer,
  });

  final int index;
  final String headline;
  final String detail;
  final bool? answer;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final flagged = answer == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: flagged ? AppColors.triageRedBg : AppColors.canvas,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border.all(
          color: flagged ? AppColors.triageRed : AppColors.line,
          width: flagged ? 1.5 : Gap.hairline,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline, style: AppType.label.copyWith(fontSize: 15)),
                const SizedBox(height: 2),
                Text(detail, style: AppType.caption),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _PillToggle(
            label: 'Yes',
            selected: flagged,
            selectedColor: AppColors.triageRed,
            onTap: () => onAnswer(true),
          ),
          const SizedBox(width: 6),
          _PillToggle(
            label: 'No',
            selected: answer == false,
            selectedColor: AppColors.triageGreen,
            onTap: () => onAnswer(false),
          ),
        ],
      ),
    );
  }
}

class _PillToggle extends StatelessWidget {
  const _PillToggle({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        constraints: const BoxConstraints(minWidth: 56, minHeight: 48),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? selectedColor : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? selectedColor : AppColors.lineStrong,
          ),
        ),
        child: Text(
          label,
          style: AppType.label.copyWith(
            color: selected ? Colors.white : AppColors.inkMuted,
          ),
        ),
      ),
    );
  }
}
