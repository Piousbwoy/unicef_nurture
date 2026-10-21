/// Which network address health data is allowed to travel over.
///
/// ### Why the rule lives in the app and not only in the platform config
///
/// Android's network security configuration and iOS's App Transport Security both
/// enforce TLS, and neither of them exists on the platforms this app actually runs
/// on today: the web build, which is what the launch configurations produce, and
/// the desktop build, which is what a district office would use. A rule that only
/// an operating system can apply is a rule that most deployments of this app do not
/// have. So the refusal sits in the one door every sync request already passes
/// through — [PlatformHttpClient.send] — and covers every platform at once,
/// including the ones nobody has configured yet.
///
/// ### What "development" means here
///
/// Cleartext is permitted in a debug or demonstration build. Not because plaintext
/// patient data is acceptable, but because the alternative is a control that
/// refuses to run against a district laptop on a LAN cable during rehearsal — and
/// controls that break demos get deleted wholesale rather than loosened
/// conditionally. A debug or demo build is not what a district installs: this flag
/// is false in a release build with demo mode off, and that is the posture that
/// matters.
///
/// ### Why the message says what to do
///
/// A worker in Savelugu shown "network error" retries until the battery dies. A
/// worker shown which part of the address is wrong either fixes it or reports the
/// exact thing that is broken, which is the difference between a control and an
/// obstacle.
library;

abstract final class TransportPolicy {
  /// Why this address must not be used, or null when it may be.
  static String? refusalFor(Uri uri, {required bool development}) {
    if (development) return null;
    if (uri.isScheme('https')) return null;
    if (uri.isScheme('http')) {
      return 'This build will not send health records over an unencrypted '
          'connection. The sync server address must start with https:// — ask '
          'the district IT officer for the secure address.';
    }
    return 'The sync server address has to be a web address (http:// or '
        'https://), not "${uri.scheme}".';
  }
}
