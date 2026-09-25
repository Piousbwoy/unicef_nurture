/// The quiet half of the Help care hub: each setting that the hub tile opens
/// lives here as one focused page. The hub shows only what a caregiver needs
/// in a moment of worry; every honesty notice moved here with the section it
/// describes, word for word, so nothing is lost — only unwrapped on demand.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/glass.dart';
import '../../../domain/entities/caregiver.dart';
import '../caregiver_providers.dart';
import '../widgets/companion.dart';
import 'caregiver_voice.dart';

String supportContactLabel(SupportContactKind kind) => switch (kind) {
  SupportContactKind.healthWorker => 'Health facility or worker',
  SupportContactKind.trustedPerson => 'Trusted person',
  SupportContactKind.transport => 'Transport contact',
};

/// Language, automatic reading, and the honest limits of bundled audio.
class HelpListeningScreen extends ConsumerWidget {
  const HelpListeningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final scope = ref.watch(caregiverScopeProvider);
    if (user == null || scope == null) return const SizedBox.shrink();
    final settings = ref.watch(caregiverSettingsProvider(scope));
    final writer = ref.watch(caregiverWriterProvider(scope));
    return CompanionPage(
      title: 'Language & listening',
      child: settings.when(
        loading: () => const Center(child: Text('Loading your support plan…')),
        error: (_, _) => Padding(
          padding: const EdgeInsets.all(20),
          child: CompanionLoadError(
            onRetry: () => ref.invalidate(caregiverSettingsProvider(scope)),
          ),
        ),
        data: (saved) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            CompanionCard(
              title: 'Listening preferences',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Preferred language: ${user.preferredLanguage}'),
                  const Text(
                    'Only matching bundled guidance uses a local-language '
                    'clip. Revised or personalized guidance uses English '
                    'device speech when available, or readable text. Each '
                    'item shows the actual language and transcript. Bundled '
                    'synthetic/draft-language audio still needs qualified '
                    'and native-speaker review.',
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final language in const [
                        'Dagbani',
                        'Hausa',
                        'Twi',
                        'English',
                      ])
                        CaregiverSaveAction(
                          label: language == user.preferredLanguage
                              ? '$language • selected'
                              : language,
                          onSave: () async {
                            if (ref.read(caregiverScopeProvider) != scope) {
                              throw const CaregiverDataException(
                                'Your account changed.',
                              );
                            }
                            ref.read(caregiverVoiceProvider(scope)).stop();
                            await ref
                                .read(sessionProvider.notifier)
                                .updateLanguage(language);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Automatic question reading: ${saved.autoRead ? 'On' : 'Off'}",
                  ),
                  CaregiverSaveAction(
                    label: saved.autoRead
                        ? 'Turn automatic reading off'
                        : 'Turn automatic reading on',
                    onSave: () => writer.settings(
                      (s) => s.copyWith(autoRead: !saved.autoRead),
                    ),
                  ),
                  const Text(
                    'Optional. You can always answer or open urgent help '
                    'without waiting for audio.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The lite-display switch, off the hub but one tap away.
class HelpDisplayScreen extends ConsumerWidget {
  const HelpDisplayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lite = ref.watch(visualEffectsProvider);
    return CompanionPage(
      title: 'Display',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          CompanionCard(
            title: 'Display',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Lite display'),
                  subtitle: Text(
                    lite
                        ? 'Blur and decorative motion are off.'
                        : 'Full display; device reduced-motion settings '
                              'still apply.',
                  ),
                  value: lite,
                  onChanged: (value) =>
                      ref.read(visualEffectsProvider.notifier).setLite(value),
                ),
                const Text(
                  'This device preference applies immediately. If device '
                  'storage is unavailable it may not survive a restart.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Who is signed in, what stays on this phone, and the way out.
class HelpAccountScreen extends ConsumerWidget {
  const HelpAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final scope = ref.watch(caregiverScopeProvider);
    if (user == null || scope == null) return const SizedBox.shrink();
    return CompanionPage(
      title: 'Account & this phone',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          CompanionCard(
            title: 'Your account and this phone',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  user.fullName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(user.phone),
                const SizedBox(height: 12),
                const Text(
                  'Home and milestone checks, notes, food choices, '
                  'shopping, preparation, support contacts, and routine '
                  'progress are local-only. They are not sent to a health '
                  'worker automatically and are not restored by account '
                  'recovery on another device. Existing clinical records '
                  'and barrier reports keep their existing sync behavior; '
                  'syncing does not prove a worker has read or responded.',
                ),
                const SizedBox(height: 12),
                CaregiverSaveAction(
                  primary: true,
                  label: 'Hand the phone back',
                  onSave: () async {
                    final navigator = Navigator.of(context);
                    final session = ref.read(sessionProvider.notifier);
                    ref.read(caregiverVoiceProvider(scope)).stop();
                    // Leave this pushed page first: sign-out rebuilds the
                    // router's root stack underneath, and a route still on
                    // top would cover the sign-in screen.
                    if (navigator.canPop()) navigator.pop();
                    // No provider invalidation here: sign-out makes
                    // caregiverScopeProvider null (every tab early-returns)
                    // and the autoDispose scoped providers clean themselves
                    // up. Forcing an invalidate after the user is gone
                    // re-runs _owner() and throws CaregiverDataException as
                    // a pending teardown error.
                    await session.signOut();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Add, edit, or remove one support contact. The notice about what saving a
/// contact does and does not do lives here, with the action it describes.
class HelpContactEditor extends ConsumerStatefulWidget {
  const HelpContactEditor({super.key, required this.kind, this.contact});
  final SupportContactKind kind;
  final SupportContact? contact;
  @override
  ConsumerState<HelpContactEditor> createState() => _HelpContactEditorState();
}

class _HelpContactEditorState extends ConsumerState<HelpContactEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.contact?.name ?? '');
  late final _number = TextEditingController(
    text: widget.contact?.number ?? '',
  );
  late final _landmark = TextEditingController(
    text: widget.contact?.landmark ?? '',
  );
  bool _saving = false;
  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    _landmark.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null) return const SizedBox.shrink();
    final writer = ref.watch(caregiverWriterProvider(scope));
    Future<void> save({bool remove = false}) async {
      if (!remove && !_form.currentState!.validate()) return;
      setState(() => _saving = true);
      try {
        await writer.settings(
          (s) => s.copyWith(
            contacts: [
              ...s.contacts.where((c) => c.kind != widget.kind),
              if (!remove)
                SupportContact(
                  kind: widget.kind,
                  name: _name.text.trim(),
                  number: _number.text.trim(),
                  landmark: _landmark.text.trim(),
                ),
            ],
          ),
        );
        if (context.mounted) Navigator.pop(context);
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }

    return CompanionPage(
      title: supportContactLabel(widget.kind),
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              "Ask permission before saving someone's contact details. The "
              'app cannot verify the number or whether they can help.',
            ),
            const SizedBox(height: 6),
            const Text(
              'Contacts you enter stay on this phone. Numbers and '
              'availability are not verified; saving a contact does not ask '
              'them for help.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              enabled: !_saving,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Contact name'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter a name.' : null,
            ),
            TextFormField(
              controller: _number,
              enabled: !_saving,
              maxLength: 24,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number'),
              validator: (v) => SupportContact.validNumber(v ?? '')
                  ? null
                  : 'Enter a phone number using digits, spaces, and an '
                        'optional leading +.',
            ),
            TextFormField(
              controller: _landmark,
              enabled: !_saving,
              maxLength: 160,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Landmark or directions (optional)',
              ),
            ),
            AbsorbPointer(
              absorbing: _saving,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CaregiverSaveAction(
                    primary: true,
                    label: 'Save contact on this phone',
                    onSave: save,
                  ),
                  if (widget.contact != null)
                    CaregiverSaveAction(
                      label: 'Remove saved contact',
                      onSave: () => save(remove: true),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
