/// Sign-in.
///
/// A real, local sign-in: phone number + PIN/password. No demo shortcuts, no
/// mock accounts. The session is verified against the on-device user store.
///
/// Two paths land here:
///   1. A returning user who has signed out, or who is opening the app for
///      the first time on a device that already has an account on it.
///   2. A fresh-install user who has just picked a role on "Who are you?"
///      and is being routed through the sign-in screen so the existing-
///      user shortcut is always one tap away.
///
/// In both cases, "Create a new account" below the form takes the user to
/// the registration flow. For a returning signed-out user, the role choice
/// is shown again. For a fresh install, the role chosen on the previous
/// screen is carried through and applied to the right form.
///
/// A "Remember me" checkbox keeps the phone number filled for the next
/// launch. Forgot-password is a local reset flow: if the phone is
/// registered on this device, the user can set a new PIN after a simple
/// self-check.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import '../../core/auth/session.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../shared/ui.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _rememberMe = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRememberedPhone();
  }

  Future<void> _loadRememberedPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('remembered_phone');
    if (saved != null && mounted) {
      setState(() {
        _phone.text = saved;
        _rememberMe = true;
      });
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _saveRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('remembered_phone', _phone.text.trim());
    } else {
      await prefs.remove('remembered_phone');
    }
  }

  Future<void> _submit() async {
    if (_phone.text.trim().length < 9) {
      setState(() => _error = 'Enter the phone number for this account.');
      return;
    }
    if (_password.text.trim().length < 4) {
      setState(() => _error = 'Enter your PIN or password.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    await _saveRememberMe();

    final ok = await ref.read(sessionProvider.notifier).signIn(
      phone: _phone.text.trim(),
      pin: _password.text.trim(),
    );

    if (!mounted) return;
    if (!ok) {
      final state = ref.read(sessionProvider);
      setState(() {
        _busy = false;
        _password.clear();
        _error = state is SessionSignedOut
            ? (state.message ?? 'That did not work. Try again.')
            : 'That did not work. Try again.';
      });
    }
  }

  void _forgotPassword() {
    // Navigate directly to the Forgot PIN reset screen.
    context.go(Routes.forgotPin);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          tooltip: 'Back to role selection',
          onPressed: () {
            ref.read(pendingRoleProvider.notifier).state = null;
            ref.read(sessionProvider.notifier).markNeedsSetup();
            context.go(Routes.setup);
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.xl,
              vertical: Gap.xxl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Brand(),
                  const SizedBox(height: Gap.xxl),

                  const FieldLabel('Phone number'),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    autocorrect: false,
                    style: AppType.bodyLarge,
                    decoration: const InputDecoration(
                      hintText: '024 000 0000',
                      prefixIcon: Icon(Icons.phone_outlined, size: 19),
                    ),
                  ),
                  const SizedBox(height: Gap.xl),

                  const FieldLabel('PIN or password'),
                  TextField(
                    controller: _password,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    autocorrect: false,
                    maxLength: 6,
                    style: AppType.bodyLarge,
                    decoration: const InputDecoration(
                      hintText: 'Enter your 4-digit PIN',
                      prefixIcon: Icon(Icons.lock_outline, size: 19),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: Gap.sm),

                  Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _rememberMe,
                          onChanged: (v) {
                            setState(() => _rememberMe = v ?? false);
                          },
                          activeColor: AppColors.ink,
                          side: const BorderSide(color: AppColors.lineStrong),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Gap.radiusSm),
                          ),
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                      Text('Remember me', style: AppType.label),
                      const Spacer(),
                      TextButton(
                        onPressed: _busy ? null : _forgotPassword,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Forgot PIN?',
                          style: AppType.label.copyWith(
                            color: AppColors.accent,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: Gap.lg),
                    Container(
                      padding: const EdgeInsets.all(Gap.md),
                      decoration: BoxDecoration(
                        color: AppColors.triageRedBg,
                        borderRadius: BorderRadius.circular(Gap.radiusSm),
                        border: Border.all(
                          color: AppColors.triageRed.withValues(alpha: 0.30),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 17,
                            color: AppColors.triageRed,
                          ),
                          const SizedBox(width: Gap.sm),
                          Expanded(
                            child: Text(
                              _error!,
                              style: AppType.label.copyWith(
                                color: AppColors.triageRed,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: Gap.xl),
                  GradientButton(
                    label: _busy ? 'Signing in…' : 'Sign in',
                    icon: Icons.login_rounded,
                    onPressed: _busy ? null : _submit,
                  ),
                  const SizedBox(height: Gap.md),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () {
                            ref
                                .read(sessionProvider.notifier)
                                .markNeedsSetup();
                            // `markNeedsSetup` is a no-op if the device is
                            // already in [SessionNeedsSetup] (a fresh
                            // install that just picked a role), so the
                            // redirect listener does not fire. Route
                            // explicitly to make the back stack land on
                            // the registration form, which reads the
                            // pending role chosen on the previous screen.
                            context.go(Routes.setup);
                          },
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 17),
                    label: const Text('Create a new account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The brand block: a quiet wordmark, not a logo tile.
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          shape: BoxShape.circle,
          boxShadow: const [AppShadows.glow],
        ),
        child: const Icon(
          Icons.favorite_rounded,
          color: Colors.white,
          size: 42,
        ),
      ),
      const SizedBox(height: Gap.lg),
      Text('CareBridge AI', style: AppType.display.copyWith(fontSize: 32)),
      const SizedBox(height: Gap.sm),
      Text(
        'AI-ASSISTED COMMUNITY HEALTHCARE',
        style: AppType.eyebrow.copyWith(
          letterSpacing: 2.0,
          color: AppColors.primary,
          fontSize: 10.5,
        ),
      ),
      const SizedBox(height: Gap.md),
      Text(
        'Nurturing care for mothers and children,\n'
        'with or without a network.',
        textAlign: TextAlign.center,
        style: AppType.caption.copyWith(fontSize: 13.5, height: 1.55),
      ),
    ],
  );
}
