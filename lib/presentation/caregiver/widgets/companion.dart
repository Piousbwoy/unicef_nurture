import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
import '../../../domain/entities/core.dart';
import '../../../domain/entities/caregiver.dart';
import '../caregiver_providers.dart';

abstract final class CompanionColors {
  static const canvas = AppColors.caregiverCanvas;
  static const blue = AppColors.primary;
  static const ink = AppColors.ink;
  static const bronze = AppColors.caregiverWarm;
  static const muted = AppColors.caregiverMuted;
  static const accent = AppColors.caregiverAccent;
  static const surface = AppColors.caregiverSurface;
}

String caregiverWhen(DateTime time) =>
    DateFormat('d MMM y, h:mm a').format(time.toLocal());
String caregiverAge(Person person) =>
    '${person.ageLabel}${person.isDobEstimated ? ' (estimated)' : ''}';

class CompanionCard extends StatelessWidget {
  const CompanionCard({
    super.key,
    required this.title,
    required this.child,
    this.eyebrow,
    this.tone,
  });
  final String title;
  final String? eyebrow;
  final Widget child;
  final Color? tone;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: GlassSurface(
      blur: false,
      tier: GlassTier.card,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (eyebrow != null) ...[
            Text(
              eyebrow!,
              style: const TextStyle(
                color: AppColors.caregiverAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Sora',
              fontWeight: FontWeight.w700,
              fontSize: 20,
              height: 1.3,
              color: tone ?? CompanionColors.ink,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class CaregiverPriorityBadge extends StatelessWidget {
  const CaregiverPriorityBadge({
    super.key,
    required this.label,
    required this.color,
  });
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0.3,
      ),
    ),
  );
}

class CompanionTheme extends StatelessWidget {
  const CompanionTheme({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return VisualEffectsScope(
      child: Theme(
        data: base.copyWith(
          scaffoldBackgroundColor: AppColors.caregiverCanvas,
          colorScheme: base.colorScheme.copyWith(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: AppColors.caregiverSurface,
            onSurface: AppColors.ink,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 56),
              padding: const EdgeInsets.all(16),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.all(12),
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 1.4),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: AppColors.primary,
            ),
          ),
          iconButtonTheme: IconButtonThemeData(
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
          ),
        ),
        child: child,
      ),
    );
  }
}

class CompanionPage extends ConsumerStatefulWidget {
  const CompanionPage({
    super.key,
    required this.title,
    required this.child,
    this.actions,
  });
  final String title;
  final Widget child;
  final List<Widget>? actions;
  @override
  ConsumerState<CompanionPage> createState() => _CompanionPageState();
}

class _CompanionPageState extends ConsumerState<CompanionPage> {
  CaregiverScope? _owner;
  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(caregiverScopeProvider);
    _owner ??= scope;
    return CompanionTheme(
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 56 + MediaQuery.textScalerOf(context).scale(16),
          title: Text(
            widget.title,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          actions: widget.actions ?? [const CaregiverEmergencyButton()],
        ),
        body: scope == null || scope != _owner
            ? const Center(
                child: Text('Your account changed. Reopen your family.'),
              )
            : widget.child,
      ),
    );
  }
}

class CaregiverEmergencyButton extends StatelessWidget {
  const CaregiverEmergencyButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Emergency help',
    icon: const Icon(Icons.emergency_outlined, color: Color(0xFFAA2929)),
    onPressed: () => showCaregiverEmergency(context),
  );
}

Future<void> showCaregiverEmergency(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Emergency help'),
    content: const SingleChildScrollView(
      child: Text(
        'If the person is very unwell or has a danger sign, go to the nearest health facility now. Do not wait for a check, a saved report, or documents.\n\nCall 112 for emergency help. Calling needs a supported phone and cellular coverage. This app does not dispatch help. If calling fails, ask someone nearby to help you reach a facility.',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      FilledButton(
        onPressed: () => caregiverDial(context, '112'),
        child: const Text('Call 112'),
      ),
    ],
  ),
);

Future<void> caregiverDial(BuildContext context, String number) async {
  final safe = number.replaceAll(RegExp(r'[^0-9+]'), '');
  bool opened = false;
  try {
    if (safe.isNotEmpty) {
      opened = await launchUrl(Uri(scheme: 'tel', path: safe));
    }
  } catch (_) {
    /* Show the number below. */
  }
  if (!context.mounted || opened) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Could not open calling. Dial $number on a phone with cellular coverage.',
      ),
    ),
  );
}

/// Controlled, durable operation: no optimistic checkmark or success claim.
class CaregiverSaveAction extends StatefulWidget {
  const CaregiverSaveAction({
    super.key,
    required this.label,
    required this.onSave,
    this.icon,
    this.primary = false,
  });
  final String label;
  final Future<void> Function() onSave;
  final IconData? icon;
  final bool primary;
  @override
  State<CaregiverSaveAction> createState() => _CaregiverSaveActionState();
}

class _CaregiverSaveActionState extends State<CaregiverSaveAction> {
  bool _saving = false;
  bool _failed = false;
  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.onSave();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _saving
        ? 'Saving…'
        : _failed
        ? 'Could not save — Retry'
        : widget.label;
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(48, widget.primary ? 56 : 48)),
    );
    return widget.primary
        ? FilledButton(
            onPressed: _saving ? null : _save,
            style: style,
            child: Text(label, textAlign: TextAlign.center),
          )
        : OutlinedButton.icon(
            onPressed: _saving ? null : _save,
            style: style,
            icon: Icon(widget.icon ?? Icons.check_rounded),
            label: Text(label, textAlign: TextAlign.center),
          );
  }
}

class CaregiverTaskToggle extends ConsumerWidget {
  const CaregiverTaskToggle({
    super.key,
    required this.personId,
    required this.kind,
    required this.sourceId,
    required this.itemKey,
    required this.occurrenceKey,
    required this.label,
  });
  final String? personId;
  final CaregiverActivityKind kind;
  final String sourceId;
  final String itemKey;
  final String occurrenceKey;
  final String label;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null) return const SizedBox.shrink();
    final writer = ref.watch(caregiverWriterProvider(scope));
    return ref
        .watch(caregiverActivityProvider(scope))
        .when(
          loading: () => Text('$label — loading saved state…'),
          error: (_, _) => CaregiverSaveAction(
            label: 'Retry saved progress',
            onSave: () async {
              ref.invalidate(caregiverActivityProvider(scope));
              await ref.read(caregiverActivityProvider(scope).future);
            },
          ),
          data: (activities) {
            final done = activities.any(
              (a) =>
                  a.personId == personId &&
                  a.kind == kind &&
                  a.sourceId == sourceId &&
                  a.itemKey == itemKey &&
                  a.occurrenceKey == occurrenceKey &&
                  a.done,
            );
            return CaregiverSaveAction(
              label: '$label • ${done ? 'Done — Undo' : 'Mark done'}',
              icon: done
                  ? Icons.check_box_outlined
                  : Icons.check_box_outline_blank,
              onSave: () => writer.activity(
                writer.entry(
                  kind: kind,
                  personId: personId,
                  sourceId: sourceId,
                  itemKey: itemKey,
                  occurrenceKey: occurrenceKey,
                  done: !done,
                ),
              ),
            );
          },
        );
  }
}

class CompanionLoadError extends StatelessWidget {
  const CompanionLoadError({
    super.key,
    required this.onRetry,
    this.message = 'Could not read saved data. Nothing was assumed complete.',
  });
  final VoidCallback onRetry;
  final String message;
  @override
  Widget build(BuildContext context) => CompanionCard(
    title: 'Could not load',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message),
        OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

class CaregiverPersonSelector extends ConsumerWidget {
  const CaregiverPersonSelector({super.key, required this.members});
  final List<Person> members;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null) return const SizedBox.shrink();
    final writer = ref.watch(caregiverWriterProvider(scope));
    return ref
        .watch(caregiverSettingsProvider(scope))
        .when(
          loading: () => const Text('Loading your family selection…'),
          error: (_, _) => CaregiverSaveAction(
            label: 'Retry family selection',
            onSave: () async {
              ref.invalidate(caregiverSettingsProvider(scope));
              await ref.read(caregiverSettingsProvider(scope).future);
            },
          ),
          data: (settings) {
            final selected = members
                .where((p) => p.id == settings.selectedPersonId)
                .firstOrNull;
            return CompanionCard(
              title: selected?.fullName ?? 'All family',
              eyebrow: 'CARING FOR',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (selected != null) Text(caregiverAge(selected)),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.people_outline),
                    label: const Text('Choose family member'),
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (context) => SafeArea(
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(20),
                          children: [
                            CaregiverSaveAction(
                              label: 'All family',
                              onSave: () async {
                                await writer.settings(
                                  (s) => s.copyWith(allFamily: true),
                                );
                                if (context.mounted) Navigator.pop(context);
                              },
                            ),
                            for (final p in members)
                              CaregiverSaveAction(
                                label: '${p.fullName} • ${caregiverAge(p)}',
                                onSave: () async {
                                  await writer.settings(
                                    (s) => s.copyWith(selectedPersonId: p.id),
                                  );
                                  if (context.mounted) Navigator.pop(context);
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
  }
}
