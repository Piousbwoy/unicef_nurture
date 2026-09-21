/// Manual and one-shot screen narration using request-scoped playback events.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/audio/caregiver_playback.dart';
import '../../core/audio/speakable_service.dart';

export '../../core/audio/speech_content_policy.dart';

class SpeakableText extends ConsumerStatefulWidget {
  const SpeakableText(this.data, {
    this.englishText, this.style, this.strutStyle, this.textAlign,
    this.textDirection, this.softWrap, this.overflow, this.maxLines,
    this.semanticsLabel, this.textWidthBasis, this.textHeightBehavior,
    this.selectionColor, this.forceLongPress = false,
    this.policy = SpeechContentPolicy.guidance, super.key,
  }) : textSpan = null;

  const SpeakableText.rich(this.textSpan, {
    this.englishText, this.style, this.strutStyle, this.textAlign,
    this.textDirection, this.softWrap, this.overflow, this.maxLines,
    this.semanticsLabel, this.textWidthBasis, this.textHeightBehavior,
    this.selectionColor, this.forceLongPress = false,
    this.policy = SpeechContentPolicy.guidance, super.key,
  }) : data = '';

  final String data;
  final InlineSpan? textSpan;
  /// Supply only a verified English counterpart of the displayed text.
  final String? englishText;
  final SpeechContentPolicy policy;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final bool? softWrap;
  final TextOverflow? overflow;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;
  final bool forceLongPress;
  String get source => englishText ?? textSpan?.toPlainText() ?? data;

  @override
  ConsumerState<SpeakableText> createState() => _SpeakableTextState();
}

class _SpeakableTextState extends ConsumerState<SpeakableText>
    with WidgetsBindingObserver {
  final _owner = Object();
  SpeakableService? _service;
  CaregiverPlayback? _event;
  bool _activeRoute = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  bool get _foreground => WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  void _stop() {
    ++_generation;
    unawaited(_service?.stop(owner: _owner) ?? Future.value());
  }

  Future<void> _speak({String? language}) async {
    if (!mounted || !_activeRoute || !_foreground || widget.source.trim().isEmpty) return;
    final generation = ++_generation;
    _service = ref.read(speakableServiceProvider);
    await _service!.speak(widget.source,
      language: language ?? ref.read(narrationLanguageProvider),
      owner: _owner, policy: widget.policy,
      onPlayback: (event) {
        if (mounted && generation == _generation) setState(() => _event = event);
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _activeRoute = (ModalRoute.isCurrentOf(context) ?? true) && TickerMode.of(context);
    if (!_activeRoute) _stop();
  }

  @override
  void didUpdateWidget(SpeakableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source || oldWidget.policy != widget.policy) {
      _stop();
      _event = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(narrationLanguageProvider, (_, _) { _stop(); setState(() => _event = null); });
    ref.listen(narrationEnabledProvider, (previous, next) {
      if (previous == true && !next) { _stop(); setState(() => _event = null); }
    });
    final text = widget.textSpan == null
        ? Text(widget.data, style: widget.style, strutStyle: widget.strutStyle,
            textAlign: widget.textAlign, textDirection: widget.textDirection,
            softWrap: widget.softWrap, overflow: widget.overflow,
            maxLines: widget.maxLines, semanticsLabel: widget.semanticsLabel,
            textWidthBasis: widget.textWidthBasis,
            textHeightBehavior: widget.textHeightBehavior,
            selectionColor: widget.selectionColor)
        : Text.rich(widget.textSpan!, style: widget.style, strutStyle: widget.strutStyle,
            textAlign: widget.textAlign, textDirection: widget.textDirection,
            softWrap: widget.softWrap, overflow: widget.overflow,
            maxLines: widget.maxLines, semanticsLabel: widget.semanticsLabel,
            textWidthBasis: widget.textWidthBasis,
            textHeightBehavior: widget.textHeightBehavior,
            selectionColor: widget.selectionColor);
    return Semantics(
      hint: 'Hold to read aloud',
      customSemanticsActions: {const CustomSemanticsAction(label: 'Read aloud'): () => _speak()},
      child: Tooltip(message: 'Hold to read aloud', child: GestureDetector(
        onLongPress: () => _speak(),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [text, if (_event != null) _PlaybackStatus(
            event: _event!, onEnglish: () => _speak(language: 'English'),
            onStop: () { _stop(); setState(() => _event = null); },
          )],
        ),
      )),
    );
  }
}

class _PlaybackStatus extends StatelessWidget {
  const _PlaybackStatus({required this.event, required this.onEnglish, required this.onStop});
  final CaregiverPlayback event;
  final VoidCallback onEnglish;
  final VoidCallback onStop;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('${event.language} - ${event.phase.name}\n${event.source}\n${event.transcript}',
        style: const TextStyle(fontSize: 12)),
      if (event.phase == CaregiverPlaybackPhase.fallback)
        TextButton(onPressed: onEnglish, child: const Text('Hear English')),
      if (event.phase == CaregiverPlaybackPhase.loading || event.phase == CaregiverPlaybackPhase.playing)
        TextButton(onPressed: onStop, child: const Text('Stop reading')),
    ],
  );
}

class NarrationSection extends ConsumerStatefulWidget {
  const NarrationSection({required this.text, required this.child,
    this.narrationKey, this.enabled = true,
    this.policy = SpeechContentPolicy.guidance, super.key});
  /// Canonical English source, never an inferred translation.
  final String text;
  final Widget child;
  final String? narrationKey;
  final bool enabled;
  final SpeechContentPolicy policy;
  @override
  ConsumerState<NarrationSection> createState() => _NarrationSectionState();
}

class _NarrationSectionState extends ConsumerState<NarrationSection>
    with WidgetsBindingObserver {
  final _owner = Object();
  SpeakableService? _service;
  bool _spoke = false;
  bool _queued = false;
  bool _active = true;
  CaregiverPlayback? _event;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  bool get _foreground => WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  void _stop() {
    ++_generation;
    unawaited(_service?.stop(owner: _owner) ?? Future.value());
  }

  void _schedule() {
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!mounted || !_active || !_foreground || !widget.enabled || _spoke ||
          !ref.read(narrationEnabledProvider) || widget.text.trim().isEmpty) return;
      _spoke = true;
      _speak(ref.read(narrationLanguageProvider));
    });
  }

  void _speak(String language) {
    if (!_active || !_foreground || !widget.enabled) return;
    final generation = ++_generation;
    _service = ref.read(speakableServiceProvider);
    unawaited(_service!.speak(widget.text, language: language, owner: _owner,
      policy: widget.policy, onPlayback: (event) {
        if (mounted && generation == _generation) setState(() => _event = event);
      }));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active = (ModalRoute.isCurrentOf(context) ?? true) && TickerMode.of(context);
    if (!_active) _stop();
    _schedule();
  }

  @override
  void didUpdateWidget(NarrationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.narrationKey != widget.narrationKey) {
      _stop(); _spoke = false; _event = null;
    }
    if (!widget.enabled) _stop();
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) { _stop(); } else { _schedule(); }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(narrationEnabledProvider, (_, next) {
      if (next) { _schedule(); } else { _stop(); setState(() => _event = null); }
    });
    ref.listen(narrationLanguageProvider, (_, _) {
      _stop(); setState(() => _event = null);
    });
    return Column(mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [widget.child, if (_event != null) _PlaybackStatus(
        event: _event!, onEnglish: () => _speak('English'),
        onStop: () { _stop(); setState(() => _event = null); },
      )],
    );
  }
}
