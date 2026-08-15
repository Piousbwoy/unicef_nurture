/// Loop in community support (Screen 70).
///
/// Optional step at referral time: select or enter a community volunteer, TBA,
/// or family contact who can help with transport or accompaniment. Stores the
/// contact on the referral and composes a real SMS handoff.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/visit_dao.dart';
import '../../domain/entities/visit.dart';
import '../shared/ui.dart';

class CommunitySupportScreen extends ConsumerStatefulWidget {
  const CommunitySupportScreen({super.key, required this.referral});

  final Referral referral;

  @override
  ConsumerState<CommunitySupportScreen> createState() =>
      _CommunitySupportScreenState();
}

class _CommunitySupportScreenState
    extends ConsumerState<CommunitySupportScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String _role = 'Community volunteer';
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;

  static const _roles = [
    'Community volunteer',
    'Traditional birth attendant',
    'Family member',
    'Neighbour',
    'Other',
  ];

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  String get _message {
    final who = _name.text.trim();
    final greeting = who.isEmpty ? 'Hello' : 'Hello $who';
    return '$greeting. The health worker listed you as a community '
        'supporter for referral ${widget.referral.referenceCode}: '
        '${widget.referral.reason}. Please help the family arrange '
        'transport, or go with them, to ${widget.referral.facilityName}.';
  }

  Future<void> _saveAndHandOff() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final supporterBlock = [
        'Community supporter: ${_name.text.trim()}',
        'Role: $_role',
        'Phone: ${_phone.text.trim()}',
        if (_notes.text.trim().isNotEmpty) 'Notes: ${_notes.text.trim()}',
      ].join('\n');

      final updated = widget.referral.copyWith(
        outcomeNotes: [
          widget.referral.outcomeNotes ?? '',
          supporterBlock,
        ].where((s) => s.isNotEmpty).join('\n\n'),
      );
      await ReferralDao.upsert(updated);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save supporter: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loop in support')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Gap.lg),
          children: [
            SectionCard(
              title: 'Who can help this family follow through?',
              subtitle:
                  '${widget.referral.referenceCode} · ${widget.referral.facilityName}',
              icon: Icons.people_outline_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FieldLabel('Supporter name'),
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'e.g. Hajia Mariam',
                    ),
                  ),
                  const SizedBox(height: Gap.lg),
                  const FieldLabel('Role'),
                  DropdownButtonFormField<String>(
                    initialValue: _role,
                    items: [
                      for (final r in _roles)
                        DropdownMenuItem(value: r, child: Text(r)),
                    ],
                    onChanged: (v) => setState(() => _role = v ?? _role),
                  ),
                  const SizedBox(height: Gap.lg),
                  const FieldLabel('Phone number'),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      hintText: 'e.g. 024 000 0000',
                    ),
                  ),
                  const SizedBox(height: Gap.lg),
                  const FieldLabel('Notes'),
                  TextField(
                    controller: _notes,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'What they agreed to do',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Gap.lg),
            SectionCard(
              title: 'SMS handoff',
              subtitle:
                  'The message below can be sent to the supporter. The app does '
                  'not send it automatically — tap to open your SMS app.',
              icon: Icons.sms_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(Gap.md),
                    decoration: BoxDecoration(
                      color: AppColors.canvas,
                      borderRadius: BorderRadius.circular(Gap.radiusSm),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Text(
                      _message,
                      style: AppType.body.copyWith(height: 1.45),
                    ),
                  ),
                  const SizedBox(height: Gap.md),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _copyMessage,
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text('Copy message'),
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _openSms,
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: const Text('Open SMS app'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: Gap.lg),
              _ErrorBox(_error!),
            ],
            const SizedBox(height: Gap.xl),
            FilledButton(
              onPressed: _busy ? null : _saveAndHandOff,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save and continue'),
            ),
            const SizedBox(height: Gap.md),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: const Text('Skip community support'),
            ),
            const SizedBox(height: Gap.xl),
          ],
        ),
      ),
    );
  }

  /// Hands the message to the phone's SMS app, addressed to the supporter
  /// when their number is known. If this device cannot open one — a tablet,
  /// the web preview — the message is copied instead, so it is never lost.
  Future<void> _openSms() async {
    final phone = _phone.text.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse(
      'sms:$phone?body=${Uri.encodeComponent(_message)}',
    );
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return;
      }
    } catch (_) {
      // Fall through to the clipboard.
    }
    if (!mounted) return;
    _copyMessage();
  }

  void _copyMessage() {
    Clipboard.setData(ClipboardData(text: _message));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Message copied. Paste it into your SMS app to send to ${_name.text.trim().isEmpty ? 'the supporter' : _name.text.trim()}.',
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Gap.md),
    decoration: BoxDecoration(
      color: AppColors.triageRedBg,
      borderRadius: BorderRadius.circular(Gap.radiusSm),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          size: 18,
          color: AppColors.triageRed,
        ),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: AppColors.triageRed,
              fontSize: 13.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
