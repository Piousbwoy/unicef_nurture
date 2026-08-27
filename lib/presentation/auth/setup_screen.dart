/// Account setup.
///
/// The two roles — frontline health worker and caregiver — are not variations
/// of each other, and the form each one fills is genuinely different.
///
/// A **frontline health worker** is registering a professional identity: the
/// zone they cover, the facility they refer to, their staff number. Every one
/// of those fields is load-bearing later — the zone decides whose households
/// appear in the day plan, the facility is printed on referral slips.
///
/// A **caregiver** is being given access to one family. They enter a family
/// code the health worker reads out, and the account is bound to that
/// household for good. There is no field on this form that could widen that
/// scope, which is the point: scope is decided at creation, not at every read.
///
/// The role is picked on the "Who are you?" screen first; the sign-in screen
/// sits in between (so an existing user can sign in without scrolling past
/// the form), and "Create a new account" on the sign-in screen brings the
/// user back here with the chosen role pre-applied.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/auth/session.dart';
import '../../core/i18n/dagbani_strings.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/household_dao.dart';
import '../../data/local/preferences_store.dart';
import '../../data/local/user_dao.dart';
import '../../data/reference/northern_ghana.dart';
import '../../domain/entities/core.dart';
import '../../domain/enums.dart';
import '../../domain/family_code.dart';
import '../shared/app_image.dart';
import '../shared/audio_button.dart';
import '../shared/ui.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  UserRole? _role;

  @override
  void initState() {
    super.initState();
    // The role choice routes through sign-in (master flow: onboarding ->
    // "Who are you?" -> sign-in -> "Create a new account" -> this screen). When
    // it does, the role the user picked is sitting in [pendingRoleProvider];
    // consume it so we land on the correct registration form rather than
    // re-asking "Who are you?".
    final pending = ref.read(pendingRoleProvider);
    if (pending != null) {
      _role = pending;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_role == null) {
      return _RoleChoice(onPick: (r) => _pickRole(context, r));
    }
    return _RegistrationForm(
      role: _role!,
      onBack: () {
        // Return to Sign In screen in chronological navigation order:
        // Role Choice -> Sign In -> Sign Up (Registration Form).
        context.go(Routes.signIn);
      },
    );
  }

  /// Records the picked role and routes to the sign-in screen. "Create a new
  /// account" on that screen will bring us back here with the role already
  /// pre-applied (see [_SetupScreenState.initState]).
  void _pickRole(BuildContext context, UserRole role) {
    ref.read(pendingRoleProvider.notifier).state = role;
    context.go(Routes.signIn);
  }
}

// ------------------------------------------------------------------ Role choice

class _RoleChoice extends ConsumerWidget {
  const _RoleChoice({required this.onPick});

  final ValueChanged<UserRole> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The same white-air, royal-blue "Clinical Luxe" canvas as the onboarding
    // slides, so picking a role reads as the next slide rather than a new app.
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            const _BrandHeader(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  Gap.lg,
                  Gap.md,
                  Gap.lg,
                  Gap.lg,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 490),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'STEP 1 OF 2 · WELCOME',
                          textAlign: TextAlign.center,
                          style: AppType.eyebrow.copyWith(
                            color: AppColors.primary,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: Gap.sm),
                        Text(
                          'Who are you?',
                          textAlign: TextAlign.center,
                          style: AppType.display.copyWith(fontSize: 32),
                        ),
                        const SizedBox(height: 10),
                        // Brand-gradient accent drop beneath the question.
                        Center(
                          child: Container(
                            width: 48,
                            height: 4,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              gradient: AppColors.brandGradient,
                            ),
                          ),
                        ),
                        const SizedBox(height: Gap.md),
                        Text(
                          'This decides what the app will let you do. It cannot be '
                          'changed afterwards without a new account.',
                          textAlign: TextAlign.center,
                          style: AppType.body.copyWith(
                            color: AppColors.inkMuted,
                            height: 1.65,
                          ),
                        ),
                        const SizedBox(height: Gap.xl),
                        AppMotion.reveal(
                          _RoleCard(
                            image: AppImages.fhwHero,
                            iconBadge: Icons.medical_services_rounded,
                            title: 'Frontline Health Worker',
                            subtitle:
                                'CHPS member, nurse, community health volunteer',
                            role: UserRole.frontlineHealthWorker,
                            onPick: onPick,
                          ),
                          distance: 16,
                        ),
                        const SizedBox(height: Gap.md),
                        AppMotion.reveal(
                          _RoleCard(
                            image: AppImages.caregiverHero,
                            iconBadge: Icons.family_restroom_rounded,
                            title: 'Caregiver',
                            subtitle:
                                'Family member caring for someone at home',
                            role: UserRole.caregiver,
                            onPick: onPick,
                          ),
                          distance: 16,
                        ),
                        const SizedBox(height: Gap.xl),
                        Center(
                          child: TextButton.icon(
                            onPressed: () => _showIntroAgain(context),
                            icon: const Icon(Icons.replay_rounded, size: 16),
                            label: const Text('Show intro screens again'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.inkMuted,
                              padding: const EdgeInsets.symmetric(
                                horizontal: Gap.md,
                                vertical: Gap.sm,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Re-runs the onboarding slides. Useful for new users on a shared device
  /// and for showing the intro in demos without having to clear app data.
  Future<void> _showIntroAgain(BuildContext context) async {
    await PreferencesStore.reset();
    if (!context.mounted) return;
    context.go(Routes.onboarding);
  }
}

/// Brand header matching the onboarding slides' top row exactly — the same
/// gradient tile + wordmark — so the role choice reads as the next slide.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [AppShadows.glow],
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: Gap.sm),
          Text(
            'CareBridge AI',
            style: GoogleFonts.sora(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.image,
    required this.iconBadge,
    required this.title,
    required this.subtitle,
    required this.role,
    required this.onPick,
  });

  final String image;
  final IconData iconBadge;
  final String title;
  final String subtitle;
  final UserRole role;
  final ValueChanged<UserRole> onPick;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Gap.radius);
    return PressScale(
      onTap: () => onPick(role),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.canvas,
          borderRadius: radius,
          border: Border.all(color: AppColors.line, width: Gap.hairline),
          boxShadow: const [AppShadows.card],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: radius,
              onTap: () => onPick(role),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The signature royal-blue ribbon the design system reserves
                  // for flagship surfaces.
                  const BrandAccent(height: 3.5),
                  Padding(
                    padding: const EdgeInsets.all(Gap.lg),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _RoleImage(image: image, iconBadge: iconBadge),
                        const SizedBox(width: Gap.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                title,
                                style: AppType.title.copyWith(
                                  fontSize: 19,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                subtitle,
                                style: AppType.caption.copyWith(
                                  fontSize: 13.5,
                                  height: 1.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Gap.sm),
                        _RoleChevron(onTap: () => onPick(role)),
                      ],
                    ),
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

/// The hero image tile on the left of a role card.
class _RoleImage extends StatelessWidget {
  const _RoleImage({required this.image, required this.iconBadge});

  final String image;
  final IconData iconBadge;

  @override
  Widget build(BuildContext context) {
    const size = 100.0;
    final radius = BorderRadius.circular(Gap.radiusSm);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceTint,
              borderRadius: radius,
              border: Border.all(color: AppColors.line, width: Gap.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: AppImage(src: image, borderRadius: radius),
          ),
          // Floating brand badge in the top-right.
          Positioned(
            top: -7,
            right: -7,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.32),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.brandGradient,
                ),
                child: Icon(iconBadge, size: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The "tap to continue" affordance on the right of a role card.
class _RoleChevron extends StatefulWidget {
  const _RoleChevron({this.onTap});

  final VoidCallback? onTap;

  @override
  State<_RoleChevron> createState() => _RoleChevronState();
}

class _RoleChevronState extends State<_RoleChevron> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          gradient: AppColors.brandGradient,
          shape: BoxShape.circle,
          boxShadow: [AppShadows.glow],
        ),
        child: AnimatedSlide(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          offset: _down ? const Offset(0.08, 0) : Offset.zero,
          child: const Icon(
            Icons.arrow_forward_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- The form

class _RegistrationForm extends ConsumerStatefulWidget {
  const _RegistrationForm({required this.role, required this.onBack});

  final UserRole role;
  final VoidCallback onBack;

  @override
  ConsumerState<_RegistrationForm> createState() => _RegistrationFormState();
}

class _RegistrationFormState extends ConsumerState<_RegistrationForm> {
  int _step = 0;
  bool _busy = false;
  String? _error;

  // Step 0: personal details
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  final _pinConfirm = TextEditingController();
  String _language = 'Dagbani';
  String _relationship = 'Mother';

  // Steps 1-3: location / work
  String _region = 'Northern Region';
  String? _district;
  String? _community;
  final _zone = TextEditingController();
  final _facility = TextEditingController();
  final _staffId = TextEditingController();

  // Caregiver link — two paths to the same place. A family that already
  // exists in the system is found by its code; a family the system has not
  // reached yet starts its own record here and the health worker adopts it
  // the first time they meet.
  final _familyCode = TextEditingController();
  Household? _linkedHousehold;
  bool _checkingCode = false;
  bool _selfCreate = false;
  final _familyName = TextEditingController();
  final _landmark = TextEditingController();

  // [11] Data & Privacy Notice — required, do not skip.
  bool _privacyAgreed = false;

  bool get _isFhw => widget.role.isFhw;

  /// Index of the privacy-consent step [11] in each wizard.
  int get _privacyStep => _isFhw ? 4 : 2;

  /// Index of the success step [12].
  int get _successStep => _isFhw ? 5 : 3;

  static const _stepTitles = [
    'Your details',
    'Region',
    'District',
    'Community / CHPS zone',
    'Data & privacy',
    'All set',
  ];

  @override
  void dispose() {
    for (final c in [
      _name,
      _phone,
      _pin,
      _pinConfirm,
      _zone,
      _facility,
      _staffId,
      _familyCode,
      _familyName,
      _landmark,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _next() async {
    if (_step == 1 &&
        !_isFhw &&
        !_selfCreate &&
        _linkedHousehold == null &&
        _familyCode.text.trim().isNotEmpty) {
      await _lookUpCode();
      if (_linkedHousehold == null) {
        return;
      }
    }
    final problem = _validateStep(_step);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _error = null;
      _step++;
    });
  }

  void _back() {
    if (_step == 0) {
      widget.onBack();
      return;
    }
    setState(() => _step--);
  }

  String? _validateStep(int step) {
    switch (step) {
      case 0:
        if (_name.text.trim().length < 3) return 'Enter your full name.';
        if (_phone.text.trim().length < 9) {
          return 'Enter a valid phone number.';
        }
        final pinProblem = Credentials.validatePin(_pin.text);
        if (pinProblem != null) return pinProblem;
        if (_pin.text != _pinConfirm.text) return 'The two PINs are different.';
        return null;
      case 1:
        if (_isFhw && _region.isEmpty) return 'Choose your region.';
        if (!_isFhw && _selfCreate) {
          if (_familyName.text.trim().length < 2) {
            return 'Enter your family name, e.g. “The Dawura family”.';
          }
          if (_district == null) return 'Choose your district.';
          if (_community == null) return 'Choose your community.';
          return null;
        }
        if (!_isFhw && _linkedHousehold == null) {
          return 'Enter the family code the health worker gave you, then tap Check.';
        }
        return null;
      case 2:
        if (_isFhw && _district == null) return 'Choose your district.';
        if (!_isFhw && !_privacyAgreed) {
          return 'Tap the agreement box to continue — your consent is required.';
        }
        return null;
      case 3:
        if (_isFhw && _community == null) return 'Choose your community.';
        return null;
      case 4:
        if (_isFhw && !_privacyAgreed) {
          return 'Tap the agreement box to continue — your consent is required.';
        }
        return null;
    }
    return null;
  }

  Future<void> _lookUpCode() async {
    setState(() {
      _checkingCode = true;
      _error = null;
      _linkedHousehold = null;
    });
    final household = await HouseholdDao.byFamilyCode(_familyCode.text);
    if (!mounted) return;
    setState(() {
      _checkingCode = false;
      _linkedHousehold = household;
      _error = household == null
          ? 'No family found with that code. Ask the health worker to read it '
                'again — it is six letters and numbers.'
          : null;
    });
  }

  Future<void> _pasteCode() async {
    final clip = await Clipboard.getData('text/plain');
    final text = clip?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clipboard is empty. Copy a family code or SMS first.'),
        ),
      );
      return;
    }

    if (text.startsWith('CAREBRIDGE_QR|')) {
      final decoded = FamilyCode.decodeQrPayload(text);
      if (decoded != null) {
        await HouseholdDao.upsert(decoded);
        if (!mounted) return;
        setState(() {
          _familyCode.text = FamilyCode.pretty(decoded.id);
          _linkedHousehold = decoded;
          _error = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⚡ Pasted digital QR pass! Household seeded in local SQLite.',
            ),
            backgroundColor: AppColors.triageGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    setState(() => _familyCode.text = text);
    await _lookUpCode();
  }

  /// [12] Account Created — success animation, ~1.5s, then the account is
  /// actually created and the router auto-routes by role.
  Future<void> _submit() async {
    final problem = _validateStep(_step);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _step = _successStep;
    });

    await Future<void>.delayed(const Duration(milliseconds: 1500));

    final household = _linkedHousehold;
    final userId = const Uuid().v4();
    final selfCreated = !_isFhw && _selfCreate;

    // A caregiver who starts their own family writes the household first, so
    // the account can be bound to it in the very same step. The record is
    // ordinary — SQLite plus sync outbox — and carries the caregiver's own id
    // as `createdBy`, which is how the FHW's caseload picks it up later.
    Household? ownHousehold;
    if (selfCreated) {
      ownHousehold = Household(
        id: const Uuid().v4(),
        name: _familyName.text.trim(),
        region: _region,
        district: _district!,
        community: _community!,
        createdBy: userId,
        headName: _name.text.trim(),
        contactPhone: _phone.text.trim(),
        landmark: _landmark.text.trim().isEmpty ? null : _landmark.text.trim(),
        createdAt: DateTime.now(),
      );
    }

    final user = AppUser(
      id: userId,
      fullName: _name.text.trim(),
      phone: _phone.text.trim(),
      role: widget.role,
      region: _isFhw ? _region : (household?.region ?? _region),
      district: _isFhw
          ? _district!
          : (household?.district ?? ownHousehold?.district ?? ''),
      community: _isFhw
          ? _community!
          : (household?.community ?? ownHousehold?.community ?? ''),
      chpsZone: _isFhw && _zone.text.trim().isNotEmpty
          ? _zone.text.trim()
          : null,
      facilityName: _isFhw && _facility.text.trim().isNotEmpty
          ? _facility.text.trim()
          : null,
      staffId: _isFhw && _staffId.text.trim().isNotEmpty
          ? _staffId.text.trim()
          : null,
      preferredLanguage: _language,
      createdAt: DateTime.now(),
    );

    try {
      if (ownHousehold != null) {
        await ref
            .read(careRepositoryProvider)
            .createOwnHousehold(user, ownHousehold);
      }
      final success = await ref
          .read(sessionProvider.notifier)
          .register(
            user: user,
            pin: _pin.text,
            linkedHouseholdId: household?.id ?? ownHousehold?.id,
          );
      if (!mounted) return;
      if (!success) {
        final session = ref.read(sessionProvider);
        final errorMsg = session is SessionSignedOut ? session.message : null;
        setState(() {
          _busy = false;
          _error =
              errorMsg ?? 'Could not complete registration. Please try again.';
          _step = _privacyStep;
        });
        return;
      }
      // Explicitly navigate to home screen upon successful registration
      context.go(Routes.homeFor(user.role));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
        // Never leave the wizard standing on the celebration step if the
        // account was not actually created.
        _step = _privacyStep;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isFhw
        ? _stepTitles[_step.clamp(0, _stepTitles.length - 1)]
        : switch (_step) {
            0 => 'Your details',
            1 => 'Your family',
            2 => 'Data & privacy',
            3 => 'All set',
            _ => 'Create account',
          };

    final isPrivacyStep = _step == _privacyStep;
    final isSuccess = _step == _successStep;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: (_busy || isSuccess) ? null : _back),
        title: Text(title),
      ),
      // The primary action lives in a persistent footer instead of the
      // scroll body: on a phone the form can exceed one screen, and a
      // submit button that needs scrolling to find feels broken. The CTA
      // stays visible on every step, one tap away.
      bottomNavigationBar: isSuccess
          ? null
          : SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(
                Gap.lg,
                Gap.xs,
                Gap.lg,
                Gap.lg,
              ),
              child: isPrivacyStep
                  ? GradientButton(
                      label: _isFhw
                          ? 'Agree & Create Account'
                          : 'Agree & Link My Family',
                      icon: Icons.verified_user_rounded,
                      onPressed: _busy ? null : _submit,
                    )
                  : GradientButton(
                      label: 'Continue',
                      onPressed: _busy ? null : _next,
                    ),
            ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Gap.lg),
          children: [
            _StepIndicator(step: _step, total: _successStep + 1),
            const SizedBox(height: Gap.lg),
            _buildStep(),
            if (_error != null) ...[
              const SizedBox(height: Gap.lg),
              _ErrorBox(_error!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    if (_step == _privacyStep) {
      return _PrivacyStep(
        agreed: _privacyAgreed,
        onChanged: (v) => setState(() => _privacyAgreed = v),
      );
    }
    if (_step == _successStep) {
      return _SuccessStep(isFhw: _isFhw);
    }

    if (_isFhw) {
      return switch (_step) {
        0 => _PersonalDetailsStep(
          name: _name,
          phone: _phone,
          pin: _pin,
          pinConfirm: _pinConfirm,
          language: _language,
          region: _region,
          isFhw: true,
          relationship: _relationship,
          onLanguageChanged: (v) => setState(() => _language = v),
          onRelationshipChanged: (v) => setState(() => _relationship = v),
        ),
        1 => _RegionStep(
          region: _region,
          onChanged: (v) => setState(() {
            _region = v;
            _district = null;
            _community = null;
          }),
        ),
        2 => _DistrictStep(
          region: _region,
          district: _district,
          onChanged: (v) => setState(() {
            _district = v;
            _community = null;
          }),
        ),
        3 => _CommunityStep(
          region: _region,
          district: _district,
          community: _community,
          zone: _zone,
          facility: _facility,
          staffId: _staffId,
          onCommunityChanged: (v) => setState(() => _community = v),
        ),
        _ => const SizedBox.shrink(),
      };
    }

    return switch (_step) {
      0 => _PersonalDetailsStep(
        name: _name,
        phone: _phone,
        pin: _pin,
        pinConfirm: _pinConfirm,
        language: _language,
        region: _region,
        isFhw: false,
        relationship: _relationship,
        onLanguageChanged: (v) => setState(() => _language = v),
        onRelationshipChanged: (v) => setState(() => _relationship = v),
      ),
      1 => _FamilyStep(
        code: _familyCode,
        household: _linkedHousehold,
        checking: _checkingCode,
        onCheck: _lookUpCode,
        onPaste: _pasteCode,
        selfCreate: _selfCreate,
        familyName: _familyName,
        landmark: _landmark,
        region: _region,
        district: _district,
        community: _community,
        onSelfCreateChanged: (v) => setState(() {
          _selfCreate = v;
          if (v) {
            _linkedHousehold = null;
            _district ??= null;
          }
        }),
        onRegionChanged: (v) => setState(() {
          _region = v;
          _district = null;
          _community = null;
        }),
        onDistrictChanged: (v) => setState(() {
          _district = v;
          _community = null;
        }),
        onCommunityChanged: (v) => setState(() => _community = v),
        onChanged: (_) {
          if (_linkedHousehold != null) {
            setState(() => _linkedHousehold = null);
          }
        },
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i <= step ? AppColors.accent : AppColors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (i < total - 1) const SizedBox(width: Gap.xs),
        ],
      ],
    );
  }
}

class _PersonalDetailsStep extends StatelessWidget {
  const _PersonalDetailsStep({
    required this.name,
    required this.phone,
    required this.pin,
    required this.pinConfirm,
    required this.language,
    required this.region,
    required this.isFhw,
    required this.relationship,
    required this.onLanguageChanged,
    required this.onRelationshipChanged,
  });

  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController pin;
  final TextEditingController pinConfirm;
  final String language;
  final String region;
  final bool isFhw;
  final String relationship;
  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<String> onRelationshipChanged;

  static const _relationships = [
    'Mother',
    'Father',
    'Grandmother',
    'Grandfather',
    'Aunt',
    'Uncle',
    'Guardian',
    'Other',
  ];

  @override
  Widget build(BuildContext context) {
    final languages = NorthernGhana.languagesOf(region);
    return SectionCard(
      title: 'About you',
      subtitle:
          'This phone may be shared, so your PIN is what keeps family records '
          'private.',
      icon: Icons.person_outline_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FieldLabel('Full name', required: true),
          TextField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'e.g. Abdul-Rahman Suleimana',
            ),
          ),
          const SizedBox(height: Gap.lg),
          const FieldLabel(
            'Phone number',
            required: true,
            why: 'This is how you sign in. It does not need airtime.',
          ),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: '024 000 0000'),
          ),
          const SizedBox(height: Gap.lg),
          if (!isFhw) ...[
            const FieldLabel(
              'Your relationship to the family',
              required: true,
              why:
                  'Shown to the health worker so they know who is checking in.',
            ),
            DropdownButtonFormField<String>(
              value: _relationships.contains(relationship)
                  ? relationship
                  : _relationships.first,
              isExpanded: true,
              items: [
                for (final r in _relationships)
                  DropdownMenuItem(
                    value: r,
                    child: Text(r, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => onRelationshipChanged(v ?? relationship),
            ),
            const SizedBox(height: Gap.lg),
          ],
          const FieldLabel(
            'Language for guidance',
            why:
                'Spoken advice will be played in this language. Tap the '
                'speaker to hear a sample.',
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: languages.contains(language)
                      ? language
                      : languages.first,
                  isExpanded: true,
                  items: [
                    for (final l in languages)
                      DropdownMenuItem(
                        value: l,
                        child: Text(l, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => onLanguageChanged(v ?? language),
                ),
              ),
              const SizedBox(width: Gap.sm),
              // Hear a sample in the currently selected language before
              // committing. The pill under the button shows which voice
              // would be used in real visits — honest, never oversold.
              AudioButton(
                text: _sampleScriptFor(language),
                language: language,
                id: 'setup_preview_$language',
                // The preview exists so a new user hears their language
                // before committing; the bank languages play their own
                // clip and the sheet shows the words actually spoken.
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: Gap.lg),
          const FieldLabel('New PIN', required: true),
          TextField(
            controller: pin,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 4,
            decoration: const InputDecoration(
              hintText: '4 digits',
              counterText: '',
            ),
          ),
          const SizedBox(height: Gap.md),
          const FieldLabel('Type it again', required: true),
          TextField(
            controller: pinConfirm,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 4,
            decoration: const InputDecoration(
              hintText: 'Repeat your PIN',
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }
}

class _RegionStep extends StatelessWidget {
  const _RegionStep({required this.region, required this.onChanged});

  final String region;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Region',
    subtitle: 'Start with the region where you work.',
    icon: Icons.location_on_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('Region', required: true),
        DropdownButtonFormField<String>(
          value: region,
          isExpanded: true,
          items: [
            for (final r in NorthernGhana.regionNames)
              DropdownMenuItem(
                value: r,
                child: Text(r, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => onChanged(v ?? region),
        ),
      ],
    ),
  );
}

class _DistrictStep extends StatelessWidget {
  const _DistrictStep({
    required this.region,
    required this.district,
    required this.onChanged,
  });

  final String region;
  final String? district;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final districts = NorthernGhana.districtsOf(region);
    return SectionCard(
      title: 'District',
      subtitle: 'Choose the district or municipality you work in.',
      icon: Icons.map_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FieldLabel(
            'District / Municipal / Metropolitan',
            required: true,
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('district-$region'),
            value: district,
            isExpanded: true,
            hint: const Text(
              'Choose your district',
              overflow: TextOverflow.ellipsis,
            ),
            items: [
              for (final d in districts)
                DropdownMenuItem(
                  value: d.name,
                  child: Text(
                    '${d.name} (${d.type.label})',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _CommunityStep extends StatelessWidget {
  const _CommunityStep({
    required this.region,
    required this.district,
    required this.community,
    required this.zone,
    required this.facility,
    required this.staffId,
    required this.onCommunityChanged,
  });

  final String region;
  final String? district;
  final String? community;
  final TextEditingController zone;
  final TextEditingController facility;
  final TextEditingController staffId;
  final ValueChanged<String?> onCommunityChanged;

  @override
  Widget build(BuildContext context) {
    final communities = district == null
        ? const <String>[]
        : NorthernGhana.communitiesOf(region, district!);
    return SectionCard(
      title: 'Community & CHPS zone',
      subtitle:
          'This decides which households appear in your day plan, and which '
          'facility is printed on your referral slips.',
      icon: Icons.place_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FieldLabel('Community', required: true),
          DropdownButtonFormField<String>(
            key: ValueKey('community-$district'),
            value: community,
            isExpanded: true,
            hint: Text(
              district == null
                  ? 'Choose a district first'
                  : 'Choose your community',
              overflow: TextOverflow.ellipsis,
            ),
            items: [
              for (final c in communities)
                DropdownMenuItem(
                  value: c,
                  child: Text(c, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: onCommunityChanged,
          ),
          const SizedBox(height: Gap.lg),
          const FieldLabel('CHPS zone'),
          TextField(
            controller: zone,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'e.g. Kpalsogu CHPS Zone',
            ),
          ),
          const SizedBox(height: Gap.lg),
          const FieldLabel(
            'Facility you refer to',
            why: 'Printed on referral slips so the family knows where to go.',
          ),
          TextField(
            controller: facility,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'e.g. Kumbungu District Hospital',
            ),
          ),
          const SizedBox(height: Gap.lg),
          const FieldLabel('Staff ID'),
          TextField(
            controller: staffId,
            decoration: const InputDecoration(hintText: 'e.g. GHS-NR-04821'),
          ),
        ],
      ),
    );
  }
}

/// Step 1 of the caregiver wizard: join your family.
///
/// Two honest paths, because both happen in real life:
///
/// **A code** — the health worker has registered the household and reads out
/// its six-character code. The account binds to that family.
///
/// **Start your own family** — no health worker has reached the compound yet,
/// or the household lives on a different phone. The caregiver creates the
/// family record themselves (name, district, community) and the health worker
/// adopts it the first time they meet. Without this path, caregiver sign-up
/// is a wall on any fresh device.
class _FamilyStep extends StatelessWidget {
  const _FamilyStep({
    required this.code,
    required this.household,
    required this.checking,
    required this.onCheck,
    required this.onPaste,
    required this.selfCreate,
    required this.familyName,
    required this.landmark,
    required this.region,
    required this.district,
    required this.community,
    required this.onSelfCreateChanged,
    required this.onRegionChanged,
    required this.onDistrictChanged,
    required this.onCommunityChanged,
    required this.onChanged,
  });

  final TextEditingController code;
  final Household? household;
  final bool checking;
  final VoidCallback onCheck;
  final VoidCallback onPaste;

  final bool selfCreate;
  final TextEditingController familyName;
  final TextEditingController landmark;
  final String region;
  final String? district;
  final String? community;
  final ValueChanged<bool> onSelfCreateChanged;
  final ValueChanged<String> onRegionChanged;
  final ValueChanged<String?> onDistrictChanged;
  final ValueChanged<String?> onCommunityChanged;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Your family',
    subtitle:
        'If the health worker registered your family, enter the six-character '
        'code they give you — or paste it if it arrived by SMS. If not, '
        'start your own family record and the health worker will pick it up '
        'the first time you meet.',
    icon: Icons.vpn_key_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!selfCreate) ...[
          Container(
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withOpacity(0.4),
              borderRadius: BorderRadius.circular(Gap.radiusSm),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.phonelink_ring_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: Gap.sm),
                    const Expanded(
                      child: Text(
                        'With the health worker right now?',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.xs),
                const Text(
                  'They can read the code out for you to type below, or send it by SMS. If it arrived as a message, paste it — no network needed.',
                  style: TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: Gap.md),
                OutlinedButton.icon(
                  onPressed: checking ? null : onPaste,
                  icon: const Icon(Icons.content_paste_rounded, size: 16),
                  label: const Text('Paste code from a message'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),
        ],
        const FieldLabel('Or type the 6-character code'),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: code,
                enabled: !selfCreate,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: 'ABC-D24'),
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: Gap.sm),
            SizedBox(
              height: Gap.tapTarget,
              // The theme's OutlinedButton style stretches to full width
              // (minimumSize: Size.fromHeight). Inside this Row the width is
              // unbounded, which makes the infinite minimum throw during
              // layout on web and blank the whole step — pin a width.
              width: 96,
              child: OutlinedButton(
                onPressed: checking || selfCreate ? null : onCheck,
                child: checking
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Check'),
              ),
            ),
          ],
        ),
        if (household != null) ...[
          const SizedBox(height: Gap.md),
          Container(
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              color: AppColors.triageGreenBg,
              borderRadius: BorderRadius.circular(Gap.radiusSm),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  color: AppColors.triageGreen,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        household!.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${household!.community}, ${household!.district}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: Gap.lg),
        // The second path. Selecting it clears any found household so the
        // two paths can never contradict each other.
        InkWell(
          onTap: () => onSelfCreateChanged(!selfCreate),
          borderRadius: BorderRadius.circular(Gap.radius),
          child: Container(
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              color: selfCreate ? AppColors.primaryLight : AppColors.surface,
              borderRadius: BorderRadius.circular(Gap.radius),
              border: Border.all(
                color: selfCreate ? AppColors.primary : AppColors.line,
                width: selfCreate ? 1.4 : Gap.hairline,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selfCreate
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selfCreate ? AppColors.primary : AppColors.inkFaint,
                  size: 22,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    'My family is not registered yet — start our own record',
                    style: AppType.body.copyWith(
                      fontSize: 14,
                      fontWeight: selfCreate
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (selfCreate) ...[
          const SizedBox(height: Gap.lg),
          const FieldLabel(
            'Family name',
            required: true,
            why: 'How your family will appear to your health worker.',
          ),
          TextField(
            controller: familyName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'e.g. The Dawura family',
            ),
          ),
          const SizedBox(height: Gap.lg),
          const FieldLabel('Region', required: true),
          DropdownButtonFormField<String>(
            value: region,
            isExpanded: true,
            items: [
              for (final r in NorthernGhana.regionNames)
                DropdownMenuItem(
                  value: r,
                  child: Text(r, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => onRegionChanged(v ?? region),
          ),
          const SizedBox(height: Gap.lg),
          const FieldLabel('District', required: true),
          DropdownButtonFormField<String>(
            key: ValueKey('district-$region'),
            value: district,
            isExpanded: true,
            hint: const Text(
              'Choose your district',
              overflow: TextOverflow.ellipsis,
            ),
            items: [
              for (final d in NorthernGhana.districtsOf(region))
                DropdownMenuItem(
                  value: d.name,
                  child: Text(d.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: onDistrictChanged,
          ),
          const SizedBox(height: Gap.lg),
          const FieldLabel('Community', required: true),
          DropdownButtonFormField<String>(
            key: ValueKey('community-$district'),
            value: community,
            isExpanded: true,
            hint: Text(
              district == null
                  ? 'Choose a district first'
                  : 'Choose your community',
              overflow: TextOverflow.ellipsis,
            ),
            items: [
              if (district != null)
                for (final c in NorthernGhana.communitiesOf(region, district!))
                  DropdownMenuItem(
                    value: c,
                    child: Text(c, overflow: TextOverflow.ellipsis),
                  ),
            ],
            onChanged: onCommunityChanged,
          ),
          const SizedBox(height: Gap.lg),
          const FieldLabel(
            'How to find your home',
            why:
                'No addresses here — “behind the mosque” is how the health '
                'worker finds you.',
          ),
          TextField(
            controller: landmark,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'e.g. Behind the primary school',
            ),
          ),
        ],
      ],
    ),
  );
}

/// [11] Data & Privacy Notice — a required, plain-language consent step. This is
/// the concrete follow-through on "protection of health data" and must never be
/// skipped or compressed away.
class _PrivacyStep extends StatelessWidget {
  const _PrivacyStep({required this.agreed, required this.onChanged});

  final bool agreed;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Your data, your control',
      subtitle:
          'Before we create your account, here is exactly how CareBridge AI '
          'keeps your information safe.',
      icon: Icons.verified_user_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PrivacyPoint(
            icon: Icons.phone_android_outlined,
            title: 'Stored on this phone',
            body:
                'Your records live on this device first. They are encrypted '
                'and protected by your PIN.',
          ),
          const SizedBox(height: Gap.lg),
          _PrivacyPoint(
            icon: Icons.cloud_sync_outlined,
            title: 'Only synced when you choose',
            body:
                'Information leaves this device only when you tap Sync and a '
                'network is available.',
          ),
          const SizedBox(height: Gap.lg),
          _PrivacyPoint(
            icon: Icons.people_outline_rounded,
            title: 'Seen only by the right people',
            body:
                'A caregiver sees only their own family. A health worker sees '
                'only the families in their zone.',
          ),
          const SizedBox(height: Gap.lg),
          _PrivacyPoint(
            icon: Icons.delete_outline_rounded,
            title: 'You can request deletion',
            body:
                'You can review or ask for your on-device data to be removed '
                'at any time in settings.',
          ),
          const SizedBox(height: Gap.xl),
          InkWell(
            onTap: () => onChanged(!agreed),
            borderRadius: BorderRadius.circular(Gap.radius),
            child: Container(
              padding: const EdgeInsets.all(Gap.md),
              decoration: BoxDecoration(
                color: agreed ? AppColors.primaryLight : AppColors.surface,
                borderRadius: BorderRadius.circular(Gap.radius),
                border: Border.all(
                  color: agreed ? AppColors.primary : AppColors.line,
                  width: agreed ? 1.4 : Gap.hairline,
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: agreed,
                      onChanged: (v) => onChanged(v ?? false),
                      activeColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.lineStrong),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Gap.radiusSm),
                      ),
                    ),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(
                      'I understand and agree to how my data will be used.',
                      style: AppType.body.copyWith(
                        fontSize: 14,
                        fontWeight: agreed ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyPoint extends StatelessWidget {
  const _PrivacyPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(Gap.sm),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(Gap.radiusSm),
          ),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppType.label.copyWith(fontSize: 14)),
              const SizedBox(height: Gap.xs),
              Text(body, style: AppType.caption.copyWith(height: 1.5)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SuccessStep extends StatefulWidget {
  const _SuccessStep({required this.isFhw});

  final bool isFhw;

  @override
  State<_SuccessStep> createState() => _SuccessStepState();
}

/// [12] Account Created — an animated confirmation. The account is actually
/// created (and the router auto-routes by role) after a short delay, so this
/// step just celebrates; there is no button to press.
class _SuccessStepState extends State<_SuccessStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: Gap.xl),
      Center(
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            padding: const EdgeInsets.all(Gap.xl),
            decoration: const BoxDecoration(
              gradient: AppColors.brandGradient,
              shape: BoxShape.circle,
              boxShadow: [AppShadows.glow],
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 56,
              color: AppColors.canvas,
            ),
          ),
        ),
      ),
      const SizedBox(height: Gap.xl),
      Text(
        'Your account is ready',
        textAlign: TextAlign.center,
        style: AppType.headline,
      ),
      const SizedBox(height: Gap.sm),
      Text(
        widget.isFhw
            ? 'You can now register households, run assessments, and start '
                  'follow-ups in your CHPS zone.'
            : 'You can now see your own family, check danger signs, and hear '
                  'guidance in your language.',
        textAlign: TextAlign.center,
        style: AppType.body.copyWith(color: AppColors.inkMuted),
      ),
      const SizedBox(height: Gap.xl),
      Center(
        child: Text(
          'Taking you to your home screen…',
          style: AppType.caption.copyWith(color: AppColors.inkFaint),
        ),
      ),
      const SizedBox(height: Gap.md),
      const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: AppColors.primary,
          ),
        ),
      ),
    ],
  );
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

/// Shows a household's family code so a CHO can read it out.
///
/// Lives here rather than in the FHW feature folder because it is the other half
/// of the caregiver sign-up above, and the two should not drift apart.
class FamilyCodeSheet extends StatelessWidget {
  const FamilyCodeSheet({super.key, required this.household});

  final Household household;

  @override
  Widget build(BuildContext context) {
    final qrData = FamilyCode.encodeQrPayload(household);
    final shortCode = FamilyCode.pretty(household.id);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(Gap.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.md,
              vertical: Gap.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'FAMILY CODE',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: Gap.sm),
          Text(
            household.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: Gap.xs),
          const Text(
            'The caregiver enters the code below when they set up their phone — it links their account to this family, no network needed. They can also scan the QR with any scanner app and paste what it reads.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.inkMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: Gap.lg),
          Container(
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(Gap.radius),
              border: Border.all(color: AppColors.lineStrong, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 180.0,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: AppColors.primary,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: Gap.lg),
          const Text(
            'READ IT OUT, OR SEND IT BY SMS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.inkMuted,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: Gap.xs),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.lg,
              vertical: Gap.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(Gap.radius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  shortCode,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 5,
                    color: AppColors.primary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: Gap.sm),
                IconButton(
                  tooltip: 'Copy to send by SMS or WhatsApp',
                  icon: const Icon(
                    Icons.copy_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: shortCode));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Code $shortCode copied — send it by SMS or WhatsApp.',
                        ),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: AppColors.primary,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.xl),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The short script the language-preview speaker reads aloud. We reuse the
/// verdict line because it is the most important sentence in the app: "go
/// to the health facility now". Caregivers will hear it most often, so
/// previewing it in their own language is the right test.
String _sampleScriptFor(String language) {
  if (language == 'Dagbani') {
    // The Dagbani draft of the most important sentence in the app. Marked as
    // a draft because the file [DagbaniStrings] is not yet verified by a
    // native speaker. The audio path will fall back to the English script
    // through the TTS engine if the user prefers to test the real sound.
    return resolveLocalized(DagbaniStrings.verdictUrgent, 'Dagbani').value;
  }
  return 'If your child cannot drink or breastfeed, go to the health '
      'facility at once. Do not wait until tomorrow.';
}
