package gh.carebridge.carebridge_ai

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

/**
 * Screen-capture protection on the field build.
 *
 * A CHPS handset carries a living district register. Without `FLAG_SECURE` it can
 * be screen-recorded, mirrored into a meeting room, or captured to a gallery where
 * the phone's owner has no further control and no idea it happened — and on Android
 * the recent-apps thumbnail is written to disk by the system regardless of the app,
 * so a name on screen becomes a name in someone else's gallery.
 *
 * `isDebuggable` is the gate rather than a build-time constant: a debug build stays
 * capturable so the screenshots that documentation, bug reports and a hackathon demo
 * depend on still exist. That is a deliberate, reviewable exception, not an oversight
 * — the artefact a district installs is the one that is protected.
 *
 * The cost is real and should be known rather than discovered: a health worker can no
 * longer screenshot a referral to carry it to a facility on paper. That is exactly why
 * the printed handoff brief exists, and it is signed for the same reason.
 */
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (!applicationInfo.flags.and(android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE).toBoolean()) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE
            )
        }
    }
}
