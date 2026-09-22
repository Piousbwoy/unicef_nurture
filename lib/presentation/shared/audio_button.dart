/// A per-message, offline playback control.
///
/// Tapping the speaker plays in the language the caller already chose — a
/// speaker button that opens a form instead of making a sound is the bug this
/// file used to ship. Holding it opens the per-message language picker, which
/// is a deliberate, rarer gesture. Screens where the language is already being
/// chosen on the form itself pass [showLanguagePicker] false and get plain
/// play/stop.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';

import '../../core/audio/caregiver_playback.dart';
import '../../core/audio/speech_content_policy.dart';
import '../../core/audio/voice_service.dart';
import '../../core/i18n/speech_bank.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/glass.dart';
import 'speech_language_sheet.dart';
import 'offline_voice_check.dart';

class AudioButton extends ConsumerStatefulWidget {
  const AudioButton({
    super.key,
    required this.text,
    required this.language,
    this.sourceLanguage = 'English',
    this.policy = SpeechContentPolicy.guidance,
    this.id,
    this.compact = false,
    this.bankClips,
    this.showLanguagePicker = true,
  });

  /// The exact English text displayed by the caller, never a bank substitution.
  final String text;
  final String language;
  final String sourceLanguage;
  final SpeechContentPolicy policy;
  final String? id;

  /// An ordered bank candidate sequence. Only full, exact coverage is eligible.
  final List<String>? bankClips;
  final bool compact;

  /// Whether holding the button may swap the language for this one message.
  final bool showLanguagePicker;

  @override
  ConsumerState<AudioButton> createState() => _AudioButtonState();
}

class _AudioButtonState extends ConsumerState<AudioButton>
    with WidgetsBindingObserver {
  bool _visible = true;
  // VoiceService is shared. Disposing an older button must not stop a newer one.
  static _AudioButtonState? _owner;
  late CaregiverSpeech _input;
  CaregiverPlayback? _playback;
  int _generation = 0;
  bool _picking = false;

  bool get _active =>
      _playback?.phase == CaregiverPlaybackPhase.loading ||
      _playback?.phase == CaregiverPlaybackPhase.playing;

  CaregiverSpeech _snapshot() => CaregiverSpeech(
    id: widget.id ?? 'inline_${widget.text.hashCode}',
    english: widget.text,
    language: widget.language,
    sourceLanguage: widget.sourceLanguage,
    policy: widget.policy,
    clipId: widget.id != null && SpeechBank.byId(widget.id!) != null
        ? widget.id
        : null,
    clipIds: widget.bankClips == null
        ? null
        : List<String>.unmodifiable(widget.bankClips!),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _input = _snapshot();
  }

  @override
  void didUpdateWidget(AudioButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id ||
        _input.english != widget.text ||
        _input.language != widget.language ||
        _input.sourceLanguage != widget.sourceLanguage ||
        _input.policy != widget.policy ||
        !listEquals(_input.clipIds, widget.bankClips)) {
      _stopOwned();
      _input = _snapshot();
      _playback = null;
    }
  }

  void _stopOwned() {
    _generation++;
    final previous = _playback;
    if (_active && previous != null) {
      _playback = CaregiverPlayback(
        phase: CaregiverPlaybackPhase.stopped,
        transcript: previous.transcript,
        language: previous.language,
        source: previous.source,
        stage: SpeechStage.cancelled,
      );
    }
    if (identical(_owner, this)) {
      _owner = null;
      unawaited(VoiceService.stop(owner: this));
    }
  }

  void _superseded() {
    _generation++;
    if (!mounted) return;
    final previous = _playback;
    setState(() {
      if (previous != null) {
        _playback = CaregiverPlayback(
          phase: CaregiverPlaybackPhase.stopped,
          transcript: previous.transcript,
          language: previous.language,
          source: previous.source,
        );
      }
    });
  }

  void _stop() {
    _stopOwned();
    _superseded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.valuesOf(context).enabled;
    if (!_visible && !_picking) _stopOwned();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(_stopOwned);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopOwned();
    super.dispose();
  }

  /// Hold: choose a language for this message only, then play it.
  Future<void> _openPicker() async {
    if (_picking) return;
    if (_active) _stop();
    final generation = _generation;
    _picking = true;
    String? selected;
    try {
      selected = await chooseSpeechLanguage(context, _input);
    } finally {
      _picking = false;
    }
    if (!mounted || generation != _generation || selected == null) return;
    await _play(selected);
  }

  /// Play [selected], superseding any other button's audio.
  Future<void> _play(String selected) async {
    if (!(ModalRoute.of(context)?.isCurrent ?? true) ||
        !TickerMode.valuesOf(context).enabled ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed)) {
      return;
    }
    if (_active) _stop();
    final generation = ++_generation;
    final input = _input;
    final speech = input.withLanguage(selected);
    _owner?._superseded();
    _owner = this;
    // Loading is active before awaiting speak, so a second tap can stop it.
    setState(() {
      _playback = CaregiverPlayback(
        phase: CaregiverPlaybackPhase.loading,
        transcript: speech.localizedText ?? speech.english,
        language: speech.localizedText == null
            ? speech.sourceLanguage
            : selected,
        source: 'Checking offline audio',
      );
    });
    bool current() => mounted && generation == _generation;
    try {
      final outcome = await VoiceService.speak(
        VoiceRequest(
          id: speech.id,
          preferredLanguage: selected,
          preferredScript: speech.english,
          sourceLanguage: speech.sourceLanguage,
          policy: speech.policy,
          owner: this,
          revision: speech.revision,
          bankClips:
              speech.clipIds ??
              (speech.clipId == null ? null : [speech.clipId!]),
        ),
        onPlayback: (event) {
          if (!current()) return;
          setState(() => _playback = event);
          if (!_active && identical(_owner, this)) _owner = null;
        },
      );
      if (!current()) return;
      // Completion normally arrives as an event. Never mark playback as playing
      // merely because the full-playback future has returned.
      if (outcome.source == VoiceSource.readAloud &&
          _playback?.phase != CaregiverPlaybackPhase.stopped &&
          _playback?.phase != CaregiverPlaybackPhase.fallback) {
        setState(() {
          _playback = CaregiverPlayback(
            phase: CaregiverPlaybackPhase.fallback,
            transcript:
                outcome.spokenScript ?? speech.localizedText ?? speech.english,
            language:
                outcome.actualLanguage ??
                (speech.localizedText == null
                    ? speech.sourceLanguage
                    : selected),
            source:
                outcome.detail ?? 'Readable text • offline audio unavailable',
            reasonCode: outcome.reasonCode,
          );
        });
      }
    } catch (_) {
      if (!current()) return;
      setState(() {
        _playback = CaregiverPlayback(
          phase: CaregiverPlaybackPhase.fallback,
          transcript: speech.localizedText ?? speech.english,
          language: speech.localizedText == null
              ? speech.sourceLanguage
              : selected,
          source: 'Readable text • offline audio unavailable',
        );
      });
    } finally {
      if (current() && identical(_owner, this)) _owner = null;
    }
  }

  Future<void> _showDetails() async {
    final event = _playback;
    if (event == null || _picking) return;
    final generation = _generation;
    _picking = true;
    String? language;
    try {
      language = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${event.language} • ${event.phase.name}',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              Text(event.source),
              SelectableText(event.transcript),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(
                      sheetContext,
                      event.requestedLanguage ?? widget.language,
                    ),
                    child: const Text('Retry'),
                  ),
                  if (OfflineSpeechLanguage.canonical(widget.sourceLanguage) ==
                      'English')
                    TextButton(
                      onPressed: () => Navigator.pop(sheetContext, 'English'),
                      child: const Text('Hear English'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Close'),
                  ),
                ],
              ),
              OfflineVoiceCheck(
                language: event.requestedLanguage ?? widget.language,
              ),
            ],
          ),
        ),
      );
    } finally {
      _picking = false;
    }
    if (mounted && generation == _generation && language != null) {
      await _play(language);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserProvider, (previous, next) {
      if (previous?.id != next?.id ||
          previous?.preferredLanguage != next?.preferredLanguage) {
        setState(() {
          _stopOwned();
          _playback = null;
        });
      }
    });
    final colour = _active ? AppColors.primary : AppColors.primaryDeep;
    final size = widget.compact ? 36.0 : 44.0;
    final loading = _playback?.phase == CaregiverPlaybackPhase.loading;
    final status = switch (_playback?.phase) {
      CaregiverPlaybackPhase.loading => 'Loading',
      CaregiverPlaybackPhase.playing => 'Playing',
      CaregiverPlaybackPhase.completed => 'Completed',
      CaregiverPlaybackPhase.stopped => 'Stopped',
      CaregiverPlaybackPhase.fallback => 'Audio unavailable',
      null => 'Ready',
    };
    final label = _active
        ? 'Stop audio'
        : widget.showLanguagePicker
        ? 'Play audio. Hold to choose another language.'
        : 'Play audio';
    final playback = _playback;
    return Flex(
      direction: widget.compact ? Axis.horizontal : Axis.vertical,
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: label,
          child: Tooltip(
            message: label,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () =>
                    _active ? _stop() : unawaited(_play(widget.language)),
                onLongPress: widget.showLanguagePicker
                    ? () => unawaited(_openPicker())
                    : null,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: AnimatedContainer(
                      duration: VisualEffects.of(
                        context,
                      ).scale(const Duration(milliseconds: 220)),
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: _active ? colour : AppColors.primaryLight,
                        shape: BoxShape.circle,
                        boxShadow: _active
                            ? const [AppShadows.glow]
                            : const [AppShadows.card],
                      ),
                      child: Icon(
                        loading
                            ? Icons.hourglass_empty_rounded
                            : _active
                            ? Icons.stop_rounded
                            : Icons.volume_up_rounded,
                        size: widget.compact ? 18 : 22,
                        color: _active ? Colors.white : colour,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (playback != null && widget.compact)
          Semantics(
            liveRegion: true,
            child: IconButton(
              onPressed: _showDetails,
              tooltip:
                  '${playback.language} • $status. Transcript and voice setup',
              icon: Icon(
                playback.phase == CaregiverPlaybackPhase.fallback
                    ? Icons.error_outline_rounded
                    : Icons.info_outline_rounded,
              ),
            ),
          ),
        if (playback != null && !widget.compact) ...[
          const SizedBox(height: 4),
          InkWell(
            onTap: _showDetails,
            child: _SourcePill(
              status: status,
              detail:
                  '${playback.language} • $status • ${playback.source}. Tap for transcript, retry, and voice setup.',
              compact: widget.compact,
            ),
          ),
        ],
      ],
    );
  }
}

/// The one-word result under the button. The full sentence — which language
/// actually spoke, and that the voice is bundled and the wording still a
/// draft — is the tooltip and the screen-reader label, because no pill this
/// narrow can show it without cutting the honest part off.
class _SourcePill extends StatelessWidget {
  const _SourcePill({
    required this.status,
    required this.detail,
    required this.compact,
  });
  final String status;
  final String detail;
  final bool compact;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: detail,
    child: Semantics(
      label: detail,
      liveRegion: true,
      excludeSemantics: true,
      child: Container(
        width: compact ? 48 : 80,
        constraints: const BoxConstraints(minHeight: 48),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          status,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryDeep,
          ),
        ),
      ),
    ),
  );
}
