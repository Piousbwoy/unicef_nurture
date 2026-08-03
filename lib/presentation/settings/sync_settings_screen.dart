/// Sync settings — the one place a supervisor points this phone at a real
/// district server.
///
/// The honest framing that governs this screen: the app works fully offline and
/// *demonstrates* sync with a loopback transport until a real endpoint is
/// configured. This screen is where that switch happens. It never pretends a
/// connection exists before it has been tested, and it tests before it saves —
/// a CHO should not walk into the field believing records are uploading to an
/// address that was mistyped.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/preferences_store.dart';
import '../shared/ui.dart';

class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  ConsumerState<SyncSettingsScreen> createState() =>
      _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends ConsumerState<SyncSettingsScreen> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  final _urlFocus = FocusNode();

  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _obscureToken = true;

  /// The URL currently saved in preferences (null = demonstration mode).
  String? _savedUrl;

  /// Outcome of the last "test connection" probe.
  String? _testMessage;
  bool? _testOk;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final url = await PreferencesStore.syncApiUrl();
    final token = await PreferencesStore.syncApiToken();
    if (!mounted) return;
    setState(() {
      _savedUrl = (url == null || url.isEmpty) ? null : url;
      _urlController.text = _savedUrl ?? '';
      _tokenController.text = token ?? '';
      _loading = false;
    });
  }

  bool get _configured => _savedUrl != null;

  /// A URL is usable only if it names a real http(s) host. Anything else would
  /// build a transport that fails on every record — better refused up front.
  String? _validate(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return null; // empty means "stay in demonstration mode"
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return 'Enter a full address like https://district.example.com';
    }
    return null;
  }

  Future<void> _test() async {
    final url = _urlController.text.trim();
    final problem = _validate(url);
    if (url.isEmpty) {
      setState(() {
        _testOk = false;
        _testMessage = 'Enter the server address first.';
      });
      return;
    }
    if (problem != null) {
      setState(() {
        _testOk = false;
        _testMessage = problem;
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _testing = true;
      _testMessage = null;
      _testOk = null;
    });

    // A lightweight reachability probe — a GET to the server root. It proves
    // the phone can reach the host without sending any patient data.
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      final response = await request
          .close()
          .timeout(const Duration(seconds: 12));
      final code = response.statusCode;
      await response.drain<void>();
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testMessage = 'Reached the server (HTTP $code). '
            'Records will upload to this address.';
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMessage = 'The server did not answer in time. Check the address '
            'and the network, then try again.';
      });
    } on SocketException catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMessage = 'Could not reach that address: ${e.message}. '
            'Check it is spelled correctly.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMessage = 'Could not connect: $e';
      });
    } finally {
      client.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final url = _urlController.text.trim();
    final problem = _validate(url);
    if (problem != null) {
      setState(() {
        _testOk = false;
        _testMessage = problem;
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    if (url.isEmpty) {
      await PreferencesStore.clearSync();
    } else {
      await PreferencesStore.setSyncApiUrl(url);
      await PreferencesStore.setSyncApiToken(_tokenController.text.trim());
    }

    // Swap in the new transport and restart sync so the change takes effect
    // immediately — the replacement service re-reads preferences and begins
    // listening for connectivity again.
    ref.invalidate(syncServiceProvider);
    await ref.read(syncServiceProvider.future);

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          url.isEmpty
              ? 'Sync server removed. Records stay on this phone.'
              : 'Sync server saved. Records will upload when there is network.',
        ),
      ),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sync settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(Gap.lg),
              children: [
                // --------------------------------------------- Current mode
                SectionCard(
                  title: _configured ? 'Real sync is on' : 'Demonstration mode',
                  subtitle: _configured
                      ? 'Records upload to the district server below whenever '
                            'the phone has network.'
                      : 'No server is configured yet. Records are saved on this '
                            'phone and marked sent without leaving it, so the '
                            'whole flow can be demonstrated. Point the phone at '
                            'a district server to make sync real.',
                  icon: _configured
                      ? Icons.cloud_done_rounded
                      : Icons.cloud_off_rounded,
                  accent: _configured
                      ? AppColors.triageGreen
                      : AppColors.triageAmber,
                  child: _configured
                      ? Container(
                          padding: const EdgeInsets.all(Gap.md),
                          decoration: BoxDecoration(
                            color: AppColors.triageGreenBg,
                            borderRadius: BorderRadius.circular(Gap.radiusSm),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.dns_outlined,
                                size: 17,
                                color: AppColors.triageGreen,
                              ),
                              const SizedBox(width: Gap.sm),
                              Expanded(
                                child: Text(
                                  _savedUrl!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.triageGreen,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: Gap.lg),

                // -------------------------------------------- Server address
                SectionCard(
                  title: 'District server',
                  subtitle:
                      'The address records upload to. Leave the address empty '
                      'to stay in demonstration mode.',
                  icon: Icons.settings_ethernet_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FieldLabel(
                        'Server address',
                        why: 'Records are posted to this address over a secure '
                            'connection.',
                      ),
                      TextField(
                        controller: _urlController,
                        focusNode: _urlFocus,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'https://district.example.com',
                          prefixIcon: const Icon(Icons.link_rounded, size: 18),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(Gap.radiusSm),
                          ),
                        ),
                      ),
                      const SizedBox(height: Gap.md),
                      const FieldLabel(
                        'Access token (optional)',
                        why: 'If the server needs a key, paste it here. It is '
                            'stored only on this phone.',
                      ),
                      TextField(
                        controller: _tokenController,
                        obscureText: _obscureToken,
                        autocorrect: false,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Bearer token',
                          prefixIcon: const Icon(Icons.key_rounded, size: 18),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(Gap.radiusSm),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureToken
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 18,
                            ),
                            onPressed: () => setState(
                              () => _obscureToken = !_obscureToken,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: Gap.md),
                      Wrap(
                        spacing: Gap.sm,
                        runSpacing: Gap.sm,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _testing ? null : _test,
                            icon: _testing
                                ? const SizedBox(
                                    height: 15,
                                    width: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.network_check_rounded),
                            label: Text(
                              _testing ? 'Checking…' : 'Test connection',
                            ),
                          ),
                          if (_configured)
                            TextButton.icon(
                              onPressed: () {
                                _urlController.clear();
                                _tokenController.clear();
                                setState(() {
                                  _testMessage = null;
                                  _testOk = null;
                                });
                              },
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              label: const Text('Clear'),
                            ),
                        ],
                      ),
                      if (_testMessage != null) ...[
                        const SizedBox(height: Gap.md),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(Gap.md),
                          decoration: BoxDecoration(
                            color: (_testOk ?? false)
                                ? AppColors.triageGreenBg
                                : AppColors.triageRedBg,
                            borderRadius: BorderRadius.circular(Gap.radiusSm),
                            border: Border(
                              left: BorderSide(
                                color: (_testOk ?? false)
                                    ? AppColors.triageGreen
                                    : AppColors.triageRed,
                                width: 4,
                              ),
                            ),
                          ),
                          child: Text(
                            _testMessage!,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                              color: (_testOk ?? false)
                                  ? AppColors.triageGreen
                                  : AppColors.triageRed,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: Gap.lg),

                // --------------------------------------------------- Honesty
                Container(
                  padding: const EdgeInsets.all(Gap.md),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(Gap.radiusSm),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 17,
                        color: AppColors.inkMuted,
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Text(
                          'Care never waits on the network. Whether or not a '
                          'server is configured, every record is saved on this '
                          'phone first and uploads by itself when there is '
                          'signal.',
                          style: AppType.caption.copyWith(height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Gap.xl),
              ],
            ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              minimum: const EdgeInsets.all(Gap.lg),
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving…' : 'Save'),
              ),
            ),
    );
  }
}
