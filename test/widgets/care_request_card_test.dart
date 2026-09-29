/// What the card may and may not promise.
///
/// The waiting state is the dangerous one: a family who believes the app has
/// already called someone may decide not to walk. So every state that holds a
/// request repeats the instruction the verdict already gave, no state claims a
/// delivery the phone has not seen, and the primary control does the thing its
/// label says — which is why a withdrawn ask is a state the card enters, not a
/// button it disables.
library;

import 'package:carebridge_ai/domain/entities/care_request.dart';
import 'package:carebridge_ai/domain/enums.dart';
import 'package:carebridge_ai/presentation/caregiver/check/care_request_card.dart';
import 'package:carebridge_ai/presentation/caregiver/widgets/premium_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CareRequest _request({
  CareRequestStatus status = CareRequestStatus.open,
  CareRequestLevel level = CareRequestLevel.urgent,
}) => CareRequest(
  id: 'req-chk-1',
  householdId: 'family',
  personId: 'baby',
  level: level,
  homeCheckId: 'chk-1',
  createdBy: 'caregiver',
  createdAt: DateTime(2026, 9, 28, 9),
  updatedAt: DateTime(2026, 9, 28, 9),
  status: status,
);

int asks = 0, withdraws = 0, refreshes = 0;

Future<void> _pump(
  WidgetTester tester, {
  CareRequest? request,
  bool sent = false,
  bool sending = false,
  String? error,
  HomeCheckVerdict verdict = HomeCheckVerdict.urgent,
}) {
  asks = 0;
  withdraws = 0;
  refreshes = 0;
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CareRequestCard(
            urgent: verdict == HomeCheckVerdict.urgent,
            verdictLabel: verdict.label,
            request: request,
            sent: sent,
            sending: sending,
            error: error,
            onAsk: () => asks++,
            onWithdraw: () => withdraws++,
            onRefresh: () => refreshes++,
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('before the family asks', () {
    testWidgets('the ask is a real button that asks', (tester) async {
      await _pump(tester);
      expect(find.text('Ask a health worker to come'), findsOneWidget);
      expect(
        find.widgetWithText(PremiumCheckButton, 'Ask for help'),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(PremiumCheckButton, 'Ask for help'),
      );
      expect(asks, 1);
    });

    testWidgets('the offer says what leaves the phone and what does not',
        (tester) async {
      await _pump(tester);
      expect(find.textContaining('It does not send your answers'), findsOneWidget);
    });

    testWidgets('nothing is promised about a request that does not exist',
        (tester) async {
      await _pump(tester);
      expect(find.text('Waiting for network'), findsNothing);
      expect(find.text('Reached your health worker'), findsNothing);
      expect(find.text('Cancel the request'), findsNothing);
    });

    testWidgets('sending shows work and offers nothing else', (tester) async {
      await _pump(tester, sending: true);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.widgetWithText(PremiumCheckButton, 'Ask for help'),
        findsNothing,
      );
    });

    testWidgets('a failed write is named, and the ask stays available',
        (tester) async {
      await _pump(
        tester,
        error: 'Your phone could not write the request. Nothing was sent.',
      );
      expect(find.textContaining('Nothing was sent'), findsOneWidget);
      expect(
        find.widgetWithText(PremiumCheckButton, 'Ask for help'),
        findsOneWidget,
      );
    });
  });

  group('a request that has not left the phone', () {
    testWidgets('it is called waiting, and says plainly that nobody knows',
        (tester) async {
      await _pump(tester, request: _request());
      expect(find.text('Waiting for network'), findsOneWidget);
      expect(find.textContaining('not a call-out'), findsOneWidget);
      expect(find.text('Reached your health worker'), findsNothing);
      expect(find.textContaining('answered'), findsNothing);
    });

    testWidgets('the verdict instruction is on the card, once', (tester) async {
      await _pump(tester, request: _request());
      expect(
        find.text('The check said: Go to the health facility now'),
        findsOneWidget,
      );
    });

    testWidgets('a caution request asks for a visit soon, not an emergency',
        (tester) async {
      await _pump(
        tester,
        request: _request(level: CareRequestLevel.today),
        verdict: HomeCheckVerdict.caution,
      );
      expect(find.text('The check said: Visit the CHW soon'), findsOneWidget);
      expect(find.textContaining('Go to the health facility'), findsNothing);
    });

    testWidgets('it can be called back, and the network checked',
        (tester) async {
      await _pump(tester, request: _request());
      await tester.tap(find.text('Check if it has been sent'));
      expect(refreshes, 1);
      await tester.tap(find.text('Cancel the request'));
      expect(withdraws, 1);
    });
  });

  group('once the server has it', () {
    testWidgets('sent reads as reached, and the cancel goes away',
        (tester) async {
      await _pump(tester, request: _request(), sent: true);
      expect(find.text('Reached your health worker'), findsOneWidget);
      expect(find.text('Waiting for network'), findsNothing);
      expect(find.text('Cancel the request'), findsNothing);
      expect(
        find.text('The check said: Go to the health facility now'),
        findsOneWidget,
      );
    });

    testWidgets('an answered request stops telling the family to act alone',
        (tester) async {
      await _pump(
        tester,
        request: _request(status: CareRequestStatus.answered),
        sent: true,
      );
      expect(find.text('Your health worker answered'), findsOneWidget);
      expect(find.text('Cancel the request'), findsNothing);
      expect(
        find.text('The check said: Go to the health facility now'),
        findsOneWidget,
      );
    });
  });
}
