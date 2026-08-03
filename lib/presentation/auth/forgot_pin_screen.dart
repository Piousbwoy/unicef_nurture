/// Forgot PIN — master flow screen [6].
///
/// A device-local reset flow because there is no SMS gateway in this build.
/// The user enters the phone number that is registered on this device, then
/// sets a new PIN. The screen is deliberately a full route, not a dialog, so
/// the keyboard never fights a card edge on a small phone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/auth/session.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/user_dao.dart';
import '../shared/ui.dart';

class ForgotPinScreen extends ConsumerStatefulWidget {
  const ForgotPinScreen({super.key});

  @override
  ConsumerState<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends ConsumerState<ForgotPinScreen> {
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  final _pinConfirm = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _phoneVerified = false;
  bool _phoneChecking = false;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider);
    if (session is SessionSignedOut && session.lastPhone != null) {
      _phone.text = session.lastPhone!;
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _pin.dispose();
    _pinConfirm.dispose();
    super.dispose();
  }

  Future<void> _verifyPhone() async {
    final phone = _phone.text.trim();
    if (phone.length < 9) {
      setState(() => _error = 'Enter the phone number for this account.');
      return;
    }
    setState(() {
      _phoneChecking = true;
      _error = null;
    });
    final user = await UserDao.byPhone(phone);
    if (!mounted) return;
    setState(() {
      _phoneChecking = false;
      _phoneVerified = user != null;
      _error = user == null
          ? 'No account found for that phone number on this device.'
          : null;
    });
  }

  Future<void> _submit() async {
    final pinProblem = Credentials.validatePin(_pin.text);
    if (pinProblem != null) {
      setState(() => _error = pinProblem);
      return;
    }
    if (_pin.text != _pinConfirm.text) {
      setState(() => _error = 'The two PINs do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref
        .read(sessionProvider.notifier)
        .resetPin(phone: _phone.text.trim(), newPin: _pin.text.trim());
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN updated. Sign in with your new PIN.')),
      );
      context.go(Routes.signIn);
    } else {
      setState(() {
        _busy = false;
        _error = 'Could not reset PIN. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () {
            if (_phoneVerified) {
              setState(() {
                _phoneVerified = false;
                _pin.clear();
                _pinConfirm.clear();
                _error = null;
              });
            } else {
              context.go(Routes.signIn);
            }
          },
        ),
        title: const Text('Reset your PIN'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.xl,
              vertical: Gap.xl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Brand mark for visual consistency.
                  Center(
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        shape: BoxShape.circle,
                        boxShadow: const [AppShadows.glow],
                      ),
                      child: const Icon(
                        Icons.lock_reset_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.lg),
                  Text(
                    _phoneVerified
                        ? 'Set a new PIN'
                        : 'Reset your PIN',
                    textAlign: TextAlign.center,
                    style: AppType.headline,
                  ),
                  const SizedBox(height: Gap.sm),
                  Text(
                    _phoneVerified
                        ? 'Choose a 4-digit PIN you will remember. Anyone with '
                            'this device will use it to sign in.'
                        : 'A reset link cannot be sent without a network SMS '
                            'gateway. Because the phone is registered on this '
                            'device, you can set a new PIN directly.',
                    textAlign: TextAlign.center,
                    style: AppType.body.copyWith(color: AppColors.inkMuted),
                  ),
                  const SizedBox(height: Gap.xl),

                  if (!_phoneVerified) ...[
                    const FieldLabel('Phone number', required: true),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            autocorrect: false,
                            style: AppType.bodyLarge,
                            decoration: const InputDecoration(
                              hintText: '024 000 0000',
                              prefixIcon: Icon(
                                Icons.phone_outlined,
                                size: 19,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: Gap.sm),
                        SizedBox(
                          height: Gap.tapTarget,
                          child: FilledButton(
                            onPressed: _phoneChecking ? null : _verifyPhone,
                            child: _phoneChecking
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Verify'),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(Gap.md),
                      decoration: BoxDecoration(
                        color: AppColors.triageGreenBg,
                        borderRadius: BorderRadius.circular(Gap.radiusSm),
                        border: Border.all(
                          color: AppColors.triageGreen.withValues(alpha: 0.30),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_outline_rounded,
                            color: AppColors.triageGreen,
                            size: 18,
                          ),
                          const SizedBox(width: Gap.sm),
                          Expanded(
                            child: Text(
                              'Phone ${_phone.text.trim()} verified',
                              style: AppType.label.copyWith(
                                color: AppColors.triageGreen,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Gap.lg),
                    const FieldLabel('New PIN', required: true),
                    TextField(
                      controller: _pin,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 4,
                      style: AppType.bodyLarge,
                      decoration: const InputDecoration(
                        hintText: '4 digits',
                        counterText: '',
                        prefixIcon: Icon(Icons.lock_outline, size: 19),
                      ),
                    ),
                    const SizedBox(height: Gap.md),
                    const FieldLabel('Confirm new PIN', required: true),
                    TextField(
                      controller: _pinConfirm,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 4,
                      style: AppType.bodyLarge,
                      decoration: const InputDecoration(
                        hintText: 'Repeat your PIN',
                        counterText: '',
                        prefixIcon: Icon(Icons.lock_outline, size: 19),
                      ),
                    ),
                  ],

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
                  if (_phoneVerified)
                    GradientButton(
                      label: _busy ? 'Resetting…' : 'Reset PIN',
                      icon: Icons.lock_open_rounded,
                      onPressed: _busy ? null : _submit,
                    )
                  else
                    const SizedBox.shrink(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
