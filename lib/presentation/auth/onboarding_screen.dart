/// First-launch onboarding — master flow screens [2], [3] and [4].
///
/// Three image-led slides that set the frame for the whole app:
///
/// [2] Maternal care — a community health worker with a pregnant woman.
/// [3] Newborn & child health — a newborn and toddler in the same household.
/// [4] Offline & AI-assisted — foreshadows the Result screen's risk badge.
///
/// Shown only on first launch. "Get started" marks onboarding seen and routes
/// to the Data & Privacy notice.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/preferences_store.dart';
import '../shared/app_image.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _slides = <_OnboardingSlide>[
    _OnboardingSlide(
      image: AppImages.onboardingMaternal,
      eyebrow: 'Maternal care',
      title: 'Supporting mothers through every stage',
      body:
          'Antenatal checks, danger-sign screening and postnatal follow-up — '
          'built around the way community health nurses already work.',
    ),
    _OnboardingSlide(
      image: AppImages.onboardingNewborn,
      eyebrow: 'Newborn & child health',
      title: 'Protecting every child from birth to five years',
      body:
          'Newborns, toddlers and their mothers are assessed together in one '
          'visit — no child is left out of the roll call.',
    ),
    _OnboardingSlide(
      image: AppImages.onboardingOffline,
      eyebrow: 'Offline & AI',
      title: 'Works without internet',
      body:
          'AI helps health workers make faster decisions. Records stay on this '
          'phone and sync when signal returns — you always make the call.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_index < _slides.length - 1) {
      _controller.nextPage(
        duration: AppMotion.duration,
        curve: AppMotion.curve,
      );
    } else {
      _finish();
    }
  }

  void _finish() {
    // The role choice [7] comes immediately after onboarding. The privacy
    // notice is folded into the registration form, so it does not need a
    // separate flag.
    PreferencesStore.markOnboardingSeen();
    context.go(Routes.setup);
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _slides.length - 1;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _TopRow(isLast: isLast, onSkip: _finish),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (i) => setState(() => _index = i),
                itemCount: _slides.length,
                itemBuilder: (_, i) => _SlideView(slide: _slides[i]),
              ),
            ),
            _BottomBar(
              index: _index,
              count: _slides.length,
              isLast: isLast,
              onNext: _next,
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingSlide {
  const _OnboardingSlide({
    required this.image,
    required this.eyebrow,
    required this.title,
    required this.body,
  });

  final String image;
  final String eyebrow;
  final String title;
  final String body;
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final _OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Gap.md),
          // The illustration is the hero — Northern users respond to images
          // first, text second.
          ClipRRect(
            borderRadius: BorderRadius.circular(Gap.radius),
            child: AspectRatio(
              aspectRatio: 4 / 4.4,
              child: AppImage(src: slide.image),
            ),
          ),
          const SizedBox(height: Gap.xl),
          Text(
            slide.eyebrow.toUpperCase(),
            textAlign: TextAlign.center,
            style: AppType.eyebrow.copyWith(
              color: AppColors.primary,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: Gap.sm),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: AppType.headline.copyWith(fontSize: 25),
          ),
          const SizedBox(height: Gap.md),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: AppType.body.copyWith(
              color: AppColors.inkMuted,
              height: 1.65,
            ),
          ),
          const SizedBox(height: Gap.lg),
        ],
      ),
    );
  }
}

class _TopRow extends StatelessWidget {
  const _TopRow({required this.isLast, required this.onSkip});

  final bool isLast;
  final VoidCallback onSkip;

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
          Flexible(
            child: Text(
              'CareBridge AI',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.sora(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
          const Spacer(),
          if (!isLast)
            TextButton(
              onPressed: onSkip,
              child: Text(
                'Skip',
                style: AppType.label.copyWith(color: AppColors.inkMuted),
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.index,
    required this.count,
    required this.isLast,
    required this.onNext,
  });

  final int index;
  final int count;
  final bool isLast;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.lg),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < count; i++)
                AnimatedContainer(
                  duration: AppMotion.fast,
                  curve: AppMotion.curve,
                  width: i == index ? 28 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == index ? AppColors.primary : AppColors.line,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Gap.lg),
          GradientButton(
            label: isLast ? 'Get Started' : 'Next',
            icon: isLast ? Icons.arrow_forward_rounded : null,
            onPressed: onNext,
          ),
          const SizedBox(height: Gap.sm),
          Text(
            isLast
                ? 'Records stay on this device and sync when there is network.'
                : 'Tap "Next" to continue',
            textAlign: TextAlign.center,
            style: AppType.caption.copyWith(fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
