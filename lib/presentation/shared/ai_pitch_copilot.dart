/// In-App Live Speaking AI Presentation & Pitch Copilot.
///
/// Designed specifically for live presentations, hackathons, and video demos
/// of CareBridge AI. When activated from the interactive Studio Toolbar in
/// [IPhoneFrame], this copilot renders a sleek, glassmorphic executive deck
/// next to the simulated device and continuously narrates the end-to-end clinical,
/// architectural, and AI system innovations out loud using a clear female voice.
///
/// Organized into an extensive ~6-minute interactive presentation covering:
/// 1. Introduction & Healthcare Mission
/// 2. Role Selection ("Who are you?" - FHW vs Caregiver)
/// 3. Offline Account Registration & PIN Cryptography
/// 4. Household Check-In & Family Roll Call Surveillance
/// 5. Performing Clinical Assessments (MUAC gauge & Neonate Danger Signs)
/// 6. AI Recommendations, Hospital Referrals & Clinical Overrides
/// 7. Deep-Dive: How Our Deterministic AI & Voice Engines Work
/// 8. Hybrid Offline SQLite Database & Synchronization Architecture
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../core/theme/app_theme.dart';

class PitchScene {
  const PitchScene({
    required this.title,
    required this.subtitle,
    required this.shortTab,
    required this.icon,
    required this.points,
    required this.narration,
    required this.durationEstimate,
  });

  final String title;
  final String subtitle;
  final String shortTab;
  final IconData icon;
  final List<String> points;
  final String narration;
  final String durationEstimate;
}

const _kPitchScenes = <PitchScene>[
  PitchScene(
    title: 'Introduction & Our Healthcare Mission',
    subtitle: 'WHY CAREBRIDGE AI WAS BORN',
    shortTab: '1. Intro & Mission',
    icon: Icons.favorite_rounded,
    durationEstimate: '~45s',
    points: [
      'Maternal & newborn mortality remains unacceptably high in remote communities across Northern Ghana.',
      'Frontline health workers face severed network connections, paper-based data fragmentation, and delayed diagnostic triage.',
      'CareBridge AI is an offline-first, AI-assisted health ecosystem connecting Community Health Officers (CHOs) and mothers.',
      'Designed in strict alignment with the UNICEF Nurturing Care framework to transform child survival and maternal well-being.',
    ],
    narration:
        'Hello, and welcome to our official product and technical walkthrough of CareBridge AI, built for the UNICEF AI for Nurturing Care innovation challenge. Across the rugged terrains and rural hinterlands of Northern Ghana, community healthcare faces an immense structural barrier: unreliable internet connectivity and fragmented medical records. Too often, mothers and young infants in remote CHPS zones wait days for critical clinical assessments simply because cloud-based healthcare systems cannot function without high-speed internet. CareBridge AI fundamentally breaks this paradigm. We have built an innovative, offline-first digital health companion that brings advanced clinical decision support, localized audio literacy, and resilient relational database synchronization directly onto edge mobile devices. Throughout the next six minutes, we will guide you through our comprehensive architecture, demonstrating exactly how our system delivers life-saving precision to the last mile of healthcare.',
  ),
  PitchScene(
    title: 'Role Selection & Our Two Healthcare Personas',
    subtitle: 'FRONTLINE HEALTH WORKERS VS. FAMILY CAREGIVERS',
    shortTab: '2. Role Selection',
    icon: Icons.group_rounded,
    durationEstimate: '~45s',
    points: [
      'Frontline Health Workers (CHOs): Professional clinical authority, household triage surveillance, and referral generation.',
      'Family Caregivers (Mothers & Fathers): Family-scoped nurturing care guidance and child milestone tracking without clinical write access.',
      'Strict architectural data boundary prevents unauthorized modification of medical registries while empowering parent literacy.',
    ],
    narration:
        'On your screen, you are observing our intuitive onboarding and role selection interface, titled "Who are you?". In community health ecosystems, effective software must serve both medical practitioners and patient families without compromising clinical data integrity. Therefore, CareBridge AI divides the application into two distinct operational personas: Frontline Health Workers, commonly known as Community Health Officers, and Family Caregivers, representing mothers, fathers, and local guardians. Frontline health workers receive full clinical scope access, enabling them to conduct household surveillance, evaluate physical symptoms, and issue hospital referral codes. Conversely, family caregivers experience a specialized, nurturing care interface tailored to their specific family unit. This separation is not merely cosmetic; it represents a strict architectural data boundary that protects medical registries while simultaneously empowering parents with accessible health education.',
  ),
  PitchScene(
    title: 'Secure Registration & Device-Local Cryptography',
    subtitle: 'ZERO-CLOUD PIN AUTHENTICATION & CONSENT',
    shortTab: '3. Sign-Up & PIN',
    icon: Icons.security_rounded,
    durationEstimate: '~45s',
    points: [
      'Offline account creation wizard operates seamlessly without cloud identity servers or SMS gateway dependencies.',
      'PBKDF2 cryptographic PIN stretching optimized with environment-aware dynamic iteration scaling to safeguard edge handsets.',
      'Caregivers are securely bound to a single household via a unique 6-character verification code, stopping data leakage.',
      'Mandatory ethical clinical data consent and privacy agreement notices embedded directly into the registration flow.',
    ],
    narration:
        'As our live presenter now selects the Frontline Health Worker role and initiates account registration, take notice of our secure offline sign-up and sign-in architecture. In remote health zones, practitioners frequently share community tablets or handsets. To ensure absolute patient privacy without relying on cloud identity authentication, CareBridge AI implements local cryptographic PIN hashing using the PBKDF2 algorithm with unique salts. During sign-up, the health worker establishes a secure four-digit PIN alongside their regional facility details, while caregivers are securely linked to their specific household using a unique six-character verification code provided by their worker. This guarantees zero patient data leakage. Furthermore, explicit data privacy and patient consent agreements are baked directly into the registration steps, ensuring strict compliance with ethical medical data governance before any assessment can begin.',
  ),
  PitchScene(
    title: 'Household Check-In & Family Roll Call',
    subtitle: 'SYSTEMATIC COMMUNITY SURVEILLANCE',
    shortTab: '4. Roll Call Flow',
    icon: Icons.home_work_rounded,
    durationEstimate: '~45s',
    points: [
      'Instant household triage dashboard categorizing families by real-time clinical vulnerability banding (Low, Moderate, High, Urgent).',
      'Tapping "Begin Household Check-In" launches the systematic Family Roll Call to guarantee no child or mother is overlooked.',
      'Tracks historical clinical assessments, child nutrition zones, immunization schedules, and maternal milestones in a clean interface.',
    ],
    narration:
        'With our health worker successfully signed in, we now transition into the core operational workflow: Active Household Surveillance. Notice how the dashboard categorizes community families using our automated vulnerability banding, immediately highlighting urgent cases in red and high-risk families in amber so the health worker knows who needs immediate visitation. As our presenter selects a household and taps the "Begin Household Check-In" button, we open the systematic Family Roll Call. In rural outreach, easy-to-use structural workflows are essential to ensure no newborn or mother is inadvertently overlooked. The roll call presents every registered household member, tracking their historical assessments, nutrition milestones, and upcoming immunization schedules in a clean, uncluttered clinical view.',
  ),
  PitchScene(
    title: 'Performing Interactive Clinical Assessments',
    subtitle: 'MALNUTRITION & NEONATAL TRIAGE AT THE EDGE',
    shortTab: '5. Assess Patients',
    icon: Icons.biotech_rounded,
    durationEstimate: '~55s',
    points: [
      'Interactive Mid-Upper Arm Circumference (MUAC) malnutrition gauge calculates nutrition status in real time without network latency.',
      'Instant malnutrition categorization into Severe Acute (SAM - Red), Moderate Acute (MAM - Yellow), Watch (Amber), and Adequate (Green).',
      'Comprehensive checking of over 12 neonatal danger signs including fast breathing, jaundice within 24 hours, feeding inability, and convulsions.',
    ],
    narration:
        'Let us now select a young patient from the roll call and execute a comprehensive clinical assessment. Notice how CareBridge AI replaces dense medical manuals with highly intuitive, interactive diagnostic instruments. As our presenter inputs the physical measurements, watch our live Mid-Upper Arm Circumference gauge—our digital MUAC tool. As the measurement is entered, the app instantaneously categorizes the infant\'s nutrition zone: identifying Severe Acute Malnutrition in red below eleven-point-five centimeters, Moderate Acute Malnutrition in yellow, or adequate nutrition in green. Alongside nutrition, the check-in systematically surveys neonatal danger signs. By simply tapping intuitive symptom cards for signs like abnormal fast breathing, early-onset jaundice, fever, or feeding resistance, the health worker gathers rigorous clinical data in seconds without writing on paper.',
  ),
  PitchScene(
    title: 'AI Recommendations, Referrals & Clinical Overrides',
    subtitle: 'HUMAN-IN-THE-LOOP HEALTHCARE DECISION MAKING',
    shortTab: '6. Refer & Override',
    icon: Icons.fact_check_rounded,
    durationEstimate: '~50s',
    points: [
      'Deterministic diagnostic engine immediately generates clinical treatment recommendations and referral advice upon assessment.',
      'When severe danger signs appear, an Emergency Hospital Referral code and offline QR transfer pass are instantly generated.',
      'Human-in-the-Loop Override: Experienced Community Health Officers can securely override automated referral triggers with documented clinical justification.',
    ],
    narration:
        'As soon as the assessment inputs are recorded, our built-in clinical diagnostic engines calculate immediate, actionable medical recommendations on the evaluation results screen. If critical danger signs or severe wasting are detected, the system issues a firm recommendation for emergency hospital referral, generating a verifiable digital referral code and QR transfer pass that closes the last-mile communication loop with regional hospitals. However, CareBridge AI respects professional human clinical judgment above all else. Notice our robust Human-in-the-Loop feature: if an experienced Community Health Officer determines that a routine referral is unnecessary—perhaps because treatment is already actively underway or local clinical context dictates an alternative care plan—they can securely override the app\'s referral recommendation. The app logs their clinical justification, ensuring total diagnostic accountability.',
  ),
  PitchScene(
    title: 'Inside Our Deterministic AI & Voice Engines',
    subtitle: 'HOW OUR INTELLIGENCE WORKS OFFLINE',
    shortTab: '7. AI Architecture',
    icon: Icons.psychology_alt_rounded,
    durationEstimate: '~55s',
    points: [
      'Vulnerability Engine: Synthesizes 18 clinical, social, and nutritional flags into a dynamic 0-100 index score for every household.',
      'Treatment Response Engine: Calculates exact longitudinal weight-velocity trajectories (grams per kilo per day) to catch therapeutic deterioration early.',
      'Honest Spoken Voice Engine: Bridges Northern Ghana\'s literacy barrier by synthesizing maternal guidance out loud in Dagbani, Hausa, and English.',
    ],
    narration:
        'Now, let us unpack the proprietary intelligence powering our AI system and explain exactly how it operates completely offline. Our technical architecture is driven by a trinity of specialized, deterministic rules engines running within the Dart runtime environment. First, our Vulnerability Engine synthesizes eighteen distinct physical, environmental, and socio-economic variables to dynamically compute a normalized risk score between zero and one hundred for every household. Second, our Treatment Response Engine tracks longitudinal child growth, computing exact weight velocity in grams per kilogram per day to alert health workers the very hour a malnourished child stops responding to therapeutic feeding. Third, to conquer the pervasive linguistic and literacy barriers of Northern Ghana, our honest spoken voice audio engine synthesizes maternal guidance out loud. Because commercial speech systems lack support for languages like Dagbani and Mampruli, our engine utilizes an honest fallback chain: playing studio recordings when available, bridging to the common Hausa trade language, or providing written local translation scripts.',
  ),
  PitchScene(
    title: 'Hybrid Offline SQLite Database & Synchronization',
    subtitle: 'RELIABILITY FOR THE TOUGHEST HEALTH FRONTIERS',
    shortTab: '8. Database & Sync',
    icon: Icons.rocket_launch_rounded,
    durationEstimate: '~45s',
    points: [
      'Relational SQLite local database (carebridge.db) coupled with reactive Riverpod state providers ensures instant read/write speeds without internet.',
      'Atomic Transaction Outbox: Clinical assessments and immutable synchronization payloads are committed simultaneously in hardware memory.',
      'Automatic background synchronization reconciles prioritized medical records immediately when cellular connectivity towers are reached.',
      'Over 160 automated diagnostic regression tests verify every clinical algorithm, RBAC role boundary, and navigation flow.',
    ],
    narration:
        'To conclude our demonstration, let us inspect the resilient data storage backbone that guarantees zero data loss: our Hybrid Offline-First Relational Architecture. Powered by a local SQLite database coupled with reactive Riverpod state providers, every household check-in, patient referral, and override log is saved instantly on the physical flash memory of the device. When an assessment is saved, our system employs an Atomic Transaction Outbox pattern—simultaneously writing the clinical medical record and an immutable cloud synchronization payload in a single atomic database operation. Whether our health worker is deep in the rural hinterland during a total network blackout or facing frequent power outages, data is never corrupted or dropped. The second the mobile device detects cellular connectivity near a town center, our background sync engine transmits high-priority emergency referrals first to central hospital servers. CareBridge AI combines uncompromising data engineering, empathetic voice literacy, and high-speed diagnostic AI to ensure every child in Northern Ghana survives and thrives. Thank you very much for experiencing our presentation.',
  ),
];

class AiPitchCopilotPanel extends StatefulWidget {
  const AiPitchCopilotPanel({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<AiPitchCopilotPanel> createState() => _AiPitchCopilotPanelState();
}

class _AiPitchCopilotPanelState extends State<AiPitchCopilotPanel>
    with SingleTickerProviderStateMixin {
  final FlutterTts _tts = FlutterTts();
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _autoSpeak = true;
  String _selectedVoiceName = 'Female Executive Narrator';
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _initTts();
    // Start speaking the first scene automatically upon opening
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_autoSpeak) _speakCurrent();
    });
  }

  /// Configures FlutterTTS to search for and select a professional female voice
  /// with articulate executive presentation pacing and warm pitch.
  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(
        0.50,
      ); // Measured, articulate executive pacing (~6 minutes total)
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.15); // Warmer, clear feminine tone

      // Search system synthesized voices for optimal lady / female vocal profiles
      try {
        final dynamic voices = await _tts.getVoices;
        if (voices is List) {
          for (final v in voices) {
            if (v is Map) {
              final name = '${v['name']}'.toLowerCase();
              final locale = '${v['locale']}'.toLowerCase();
              if (locale.contains('en') &&
                  (name.contains('female') ||
                      name.contains('zira') ||
                      name.contains('samantha') ||
                      name.contains('victoria') ||
                      name.contains('hazel') ||
                      name.contains('google us english') ||
                      name.contains('en-us-standard-c') ||
                      name.contains('en-us-standard-f') ||
                      name.contains('en-us-standard-g') ||
                      name.contains('en-gb-standard-a') ||
                      name.contains('woman') ||
                      name.contains('siri'))) {
                await _tts.setVoice({
                  'name': '${v['name']}',
                  'locale': '${v['locale']}',
                });
                if (mounted) {
                  setState(() => _selectedVoiceName = '${v['name']}');
                }
                break;
              }
            }
          }
        }
      } catch (_) {
        // Voice scanning fallback; pitch 1.15 maintains articulate female tone
      }

      _tts.setCompletionHandler(() {
        if (mounted) setState(() => _isPlaying = false);
      });
      _tts.setCancelHandler(() {
        if (mounted) setState(() => _isPlaying = false);
      });
      _tts.setErrorHandler((dynamic _) {
        if (mounted) setState(() => _isPlaying = false);
      });
    } catch (_) {
      // Ignore initial audio setup errors on unsupported web environments
    }
  }

  Future<void> _speakCurrent() async {
    try {
      await _tts.stop();
      if (!mounted) return;
      setState(() => _isPlaying = true);
      final scene = _kPitchScenes[_currentIndex];
      await _tts.speak(scene.narration);
    } catch (_) {
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  Future<void> _stopSpeech() async {
    try {
      await _tts.stop();
      if (mounted) setState(() => _isPlaying = false);
    } catch (_) {
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  void _selectScene(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
    if (_autoSpeak) {
      _speakCurrent();
    } else {
      _stopSpeech();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = _kPitchScenes[_currentIndex];
    final isFirst = _currentIndex == 0;
    final isLast = _currentIndex == _kPitchScenes.length - 1;

    return Container(
      width: 420,
      constraints: const BoxConstraints(maxHeight: 760),
      decoration: BoxDecoration(
        color: const Color(0xFF0D121D).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: AppColors.primaryGlow.withValues(alpha: 0.55),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.75),
            blurRadius: 36,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: AppColors.primaryGlow.withValues(alpha: 0.22),
            blurRadius: 24,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header Bar ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryDeep.withValues(alpha: 0.75),
                  const Color(0xFF161E30),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    shape: BoxShape.circle,
                    boxShadow: const [AppShadows.glow],
                  ),
                  child: const Icon(
                    Icons.record_voice_over_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '6-Min AI Pitch Copilot',
                            style: AppType.title.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.amberAccent.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                            child: Text(
                              scene.durationEstimate,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.amberAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'SCENE ${_currentIndex + 1} OF ${_kPitchScenes.length} • LADY NARRATOR',
                        style: AppType.eyebrow.copyWith(
                          color: Colors.amberAccent,
                          fontSize: 10,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    _stopSpeech();
                    widget.onClose();
                  },
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  tooltip: 'Close AI Copilot',
                ),
              ],
            ),
          ),

          // ── Scene Selector Carousel Tabs ────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: List.generate(_kPitchScenes.length, (idx) {
                final isSelected = idx == _currentIndex;
                final s = _kPitchScenes[idx];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () => _selectScene(idx),
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: isSelected ? AppColors.brandGradient : null,
                        color: isSelected
                            ? null
                            : Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? Colors.amberAccent
                              : Colors.white.withValues(alpha: 0.18),
                          width: 1,
                        ),
                        boxShadow: isSelected ? const [AppShadows.glow] : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            s.shortTab,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: isSelected ? Colors.white : Colors.white70,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            s.durationEstimate,
                            style: TextStyle(
                              fontSize: 10,
                              color: isSelected
                                  ? Colors.amberAccent
                                  : Colors.white38,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          // ── Audio Narration Control Bar ─────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2234),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _isPlaying ? _stopSpeech : _speakCurrent,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isPlaying
                          ? AppColors.triageRed
                          : AppColors.triageGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    icon: Icon(
                      _isPlaying ? Icons.stop_rounded : Icons.volume_up_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _isPlaying ? 'Stop Audio' : 'Speak Scene',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Auto-speak:',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Switch(
                    value: _autoSpeak,
                    onChanged: (v) {
                      setState(() => _autoSpeak = v);
                      if (v && !_isPlaying) _speakCurrent();
                      if (!v && _isPlaying) _stopSpeech();
                    },
                    activeColor: Colors.amberAccent,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ),
          ),

          // ── Active Speaking Wave Indicator ──────────────────────────
          if (_isPlaying)
            FadeTransition(
              opacity: _pulseCtrl,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.triageGreenBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.triageGreen.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.graphic_eq_rounded,
                      color: AppColors.triageGreen,
                      size: 17,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Lady AI Narrator speaking ($_selectedVoiceName)...',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.triageGreen,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Scene Content Area ──────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.primaryGlow.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        child: Icon(
                          scene.icon,
                          color: AppColors.primaryGlow,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              scene.subtitle,
                              style: AppType.eyebrow.copyWith(
                                color: AppColors.primaryGlow,
                                letterSpacing: 1.6,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              scene.title,
                              style: AppType.title.copyWith(
                                color: Colors.white,
                                fontSize: 18.5,
                                height: 1.25,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'KEY PRESENTATION HIGHLIGHTS & ACTIONS:',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.amberAccent,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...scene.points.map((pt) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Colors.amberAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              pt,
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: Colors.white,
                                height: 1.45,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(
                        Icons.record_voice_over_outlined,
                        size: 15,
                        color: Colors.white54,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'LADY AI NARRATOR AUDIO SCRIPT:',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white54,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131B2A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.primaryGlow.withValues(alpha: 0.35),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Text(
                      '“${scene.narration}”',
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Color(0xFFE2E8F0),
                        fontStyle: FontStyle.italic,
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // The seam between header and footer: Flutter cannot paint a
          // one-sided border alongside a borderRadius, so the hairline is
          // drawn as its own sliver instead.
          Container(height: 1, color: Colors.white.withValues(alpha: 0.12)),

          // ── Footer Navigation ───────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF131926),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(26),
              ),
            ),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: isFirst
                      ? null
                      : () => _selectScene(_currentIndex - 1),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 14),
                  label: const Text(
                    'Prev Scene',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () {
                    if (isLast) {
                      _selectScene(0); // Restart pitch loop
                    } else {
                      _selectScene(_currentIndex + 1);
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: isLast ? Colors.amber : AppColors.primary,
                    foregroundColor: isLast ? Colors.black : Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: Icon(
                    isLast
                        ? Icons.restart_alt_rounded
                        : Icons.arrow_forward_ios_rounded,
                    size: 16,
                  ),
                  label: Text(
                    isLast ? 'Restart Pitch' : 'Next Scene',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
