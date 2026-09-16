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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/preferences_store.dart';
import '../../data/sync/http_client.dart';
import '../../data/sync/pull_service.dart';
import '../../data/sync/server_auth_client.dart';
import '../shared/ui.dart';

class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  ConsumerState<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
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

  // ------------------------------------- Delta pull (records coming down)
  bool _pulling = false;

  /// Outcome of the last "Pull now" press — rendered exactly as reported.
  String? _pullMessage;
  bool? _pullOk;

  /// What this account last received from the server on this device.
  String? _lastPullLine;

  /// Who the server says owns this device's credential, or an honest
  /// explanation of why that cannot be confirmed right now.
  String? _serverIdentity;

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

    // The last-pull line comes from the same provider the sync banner reads,
    // so the two can never disagree about what the engine actually did.
    String? pullLine;
    try {
      pullLine = await ref.read(lastPullProvider.future);
    } catch (_) {
      pullLine = null; // honesty over polish: fall back to "never pulled"
    }

    if (!mounted) return;
    setState(() {
      _savedUrl = (url == null || url.isEmpty) ? null : url;
      _urlController.text = _savedUrl ?? '';
      _tokenController.text = token ?? '';
      _lastPullLine = pullLine;
      _loading = false;
    });

    // The identity probe needs the network — run it after first paint so a
    // slow server never holds the screen hostage.
    await _loadServerIdentity();
  }

  /// Asks the server who owns this device's credential, and shows the answer
  /// — or the precise reason there is no answer — exactly as it is. No
  /// guessed names, no fabricated sessions.
  Future<void> _loadServerIdentity() async {
    if (!_configured) {
      // Demonstration mode never talks to a server; the "Current mode" card
      // already explains what that means, so no identity line is shown.
      if (mounted) setState(() => _serverIdentity = null);
      return;
    }
    Map<String, dynamic>? profile;
    try {
      profile = await ServerAuthClient.currentUserProfile();
    } catch (_) {
      profile = null; // the probe already swallows its own errors
    }
    if (!mounted) return;
    if (profile != null) {
      // Resolve the fields where promotion holds — inside the setState
      // closure the analyzer can no longer see that profile is non-null.
      final name = profile['full_name'];
      final role = profile['role'];
      final who = name is String && name.isNotEmpty ? name : 'unknown name';
      setState(() {
        _serverIdentity =
            'Signed in to the server as $who (${_roleLabel(role)}).';
      });
      return;
    }
    // Null means either no credential at all, or one the server could not
    // confirm (offline, expired, revoked). Those are different claims and
    // get different sentences.
    final hasCredential = await ServerAuthClient.pickAuthorization() != null;
    if (!mounted) return;
    setState(() {
      _serverIdentity = hasCredential
          ? 'Could not confirm the server sign-in just now — the server may '
                'be offline or the saved session may have expired. Pulling '
                'retries on its own.'
          : 'No server session on this device. Sign in or register while '
                'connected to establish one.';
    });
  }

  String _roleLabel(Object? role) => switch (role) {
        'fhw' => 'frontline health worker',
        'caregiver' => 'caregiver',
        _ => role is String && role.isNotEmpty ? role : 'team member',
      };

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
    // the phone can reach the host without sending any patient data, and the
    // reply body names the service so the operator can confirm it really is
    // the district server answering, not some other machine on that port.
    try {
      final reply = await PlatformHttpClient.get(
        Uri.parse(url),
        timeout: const Duration(seconds: 10),
      );
      final identity = reply.jsonBody;
      final service = identity?['service'];
      final version = identity?['version'];
      final who = service is String && service.isNotEmpty
          ? (version == null ? ' — $service' : ' — $service v$version')
          : '';
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testMessage =
            'Reached the server (HTTP ${reply.statusCode})$who. '
            'Records will upload to this address.';
      });
    } on HttpFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMessage = e.kind == HttpFailureKind.timeout
            ? 'The server did not answer in time. Check the address '
                'and the network, then try again.'
            : 'Could not reach that address: ${e.message}. '
                'Check it is spelled correctly.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMessage = 'Could not connect: $e';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// Manual delta pull. Always honest: the message is built from the
  /// [PullReport] the engine returns, including the "nothing configured to
  /// pull from" case, which is exactly what demonstration mode is.
  Future<void> _pullNow() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _pulling = true;
      _pullMessage = null;
      _pullOk = null;
    });

    // runPull never throws — every outcome comes back as a report.
    final report = await ref.read(pullNowProvider)();

    // The pull advanced the watermark; re-read the exact line the banner
    // shows so settings and banner can never disagree.
    String? line;
    try {
      line = await ref.read(lastPullProvider.future);
    } catch (_) {
      line = _lastPullLine;
    }
    if (!mounted) return;
    setState(() {
      _pulling = false;
      _pullOk = report.isSuccess;
      _lastPullLine = line ?? _lastPullLine;
      _pullMessage = switch (report.status) {
        PullStatus.success =>
          'Pulled ${report.pages} page${report.pages == 1 ? '' : 's'}: '
              '${report.rowsApplied} new or updated record'
              '${report.rowsApplied == 1 ? '' : 's'} merged, '
              '${report.rowsSkipped} already up to date here.',
        PullStatus.notConfigured =>
          'No district server is configured, so there is nothing to pull '
              'from. Records stay on this phone.',
        PullStatus.unauthorized =>
          'The server did not accept the sign-in on this device. Sign in or '
              'register again while connected, then pull.',
        PullStatus.unavailable =>
          'The server could not be reached just now. Pulling retries by '
              'itself when the app starts or the network returns.',
      };
    });

    // A pull that worked proves the session works — refresh the identity
    // line, which may have failed earlier while offline.
    if (report.isSuccess) await _loadServerIdentity();
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
                        why:
                            'Records are posted to this address over a secure '
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
                        why:
                            'If the server needs a key, paste it here. It is '
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
                            onPressed: () =>
                                setState(() => _obscureToken = !_obscureToken),
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
                        _HonestResult(
                          message: _testMessage!,
                          ok: _testOk ?? false,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: Gap.lg),

                // ------------------------------------- Records from others
                SectionCard(
                  title: 'Records from other devices',
                  subtitle:
                      'Pulling brings down the records other devices have '
                      'shared for your area, so a family can visit any nurse '
                      'and be recognised with their history intact.',
                  icon: Icons.cloud_download_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _lastPullLine ??
                            'This account has not pulled from the server on '
                                'this device yet.',
                        style: AppType.caption.copyWith(height: 1.5),
                      ),
                      if (_serverIdentity != null) ...[
                        const SizedBox(height: Gap.sm),
                        Text(
                          _serverIdentity!,
                          style: AppType.caption.copyWith(height: 1.5),
                        ),
                      ],
                      const SizedBox(height: Gap.md),
                      OutlinedButton.icon(
                        onPressed: (!_configured || _pulling)
                            ? null
                            : _pullNow,
                        icon: _pulling
                            ? const SizedBox(
                                height: 15,
                                width: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(_pulling ? 'Pulling…' : 'Pull now'),
                      ),
                      if (!_configured) ...[
                        const SizedBox(height: Gap.sm),
                        Text(
                          'Configure a district server above to enable '
                              'pulling.',
                          style: AppType.caption.copyWith(height: 1.5),
                        ),
                      ],
                      if (_pullMessage != null) ...[
                        const SizedBox(height: Gap.md),
                        _HonestResult(
                          message: _pullMessage!,
                          ok: _pullOk ?? false,
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

/// The green/red outcome box shared by "Test connection" and "Pull now" —
/// one widget so both probes tell the truth in the same voice.
class _HonestResult extends StatelessWidget {
  const _HonestResult({required this.message, required this.ok});

  final String message;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppColors.triageGreen : AppColors.triageRed;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: ok ? AppColors.triageGreenBg : AppColors.triageRedBg,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
      ),
      child: AccentEdge(
        accent: color,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Text(
            message,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              height: 1.4,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
