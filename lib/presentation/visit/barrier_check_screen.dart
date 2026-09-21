/// An optional clinic conversation. Skip continues; back leaves the session open.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/care_repository.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../fhw/clinic_widgets.dart';

class BarrierCheckScreen extends ConsumerStatefulWidget {
  const BarrierCheckScreen({super.key, required this.householdId});
  final String householdId;

  @override
  ConsumerState<BarrierCheckScreen> createState() => _BarrierCheckScreenState();
}

class _BarrierCheckScreenState extends ConsumerState<BarrierCheckScreen> {
  final Set<CareBarrier> _selected = {};
  final _notes = TextEditingController();
  // Reuse the same ID when retrying a possibly committed write.
  final _reportId = const Uuid().v4();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_selected.isEmpty && _notes.text.trim().isEmpty) {
      // An empty response is not evidence of a barrier report.
      Navigator.of(context).pop(true);
      return;
    }
    final user = ref.read(currentUserProvider);
    if (user == null) {
      setState(
        () => _error = 'Sign in again to record barriers, or skip for now.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(careRepositoryProvider)
          .recordBarrier(
            user,
            BarrierReport(
              id: _reportId,
              householdId: widget.householdId,
              barriers: _selected.toList(),
              recordedBy: user.id,
              recordedAt: DateTime.now(),
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            ),
          );
      if (!mounted) return;
      ref.invalidate(barrierHistoryProvider(widget.householdId));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is AccessDenied
              ? e.message
              : 'Could not save barriers. Retry or skip to continue care.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final household = ref.watch(householdProvider(widget.householdId));
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text('Care barriers'),
          leading: BackButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const ClinicStepHeader(
              steps: [
                'Household record',
                'Who is here',
                'Assessment queue',
                'Review session',
              ],
              current: 1,
            ),
            ClinicCard(
              title: 'Anything making care difficult?',
              subtitle:
                  'Optional · ${household.valueOrNull?.name ?? 'This household'}. Ask about support needed for clinic care or referrals.',
              child: Column(
                children: [
                  for (final barrier in CareBarrier.values)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _selected.contains(barrier),
                      title: Text(
                        barrier.label,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(barrier.suggestedAction),
                      onChanged: _busy
                          ? null
                          : (on) => setState(() {
                              if (on == true) {
                                _selected.add(barrier);
                              } else {
                                _selected.remove(barrier);
                              }
                            }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ClinicCard(
              title: 'Additional context',
              child: TextField(
                controller: _notes,
                enabled: !_busy,
                minLines: 3,
                maxLines: null,
                decoration: const InputDecoration(
                  hintText: 'Optional notes or support discussed',
                ),
              ),
            ),
            const SizedBox(height: 20),
            const ClinicStatusLine(
              text:
                  'Skipping does not create a barrier report. Going back keeps any session already opened available to resume.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              ClinicStatusLine(text: _error!, icon: Icons.info_outline),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(_busy ? 'Saving…' : 'Save & continue'),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(true),
              child: const Text('Skip for now'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
