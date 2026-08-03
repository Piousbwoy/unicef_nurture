/// Barriers to Care check (Screen 23).
///
/// Asked once per household assessment session, directly from the gaps
/// diagram: "What makes it hard for this family to get care when it's
/// needed?" Multi-select, non-judgmental, and written to the real
/// [BarrierDao] so the answer shapes referral guidance and zone-level
/// pattern detection.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/visit_dao.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../shared/ui.dart';

class BarrierCheckScreen extends ConsumerStatefulWidget {
  const BarrierCheckScreen({super.key, required this.householdId});

  final String householdId;

  @override
  ConsumerState<BarrierCheckScreen> createState() => _BarrierCheckScreenState();
}

class _BarrierCheckScreenState extends ConsumerState<BarrierCheckScreen> {
  final Set<CareBarrier> _selected = {};
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await BarrierDao.save(
        BarrierReport(
          id: const Uuid().v4(),
          householdId: widget.householdId,
          barriers: _selected.toList(),
          recordedBy: user.id,
          recordedAt: DateTime.now(),
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save barriers: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final household = ref.watch(householdProvider(widget.householdId));

    return Scaffold(
      appBar: AppBar(
        title: const Text("What's getting in the way?"),
        leading: BackButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Gap.lg),
          children: [
            SectionCard(
              title: 'What makes it hard for this family to get care?',
              subtitle:
                  'Ask once, before you see the family. If you know what stops '
                  'them, you can fix it before you leave — and many similar '
                  'answers show your supervisor a problem to act on.',
              icon: Icons.signpost_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    household.valueOrNull?.name ?? 'This household',
                    style: AppType.label.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: Gap.lg),
                  for (final barrier in CareBarrier.values)
                    _BarrierTile(
                      barrier: barrier,
                      selected: _selected.contains(barrier),
                      onToggle: () {
                        setState(() {
                          if (_selected.contains(barrier)) {
                            _selected.remove(barrier);
                          } else {
                            _selected.add(barrier);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: Gap.lg),
            SectionCard(
              title: 'Anything else to explain?',
              icon: Icons.notes_outlined,
              child: TextField(
                controller: _notes,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Optional context, e.g. road flooded after rain',
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: Gap.lg),
              _ErrorBox(_error!),
            ],
            const SizedBox(height: Gap.xl),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save & continue'),
            ),
            const SizedBox(height: Gap.md),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: const Text('Skip — continue'),
            ),
            const SizedBox(height: Gap.xl),
          ],
        ),
      ),
    );
  }
}

class _BarrierTile extends StatelessWidget {
  const _BarrierTile({
    required this.barrier,
    required this.selected,
    required this.onToggle,
  });

  final CareBarrier barrier;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.sm),
    child: Material(
      color: selected ? AppColors.primaryLight : AppColors.canvas,
      borderRadius: BorderRadius.circular(Gap.radiusSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.all(Gap.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Gap.radiusSm),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.line,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: selected,
                  onChanged: (_) => onToggle(),
                  activeColor: AppColors.accent,
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      barrier.label,
                      style: AppType.label.copyWith(fontSize: 14.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      barrier.suggestedAction,
                      style: AppType.caption.copyWith(height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Gap.md),
    decoration: BoxDecoration(
      color: AppColors.triageRedBg,
      borderRadius: BorderRadius.circular(Gap.radiusSm),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          size: 18,
          color: AppColors.triageRed,
        ),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: AppColors.triageRed,
              fontSize: 13.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
