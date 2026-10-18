/// Data & Privacy Notice.
///
/// Screen 5 of the master flow: plain-language consent before the user can sign
/// in or create an account. The checkbox is required — this is the concrete
/// follow-through on "Protection of health data."
///
/// Every sentence here must be one the code can be tested against. A privacy
/// notice that over-promises is worse than a plain one: it is the document a
/// regulator reads first, and "encrypted" written above an unencrypted file is
/// not a small inaccuracy — it is the difference between a health-data system and
/// a claim about one. Where a protection is not yet in place, the honest word is
/// here instead, alongside what *is*.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/preferences_store.dart';
import '../../domain/compliance.dart';

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
              title: 'Stored on this phone first',
              body:
                  'Your records are kept on this device so care works with no '
                  'network. This phone\u2019s own lock and your PIN are what stand '
                  'between them and anyone holding it. The app does not yet '
                  'scramble the records inside the phone \u2014 if it is lost, tell '
                  'the district team, and ask them for the list of who could have '
                  'seen your record.',
            ),
            const SizedBox(height: Gap.lg),
            _Point(
              icon: Icons.cloud_sync_outlined,
              title: 'Only synced to continue your care',
              body:
                  'Information leaves this device for the district team\u2019s '
                  'server, so a health worker elsewhere can continue your care. '
                  'It is not sent because a timer decided to.',
            ),
            const SizedBox(height: Gap.lg),
            _Point(
              icon: Icons.people_outline_rounded,
              title: 'Seen only by the right people, and written down',
              body:
                  'A caregiver sees only their own family. Each time a health '
                  'worker opens a record, the app writes down who, when, and the '
                  'reason they were allowed to. Ask to see that list \u2014 it is '
                  'yours.',
            ),
            const SizedBox(height: Gap.lg),
            _Point(
              icon: Icons.delete_outline_rounded,
              title: 'You can ask, and asking is recorded',
              body:
                  'Ask to see who opened your record, ask for a correction, object '
                  'to a use, or ask for it to be erased. The request is logged with '
                  'a date and answered within ${CareNotice.serviceDeadlineLabel}. '
                  'Anything already handed to a facility is listed for you rather '
                  'than quietly forgotten.',
            ),

            const SizedBox(height: Gap.xxl),
            // Which words this consent was given against. If the notice below
            // changes, a grant recorded here is provably about the older text,
            // and the app asks again rather than assuming it still stands.
            Center(
              child: Text(
                'Notice ${CareNotice.currentVersion}',
                style: AppType.caption.copyWith(
                  fontSize: 11,
                  color: AppColors.inkFaint,
                ),
              ),
            ),
            const SizedBox(height: Gap.lg),
            _AgreementSwitch(
              value: _agreed,
              onChanged: (v) => setState(() => _agreed = v),
            ),
            const SizedBox(height: Gap.xl),
            FilledButton(
              onPressed: _agreed
                  ? () {
                      PreferencesStore.markPrivacyConsentSeen();
                      context.go(Routes.signIn);
                    }
                  : null,
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
  const _Point({required this.icon, required this.title, required this.body});

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
