import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
import '../../../core/theme/motion.dart';
import '../../../domain/entities/caregiver.dart';
import '../caregiver_providers.dart';
import '../widgets/companion.dart';
import 'audio_guide_screen.dart';
import 'caregiver_voice.dart';

class CaregiverHelpTab extends ConsumerWidget {
  const CaregiverHelpTab({super.key, required this.householdId});
  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final scope = ref.watch(caregiverScopeProvider);
    if (user == null || scope == null) return const SizedBox.shrink();
    final settings = ref.watch(caregiverSettingsProvider(scope));
    final writer = ref.watch(caregiverWriterProvider(scope));
    final lite = ref.watch(visualEffectsProvider);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        GlassSurface(
          tier: GlassTier.hero,
          blur: false,
          padding: EdgeInsets.zero,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GlassTier.hero.radius),
              gradient: AppColors.caregiverGradient,
            ),
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.support_agent_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Help and support',
                          style: TextStyle(
                            fontFamily: 'Sora',
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Emergency contacts, people who may help, listening options, and display settings.',
                    style: TextStyle(
                      color: AppColors.white85,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        CompanionCard(
          title: 'If it is an emergency',
          tone: AppColors.triageRed,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'If someone is very unwell or has a danger sign, go to the nearest health facility now. Do not wait for morning, a saved check, documents, or a completed checklist.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => caregiverDial(context, '112'),
                icon: const Icon(Icons.call_outlined),
                label: const Text('Call 112 — emergency line'),
              ),
              const Text(
                'Calling needs a supported phone and cellular coverage. If calling fails, ask someone nearby to help you reach a facility. This app does not dispatch help or arrange transport.',
              ),
            ],
          ),
        ),
        settings.when(
          loading: () => const Text('Loading your support plan…'),
          error: (_, _) => CompanionLoadError(
            onRetry: () => ref.invalidate(caregiverSettingsProvider(scope)),
          ),
          data: (saved) => Column(
            children: [
              CompanionCard(
                title: 'People who may help',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Contacts you enter stay on this phone. Numbers and availability are not verified; saving a contact does not ask them for help.',
                    ),
                    for (final kind in SupportContactKind.values)
                      _ContactCard(
                        kind: kind,
                        contact: saved.contacts
                            .where((c) => c.kind == kind)
                            .firstOrNull,
                      ),
                  ],
                ),
              ),
              CompanionCard(
                title: 'Listening preferences',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Preferred language: ${user.preferredLanguage}'),
                    const Text(
                      'Only matching bundled guidance uses a local-language clip. Revised or personalized guidance uses English device speech when available, or readable text. Each item shows the actual language and transcript. Bundled synthetic/draft-language audio still needs qualified and native-speaker review.',
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
                      'Optional. You can always answer or open urgent help without waiting for audio.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        CompanionCard(
          title: 'Voice topic library',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Listen, stop, or replay a topic. Read its transcript if audio is unavailable.',
              ),
              OutlinedButton.icon(
                onPressed: () {
                  ref.read(caregiverVoiceProvider(scope)).stop();
                  Navigator.of(context).push(
                    GlassPageRoute<void>(
                      builder: (_) =>
                          CaregiverAudioGuideScreen(householdId: householdId),
                    ),
                  );
                },
                icon: const Icon(Icons.headphones_outlined),
                label: const Text('Open the voice guide'),
              ),
            ],
          ),
        ),
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
                      : 'Full display; device reduced-motion settings still apply.',
                ),
                value: lite,
                onChanged: (value) =>
                    ref.read(visualEffectsProvider.notifier).setLite(value),
              ),
              const Text(
                'This device preference applies immediately. If device storage is unavailable it may not survive a restart.',
              ),
            ],
          ),
        ),
        CompanionCard(
          title: 'Your account and this phone',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${user.fullName}\n${user.phone}'),
              const SizedBox(height: 12),
              const Text(
                'Home and milestone checks, notes, food choices, shopping, preparation, support contacts, and routine progress are local-only. They are not sent to a health worker automatically and are not restored by account recovery on another device. Existing clinical records and barrier reports keep their existing sync behavior; syncing does not prove a worker has read or responded.',
              ),
              const SizedBox(height: 12),
              CaregiverSaveAction(
                primary: true,
                label: 'Hand the phone back',
                onSave: () async {
                  ref.read(caregiverVoiceProvider(scope)).stop();
                  // No provider invalidation here: sign-out makes
                  // caregiverScopeProvider null (every tab early-returns) and the
                  // autoDispose scoped providers clean themselves up. Forcing an
                  // invalidate after the user is gone re-runs _owner() and throws
                  // CaregiverDataException as a pending teardown error.
                  await ref.read(sessionProvider.notifier).signOut();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String supportContactLabel(SupportContactKind kind) => switch (kind) {
  SupportContactKind.healthWorker => 'Health facility or worker',
  SupportContactKind.trustedPerson => 'Trusted person',
  SupportContactKind.transport => 'Transport contact',
};

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.kind, this.contact});
  final SupportContactKind kind;
  final SupportContact? contact;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          supportContactLabel(kind),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (contact == null)
          const Text('No contact saved.')
        else ...[
          Text('${contact!.name}\n${contact!.number}'),
          if (contact!.landmark.isNotEmpty)
            Text('Landmark: ${contact!.landmark}'),
          OutlinedButton.icon(
            onPressed: () => caregiverDial(context, contact!.number),
            icon: const Icon(Icons.call_outlined),
            label: Text('Call ${contact!.name}'),
          ),
        ],
        OutlinedButton(
          onPressed: () => Navigator.of(context).push(
            GlassPageRoute<void>(
              builder: (_) => _ContactEditor(kind: kind, contact: contact),
            ),
          ),
          child: Text(
            "${contact == null ? 'Add' : 'Edit'} ${supportContactLabel(kind).toLowerCase()}",
          ),
        ),
      ],
    ),
  );
}

class _ContactEditor extends ConsumerStatefulWidget {
  const _ContactEditor({required this.kind, this.contact});
  final SupportContactKind kind;
  final SupportContact? contact;
  @override
  ConsumerState<_ContactEditor> createState() => _ContactEditorState();
}

class _ContactEditorState extends ConsumerState<_ContactEditor> {
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
              "Ask permission before saving someone's contact details. The app cannot verify the number or whether they can help.",
            ),
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
                  : 'Enter a phone number using digits, spaces, and an optional leading +.',
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
