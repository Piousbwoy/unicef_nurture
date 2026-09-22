/// Universal voice-narration toggle.
///
/// Sits in the app bar of both the FHW and Caregiver shells. Tapping flips
/// [narrationEnabledProvider]; long-pressing opens a small sheet that lets
/// the user change their preferred guidance language, which is the language
/// narration will use. The button never plays audio by itself — it only
/// arms or disarms the pipeline that [SpeakableText] and
/// [NarrationSection] trigger.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/audio/caregiver_playback.dart' show OfflineSpeechLanguage;
import '../../core/theme/app_theme.dart';
import 'offline_voice_check.dart';

class NarrationButton extends ConsumerWidget {
  const NarrationButton({super.key, this.compact = false, this.iconColor});

  /// Renders a slightly smaller button suitable for the caregiver bar.
  final bool compact;

  /// Overrides the glyph colour. The FHW header sits on a deep-blue gradient
  /// where the default blue/muted icon disappears, so it passes white here;
  /// every other host keeps the state-driven default.
  final Color? iconColor;

  static const _keyEnabled = ValueKey('narration-button-enabled');
  static const _keyDisabled = ValueKey('narration-button-disabled');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(narrationEnabledProvider);
    final language = ref.watch(narrationLanguageProvider);
    return IconButton(
      key: enabled ? _keyEnabled : _keyDisabled,
      tooltip: enabled
          ? 'Narration on ($language). Tap to silence. Hold to change language.'
          : 'Tap to have the app read aloud in $language. Hold to change language.',
      onPressed: () => ref.read(narrationEnabledProvider.notifier).toggle(),
      onLongPress: () => _showLanguagePicker(context, ref),
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: Icon(
          enabled
              ? Icons.record_voice_over_rounded
              : Icons.voice_over_off_rounded,
          key: ValueKey(enabled),
          size: compact ? 20 : 22,
          color: iconColor ?? (enabled ? AppColors.primary : AppColors.inkMuted),
        ),
      ),
    );
  }

  Future<void> _showLanguagePicker(BuildContext context, WidgetRef ref) async {
    final accountId = ref.read(currentUserProvider)?.id;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => const _NarrationLanguageSheet(),
    );
    if (selected == null ||
        !context.mounted ||
        ref.read(currentUserProvider)?.id != accountId) {
      return;
    }
    await ref.read(sessionProvider.notifier).updateLanguage(selected);
    if (!context.mounted || ref.read(currentUserProvider)?.id != accountId) return;
    // Turning narration on when the user just picked a language is the
    // natural next step; only auto-enable if it was previously off so we
    // never silence a session that is already reading aloud.
    if (!ref.read(narrationEnabledProvider)) {
      await ref.read(narrationEnabledProvider.notifier).setEnabled(true);
    }
  }
}

class _NarrationLanguageSheet extends ConsumerWidget {
  const _NarrationLanguageSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(narrationLanguageProvider);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Narration language',
              style: AppType.title.copyWith(
                fontFamily: 'Sora',
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose the language the app should speak in when you tap '
              'narration or hold on a piece of text.',
              style: AppType.caption.copyWith(color: AppColors.inkMuted),
            ),
            const SizedBox(height: 16),
            for (final language in OfflineSpeechLanguage.names)
              _LanguageTile(
                language: language,
                selected: language == current,
                onTap: () => Navigator.of(context).pop(language),
              ),
            OfflineVoiceCheck(language: current),
          ],
        ),
      )),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.language,
    required this.selected,
    required this.onTap,
  });
  final String language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded,
        color: selected ? AppColors.primary : AppColors.inkMuted,
      ),
      title: Text(
        language,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? AppColors.primary : AppColors.ink,
        ),
      ),
      subtitle: Text(switch (language) {
        'Dagbani' => 'Bundled draft phrases only. Other text needs an offline Dagbani voice; English is optional.',
        'English' => 'Requires a verified offline English device voice.',
        _ => 'Bundled draft phrases; dynamic speech depends on available offline models. Not clinically reviewed.',
      }),
      trailing: selected
          ? const Icon(Icons.check_rounded, color: AppColors.primary)
          : null,
    );
  }
}
