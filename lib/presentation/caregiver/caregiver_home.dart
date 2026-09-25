import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/glass.dart';
import '../shared/narration_button.dart';
import '../shared/ui.dart';
import 'caregiver_providers.dart';
import 'care_plan/care_plan_tab.dart';
import 'check/check_tab.dart';
import 'family/family_tab.dart';
import 'growth/grow_play_tab.dart';
import 'help/help_tab.dart';
import 'help/caregiver_voice.dart';
import 'widgets/companion.dart';

class CaregiverHome extends ConsumerStatefulWidget {
  const CaregiverHome({super.key});
  @override
  ConsumerState<CaregiverHome> createState() => _CaregiverHomeState();
}

class _CaregiverHomeState extends ConsumerState<CaregiverHome> {
  int _tab = 0;
  String? _identity;
  void _switch(int tab) {
    final scope = ref.read(caregiverScopeProvider);
    if (scope != null) ref.read(caregiverVoiceProvider(scope)).stop();
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final scope = ref.watch(caregiverScopeProvider);
    final isOnline = ref.watch(connectivityProvider).valueOrNull ?? false;
    // Keep offline speech ready without blocking the shell.
    ref.read(neuralTranslationProvider.future);
    ref.read(piperTtsProvider.future);
    if (user == null) return const SizedBox.shrink();
    if (scope == null) {
      return CompanionTheme(
        child: Scaffold(
          backgroundColor: AppColors.caregiverCanvas,
          appBar: AppBar(
            title: const Text(
              'CareBridge AI',
              style: TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w700),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.family_restroom_rounded,
                        color: AppColors.primary,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Your family record is unavailable',
                      style: TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Sign out and sign in with the account you used to create your family.',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.inkMuted,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    OutlinedButton.icon(
                      onPressed: () =>
                          ref.read(sessionProvider.notifier).signOut(),
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final identity = '${scope.userId}/${scope.householdId}';
    if (_identity != identity) {
      _identity = identity;
      _tab = 0;
    }
    ref.watch(caregiverWriterProvider(scope));
    ref.watch(caregiverCalendarProvider);
    ref.watch(caregiverVoiceProvider(scope));
    final household = scope.householdId;
    return CompanionTheme(
      child: Builder(
        builder: (context) {
          final fx = VisualEffects.of(context);
          final page = KeyedSubtree(
            key: ValueKey('$identity/$_tab'),
            child: switch (_tab) {
              0 => CaregiverFamilyTab(
                householdId: household,
                onSwitch: _switch,
              ),
              1 => CaregiverCheckTab(householdId: household),
              2 => CaregiverGrowPlayTab(householdId: household),
              3 => CaregiverCarePlanTab(householdId: household),
              _ => CaregiverHelpTab(householdId: household),
            },
          );
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
            ),
            child: Scaffold(
              backgroundColor: CaregiverLuxePalette.celestialCanvas,
              body: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _CaregiverHeader(isOnline: isOnline),
                    Expanded(
                      child: fx.motion
                          ? AnimatedSwitcher(
                              key: ValueKey(identity),
                              duration: fx.scale(
                                const Duration(milliseconds: 220),
                              ),
                              switchInCurve: Curves.easeOut,
                              switchOutCurve: Curves.easeIn,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                              child: page,
                            )
                          : page,
                    ),
                  ],
                ),
              ),
              bottomNavigationBar: CaregiverNavigation(
                index: _tab,
                onSelect: _switch,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CaregiverHeader extends ConsumerWidget {
  const _CaregiverHeader({required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fx = VisualEffects.of(context);
    final narrationEnabled = ref.watch(narrationEnabledProvider);
    final theme = Theme.of(context);
    final title = Semantics(
      header: true,
      child: Row(
        children: [
          if (Navigator.of(context).canPop())
            const SizedBox(
              width: 48,
              height: 48,
              child: BackButton(color: CaregiverLuxePalette.twilightNavy),
            ),
          const Expanded(
            child: Text(
              'My family',
              softWrap: true,
              style: TextStyle(
                fontFamily: 'Sora',
                fontWeight: FontWeight.w700,
                fontSize: 22,
                height: 1.3,
                letterSpacing: -0.5,
                color: CaregiverLuxePalette.twilightMidnight,
              ),
            ),
          ),
        ],
      ),
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: NarrationButton(
            key: ValueKey(fx.motion ? null : narrationEnabled),
            compact: true,
            iconColor: CaregiverLuxePalette.twilightNavy,
          ),
        ),
        const SizedBox(
          width: 56,
          height: 48,
          child: CaregiverEmergencyButton(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ConnectivityDot(
            key: ValueKey(fx.motion ? null : isOnline),
            isOnline: isOnline,
          ),
        ),
      ],
    );
    return TickerMode(
      enabled: fx.motion,
      child: Theme(
        data: theme.copyWith(
          splashFactory: fx.motion
              ? theme.splashFactory
              : NoSplash.splashFactory,
          highlightColor: fx.motion ? theme.highlightColor : Colors.transparent,
        ),
        child: Material(
          key: ValueKey(fx.motion),
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked =
                    constraints.maxWidth < 324 ||
                    MediaQuery.textScalerOf(context).scale(22) > 28;
                if (stacked) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      title,
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: controls,
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 12),
                    controls,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class CaregiverNavigation extends StatelessWidget {
  const CaregiverNavigation({
    super.key,
    required this.index,
    required this.onSelect,
  });
  final int index;
  final ValueChanged<int> onSelect;
  static const labels = ['Family', 'Check', 'Grow & Play', 'Care plan', 'Help'];
  static const icons = [
    Icons.family_restroom_rounded,
    Icons.health_and_safety_outlined,
    Icons.toys_outlined,
    Icons.event_note_outlined,
    Icons.support_agent_outlined,
  ];
  @override
  Widget build(BuildContext context) {
    final fx = VisualEffects.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final defaults = DefaultTextStyle.of(context);
    final labelStyle = defaults.style.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      height: 1.35,
      letterSpacing: 0,
    );
    final radius = BorderRadius.circular(28);
    return TickerMode(
      enabled: fx.motion,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth < 328 || scaler.scale(12) > 16 ? 3 : 5;
              final cellWidth = (constraints.maxWidth - 16) / columns;
              final rowCount = (labels.length / columns).ceil();
              final rowHeights = List<double>.filled(rowCount, 48);
              // Measure the actual scaled labels, not a fixed grid aspect ratio.
              for (var i = 0; i < labels.length; i++) {
                final painter = TextPainter(
                  text: TextSpan(text: labels[i], style: labelStyle),
                  textDirection: direction,
                  textScaler: scaler,
                  locale: Localizations.maybeLocaleOf(context),
                  textHeightBehavior: defaults.textHeightBehavior,
                )..layout(maxWidth: cellWidth - 12);
                final height = 54 + painter.height.ceilToDouble();
                final row = i ~/ columns;
                if (height > rowHeights[row]) rowHeights[row] = height;
                painter.dispose();
              }
              final selectedRow = index ~/ columns;
              final selectedColumn = index % columns;
              final selectedRowCount = selectedRow == rowCount - 1
                  ? labels.length - selectedRow * columns
                  : columns;
              final start =
                  (columns - selectedRowCount) * cellWidth / 2 +
                  selectedColumn * cellWidth +
                  2;
              final top = selectedRow == 0 ? 0.0 : rowHeights[0] + 6;
              final indicator = IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey('caregiver-dock-indicator'),
                  decoration: BoxDecoration(
                    color: CaregiverLuxePalette.azurePrimary,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: CaregiverLuxePalette.specularStroke,
                    ),
                    boxShadow: fx.blur
                        ? [
                            BoxShadow(
                              color: CaregiverLuxePalette.azurePrimary
                                  .withValues(alpha: 0.18),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : const [],
                  ),
                ),
              );
              final content = Padding(
                padding: const EdgeInsets.all(8),
                child: Stack(
                  children: [
                    if (fx.motion)
                      AnimatedPositionedDirectional(
                        duration: fx.scale(const Duration(milliseconds: 260)),
                        curve: Curves.easeOutCubic,
                        start: start,
                        top: top,
                        width: cellWidth - 4,
                        height: rowHeights[selectedRow],
                        child: indicator,
                      )
                    else
                      PositionedDirectional(
                        start: start,
                        top: top,
                        width: cellWidth - 4,
                        height: rowHeights[selectedRow],
                        child: indicator,
                      ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var row = 0; row < rowCount; row++) ...[
                          if (row > 0) const SizedBox(height: 6),
                          SizedBox(
                            height: rowHeights[row],
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (
                                  var i = row * columns;
                                  i < (row + 1) * columns && i < labels.length;
                                  i++
                                )
                                  SizedBox(
                                    width: cellWidth,
                                    child: _destination(
                                      context,
                                      i,
                                      labelStyle,
                                      fx,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
              final surface = DecoratedBox(
                decoration: BoxDecoration(
                  color: fx.blur
                      ? CaregiverLuxePalette.pearlGlassTint
                      : CaregiverLuxePalette.pearlSurface,
                  borderRadius: radius,
                  border: Border.all(color: CaregiverLuxePalette.hairLineQuiet),
                ),
                child: Stack(
                  children: [
                    const Positioned(
                      top: 1,
                      left: 24,
                      right: 24,
                      child: IgnorePointer(
                        child: SizedBox(
                          height: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  CaregiverLuxePalette.specularStroke,
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    content,
                  ],
                ),
              );
              return DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  boxShadow: fx.blur
                      ? CaregiverLuxePalette.featheredShadow
                      : const [],
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  child: fx.blur
                      ? BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: surface,
                        )
                      : surface,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _destination(
    BuildContext context,
    int destination,
    TextStyle labelStyle,
    VisualEffects fx,
  ) {
    final selected = destination == index;
    final foreground = selected
        ? CaregiverLuxePalette.pearlSurface
        : CaregiverLuxePalette.twilightMuted;
    return Semantics(
      selected: selected,
      button: true,
      label: labels[destination],
      child: Material(
        key: ValueKey(fx.motion),
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          splashFactory: fx.motion
              ? Theme.of(context).splashFactory
              : NoSplash.splashFactory,
          highlightColor: fx.motion ? null : Colors.transparent,
          hoverDuration: fx.scale(const Duration(milliseconds: 50)),
          focusColor: CaregiverLuxePalette.twilightNavy.withValues(alpha: 0.12),
          enableFeedback: false,
          onTap: () {
            if (!selected) HapticFeedback.lightImpact();
            onSelect(destination);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              child: ExcludeSemantics(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icons[destination], color: foreground, size: 24),
                    const SizedBox(height: 6),
                    Text(
                      labels[destination],
                      textAlign: TextAlign.center,
                      softWrap: true,
                      style: labelStyle.copyWith(color: foreground),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
