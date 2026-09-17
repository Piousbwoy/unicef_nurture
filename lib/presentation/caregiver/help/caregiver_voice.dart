import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/audio/caregiver_playback.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/glass.dart';
import '../../../domain/entities/caregiver.dart';
import '../../shared/speech_language_sheet.dart';
import '../caregiver_providers.dart';

final caregiverVoiceBackendProvider =
    Provider<CaregiverVoiceBackend Function()>(
      (ref) => DeviceCaregiverVoice.new,
    );
final caregiverVoiceProvider = ChangeNotifierProvider.autoDispose
    .family<CaregiverVoiceController, CaregiverScope>((ref, scope) {
      // Language and owner changes dispose playback; no previous account transcript survives.
      ref.watch(currentUserProvider);
      final active = ref.watch(caregiverScopeProvider);
      final controller = CaregiverVoiceController(
        ref.watch(caregiverVoiceBackendProvider)(),
      );
      if (active != scope) controller.stop(notify: false);
      return controller;
    });

class CaregiverVoiceController extends ChangeNotifier
    with WidgetsBindingObserver {
  CaregiverVoiceController(this.backend) {
    WidgetsBinding.instance.addObserver(this);
  }
  final CaregiverVoiceBackend backend;
  CaregiverSpeech? speech;
  CaregiverPlayback? playback;
  int _generation = 0;
  bool _disposed = false;
  bool get active =>
      playback?.phase == CaregiverPlaybackPhase.loading ||
      playback?.phase == CaregiverPlaybackPhase.playing;

  Future<void> play(CaregiverSpeech item) async {
    if (_disposed) return;
    final generation = ++_generation;
    speech = item;
    final localized = item.localizedText;
    final language = OfflineSpeechLanguage.canonical(item.language);
    playback = CaregiverPlayback(
      phase: CaregiverPlaybackPhase.loading,
      transcript: localized ?? item.english,
      language: localized == null ? 'English' : language,
      source: 'Checking offline audio',
    );
    notifyListeners();
    try {
      await backend.play(item, (event) {
        if (_disposed || generation != _generation) return;
        playback = event;
        notifyListeners();
      });
    } catch (_) {
      if (_disposed || generation != _generation) return;
      playback = CaregiverPlayback(
        phase: CaregiverPlaybackPhase.fallback,
        transcript: localized ?? item.english,
        language: localized == null ? 'English' : language,
        source: localized == null
            ? 'No $language translation for this message • English text only'
            : '$language offline audio unavailable • readable text only',
      );
      notifyListeners();
    }
  }

  void stop({bool notify = true}) {
    if (_disposed) return;
    _generation++;
    unawaited(backend.stop());
    final previous = playback;
    if (previous != null) {
      playback = CaregiverPlayback(
        phase: CaregiverPlaybackPhase.stopped,
        transcript: previous.transcript,
        language: previous.language,
        source: previous.source,
      );
    }
    if (notify && !_disposed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) stop();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(backend.dispose());
    super.dispose();
  }
}

class CaregiverListen extends ConsumerStatefulWidget {
  const CaregiverListen({
    super.key,
    required this.speech,
    this.label = 'Hear this guidance',
  });
  final CaregiverSpeech speech;
  final String label;
  @override
  ConsumerState<CaregiverListen> createState() => _CaregiverListenState();
}

class _CaregiverListenState extends ConsumerState<CaregiverListen>
    with SingleTickerProviderStateMixin {
  CaregiverVoiceController? _voice;
  CaregiverSpeech? _ownedSpeech;
  late CaregiverSpeech _input;
  AnimationController? _pulse;
  String? _chosenLanguage;
  int _generation = 0;
  bool _picking = false;

  CaregiverSpeech _snapshot(CaregiverSpeech speech) => CaregiverSpeech(
    id: speech.id,
    english: speech.english,
    language: speech.language,
    clipId: speech.clipId,
    clipIds: speech.clipIds == null
        ? null
        : List<String>.unmodifiable(speech.clipIds!),
  );

  bool _sameMessage(CaregiverSpeech a, CaregiverSpeech b) =>
      a.id == b.id &&
      a.english == b.english &&
      a.clipId == b.clipId &&
      listEquals(a.clipIds, b.clipIds);

  @override
  void initState() {
    super.initState();
    _input = _snapshot(widget.speech);
  }

  void _stopOwned() {
    if (_ownedSpeech != null && identical(_voice?.speech, _ownedSpeech)) {
      _voice?.stop(notify: false);
    }
    _ownedSpeech = null;
  }

  @override
  void dispose() {
    _generation++;
    _stopOwned();
    _pulse?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CaregiverListen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameMessage(_input, widget.speech) ||
        _input.language != widget.speech.language) {
      _generation++;
      _stopOwned();
      _chosenLanguage = null;
      _input = _snapshot(widget.speech);
    }
  }

  Future<void> _choose(CaregiverVoiceController voice, CaregiverScope scope) async {
    if (_picking) return;
    // Stop any other message in this scope before opening the picker.
    if (voice.active) voice.stop();
    final generation = ++_generation;
    final input = _input;
    final account = ref.read(currentUserProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    _picking = true;
    String? selected;
    try {
      selected = await chooseSpeechLanguage(context, input);
    } finally {
      _picking = false;
    }
    if (!mounted || generation != _generation || selected == null) return;
    if (!identical(ProviderScope.containerOf(context, listen: false), container) ||
        ref.read(caregiverScopeProvider) != scope ||
        !identical(ref.read(currentUserProvider), account) ||
        !identical(ref.read(caregiverVoiceProvider(scope)), voice)) {
      return;
    }
    final speech = input.withLanguage(selected);
    setState(() {
      _chosenLanguage = selected;
      _ownedSpeech = speech;
    });
    await voice.play(speech);
  }

  @override
  Widget build(BuildContext context) {
    // Invalidate even a rapid account/scope switch away and back while a sheet
    // is open. The post-await comparisons also protect provider-scope changes.
    ref.listen(currentUserProvider, (_, _) {
      _generation++;
      _chosenLanguage = null;
    });
    ref.listen(caregiverScopeProvider, (_, _) {
      _generation++;
      _chosenLanguage = null;
    });
    final scope = ref.watch(caregiverScopeProvider);
    if (scope == null) {
      _pulse?.stop();
      return const SizedBox.shrink();
    }
    final voice = ref.watch(caregiverVoiceProvider(scope));
    if (!identical(_voice, voice)) {
      _generation++;
      _chosenLanguage = null;
      _ownedSpeech = null;
      _voice = voice;
    }
    final currentSpeech = voice.speech;
    final state = currentSpeech != null &&
            _sameMessage(currentSpeech, _input) &&
            (identical(currentSpeech, _ownedSpeech) ||
                currentSpeech.language == _input.language)
        ? voice.playback
        : null;
    final active = state != null && voice.active;
    final isLoading = state?.phase == CaregiverPlaybackPhase.loading;
    final animate = VisualEffects.of(context).motion &&
        state?.phase == CaregiverPlaybackPhase.playing;
    if (animate) {
      final pulse = _pulse ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      );
      if (!pulse.isAnimating) pulse.repeat(reverse: true);
    } else {
      _pulse?.stop();
    }
    final language = _chosenLanguage ?? OfflineSpeechLanguage.canonical(_input.language);
    final selected = _input.withLanguage(language);
    final localized = selected.localizedText;
    final transcript = state?.transcript ?? localized ?? _input.english;
    final transcriptLanguage = state?.language ?? (localized == null ? 'English' : language);
    final status = switch (state?.phase) {
      CaregiverPlaybackPhase.loading => 'Loading',
      CaregiverPlaybackPhase.playing => 'Playing',
      CaregiverPlaybackPhase.completed => 'Playback complete',
      CaregiverPlaybackPhase.stopped => 'Stopped',
      CaregiverPlaybackPhase.fallback => 'Audio unavailable',
      null => widget.label,
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.checkBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.checkBlue.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _VoicePlayButton(
                active: active,
                loading: isLoading,
                pulse: animate ? _pulse : null,
                onTap: () {
                  if (active) {
                    _generation++;
                    voice.stop();
                  } else {
                    unawaited(_choose(voice, scope));
                  }
                },
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        status,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.checkNavy,
                        ),
                      ),
                    ),
                    Text('Selected: $language'),
                    if (state != null)
                      Text(
                        '${state.language} • ${state.source}',
                        style: const TextStyle(fontSize: 12, color: AppColors.caregiverMuted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (transcript.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$transcriptLanguage transcript'),
                  const SizedBox(height: 6),
                  Text(
                    transcript,
                    style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.checkNavy),
                  ),
                  if (transcriptLanguage != 'English') ...[
                    const SizedBox(height: 10),
                    const Text('English original'),
                    Text(_input.english, style: const TextStyle(height: 1.5)),
                  ],
                ],
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              language == 'English'
                  ? 'English audio needs an installed offline English voice on this phone. It may be unavailable.'
                  : localized == null
                  ? 'No $language translation is available offline for this exact message. '
                        'Read the English original, or choose English in the language picker.'
                  : 'Draft $language translation from the bundled speech bank. '
                        'Bundled voices are synthetic. Native-speaker and clinical review are needed.',
              style: const TextStyle(fontSize: 11.5, color: AppColors.caregiverMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoicePlayButton extends StatelessWidget {
  const _VoicePlayButton({
    required this.active,
    required this.loading,
    required this.pulse,
    required this.onTap,
  });
  final bool active;
  final bool loading;
  final AnimationController? pulse;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = active ? 'Stop audio' : 'Choose speech language';
    final button = Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkResponse(
            onTap: onTap,
            radius: 30,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.checkBlue,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.checkBlue.withValues(alpha: 0.3),
                    blurRadius: active ? 16 : 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                loading
                    ? Icons.hourglass_empty_rounded
                    : active
                    ? Icons.stop_rounded
                    : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
    final animation = pulse;
    if (animation == null) return button;
    return AnimatedBuilder(
      animation: animation,
      child: button,
      builder: (context, child) => Transform.scale(
        scale: 1 + animation.value * 0.08,
        child: child,
      ),
    );
  }
}
