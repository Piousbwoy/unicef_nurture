import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../core/audio/caregiver_playback.dart';
import '../../core/ml/voice_pack_install.dart';

/// Existing language/settings surfaces share this small, explicit installer.
class OfflineVoiceCheck extends StatefulWidget {
  const OfflineVoiceCheck({super.key, required this.language});
  final String language;
  @override
  State<OfflineVoiceCheck> createState() => _OfflineVoiceCheckState();
}

class _OfflineVoiceCheckState extends State<OfflineVoiceCheck> {
  final _installer = VoicePackInstaller();
  final _voice = DeviceCaregiverVoice();
  late String _language;
  bool _busy = false;
  bool _cancellable = true;
  double? _progress;
  String _status = 'Check this device before relying on offline audio.';
  String? _transcript;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _language = OfflineSpeechLanguage.resolve(account: widget.language);
  }

  @override
  void didUpdateWidget(OfflineVoiceCheck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language) {
      _cancel();
      _language = OfflineSpeechLanguage.resolve(account: widget.language);
      _transcript = null;
      _status = 'Check this device before relying on offline audio.';
    }
  }

  void _cancel() {
    ++_generation;
    _installer.cancel();
    unawaited(_voice.stop());
    _busy = false;
  }

  @override
  void dispose() {
    _cancel();
    unawaited(_voice.dispose());
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function(int) action, {
    bool cancellable = true,
  }) async {
    if (_busy) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _cancellable = cancellable;
      _progress = null;
      _transcript = null;
    });
    try {
      await action(generation);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _status =
              'Not ready. Check the connection and free storage, then retry. A missing or invalid pack cannot be activated. Existing records are untouched.',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  void _message(int generation, String value) {
    if (mounted && generation == _generation) setState(() => _status = value);
  }

  Future<void> _install(bool translation) => _run((generation) async {
    _message(
      generation,
      'Downloading $_language ${translation ? 'translation' : 'voice'} files…',
    );
    await _installer.install(
      _language,
      translation: translation,
      progress: (received, total) {
        if (mounted && generation == _generation) {
          setState(() {
            _progress = total > 0 ? received / total : null;
            _status =
                '${(received / 1048576).toStringAsFixed(1)} / ${(total / 1048576).toStringAsFixed(1)} MiB';
          });
        }
      },
    );
    _message(
      generation,
      'Files verified. Run Check voice; cached files alone do not prove playback or translation readiness.',
    );
  });
  Future<void> _check() => _run((generation) async {
    _message(
      generation,
      'Checking installed files and preparing a short voice sample…',
    );
    final shell = await _installer.shellReady();
    if (generation != _generation) return;
    final local = ['Twi', 'Hausa'].contains(_language);
    final translation =
        local && await _installer.installed(_language, translation: true);
    if (generation != _generation) return;
    final text = switch (_language) {
      'Twi' => 'Maakye, wo ho te sɛn?',
      'Hausa' => 'Sannu. Yaya kake?',
      _ => 'Welcome to CareBridge.',
    };
    if (!OfflineSpeechLanguage.names.contains(_language)) {
      _message(
        generation,
        '$_language is not supported by an installed CareBridge voice. Choose a listed language explicitly to check it.',
      );
      return;
    }
    if (_language == 'Dagbani') {
      _message(
        generation,
        'Dagbani uses exact bundled recordings. Dynamic Dagbani speech is not installed.',
      );
      return;
    }
    await _voice.play(
      CaregiverSpeech(
        id: 'offline-voice-check',
        english: text,
        sourceLanguage: _language,
        language: _language,
      ),
      (event) {
        if (!mounted || generation != _generation) return;
        setState(() {
          _transcript = event.transcript;
          _status = event.phase == CaregiverPlaybackPhase.completed
              ? 'Sample playback completed. ${shell ? 'Offline shell verified.' : 'Install the offline shell and reload before offline use.'} '
                    '${local
                        ? translation
                              ? 'Translation files present; dynamic translation still requires runtime validation.'
                              : 'Dynamic translation pack is unavailable.'
                        : ''}'
              : event.source;
        });
      },
    );
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Divider(),
      Text(
        'Offline voice check',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      DropdownButton<String>(
        value: _language,
        isExpanded: true,
        items:
            <String>[
                  ...OfflineSpeechLanguage.names,
                  if (!OfflineSpeechLanguage.names.contains(_language))
                    _language,
                ]
                .map(
                  (name) => DropdownMenuItem(
                    value: name,
                    child: Text(
                      OfflineSpeechLanguage.names.contains(name)
                          ? name
                          : '$name (unsupported)',
                    ),
                  ),
                )
                .toList(),
        onChanged: _busy
            ? null
            : (value) => setState(() {
                _language = value!;
                _transcript = null;
                _status = 'Check this device before relying on offline audio.';
              }),
      ),
      Semantics(liveRegion: true, child: Text(_status)),
      if (_transcript != null) SelectableText(_transcript!),
      if (_busy) ...[
        const SizedBox(height: 8),
        LinearProgressIndicator(value: _progress),
      ],
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: _busy ? null : _check,
            child: const Text('Check voice'),
          ),
          if (_installer.downloadable &&
              ['Twi', 'Hausa'].contains(_language)) ...[
            TextButton(
              onPressed: _busy ? null : () => _install(false),
              child: const Text('Install voice'),
            ),
            TextButton(
              onPressed: _busy ? null : () => _install(true),
              child: const Text('Install translation'),
            ),
          ],
          if (kIsWeb && _installer.downloadable)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _run((generation) async {
                      _message(
                        generation,
                        'Installing offline app, runtime, and recordings… Browser-managed installation continues if this sheet is closed.',
                      );
                      final ready = await _installer.installShell();
                      _message(
                        generation,
                        ready
                            ? 'Offline app files verified.'
                            : 'Installation needs a reload. Save your work, close other CareBridge tabs, and reopen.',
                      );
                    }, cancellable: false),
              child: const Text('Install offline app'),
            ),
          if (_busy && _cancellable)
            TextButton(
              onPressed: () => setState(() {
                _cancel();
                _status = 'Cancelled. You can retry.';
              }),
              child: const Text('Cancel'),
            ),
        ],
      ),
      const Text(
        'Voices are synthetic and require fluent-speaker review. Twi and Hausa voice licenses restrict commercial use. Patient text stays on this device.',
        style: TextStyle(fontSize: 12),
      ),
    ],
  );
}
