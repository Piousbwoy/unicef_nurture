import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/motion.dart';
import '../../../domain/entities/caregiver.dart';
import '../../../domain/entities/core.dart';
import '../caregiver_providers.dart';
import '../widgets/companion.dart';

class CaregiverPreparation extends ConsumerWidget {
  const CaregiverPreparation({
    super.key,
    required this.person,
    this.sourceId = 'clinic-preparation',
  });
  final Person person;
  final String sourceId;
  static const items = {
    'phone': 'Phone, if available',
    'records': 'Available health records or NHIS card',
    'questions': 'Questions to ask the health worker',
    'support': 'A person who can accompany you',
    'transport': 'Transport arrangements discussed',
    'bag': 'Personal items or bag prepared',
  };
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null) return const SizedBox.shrink();
    final activity = ref.watch(caregiverActivityProvider(scope));
    return CompanionCard(
      title: 'Your preparation • ${person.fullName}',
      eyebrow: caregiverAge(person),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Missing documents, money, or an unfinished checklist must not delay emergency care. Nothing here books transport or an appointment.',
          ),
          for (final item in items.entries)
            CaregiverTaskToggle(
              personId: person.id,
              kind: CaregiverActivityKind.preparation,
              sourceId: sourceId,
              itemKey: item.key,
              occurrenceKey: 'current',
              label: item.value,
            ),
          activity.when(
            loading: () => const Text('Loading preparation notes…'),
            error: (_, _) => CompanionLoadError(
              onRetry: () => ref.invalidate(caregiverActivityProvider(scope)),
            ),
            data: (entries) {
              final note = entries
                  .where(
                    (a) =>
                        a.kind == CaregiverActivityKind.preparation &&
                        a.personId == person.id &&
                        a.sourceId == sourceId &&
                        a.itemKey == 'details',
                  )
                  .firstOrNull;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (note != null)
                    Text(
                      'Saved ${caregiverWhen(note.updatedAt)}\n${note.note}',
                    ),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      GlassPageRoute<void>(
                        builder: (_) => _PreparationEditor(
                          person: person,
                          sourceId: sourceId,
                          note: note?.note ?? '',
                        ),
                      ),
                    ),
                    child: const Text(
                      'Write questions, support, or transport details',
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PreparationEditor extends ConsumerStatefulWidget {
  const _PreparationEditor({
    required this.person,
    required this.sourceId,
    required this.note,
  });
  final Person person;
  final String sourceId;
  final String note;
  @override
  ConsumerState<_PreparationEditor> createState() => _PreparationEditorState();
}

class _PreparationEditorState extends ConsumerState<_PreparationEditor> {
  late final _text = TextEditingController(text: widget.note);
  bool _saving = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null) return const SizedBox.shrink();
    final writer = ref.watch(caregiverWriterProvider(scope));
    return CompanionPage(
      title: 'Clinic preparation',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('${widget.person.fullName} • ${caregiverAge(widget.person)}'),
          const Text(
            'Write questions to ask, who may help, and your travel plan. This note does not book or request any service.',
          ),
          TextField(
            controller: _text,
            enabled: !_saving,
            minLines: 4,
            maxLines: 10,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'My preparation notes',
            ),
          ),
          CaregiverSaveAction(
            primary: true,
            label: 'Save preparation notes',
            onSave: () async {
              setState(() => _saving = true);
              try {
                await writer.activity(
                  writer.entry(
                    kind: CaregiverActivityKind.preparation,
                    personId: widget.person.id,
                    sourceId: widget.sourceId,
                    itemKey: 'details',
                    occurrenceKey: 'current',
                    note: _text.text.trim(),
                  ),
                );
                if (context.mounted) Navigator.pop(context);
              } finally {
                if (mounted) setState(() => _saving = false);
              }
            },
          ),
        ],
      ),
    );
  }
}
