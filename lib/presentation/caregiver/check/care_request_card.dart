/// The family's request for help, and the only honest thing it can promise at
/// each moment: not yet asked, written but not sent, sent, answered.
///
/// The middle state is the trap. A queued row is not a person on a motorbike, so
/// every state that holds a request repeats the instruction the verdict already
/// gave. Nothing here infers delivery from elapsed time: `sent` is read from the
/// outbox by the controller, and `Check if it has been sent` is the family's own
/// way to ask the same question again.
///
/// The instruction line is prefixed rather than quoted bare. The result page's
/// own headline already carries that exact sentence, and a second copy of it on
/// the same screen would read as a rendering fault, not as emphasis.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/care_request.dart';
import '../../../domain/enums.dart';
import '../widgets/companion.dart';
import '../widgets/premium_button.dart';

class CareRequestCard extends StatelessWidget {
  const CareRequestCard({
    super.key,
    required this.urgent,
    required this.verdictLabel,
    required this.request,
    required this.sent,
    required this.sending,
    required this.error,
    required this.onAsk,
    required this.onWithdraw,
    required this.onRefresh,
  });

  final bool urgent;

  /// `HomeCheckVerdict.label` — the same reviewed sentence the verdict button
  /// speaks, so the card cannot tell the family something milder.
  final String verdictLabel;
  final CareRequest? request;
  final bool sent;
  final bool sending;
  final String? error;
  final VoidCallback onAsk;
  final VoidCallback onWithdraw;
  final VoidCallback onRefresh;

  bool get _answered => request?.status == CareRequestStatus.answered;

  String get _title => switch (request) {
    null => 'Ask a health worker to come',
    _ when _answered => 'Your health worker answered',
    _ when sent => 'Reached your health worker',
    _ => 'Waiting for network',
  };

  String get _body => switch (request) {
    null =>
      'The request sends the name of the family member you are worried about '
          'and how urgent the check said it is. It does not send your answers.',
    _ when _answered =>
      'They have read your request. A reply is not the same thing as someone '
          'arriving.',
    _ when sent =>
      'Your health worker has your request. Whether they can come depends on '
          'the rest of their day.',
    _ =>
      'Your phone has not reached the network yet, so nobody has been told. '
          'This is not a call-out and will not bring anyone today.',
  };

  @override
  Widget build(BuildContext context) {
    final asked = request != null;
    return CompanionCard(
      title: _title,
      eyebrow: asked ? 'YOUR REQUEST' : 'FROM THIS CHECK',
      tone: urgent ? AppColors.triageRed : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_body, style: caregiverBody()),
          if (asked) ...[
            const SizedBox(height: 12),
            Text(
              'The check said: $verdictLabel',
              style: caregiverBody(
                size: 15,
                color: urgent ? AppColors.triageRed : CompanionColors.ink,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: caregiverBody(size: 14, color: AppColors.triageRed),
            ),
          ],
          if (sending)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          else if (!asked)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: PremiumCheckButton(
                label: 'Ask for help',
                icon: Icons.campaign_outlined,
                trailingIcon: Icons.arrow_forward_rounded,
                height: 54,
                onPressed: onAsk,
              ),
            )
          else if (!_answered && !sent)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Check if it has been sent'),
                  ),
                  TextButton.icon(
                    onPressed: onWithdraw,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.triageRed,
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Cancel the request'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
