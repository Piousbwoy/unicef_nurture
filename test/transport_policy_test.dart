/// The transport rule: where health data may be sent, and where it may not.
///
/// Two things are pinned here that are easy to get wrong and quiet when they do.
/// The first is that the refusal fires **before** [PlatformHttpClient]'s test
/// seam — a control that a fake could step around is not a control. The second is
/// that a refused address is reported as permanent rather than as a network
/// problem, because the difference decides whether a worker retries all morning or
/// goes and asks for the right address.
library;

import 'package:carebridge_ai/data/sync/http_client.dart';
import 'package:carebridge_ai/data/sync/transport_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the transport policy', () {
    test('a release build will not send records in plaintext', () {
      final refusal = TransportPolicy.refusalFor(
        Uri.parse('http://192.168.1.9:3000'),
        development: false,
      );
      expect(refusal, isNotNull);
      // Says what to do, and names the fix. "Network error" would send her back
      // to the same address with the same result.
      expect(refusal, contains('https://'));
      expect(refusal, isNot(contains('network')));
    });

    test('a secure address is always allowed', () {
      expect(
        TransportPolicy.refusalFor(
          Uri.parse('https://district.example.org'),
          development: false,
        ),
        isNull,
      );
    });

    test('a development or rehearsal build may use the LAN laptop', () {
      // Without this, the control gets deleted after it breaks a demo rather than
      // tuned. The release posture above is the one that matters.
      expect(
        TransportPolicy.refusalFor(
          Uri.parse('http://192.168.1.9:3000'),
          development: true,
        ),
        isNull,
      );
    });

    test('a non-web scheme is refused with the scheme named', () {
      final refusal = TransportPolicy.refusalFor(
        Uri.parse('ftp://district.example.org'),
        development: false,
      );
      expect(refusal, contains('ftp'));
    });
  });

  group('the rule at the one HTTP door', () {
    bool seamReached = false;

    setUp(() {
      seamReached = false;
      // Static state is shared across the whole file, so it is restored after
      // each test rather than left set — a leaked `false` here would make every
      // later plaintext request in the suite fail for the wrong reason.
      addTearDown(() => PlatformHttpClient.allowInsecureTransports = true);
      PlatformHttpClient.override = (method, uri, headers, body) async {
        seamReached = true;
        return const HttpReply(200, '{}');
      };
      addTearDown(() => PlatformHttpClient.override = null);
    });

    test('a plaintext POST never reaches the network layer', () async {
      PlatformHttpClient.allowInsecureTransports = false;

      expect(
        () => PlatformHttpClient.post(
          Uri.parse('http://district.example.org/api/sync'),
          body: '{"payload":"a child record"}',
        ),
        throwsA(
          isA<HttpFailure>().having(
            (f) => f.kind,
            'kind',
            HttpFailureKind.insecureTransport,
          ),
        ),
      );
      // The point of the assertion. The guard sits before the test seam, so no
      // caller and no fake can find a way around it.
      expect(seamReached, isFalse);
    });

    test('a secure address goes through normally', () async {
      PlatformHttpClient.allowInsecureTransports = false;
      final reply = await PlatformHttpClient.post(
        Uri.parse('https://district.example.org/api/sync'),
        body: '{}',
      );
      expect(reply.statusCode, 200);
      expect(seamReached, isTrue);
    });

    test('the refusal survives the taxonomy callers already handle', () async {
      // Callers switch exhaustively over the kinds; an unclassified failure would
      // land in a generic catch and be reported as a network error.
      PlatformHttpClient.allowInsecureTransports = false;
      try {
        await PlatformHttpClient.get(
          Uri.parse('http://district.example.org/api/pull'),
        );
        fail('expected HttpFailure');
      } on HttpFailure catch (e) {
        expect(e.kind, HttpFailureKind.insecureTransport);
        expect(e.toString(), contains('insecureTransport'));
      }
    });
  });
}
