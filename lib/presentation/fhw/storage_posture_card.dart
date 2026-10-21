/// Storage posture, and the one action that can change it.
///
/// Extracted from the profile tab because it is the only surface in the app that
/// states, in words, what is protecting the register on this handset — and that
/// sentence has to be legible at the sizes a real CHPS phone uses. The card is
/// reachable from My Work, and the supervision desk shows the same posture.
///
/// ### Why the sentence is always shown
///
/// The posture is computed from the engine that actually opened the file, not from
/// what the build was meant to do, so there is no state in which showing it is
/// misleading. What would be misleading is a lock icon that assumes encryption a
/// web build cannot provide.
///
/// ### Why the button is not always shown
///
/// An action that is known to fail is not transparency, it is a second way of
/// hiding the failure. So it appears only when this build can convert the register
/// *and* the signed-in account is a health worker: a caregiver's own handset has no
/// business running a storage migration over the register a district is
/// accountable for.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/fhw_luxe.dart';
import '../../data/local/database_conversion.dart';
import '../../data/local/database_secret.dart';
import '../../domain/entities/core.dart';
import '../shared/ui.dart';

class StoragePostureCard extends ConsumerStatefulWidget {
  const StoragePostureCard({super.key, this.actionOverride});

  /// Null everywhere in the app, where [offersAction] decides. A test passes
  /// `true` or `false` to pin the layout of each variant on a build that cannot
  /// convert: the button label below is the longest string in this card, and it is
  /// the one most likely to overflow at 200% text on a 320px phone — which is
  /// exactly the failure a desktop test machine would otherwise never see. The
  /// rule itself is tested directly, as [offersAction].
  @visibleForTesting
  final bool? actionOverride;

  /// The whole policy of this card, as a function, so it can be tested without a
  /// phone that can convert.
  ///
  /// The action appears only when a verdict exists, the verdict is "not
  /// encrypted", the signed-in account is a health worker, and this build is one
  /// of the mobile builds that carries the SQLCipher engine. An action that is
  /// known to fail is not transparency, it is a second way of hiding the failure.
  @visibleForTesting
  static bool offersAction({
    required AtRestPosture? posture,
    required AppUser? user,
    required bool buildCanConvert,
  }) =>
      posture != null &&
      !posture.encrypted &&
      (user?.role.isFhw ?? false) &&
      buildCanConvert;

  @override
  ConsumerState<StoragePostureCard> createState() => StoragePostureCardState();
}

class StoragePostureCardState extends ConsumerState<StoragePostureCard> {
  bool _running = false;
  String? _result;

  Future<void> _convert() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Encrypt the register on this device?'),
        content: const Text(
          'Every record stays on this phone — nothing is sent, and no network is '
          'needed. The app copies the register into an encrypted file, counts '
          'every table in both, and only then swaps them. If the two do not '
          'match, it stops and leaves the current register exactly as it is.\n\n'
          'The unencrypted original is kept as a fallback until the app has '
          'opened the encrypted one successfully once, then removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Encrypt now'),
          ),
        ],
      ),
    );
    if (go != true) return;

    setState(() {
      _running = true;
      _result = null;
    });
    try {
      final outcome = await DatabaseConversion.runGuarded();
      if (!mounted) return;
      setState(() => _result = outcome.message);
      // Re-read the posture from the file rather than trusting that the migration
      // said it worked: what this card shows next is what the database opener
      // actually found when it reopened the register.
      ref.invalidate(atRestPostureProvider);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final posture = ref.watch(atRestPostureProvider).valueOrNull;
    final user = ref.watch(currentUserProvider);
    final canAct = StoragePostureCard.offersAction(
      posture: posture,
      user: user,
      buildCanConvert: DatabaseConversion.supportedByThisBuild,
    );
    final showAction = widget.actionOverride ?? canAct;

    return SectionCard(
      // The shape carries the state as well as the sentence, so the difference is
      // visible without relying on colour. While no verdict exists the shape is
      // deliberately neutral: an open padlock would report "not encrypted" before
      // anything had looked, and a closed one would claim the opposite.
      title: 'Storage & encryption',
      subtitle:
          _result ??
          posture?.summary ??
          'Checking how this device stores its records…',
      icon: posture == null
          ? Icons.hourglass_empty_rounded
          : posture.encrypted
          ? Icons.lock_rounded
          : Icons.lock_open_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (posture != null && posture.encrypted)
            Text(
              'New records are written to this file as they are made. Nothing '
              'further is needed here.',
              style: AppType.caption.copyWith(
                color: FhwLuxePalette.textSecondary,
              ),
            ),
          if (showAction) ...[
            const SizedBox(height: Gap.sm),
            OutlinedButton.icon(
              onPressed: _running ? null : _convert,
              icon: const Icon(Icons.lock_rounded, size: 17),
              label: Text(
                _running
                    ? 'Encrypting…'
                    : 'Encrypt the register on this device',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
