import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature, PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import 'ai_pitch_copilot.dart';

/// Supported device models in the interactive simulator.
enum DeviceModel {
  iPhone16Pro(
    name: 'iPhone 16 Pro',
    width: 393,
    height: 852,
    cornerRadius: 44,
    hasDynamicIsland: true,
    hasStatusBar: true,
    isAndroid: false,
    icon: Icons.phone_iphone,
  ),
  iPhone16ProMax(
    name: 'iPhone 16 Pro Max',
    width: 430,
    height: 932,
    cornerRadius: 46,
    hasDynamicIsland: true,
    hasStatusBar: true,
    isAndroid: false,
    icon: Icons.smartphone,
  ),
  iPhone16(
    name: 'iPhone 16',
    width: 375,
    height: 812,
    cornerRadius: 40,
    hasDynamicIsland: true,
    hasStatusBar: true,
    isAndroid: false,
    icon: Icons.phone_android,
  ),
  galaxyS24Ultra(
    name: 'Galaxy S24 Ultra',
    width: 412,
    height: 915,
    cornerRadius: 26,
    hasDynamicIsland: false,
    hasStatusBar: true,
    isAndroid: true,
    icon: Icons.android_rounded,
  ),
  pixel9Pro(
    name: 'Pixel 9 Pro',
    width: 412,
    height: 892,
    cornerRadius: 42,
    hasDynamicIsland: false,
    hasStatusBar: true,
    isAndroid: true,
    icon: Icons.smartphone_rounded,
  ),
  iPadPro(
    name: 'iPad Pro 11"',
    width: 834,
    height: 1194,
    cornerRadius: 24,
    hasDynamicIsland: false,
    hasStatusBar: false,
    isAndroid: false,
    icon: Icons.tablet_mac,
  ),
  edgeToEdge(
    name: 'Web Responsive',
    width: 0,
    height: 0,
    cornerRadius: 0,
    hasDynamicIsland: false,
    hasStatusBar: false,
    isAndroid: false,
    icon: Icons.desktop_mac,
  );

  const DeviceModel({
    required this.name,
    required this.width,
    required this.height,
    required this.cornerRadius,
    required this.hasDynamicIsland,
    required this.hasStatusBar,
    required this.isAndroid,
    required this.icon,
  });
  final String name;
  final double width;
  final double height;
  final double cornerRadius;
  final bool hasDynamicIsland;
  final bool hasStatusBar;
  final bool isAndroid;
  final IconData icon;
}

/// Authentic Apple-style titanium finishes for the device chassis.
enum ChassisFinish {
  natural(
    name: 'Natural Titanium',
    rimColors: [
      Color(0xFF8C8E91),
      Color(0xFF5E6267),
      Color(0xFF45494E),
      Color(0xFF65696E),
    ],
    swatchColor: Color(0xFF8E8D88),
  ),
  black(
    name: 'Black Titanium',
    rimColors: [
      Color(0xFF434548),
      Color(0xFF2A2C2F),
      Color(0xFF1B1D1F),
      Color(0xFF2E3134),
    ],
    swatchColor: Color(0xFF2E2F32),
  ),
  white(
    name: 'White Titanium',
    rimColors: [
      Color(0xFFE4E7EA),
      Color(0xFFC3C7CE),
      Color(0xFFA6ABB4),
      Color(0xFFCDD2DA),
    ],
    swatchColor: Color(0xFFE5E7E2),
  ),
  desert(
    name: 'Desert Titanium',
    rimColors: [
      Color(0xFF988877),
      Color(0xFF746556),
      Color(0xFF5E4F41),
      Color(0xFF7A6B5C),
    ],
    swatchColor: Color(0xFFBCA995),
  ),
  pacificBlue(
    name: 'Blue Titanium',
    rimColors: [
      Color(0xFF38495D),
      Color(0xFF253344),
      Color(0xFF192534),
      Color(0xFF2B3A4D),
    ],
    swatchColor: Color(0xFF324151),
  );

  const ChassisFinish({
    required this.name,
    required this.rimColors,
    required this.swatchColor,
  });
  final String name;
  final List<Color> rimColors;
  final Color swatchColor;
}

/// Studio background lightning environments.
enum StudioBackdrop {
  royalStudio(
    name: 'Royal Studio',
    isDark: true,
    colors: [Color(0xFF1B2E55), Color(0xFF0F1B38), Color(0xFF070F22)],
    glowColor: AppColors.primaryGlow,
  ),
  midnight(
    name: 'Obsidian Midnight',
    isDark: true,
    colors: [Color(0xFF1D1F24), Color(0xFF101215), Color(0xFF050608)],
    glowColor: Color(0xFF4A5568),
  ),
  slate(
    name: 'Sleek Graphite',
    isDark: true,
    colors: [Color(0xFF3A414B), Color(0xFF252930), Color(0xFF14171B)],
    glowColor: Color(0xFF90CDF4),
  ),
  cleanLight(
    name: 'Clean Showcase',
    isDark: false,
    colors: [Color(0xFFFFFFFF), Color(0xFFF0F4F8), Color(0xFFDFE6EE)],
    glowColor: Color(0xFF1B56DB),
  ),
  cyberPulse(
    name: 'Cyber Pulse',
    isDark: true,
    colors: [Color(0xFF2A1548), Color(0xFF130A2B), Color(0xFF070214)],
    glowColor: Color(0xFFB83280),
  );

  const StudioBackdrop({
    required this.name,
    required this.isDark,
    required this.colors,
    required this.glowColor,
  });
  final String name;
  final bool isDark;
  final List<Color> colors;
  final Color glowColor;
}

/// A comprehensive scroll behavior that guarantees desktop mouse, touch, and
/// trackpad drag gestures interact smoothly when tested in Chrome.
class _SimulatorScrollBehavior extends MaterialScrollBehavior {
  const _SimulatorScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  };
}

/// A state-of-the-art, interactive device simulator used to present the app on web.
///
/// Running `flutter run -d chrome` on a desktop/laptop wraps the mobile app in an
/// ultra-realistic, sizeable iPhone 16 Pro / iPad simulator with zoom controls,
/// orientation switching, titanium color swatches, live system clocks, and interactive
/// micro-animations.
class IPhoneFrame extends StatefulWidget {
  const IPhoneFrame({super.key, required this.child});

  final Widget child;

  @override
  State<IPhoneFrame> createState() => _IPhoneFrameState();
}

class _IPhoneFrameState extends State<IPhoneFrame> {
  DeviceModel _selectedDevice = DeviceModel.iPhone16Pro;
  ChassisFinish _selectedFinish = ChassisFinish.natural;
  StudioBackdrop _selectedBackdrop = StudioBackdrop.royalStudio;
  bool _isLandscape = false;
  double? _customScale; // null means Fit to Screen
  bool _hideControls = false;
  bool _freezeTime = false; // Toggles between live time and keynote 9:41
  bool _aiPitchMode = false; // Toggles the interactive AI Pitch Copilot presentation deck

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    // If running directly on a phone browser tab, skip simulating a chassis.
    if (mq.size.width <= 550 && _selectedDevice != DeviceModel.edgeToEdge) {
      return ScrollConfiguration(
        behavior: const _SimulatorScrollBehavior(),
        child: widget.child,
      );
    }

    return Navigator(
      onGenerateRoute: (settings) => PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, _, _) => Scaffold(
          backgroundColor: Colors.transparent,
          body: LayoutBuilder(
            builder: (context, constraints) {
          // ── Edge-to-Edge Web Responsive Mode ──────────────────────
          if (_selectedDevice == DeviceModel.edgeToEdge) {
            return Stack(
              fit: StackFit.expand,
              children: [
                ScrollConfiguration(
                  behavior: const _SimulatorScrollBehavior(),
                  child: widget.child,
                ),
                _buildFloatingControlDock(1.0),
              ],
            );
          }

          // ── Device Frame Dimension Calculation ────────────────────
          final logicalW = _isLandscape ? _selectedDevice.height : _selectedDevice.width;
          final logicalH = _isLandscape ? _selectedDevice.width : _selectedDevice.height;

          const rim = 4.0;
          const bezel = 10.0;
          const inset = rim + bezel;
          final frameW = logicalW + inset * 2;
          final frameH = logicalH + inset * 2;

          final maxW = math.max(100.0, constraints.maxWidth - 48.0);
          final maxH = math.max(
            100.0,
            constraints.maxHeight - (_hideControls ? 48.0 : 120.0),
          );

          final fitScale = math.min(maxW / frameW, maxH / frameH);
          final effectiveScale = _customScale ?? math.min(1.15, fitScale);
          final displayW = frameW * effectiveScale;
          final displayH = frameH * effectiveScale;

          return Stack(
            fit: StackFit.expand,
            children: [
              // ── Studio lighting & backdrop ─────────────────────────
              _buildStudioBackdrop(),

              // ── Ambient background radiation glow ─────────────────
              Center(
                child: Container(
                  width: displayW * 1.8,
                  height: displayH * 1.4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _selectedBackdrop.glowColor.withValues(alpha: 0.22),
                        _selectedBackdrop.glowColor.withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),

              // ── Soft floor reflection grounding the handset ────────
              Positioned(
                bottom: math.max(10.0, (constraints.maxHeight - displayH) / 2 - 40),
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: displayW * 1.3,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.5,
                        colors: [
                          _selectedBackdrop.glowColor.withValues(alpha: 0.25),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Scrollable interactive device canvas ───────────────
              // Decouples screen scaling from window constraints so
              // resolution and hit testing remain razor sharp at any size.
              Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: _hideControls ? 20 : 88,
                        top: 24,
                        left: 24,
                        right: 24,
                      ),
                      child: SizedBox(
                        width: displayW,
                        height: displayH,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: SizedBox(
                            width: frameW,
                            height: frameH,
                            child: _DeviceChassis(
                              device: _selectedDevice,
                              finish: _selectedFinish,
                              isLandscape: _isLandscape,
                              freezeTime: _freezeTime,
                              child: widget.child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── In-App Live AI Presentation Copilot Panel ──────────
              if (_aiPitchMode)
                Positioned(
                  top: 24,
                  bottom: 88,
                  right: constraints.maxWidth > 920 ? 24 : null,
                  left: constraints.maxWidth <= 920 ? 16 : null,
                  width: constraints.maxWidth <= 920
                      ? (constraints.maxWidth - 32).clamp(300.0, 420.0)
                      : 400,
                  child: SafeArea(
                    child: Align(
                      alignment: constraints.maxWidth > 920
                          ? Alignment.topRight
                          : Alignment.center,
                      child: AiPitchCopilotPanel(
                        onClose: () => setState(() => _aiPitchMode = false),
                      ),
                    ),
                  ),
                ),

              // ── Interactive floating dock & showcase controls ──────
              _buildFloatingControlDock(fitScale),
            ],
          );
        },
      ),
    ),
    ),
    );
  }

  Widget _buildStudioBackdrop() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.4,
          colors: _selectedBackdrop.colors,
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
    );
  }

  Widget _buildFloatingControlDock(double fitScale) {
    if (_hideControls) {
      return Positioned(
        bottom: 16,
        right: 16,
        child: FloatingActionButton.small(
          onPressed: () => setState(() => _hideControls = false),
          backgroundColor: const Color(0xFF1E2430),
          foregroundColor: Colors.white,
          tooltip: 'Show Simulator Controls',
          child: const Icon(Icons.tune, size: 18),
        ),
      );
    }

    return Positioned(
      bottom: 20,
      left: 16,
      right: 16,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF11151F).withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(38),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.16),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: AppColors.primaryGlow.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Device Model Selector
                _buildDeviceDropdown(),
                _divider(),

                // 2. Zoom Controls
                IconButton(
                  onPressed: _customScale == null && _selectedDevice == DeviceModel.edgeToEdge
                      ? null
                      : () {
                          final cur = _customScale ?? math.min(1.15, fitScale);
                          setState(() => _customScale = math.max(0.4, cur - 0.1));
                        },
                  icon: const Icon(Icons.remove, size: 18, color: Colors.white70),
                  tooltip: 'Zoom Out',
                  visualDensity: VisualDensity.compact,
                ),
                _buildZoomMenu(fitScale),
                IconButton(
                  onPressed: _customScale == null && _selectedDevice == DeviceModel.edgeToEdge
                      ? null
                      : () {
                          final cur = _customScale ?? math.min(1.15, fitScale);
                          setState(() => _customScale = math.min(2.0, cur + 0.1));
                        },
                  icon: const Icon(Icons.add, size: 18, color: Colors.white70),
                  tooltip: 'Zoom In',
                  visualDensity: VisualDensity.compact,
                ),
                _divider(),

                // 3. Orientation Switch
                IconButton(
                  onPressed: _selectedDevice == DeviceModel.edgeToEdge
                      ? null
                      : () => setState(() => _isLandscape = !_isLandscape),
                  icon: Icon(
                    _isLandscape
                        ? Icons.screen_lock_landscape_outlined
                        : Icons.screen_lock_portrait_outlined,
                    color: _selectedDevice == DeviceModel.edgeToEdge
                        ? Colors.white24
                        : AppColors.primaryGlow,
                  ),
                  tooltip: 'Rotate Orientation (${_isLandscape ? "Landscape" : "Portrait"})',
                ),
                _divider(),

                // 4. Titanium Chassis Finish Swatches
                if (_selectedDevice != DeviceModel.edgeToEdge) ...[
                  _buildFinishSelector(),
                  _divider(),
                ],

                // 5. Studio Environment Backdrop
                _buildBackdropSelector(),
                _divider(),

                // 6. Clock Freeze Toggle (Real-time vs 9:41 Demo)
                IconButton(
                  onPressed: () => setState(() => _freezeTime = !_freezeTime),
                  icon: Icon(
                    _freezeTime ? Icons.schedule : Icons.timer_outlined,
                    color: _freezeTime ? Colors.amberAccent : Colors.white70,
                    size: 20,
                  ),
                  tooltip: _freezeTime ? 'Demo Time (9:41) • Tap for Live Clock' : 'Live Local Clock • Tap for 9:41 Demo',
                ),
                _divider(),

                // 7. AI Pitch & Live Speaking Demo Copilot
                InkWell(
                  onTap: () => setState(() => _aiPitchMode = !_aiPitchMode),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: _aiPitchMode ? AppColors.brandGradient : null,
                      color: _aiPitchMode
                          ? null
                          : Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _aiPitchMode
                            ? Colors.amberAccent
                            : Colors.white.withValues(alpha: 0.25),
                        width: 1.2,
                      ),
                      boxShadow: _aiPitchMode ? const [AppShadows.glow] : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _aiPitchMode
                              ? Icons.campaign_rounded
                              : Icons.auto_awesome_rounded,
                          color: _aiPitchMode
                              ? Colors.white
                              : Colors.amberAccent,
                          size: 17,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'AI Pitch Mode',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _divider(),

                // 8. Hide Controls Button
                IconButton(
                  onPressed: () => setState(() => _hideControls = true),
                  icon: const Icon(Icons.visibility_off_outlined, size: 18, color: Colors.white60),
                  tooltip: 'Hide Controls (Showcase Mode)',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceDropdown() {
    return PopupMenuButton<DeviceModel>(
      initialValue: _selectedDevice,
      tooltip: 'Select Device Emulator',
      offset: const Offset(0, -310),
      color: const Color(0xFF1E2432),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
      ),
      onSelected: (model) => setState(() {
        _selectedDevice = model;
        if (model == DeviceModel.edgeToEdge) _customScale = null;
      }),
      itemBuilder: (context) => DeviceModel.values.map((d) {
        return PopupMenuItem<DeviceModel>(
          value: d,
          child: Row(
            children: [
              Icon(d.icon, color: _selectedDevice == d ? AppColors.primaryGlow : Colors.white70, size: 20),
              const SizedBox(width: 12),
              Text(
                d.name,
                style: GoogleFonts.inter(
                  color: _selectedDevice == d ? Colors.white : Colors.white70,
                  fontWeight: _selectedDevice == d ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Icon(_selectedDevice.icon, color: AppColors.primaryGlow, size: 18),
            const SizedBox(width: 8),
            Text(
              _selectedDevice.name,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_up, color: Colors.white70, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomMenu(double fitScale) {
    String label;
    if (_selectedDevice == DeviceModel.edgeToEdge) {
      label = 'Auto';
    } else if (_customScale == null) {
      label = 'Fit';
    } else {
      label = '${(_customScale! * 100).round()}%';
    }

    return PopupMenuButton<double?>(
      tooltip: 'Select Screen Zoom Level',
      offset: const Offset(0, -200),
      color: const Color(0xFF1E2432),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
      ),
      onSelected: (val) => setState(() => _customScale = val),
      itemBuilder: (context) => [
        const PopupMenuItem(value: null, child: Text('Fit to Screen', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 0.5, child: Text('50% • Compact', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 0.75, child: Text('75% • Comfortable', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 1.0, child: Text('100% • True 1:1 Size', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 1.25, child: Text('125% • Large', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 1.5, child: Text('150% • Presentation', style: TextStyle(color: Colors.white))),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildFinishSelector() {
    return PopupMenuButton<ChassisFinish>(
      initialValue: _selectedFinish,
      tooltip: 'Chassis Finish (${_selectedFinish.name})',
      offset: const Offset(0, -220),
      color: const Color(0xFF1E2432),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
      ),
      onSelected: (f) => setState(() => _selectedFinish = f),
      itemBuilder: (context) => ChassisFinish.values.map((f) {
        return PopupMenuItem<ChassisFinish>(
          value: f,
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: f.swatchColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white38, width: 1.5),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                f.name,
                style: GoogleFonts.inter(
                  color: _selectedFinish == f ? Colors.white : Colors.white70,
                  fontWeight: _selectedFinish == f ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: _selectedFinish.swatchColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white60, width: 2),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.color_lens_outlined, color: Colors.white70, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildBackdropSelector() {
    return PopupMenuButton<StudioBackdrop>(
      initialValue: _selectedBackdrop,
      tooltip: 'Studio Atmosphere (${_selectedBackdrop.name})',
      offset: const Offset(0, -220),
      color: const Color(0xFF1E2432),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
      ),
      onSelected: (b) => setState(() => _selectedBackdrop = b),
      itemBuilder: (context) => StudioBackdrop.values.map((b) {
        return PopupMenuItem<StudioBackdrop>(
          value: b,
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: b.colors),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white38, width: 1.5),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                b.name,
                style: GoogleFonts.inter(
                  color: _selectedBackdrop == b ? Colors.white : Colors.white70,
                  fontWeight: _selectedBackdrop == b ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, color: AppColors.primaryGlow, size: 18),
            const SizedBox(width: 4),
            Text(
              'Studio',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Colors.white.withValues(alpha: 0.12),
    );
  }
}

/// The ultra-realistic physical hardware chassis surrounding the running Flutter app.
class _DeviceChassis extends StatelessWidget {
  const _DeviceChassis({
    required this.device,
    required this.finish,
    required this.isLandscape,
    required this.freezeTime,
    required this.child,
  });

  final DeviceModel device;
  final ChassisFinish finish;
  final bool isLandscape;
  final bool freezeTime;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const rim = 4.0;
    const bezel = 10.0;
    const inset = rim + bezel;

    final screenW = isLandscape ? device.height : device.width;
    final screenH = isLandscape ? device.width : device.height;
    final frameW = screenW + inset * 2;
    final frameH = screenH + inset * 2;

    final chassisRadius = device.cornerRadius + inset;
    final screenRadius = device.cornerRadius;

    final mq = MediaQuery.of(context);
    EdgeInsets safePadding = EdgeInsets.zero;
    if (device.isAndroid) {
      safePadding = isLandscape
          ? const EdgeInsets.only(left: 48, right: 48, bottom: 20)
          : const EdgeInsets.only(top: 44, bottom: 26);
    } else if (device == DeviceModel.iPhone16Pro || device == DeviceModel.iPhone16ProMax || device == DeviceModel.iPhone16) {
      safePadding = isLandscape
          ? const EdgeInsets.only(left: 54, right: 54, bottom: 22)
          : const EdgeInsets.only(top: 54, bottom: 34);
    } else if (device == DeviceModel.iPadPro) {
      safePadding = const EdgeInsets.only(top: 24, bottom: 20);
    }

    final titaniumGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: finish.rimColors,
      stops: const [0.0, 0.35, 0.7, 1.0],
    );

    return SizedBox(
      width: frameW,
      height: frameH,
      child: Stack(
        children: [
          // ── Hardware physical buttons ──────────────────────────────────
          if (device.isAndroid) ...[
            if (!isLandscape) ...[
              _sideButton(right: -3, top: 180, width: 6, height: 64), // Volume rocker
              _sideButton(right: -3, top: 262, width: 6, height: 42), // Power button
            ] else ...[
              _sideButton(top: -3, right: 180, width: 64, height: 6), // Volume rocker rotated
              _sideButton(top: -3, right: 262, width: 42, height: 6), // Power button rotated
            ],
          ] else ...[
            if (!isLandscape) ...[
              _sideButton(left: -3, top: 136, width: 6, height: 30), // Action button
              _sideButton(left: -3, top: 190, width: 6, height: 56), // Volume up
              _sideButton(left: -3, top: 258, width: 6, height: 56), // Volume down
              _sideButton(right: -3, top: 214, width: 6, height: 92), // Power button
              _sideButton(right: -3, bottom: 140, width: 6, height: 54), // Camera Control (2025/2026)
            ] else ...[
              _sideButton(top: -3, right: 136, width: 30, height: 6), // Action button rotated
              _sideButton(top: -3, right: 190, width: 56, height: 6), // Vol up rotated
              _sideButton(top: -3, right: 258, width: 56, height: 6), // Vol down rotated
              _sideButton(bottom: -3, right: 214, width: 92, height: 6), // Power button rotated
            ],
          ],

          // ── Outer titanium rim with shadow & chamfer reflection ────────
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: titaniumGradient,
                borderRadius: BorderRadius.circular(chassisRadius),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.22),
                  width: 1,
                ),
                boxShadow: const [
                  BoxShadow(color: Color(0x40000000), blurRadius: 64, offset: Offset(0, 26)),
                  BoxShadow(color: Color(0x26000000), blurRadius: 18, offset: Offset(0, 6)),
                ],
              ),
            ),
          ),

          // ── Inner black display bezel ──────────────────────────────────
          Positioned(
            left: rim,
            top: rim,
            right: rim,
            bottom: rim,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF090A0C),
                borderRadius: BorderRadius.circular(chassisRadius - rim),
              ),
            ),
          ),

          // ── Active Retina viewport & simulated touch gestures ──────────
          Positioned(
            left: inset,
            top: inset,
            right: inset,
            bottom: inset,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(screenRadius),
              child: MediaQuery(
                data: mq.copyWith(
                  size: Size(screenW, screenH),
                  padding: safePadding,
                  viewPadding: safePadding,
                  devicePixelRatio: 3.0,
                ),
                child: ScrollConfiguration(
                  behavior: const _SimulatorScrollBehavior(),
                  child: Stack(
                    children: [
                      Positioned.fill(child: child),
                      if (device.hasStatusBar && !isLandscape && !device.isAndroid)
                        _StatusBar(deviceWidth: screenW, freezeTime: freezeTime),
                      if (device.hasStatusBar && isLandscape && !device.isAndroid)
                        _LandscapeStatusBar(deviceWidth: screenW, freezeTime: freezeTime),
                      if (device.hasStatusBar && device.isAndroid)
                        _AndroidStatusBar(deviceWidth: screenW, freezeTime: freezeTime, isLandscape: isLandscape),
                      if (device.hasDynamicIsland)
                        _DynamicIsland(isLandscape: isLandscape, screenW: screenW),
                      if (device.isAndroid)
                        _AndroidHolePunch(isLandscape: isLandscape, screenW: screenW, isGalaxy: device == DeviceModel.galaxyS24Ultra),
                      if (!device.isAndroid && device != DeviceModel.edgeToEdge && device != DeviceModel.iPadPro)
                        _HomeIndicator(isLandscape: isLandscape),
                      if (device.isAndroid)
                        _AndroidNavIndicator(isLandscape: isLandscape),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sideButton({
    double? left,
    double? right,
    double? top,
    double? bottom,
    required double width,
    required double height,
  }) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: finish.rimColors,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

/// Interactive Dynamic Island with micro-animations & hardware camera cutout reflection.
class _DynamicIsland extends StatefulWidget {
  const _DynamicIsland({required this.isLandscape, required this.screenW});
  final bool isLandscape;
  final double screenW;

  @override
  State<_DynamicIsland> createState() => _DynamicIslandState();
}

class _DynamicIslandState extends State<_DynamicIsland> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    if (widget.isLandscape) {
      // In landscape, the pill sits near the leading (left) edge.
      return Positioned(
        left: 11,
        top: 24,
        bottom: 24,
        child: Center(
          child: Container(
            width: 28,
            height: 104,
            decoration: BoxDecoration(
              color: const Color(0xFF000000),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );
    }

    final islandWidth = _isHovered ? 230.0 : 120.0;
    final islandHeight = _isHovered ? 38.0 : 34.0;
    final leftPos = (widget.screenW - islandWidth) / 2;

    return Positioned(
      top: 11,
      left: leftPos,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: () => setState(() => _isHovered = !_isHovered),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutBack,
            width: islandWidth,
            height: islandHeight,
            decoration: BoxDecoration(
              color: const Color(0xFF020305),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Hardware Camera Lens & FaceID Sensor simulation
                  if (!_isHovered) ...[
                    Positioned(
                      right: 14,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: const Color(0xFF141720),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF262A38), width: 1),
                        ),
                        child: Center(
                          child: Container(
                            width: 3.5,
                            height: 3.5,
                            decoration: const BoxDecoration(
                              color: Color(0xFF38466E),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    // Micro-animated active AI status badge when hovered
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.triageGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'CareBridge AI • Ready',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The iOS portrait status bar with real-time clock and connectivity glyphs.
class _StatusBar extends StatefulWidget {
  const _StatusBar({required this.deviceWidth, required this.freezeTime});
  final double deviceWidth;
  final bool freezeTime;

  @override
  State<_StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<_StatusBar> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const ink = AppColors.ink;
    final timeStr = widget.freezeTime
        ? '9:41'
        : '${_now.hour}:${_now.minute.toString().padLeft(2, "0")}';

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SizedBox(
        height: 54,
        child: Stack(
          children: [
            // Current Time
            Positioned(
              left: 32,
              top: 17,
              child: Text(
                timeStr,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),

            // Connectivity Icons (5G, WiFi, Battery)
            Positioned(
              right: 28,
              top: 18,
              child: Row(
                children: [
                  const _SignalBars(color: ink),
                  const SizedBox(width: 5),
                  Text(
                    '5G',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: ink,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(Icons.wifi, size: 15, color: ink),
                  const SizedBox(width: 6),
                  const _Battery(color: ink),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Landscape status bar layout with minimal side intrusion.
class _LandscapeStatusBar extends StatelessWidget {
  const _LandscapeStatusBar({required this.deviceWidth, required this.freezeTime});
  final double deviceWidth;
  final bool freezeTime;

  @override
  Widget build(BuildContext context) {
    const ink = AppColors.ink;
    final now = DateTime.now();
    final timeStr = freezeTime ? '9:41' : '${now.hour}:${now.minute.toString().padLeft(2, "0")}';

    return Positioned(
      top: 6,
      left: 54,
      right: 54,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            timeStr,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
          Row(
            children: [
              const _SignalBars(color: ink),
              const SizedBox(width: 6),
              const Icon(Icons.wifi, size: 14, color: ink),
              const SizedBox(width: 6),
              const _Battery(color: ink),
            ],
          ),
        ],
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final h in const [4.0, 6.5, 9.0, 11.5])
          Container(
            width: 2.8,
            height: h,
            margin: const EdgeInsets.only(right: 1.5),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
      ],
    );
  }
}

class _Battery extends StatelessWidget {
  const _Battery({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 23,
          height: 12,
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
            borderRadius: BorderRadius.circular(3.5),
          ),
          child: Container(
            width: 17,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        ),
        const SizedBox(width: 1),
        Container(
          width: 1.5,
          height: 4,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ],
    );
  }
}

class _HomeIndicator extends StatelessWidget {
  const _HomeIndicator({required this.isLandscape});
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: isLandscape ? 6 : 8,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          width: isLandscape ? 180 : 136,
          height: 5,
          decoration: BoxDecoration(
            color: AppColors.ink.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

class _AndroidStatusBar extends StatefulWidget {
  const _AndroidStatusBar({
    required this.deviceWidth,
    required this.freezeTime,
    required this.isLandscape,
  });
  final double deviceWidth;
  final bool freezeTime;
  final bool isLandscape;

  @override
  State<_AndroidStatusBar> createState() => _AndroidStatusBarState();
}

class _AndroidStatusBarState extends State<_AndroidStatusBar> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLandscape) return const SizedBox.shrink();

    const ink = AppColors.ink;
    final timeStr = widget.freezeTime
        ? '10:00'
        : '${_now.hour}:${_now.minute.toString().padLeft(2, "0")}';

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                timeStr,
                style: GoogleFonts.roboto(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: ink,
                  letterSpacing: 0.2,
                ),
              ),
              Row(
                children: [
                  Icon(Icons.wifi, size: 15, color: ink),
                  const SizedBox(width: 6),
                  Icon(Icons.signal_cellular_4_bar, size: 15, color: ink),
                  const SizedBox(width: 6),
                  Text(
                    '98%',
                    style: GoogleFonts.roboto(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                  const SizedBox(width: 3),
                  const _AndroidBattery(color: ink),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AndroidBattery extends StatelessWidget {
  const _AndroidBattery({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 11,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.2),
        borderRadius: BorderRadius.circular(2.5),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

class _AndroidHolePunch extends StatelessWidget {
  const _AndroidHolePunch({required this.isLandscape, required this.screenW, required this.isGalaxy});
  final bool isLandscape;
  final double screenW;
  final bool isGalaxy;

  @override
  Widget build(BuildContext context) {
    if (isLandscape) return const SizedBox.shrink();
    final size = isGalaxy ? 13.0 : 15.0;
    return Positioned(
      top: 10,
      left: (screenW - size) / 2,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF07080A),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF191B20), width: 1),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 4, spreadRadius: 1),
          ],
        ),
        child: Center(
          child: Container(
            width: size * 0.45,
            height: size * 0.45,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF1E2638).withValues(alpha: 0.8),
                  const Color(0xFF080B10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AndroidNavIndicator extends StatelessWidget {
  const _AndroidNavIndicator({required this.isLandscape});
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: isLandscape ? 5 : 8,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          width: isLandscape ? 140 : 108,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.ink.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
