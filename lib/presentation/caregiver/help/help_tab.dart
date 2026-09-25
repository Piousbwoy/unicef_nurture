/// The Help tab as a care hub. What a worried caregiver needs is on this
/// screen: the emergency path and the people who may help. Everything quiet
/// (language, voice library, display, account) sits behind one focused tile
/// each, and every honesty notice travels with the section it describes.
library;

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
import 'help_hub_screens.dart';

class CaregiverHelpTab extends ConsumerWidget {
  const CaregiverHelpTab({super.key, required this.householdId});
  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final scope = ref.watch(caregiverScopeProvider);
    if (user == null || scope == null) return const SizedBox.shrink();
    final settings = ref.watch(caregiverSettingsProvider(scope));
    void push(Widget page) =>
        Navigator.of(context).push(GlassPageRoute<void>(builder: (_) => page));
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        StaggeredReveal(index: 0, child: const _HelpHero()),
        const SizedBox(height: 12),
        StaggeredReveal(index: 1, child: const _EmergencyCard()),
        const SizedBox(height: 12),
        StaggeredReveal(
          index: 2,
          child: settings.when(
            loading: () => const CompanionCard(
              title: 'People who may help',
              child: Text('Loading your support plan…'),
            ),
            error: (_, _) => CompanionLoadError(
              onRetry: () => ref.invalidate(caregiverSettingsProvider(scope)),
            ),
            data: (saved) => CompanionCard(
              title: 'People who may help',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final kind in SupportContactKind.values)
                    _ContactTile(
                      kind: kind,
                      contact: saved.contacts
                          .where((c) => c.kind == kind)
                          .firstOrNull,
                      onOpen: () => push(
                        HelpContactEditor(
                          kind: kind,
                          contact: saved.contacts
                              .where((c) => c.kind == kind)
                              .firstOrNull,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        StaggeredReveal(
          index: 3,
          child: _HubGrid(
            tiles: [
              _HubEntry(
                title: 'Language & listening',
                hint: 'Preferred language and automatic reading',
                icon: Icons.record_voice_over_outlined,
                onTap: () => push(const HelpListeningScreen()),
              ),
              _HubEntry(
                title: 'Voice guide',
                hint: 'Listen, stop, or replay a topic.',
                icon: Icons.headphones_outlined,
                onTap: () {
                  ref.read(caregiverVoiceProvider(scope)).stop();
                  push(CaregiverAudioGuideScreen(householdId: householdId));
                },
              ),
              _HubEntry(
                title: 'Display',
                hint: 'Full or lite for slow phones',
                icon: Icons.brightness_6_outlined,
                onTap: () => push(const HelpDisplayScreen()),
              ),
              _HubEntry(
                title: 'Account & this phone',
                hint: 'Your details and handing back',
                icon: Icons.badge_outlined,
                onTap: () => push(const HelpAccountScreen()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The gradient header: who this tab is, said once, in one breath.
class _HelpHero extends StatelessWidget {
  const _HelpHero();

  @override
  Widget build(BuildContext context) => GlassSurface(
    tier: GlassTier.hero,
    blur: false,
    padding: EdgeInsets.zero,
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GlassTier.hero.radius),
        gradient: AppColors.caregiverGradient,
      ),
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.support_agent_rounded, color: Colors.white, size: 40),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Help and support',
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Emergency contacts, people who may help, listening '
                    'options, and display settings.',
                    style: TextStyle(
                      color: AppColors.white85,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The one card that shouts: get to a facility, and the line to call. The
/// caveat about calling stays true to the device's limits — quiet, not gone.
class _EmergencyCard extends StatefulWidget {
  const _EmergencyCard();

  @override
  State<_EmergencyCard> createState() => _EmergencyCardState();
}

class _EmergencyCardState extends State<_EmergencyCard> {
  bool _know = false;

  @override
  Widget build(BuildContext context) => GlassSurface(
    blur: false,
    tier: GlassTier.card,
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.triageRed.withValues(alpha: 0.10),
              ),
              child: const Icon(
                Icons.emergency_outlined,
                color: AppColors.triageRed,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'If it is an emergency',
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  height: 1.25,
                  letterSpacing: -0.2,
                  color: AppColors.triageRed,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'If someone is very unwell or has a danger sign, go to the '
          'nearest health facility now. Do not wait for morning, a saved '
          'check, documents, or a completed checklist.',
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: () => caregiverDial(context, '112'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.triageRed,
            foregroundColor: Colors.white,
            minimumSize: const Size(48, 56),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.call_outlined, size: 22),
              SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Call 112 — emergency line',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: () => setState(() => _know = !_know),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: CompanionColors.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'What to know',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: CompanionColors.blue,
                    ),
                  ),
                ),
                Icon(
                  Icons.expand_more_rounded,
                  size: 20,
                  color: CompanionColors.muted,
                ),
              ],
            ),
          ),
        ),
        if (_know)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'Calling needs a supported phone and cellular coverage. If '
              'calling fails, ask someone nearby to help you reach a '
              'facility. This app does not dispatch help or arrange '
              'transport.',
            ),
          ),
      ],
    ),
  );
}

/// One saved (or missing) helper, as a live tile: the call is a tap away,
/// the editing lives on its own page.
class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.kind,
    required this.contact,
    required this.onOpen,
  });
  final SupportContactKind kind;
  final SupportContact? contact;
  final VoidCallback onOpen;

  IconData get _icon => switch (kind) {
    SupportContactKind.healthWorker => Icons.local_hospital_outlined,
    SupportContactKind.trustedPerson => Icons.diversity_3_outlined,
    SupportContactKind.transport => Icons.directions_car_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final label = supportContactLabel(kind);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        button: true,
        label: '$label: ${contact?.name ?? 'no contact saved'}',
        child: Material(
          color: CaregiverLuxePalette.pearlSurfaceSunken,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: CaregiverLuxePalette.azureIce,
                        ),
                        child: Icon(
                          _icon,
                          size: 20,
                          color: CompanionColors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: AppType.eyebrow.copyWith(
                                fontSize: 10.5,
                                letterSpacing: 0.9,
                                color: CompanionColors.muted,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              contact?.name ?? 'No contact saved.',
                              style: TextStyle(
                                fontWeight: contact == null
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                                fontSize: 15,
                                height: 1.35,
                                color: contact == null
                                    ? CompanionColors.muted
                                    : CompanionColors.ink,
                              ),
                            ),
                            if (contact != null) ...[
                              Text(
                                contact!.number,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  height: 1.35,
                                  color: CompanionColors.muted,
                                ),
                              ),
                              if (contact!.landmark.isNotEmpty)
                                Text(
                                  'Landmark: ${contact!.landmark}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.35,
                                    color: CompanionColors.muted,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: CompanionColors.muted,
                      ),
                    ],
                  ),
                  if (contact != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: OutlinedButton(
                        onPressed: () =>
                            caregiverDial(context, contact!.number),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        // The phone action stays with the number it dials.
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.call_outlined, size: 18),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Call ${contact!.name}',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
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
  }
}

class _HubEntry {
  const _HubEntry({
    required this.title,
    required this.hint,
    required this.icon,
    required this.onTap,
  });
  final String title;
  final String hint;
  final IconData icon;
  final VoidCallback onTap;
}

/// The four quiet settings as tiles. Two columns at normal sizes; each tile
/// takes the full row when the text is scaled up, so nothing ever clips.
class _HubGrid extends StatelessWidget {
  const _HubGrid({required this.tiles});
  final List<_HubEntry> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wideText = MediaQuery.textScalerOf(context).scale(14) > 21;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: wideText
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 10) / 2,
                child: _HubTile(entry: tile),
              ),
          ],
        );
      },
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({required this.entry});
  final _HubEntry entry;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: entry.title,
    child: Material(
      color: CaregiverLuxePalette.pearlSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: CaregiverLuxePalette.hairLineQuiet),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: entry.onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      CaregiverLuxePalette.azureElectric,
                      CaregiverLuxePalette.azurePrimary,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: CaregiverLuxePalette.azurePrimary.withValues(
                        alpha: 0.28,
                      ),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(entry.icon, size: 20, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                entry.title,
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  height: 1.3,
                  color: CompanionColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                entry.hint,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: CompanionColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
