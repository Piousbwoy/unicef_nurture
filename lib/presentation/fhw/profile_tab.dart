/// The "Me" tab: who you are, whether your work is reaching the district, and
/// the two deliberate exits.
///
/// Sign-out lives here and is obvious on purpose — handing this phone to a
/// mother for caregiver mode is a normal daily action, not an edge case. The
/// connection & sync centre exists because the commonest fear in the field is
/// that unsent means lost; the live online/offline state, the numbers and the
/// reassurance sit next to each other so a CHO can see — not guess — that their
/// morning's work is safe and on its way.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/ml/offline_inference_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/outbox_dao.dart';
import '../../data/local/preferences_store.dart';
import '../../domain/entities/core.dart';
import '../assessment/form_kit.dart';
import '../settings/sync_settings_screen.dart';
import '../shared/ui.dart';

class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({super.key});

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> {
  List<OutboxEntry> _stuck = const [];
  bool _draining = false;

  @override
  void initState() {
    super.initState();
    _loadStuck();
  }

  Future<void> _loadStuck() async {
    final stuck = await ref.read(syncServiceProvider).valueOrNull?.stuck();
    if (mounted) setState(() => _stuck = stuck ?? []);
  }

  Future<void> _drain() async {
    setState(() => _draining = true);
    final report = await ref.read(syncServiceProvider).valueOrNull?.drain();
    await _loadStuck();
    if (!mounted) return;
    setState(() => _draining = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          report == null
              ? 'Sync is not ready yet.'
              : report.attempted == 0
              ? 'Nothing was waiting to send.'
              : '${report.accepted} record${report.accepted == 1 ? '' : 's'} '
                    'sent${report.deferred > 0 ? ', ${report.deferred} deferred \u2014 the network went again' : ''}.',
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Records already saved stay safely on this phone. Anyone can sign '
          'back in with their PIN.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay signed in'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (sure == true && mounted) {
      await ref.read(sessionProvider.notifier).signOut();
    }
  }

  Future<void> _resetDevice() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset this device?'),
        content: const Text(
          'Returns the phone to first-launch setup. All records on this '
          'device will be cleared and a new user can start fresh.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.triageRed,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (sure == true && mounted) {
      await PreferencesStore.reset();
      ref.read(sessionProvider.notifier).markNeedsSetup();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();

    final sync = ref.watch(syncStatusProvider);
    final online = ref.watch(connectivityProvider);
    final isOnline = online.maybeWhen(data: (o) => o, orElse: () => false);

    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        _ProfileHeader(user: user),
        const SizedBox(height: Gap.md),

        SectionCard(
          title: 'District Database & Offline Sync',
          subtitle:
              'Records captured offline persist locally on SQLite and automatically synchronize when network connectivity with the district health server is re-established.',
          icon: Icons.cloud_sync_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ConnectivityHero(isOnline: isOnline),
              const SizedBox(height: Gap.md),
              sync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: Gap.md),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => ErrorView(error: e),
                data: (summary) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          summary.isClean
                              ? Icons.check_circle_rounded
                              : summary.criticalPending > 0
                              ? Icons.priority_high_rounded
                              : Icons.cloud_off_rounded,
                          size: 20,
                          color: summary.isClean
                              ? AppColors.triageGreen
                              : summary.criticalPending > 0
                              ? AppColors.triageRed
                              : AppColors.offline,
                        ),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: Text(
                            summary.label,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Gap.xs),
                    Text(
                      summary.detail,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.inkMuted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: Gap.md),
                    Row(
                      children: [
                        Expanded(
                          child: StatTile(
                            value: '${summary.pending}',
                            label: 'Pending Sync Queue',
                            colour: AppColors.offline,
                          ),
                        ),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: StatTile(
                            value: '${summary.criticalPending}',
                            label: 'Urgent Priority',
                            colour: summary.criticalPending > 0
                                ? AppColors.triageRed
                                : AppColors.triageGreen,
                          ),
                        ),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: StatTile(
                            value: '${summary.failing}',
                            label: 'Sync Retries / Errors',
                            colour: summary.failing > 0
                                ? AppColors.triageAmber
                                : AppColors.triageGreen,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.md),
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                children: [
                  FilledButton.icon(
                    onPressed: _draining ? null : _drain,
                    icon: _draining
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.sync_rounded),
                    label: Text(_draining ? 'Synchronizing District Server...' : 'Sync Records to District Database'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SyncSettingsScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.dns_rounded),
                    label: const Text('District Server Config'),
                  ),
                ],
              ),
              if (_stuck.isNotEmpty) ...[
                const SizedBox(height: Gap.md),
                const Text(
                  'Unresolved records requiring district supervisor diagnostic review:',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.triageAmber,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: Gap.sm),
                for (final entry in _stuck)
                  Container(
                    margin: const EdgeInsets.only(bottom: Gap.xs),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.md,
                      vertical: Gap.sm,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.triageAmberBg,
                      borderRadius: BorderRadius.circular(Gap.radiusSm),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.sync_problem_rounded,
                          size: 18,
                          color: AppColors.triageAmber,
                        ),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: Text(
                            '${entry.entityTable} · ${entry.attempts} attempts'
                            '${entry.lastError == null ? '' : ' — ${entry.lastError}'}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            await ref
                                .read(syncServiceProvider)
                                .valueOrNull
                                ?.retry(entry.id);
                            await _loadStuck();
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Gap.md),

        SectionCard(
          title: 'Clinical Localization & Voice',
          icon: Icons.translate_rounded,
          padding: const EdgeInsets.symmetric(vertical: Gap.sm),
          child: Column(
            children: [
              _SettingsTile(
                icon: Icons.language_rounded,
                title: 'Regional Languages & Audio Guidance',
                subtitle: 'Configured for Northern Region deployments. Switch display and voice prompt read-aloud preferences (English, Twi, Dagbani, Hausa).',
                onTap: () async {
                  await showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => _LanguageAndVoiceSheet(user: user),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),

        SectionCard(
          title: 'Offline AI Model Pack',
          icon: Icons.psychology_rounded,
          padding: const EdgeInsets.symmetric(vertical: Gap.sm),
          child: Column(
            children: [
              _SettingsTile(
                icon: Icons.verified_outlined,
                title: 'Model integrity & versions',
                subtitle: 'Verify which TFLite models are installed and whether their SHA-256 matches the shipped metrics pack.',
                onTap: () async {
                  await showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => const _ModelPackSheet(),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),

        SectionCard(
          title: 'Device Governance & RBAC Security',
          icon: Icons.security_rounded,
          padding: const EdgeInsets.symmetric(vertical: Gap.sm),
          child: Column(
            children: [
              _SettingsTile(
                icon: Icons.lock_outline_rounded,
                title: 'RBAC PIN Security Guard Active',
                subtitle: 'Authentication credential resets are governed by the District Health Office supervisor to ensure clinical data compliance and audit trail validity.',
                onTap: null,
              ),
              _SettingsTile(
                icon: Icons.tablet_mac_rounded,
                title: 'CHPS Assigned Terminal',
                subtitle: 'Registered ${user.createdAt != null ? DateFormat('d MMM yyyy').format(user.createdAt!) : 'Active Terminal'} · Offline encryption & audit log enabled',
                onTap: null,
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.lg),

        Row(
          children: [
            Expanded(
              flex: 3,
              child: FilledButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.lock_rounded),
                label: const Text('Lock Session (Sign Out)'),
              ),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                onPressed: _resetDevice,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.inkMuted,
                  side: const BorderSide(color: AppColors.line, width: 1.2),
                ),
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Device Reset'),
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.xl),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(Gap.radius),
        boxShadow: const [AppShadows.glow],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white.withValues(alpha: 0.22),
            child: Text(
              user.initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 20,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.fullName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: Gap.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    user.role.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const SizedBox(height: Gap.xs),
                Text(
                  user.facilityName ?? '${user.community}, ${user.district}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${user.phone} · Guidance in ${user.preferredLanguage}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectivityHero extends StatelessWidget {
  const _ConnectivityHero({required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final colour = isOnline ? AppColors.triageGreen : AppColors.offline;
    final bg = isOnline ? AppColors.triageGreenBg : AppColors.offlineBg;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border(left: BorderSide(color: colour, width: 4)),
      ),
      child: Row(
        children: [
          Icon(
            isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            size: 22,
            color: colour,
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: colour,
                  ),
                ),
                Text(
                  isOnline
                      ? 'Connected. Saved records upload automatically.'
                      : 'No network right now. Records stay safe here and '
                            'send themselves when signal returns.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.inkMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.md,
            vertical: Gap.md,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(Gap.sm),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(Gap.radiusXs),
                ),
                child: Icon(icon, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.inkFaint,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageAndVoiceSheet extends ConsumerStatefulWidget {
  const _LanguageAndVoiceSheet({required this.user});

  final AppUser user;

  @override
  ConsumerState<_LanguageAndVoiceSheet> createState() =>
      _LanguageAndVoiceSheetState();
}

class _LanguageAndVoiceSheetState
    extends ConsumerState<_LanguageAndVoiceSheet> {
  late String? _selected;

  static const _languageCodes = ['en', 'tw', 'dag', 'ha'];
  static const _languageLabels = {
    'en': 'English',
    'tw': 'Twi',
    'dag': 'Dagbani',
    'ha': 'Hausa',
  };

  String _codeFromPreferred(String pref) {
    switch (pref.toLowerCase()) {
      case 'english':
        return 'en';
      case 'twi':
        return 'tw';
      case 'dagbani':
        return 'dag';
      case 'hausa':
        return 'ha';
      default:
        return 'en';
    }
  }

  @override
  void initState() {
    super.initState();
    _selected = _codeFromPreferred(widget.user.preferredLanguage);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: Gap.lg,
        right: Gap.lg,
        top: Gap.sm,
        bottom: MediaQuery.of(context).viewInsets.bottom + Gap.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Clinical Language & Voice', style: AppType.title),
          const SizedBox(height: Gap.xs),
          Text(
            'Select language preferences for clinical assessments, counseling, and automated voice guidance across Northern Region health zones.',
            style: AppType.caption.copyWith(color: AppColors.inkMuted),
          ),
          const SizedBox(height: Gap.md),
          ChoiceChipsField<String?>(
            label: 'Display language',
            options: _languageCodes,
            labelOf: (code) => _languageLabels[code ?? 'en'] ?? 'English',
            value: _selected,
            onChanged: (val) async {
              setState(() => _selected = val);
              final navigator = Navigator.of(context);
              if (val != null) {
                try {
                  await PreferencesStore.setPreferredLanguage(val);
                } catch (_) {}
              }
              if (mounted) navigator.pop();
            },
          ),
          const Divider(),
          const SizedBox(height: Gap.sm),
          Text(
            'Voice Guidance Profiles:',
            style: AppType.eyebrow,
          ),
          const SizedBox(height: Gap.sm),
          _VoiceRow(
            langName: 'English',
            pillStatus: 'Active Voice Engine',
            pillBg: AppColors.triageGreenBg,
            pillFg: AppColors.triageGreen,
          ),
          _VoiceRow(
            langName: 'Twi',
            pillStatus: 'Scheduled Field Enhancement',
            pillBg: AppColors.primaryLight,
            pillFg: AppColors.primary,
          ),
          _VoiceRow(
            langName: 'Dagbani',
            pillStatus: 'Scheduled Field Enhancement',
            pillBg: AppColors.primaryLight,
            pillFg: AppColors.primary,
          ),
          _VoiceRow(
            langName: 'Hausa',
            pillStatus: 'Scheduled Field Enhancement',
            pillBg: AppColors.primaryLight,
            pillFg: AppColors.primary,
          ),
          const SizedBox(height: Gap.md),
          Center(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
              label: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceRow extends StatelessWidget {
  const _VoiceRow({
    required this.langName,
    required this.pillStatus,
    required this.pillBg,
    required this.pillFg,
  });

  final String langName;
  final String pillStatus;
  final Color pillBg;
  final Color pillFg;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: AppColors.surface,
        child: Icon(Icons.record_voice_over, size: 14, color: AppColors.primary),
      ),
      title: Text(
        langName,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xs),
        decoration: BoxDecoration(
          color: pillBg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          pillStatus,
          style: TextStyle(
            color: pillFg,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ModelPackSheet extends ConsumerWidget {
  const _ModelPackSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final future = OfflineInferenceService.instance.modelStatuses();
    return Padding(
      padding: EdgeInsets.only(
        left: Gap.lg,
        right: Gap.lg,
        top: Gap.sm,
        bottom: MediaQuery.of(context).viewInsets.bottom + Gap.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Offline AI Model Pack', style: AppType.title),
          const SizedBox(height: Gap.xs),
          Text(
            'Models run fully offline on the tablet. When a model is not installed or not verified, the app uses the deterministic clinical calculator fallback.',
            style: AppType.caption.copyWith(color: AppColors.inkMuted),
          ),
          const SizedBox(height: Gap.md),
          FutureBuilder<List<OfflineModelStatus>>(
            future: future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError || !snap.hasData) {
                return const Text(
                  'Could not read model pack status on this device.',
                  style: TextStyle(color: AppColors.triageAmber),
                );
              }
              final list = snap.data!;
              return Column(
                children: [
                  for (final s in list) _ModelStatusTile(status: s),
                ],
              );
            },
          ),
          const SizedBox(height: Gap.md),
          Center(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
              label: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelStatusTile extends StatelessWidget {
  const _ModelStatusTile({required this.status});

  final OfflineModelStatus status;

  @override
  Widget build(BuildContext context) {
    final installed = status.isModelPresent;
    final usable = status.isModelUsable;
    final verified = status.integrityVerified;
    final mismatch = status.expectedSha256 != null &&
        status.actualSha256 != null &&
        status.expectedSha256 != status.actualSha256;
    final colour = !installed
        ? AppColors.inkMuted
        : usable && verified
        ? AppColors.triageGreen
        : AppColors.triageAmber;
    final bg = !installed
        ? AppColors.canvas
        : usable && verified
        ? AppColors.triageGreenBg
        : AppColors.triageAmberBg;
    final pill = !installed
        ? 'Not installed'
        : !usable && mismatch
        ? 'Blocked'
        : usable && verified
        ? 'Verified'
        : mismatch
        ? 'Mismatch'
        : 'Unverified';
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Gap.radiusSm),
                ),
                child: Icon(
                  verified ? Icons.verified_rounded : Icons.psychology_rounded,
                  size: 18,
                  color: colour,
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status.modelVersion ?? '—',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.sm,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  pill,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: colour,
                  ),
                ),
              ),
            ],
          ),
          if (status.trainingDataset != null) ...[
            const SizedBox(height: Gap.sm),
            _ModelPackRow(
              icon: Icons.dataset_outlined,
              label: 'Training data',
              value: status.trainingDataset!,
              valueColor: AppColors.ink,
            ),
          ],
          if (status.ghanaPriors.isNotEmpty) ...[
            const SizedBox(height: Gap.xs),
            _ModelPackRow(
              icon: Icons.menu_book_outlined,
              label: 'Ghana priors',
              value: status.ghanaPriors.join(' · '),
              valueColor: AppColors.ink,
            ),
          ],
          if (status.internalValidation.isNotEmpty)
            _ModelPackMetrics(
              block: status.internalValidation,
              blockLabel: 'Internal hold-out (20%)',
              brierScore: status.brierScore,
            ),
          if (status.externalValidation.isNotEmpty)
            _ModelPackMetrics(
              block: status.externalValidation,
              blockLabel: 'External validation (UCI Bangladesh)',
            ),
          if (status.versionLadder.isNotEmpty) ...[
            const SizedBox(height: Gap.xs),
            _ModelPackRow(
              icon: Icons.history_rounded,
              label: 'Version ladder',
              value: status.versionLadder.entries
                  .map((e) => '${e.key}: ${e.value}')
                  .join(' · '),
              valueColor: AppColors.inkMuted,
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelPackRow extends StatelessWidget {
  const _ModelPackRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppColors.inkMuted),
          const SizedBox(width: Gap.xs),
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.inkMuted,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11.5,
                color: valueColor,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelPackMetrics extends StatelessWidget {
  const _ModelPackMetrics({
    required this.block,
    required this.blockLabel,
    this.brierScore,
  });

  final Map<String, Object?> block;
  final String blockLabel;
  final double? brierScore;

  @override
  Widget build(BuildContext context) {
    double? d(String k) {
      final v = block[k];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    final auc = d('holdout_auc');
    final sens = d('sensitivity');
    final spec = d('specificity');
    final thr = d('best_threshold');
    final n = block['n'] ?? block['n_test'];
    final tiles = <Widget>[];
    void add(String label, double? v) {
      if (v == null) return;
      tiles.add(
        _MiniStat(
          label: label,
          value: v.toStringAsFixed(v < 1 && v > 0 ? 3 : 1),
        ),
      );
    }
    add('AUC', auc);
    add('Sens', sens);
    add('Spec', spec);
    if (thr != null) add('Thr', thr);
    if (n != null) add('n', n is num ? n.toDouble() : null);
    if (brierScore != null) add('Brier', brierScore);

    if (tiles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            blockLabel,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.inkMuted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: tiles),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: AppColors.inkMuted,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
