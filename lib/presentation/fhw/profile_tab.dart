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

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/outbox_dao.dart';
import '../../data/local/preferences_store.dart';
import '../../domain/entities/core.dart';
import '../../domain/enums.dart';
import '../settings/data_inspector_screen.dart';
import '../settings/sync_settings_screen.dart';
import '../settings/voice_test_screen.dart';
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
      // Drop the onboarding-seen flag so the next launch walks through the
      // introduction slides again, the way a fresh device would.
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
        // ------------------------------------------------------------ Account
        _ProfileHeader(user: user),
        const SizedBox(height: Gap.md),

        // ----------------------------------------- Connection & sync centre
        // The live heart of the tab: is the phone online right now, is anything
        // waiting, and the two actions — send now, and point the phone at a real
        // district server.
        SectionCard(
          title: 'Connection & sync',
          subtitle:
              'Everything you save is kept on this phone first and uploads by '
              'itself when there is network. You never lose work.',
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
                            label: 'Waiting to send',
                            colour: AppColors.offline,
                          ),
                        ),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: StatTile(
                            value: '${summary.criticalPending}',
                            label: 'Urgent, still here',
                            colour: summary.criticalPending > 0
                                ? AppColors.triageRed
                                : AppColors.triageGreen,
                          ),
                        ),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: StatTile(
                            value: '${summary.failing}',
                            label: 'Need attention',
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
                        : const Icon(Icons.send_rounded),
                    label: Text(_draining ? 'Sending…' : 'Send everything now'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SyncSettingsScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Sync settings'),
                  ),
                ],
              ),
              if (_stuck.isNotEmpty) ...[
                const SizedBox(height: Gap.md),
                const Text(
                  'Could not be sent after several tries. A supervisor may '
                  'need to look at these.',
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

        // ----------------------------------------------------------- Settings
        SectionCard(
          title: 'Settings',
          icon: Icons.settings_outlined,
          padding: const EdgeInsets.symmetric(vertical: Gap.sm),
          child: Column(
            children: [
              _SettingsTile(
                icon: Icons.dns_outlined,
                title: 'Sync server',
                subtitle: 'Point this phone at the district server, or check '
                    'the connection.',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SyncSettingsScreen()),
                ),
              ),
              _SettingsTile(
                icon: Icons.record_voice_over_rounded,
                title: 'Voice & language',
                subtitle: 'Test what this phone can speak, and how to add a '
                    'real Dagbani recording.',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const VoiceTestScreen()),
                ),
              ),
              _SettingsTile(
                icon: Icons.storage_rounded,
                title: 'On-device database',
                subtitle: 'Browse the records stored on this phone — every '
                    'table, how many rows it holds, and the newest entries.',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DataInspectorScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),

        // -------------------------------------------------------- Permissions
        SectionCard(
          title: 'What this account can do',
          subtitle:
              'Permissions are checked every time an action is taken, not '
              'just when a screen opens.',
          icon: Icons.verified_user_outlined,
          child: Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (final p in Permission.values)
                _PermissionChip(
                  label: _permissionLabel(p),
                  granted: user.can(p),
                ),
            ],
          ),
        ),
        const SizedBox(height: Gap.lg),

        // ------------------------------------------------------------- Exits
        FilledButton.icon(
          onPressed: _signOut,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sign out'),
        ),
        const SizedBox(height: Gap.sm),
        OutlinedButton.icon(
          onPressed: _resetDevice,
          icon: const Icon(Icons.restart_alt_rounded),
          label: const Text('Reset this device'),
        ),
        const SizedBox(height: Gap.xl),
      ],
    );
  }
}

/// The premium identity card at the top of the tab — the worker's name, role
/// and zone on the signature brand gradient, so "who am I signed in as" is
/// answered at a glance before anything else.
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

/// The always-visible, real-time online/offline banner. This is the honest
/// answer to "is my work getting through?" — green when the phone has a data
/// connection, purple when it does not, with a plain-language line about what
/// that means for the records already saved.
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

/// A tappable settings row with a leading icon and a chevron.
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
  final VoidCallback onTap;

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

class _PermissionChip extends StatelessWidget {
  const _PermissionChip({required this.label, required this.granted});

  final String label;
  final bool granted;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.xs),
    decoration: BoxDecoration(
      color: granted ? AppColors.triageGreenBg : AppColors.canvas,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: granted
            ? AppColors.triageGreen.withValues(alpha: 0.4)
            : AppColors.line,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          granted ? Icons.check_rounded : Icons.close_rounded,
          size: 14,
          color: granted ? AppColors.triageGreen : AppColors.inkFaint,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: granted ? AppColors.ink : AppColors.inkFaint,
          ),
        ),
      ],
    ),
  );
}

String _permissionLabel(Permission p) => switch (p) {
  Permission.registerHousehold => 'Register households',
  Permission.viewAllHouseholds => 'See whole zone',
  Permission.viewOwnFamilyOnly => 'See own family only',
  Permission.recordClinicalVitals => 'Record measurements',
  Permission.runClinicalAssessment => 'Run assessments',
  Permission.runCaregiverTriage => 'Danger-sign check',
  Permission.issueReferral => 'Issue referrals',
  Permission.confirmReferralArrival => 'Confirm arrivals',
  Permission.overrideAiRecommendation => 'Override recommendations',
  Permission.viewCommunityInsights => 'See zone insights',
  Permission.recordBarrier => 'Report barriers',
  Permission.planVisitRoute => 'Plan the day',
  Permission.exportRecords => 'Export records',
};
