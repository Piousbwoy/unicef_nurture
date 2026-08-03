/// Data & Privacy Notice.
///
/// Screen 5 of the master flow: plain-language consent before the user can sign
/// in or create an account. The checkbox is required — this is the concrete
/// follow-through on "Protection of health data."
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/preferences_store.dart';

class PrivacyConsentScreen extends StatefulWidget {
  const PrivacyConsentScreen({super.key});

  @override
  State<PrivacyConsentScreen> createState() => _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends State<PrivacyConsentScreen> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Gap.xl),
          children: [
            const SizedBox(height: Gap.lg),
            Text('Your data', style: AppType.headline),
            const SizedBox(height: Gap.sm),
            Text(
              'How CareBridge AI keeps information safe before you begin.',
              style: AppType.caption.copyWith(fontSize: 14),
            ),
            const SizedBox(height: Gap.xxl),

            _Point(
              icon: Icons.phone_android_outlined,
              title: 'Stored on this phone',
              body:
                  'Your records live on this device first. They are encrypted '
                  'and protected by your PIN.',
            ),
            const SizedBox(height: Gap.lg),
            _Point(
              icon: Icons.cloud_sync_outlined,
              title: 'Only synced when you choose',
              body:
                  'Information leaves this device only when you tap Sync and '
                  'a network is available.',
            ),
            const SizedBox(height: Gap.lg),
            _Point(
              icon: Icons.people_outline_rounded,
              title: 'Seen only by the right people',
              body:
                  'A caregiver sees only their own family. A health worker sees '
                  'only the families in their zone.',
            ),
            const SizedBox(height: Gap.lg),
            _Point(
              icon: Icons.delete_outline_rounded,
              title: 'You can request deletion',
              body:
                  'You can review or ask for your on-device data to be removed '
                  'at any time in settings.',
            ),

            const SizedBox(height: Gap.xxl),
            _AgreementSwitch(
              value: _agreed,
              onChanged: (v) => setState(() => _agreed = v),
            ),
            const SizedBox(height: Gap.xl),
            FilledButton(
              onPressed: _agreed ? () {
                PreferencesStore.markPrivacyConsentSeen();
                context.go(Routes.signIn);
              } : null,
              child: const Text('Continue to sign in'),
            ),
            const SizedBox(height: Gap.md),
            OutlinedButton(
              onPressed: () => context.go(Routes.setup),
              child: const Text('Create a new account instead'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: AppColors.accent),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppType.label.copyWith(fontSize: 14)),
              const SizedBox(height: Gap.xs),
              Text(body, style: AppType.caption.copyWith(height: 1.5)),
            ],
          ),
        ),
      ],
    );
  }
}

class _AgreementSwitch extends StatelessWidget {
  const _AgreementSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(Gap.radius),
      child: Container(
        padding: const EdgeInsets.all(Gap.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Gap.radius),
          border: Border.all(
            color: value ? AppColors.accent : AppColors.line,
            width: value ? 1 : Gap.hairline,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: AppColors.ink,
                side: const BorderSide(color: AppColors.lineStrong),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Gap.radiusSm),
                ),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(
                'I understand and agree to how my data will be used.',
                style: AppType.body.copyWith(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
