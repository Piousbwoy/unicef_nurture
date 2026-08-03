/// The child assessment: the WHO young-infant chart below two months, the
/// classic IMCI sick-child chart above it.
///
/// The split is by *today's age*, not the registration label — a "newborn"
/// who turned nine weeks last Tuesday is assessed on the sick-child chart,
/// and the form follows [Person.effectiveClientType] rather than trusting the
/// label.
///
/// Two things this form does that the paper charts cannot:
///
/// **The birth record walks in with the baby.** Birth weight, gestation,
/// plurality, resuscitation and delivery place are read from the record and
/// shown, not re-asked. Re-asking a birth weight the app already holds is how
/// CHOs learn to stop keeping records.
///
/// **Every measurement taken here joins the growth series.** MUAC, weight and
/// height are saved as a [GrowthMeasurement] so the trajectory engine can see
/// the slope between visits — a child falling 0.4 cm of MUAC a month is in
/// trouble while every single reading still says "yellow".
///
/// The immunisation block reads the weighing card: the CHO ticks what is
/// marked there, and the catch-up engine works out what is due today, what is
/// overdue, and what can never be given late (rotavirus).
library;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../data/reference/local_foods.dart';
import '../../domain/engines/child_engine.dart';
import '../../domain/engines/immunisation_engine.dart';
import '../../domain/engines/measurement_safety_engine.dart';
import '../../domain/engines/young_infant_engine.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../shared/ui.dart';
import 'form_kit.dart';
import 'types.dart';
import 'widgets/muac_gauge.dart';

const _uuid = Uuid();

class ChildProtocolForm extends StatefulWidget {
  const ChildProtocolForm({
    super.key,
    required this.input,
    required this.onComplete,
  });

  final AssessmentContext input;
  final ValueChanged<AssessmentDraft> onComplete;

  @override
  State<ChildProtocolForm> createState() => _ChildProtocolFormState();
}

class _ChildProtocolFormState extends State<ChildProtocolForm> {
  AssessmentContext get input => widget.input;
  Person get person => input.person;
  BirthRecord? get birth => input.birth;

  bool get isYoungInfant =>
      person.effectiveClientType == ClientType.newborn;

  bool _busy = false;

  // ------------------------------------------------------------------- Anchor
  final _ageDays = TextEditingController();
  final _ageMonths = TextEditingController();

  // ------------------------------------------------------------- Measurements
  final _rr = TextEditingController();
  final _temp = TextEditingController();
  final _weight = TextEditingController();
  final _height = TextEditingController();
  final _muac = TextEditingController();
  final _spo2 = TextEditingController();
  final _hb = TextEditingController();

  // ------------------------------------------------------------- Danger signs
  final Set<String> _signs = {};

  // ------------------------------------------------------------- Young infant
  int? _feedsPerDay;
  int? _pustules;
  bool? _bfOneHour;

  // ---------------------------------------------------------------- Sick child
  final _coughDays = TextEditingController();
  final _diarrhoeaDays = TextEditingController();
  final _feverDays = TextEditingController();
  final _earDays = TextEditingController();
  bool _rdtDone = false;
  bool? _rdtPositive;
  bool? _stillBf;
  int? _mealsPerDay;
  final Set<FoodGroup> _groups = {};
  bool _feedingChanged = false;
  bool? _appetite;
  bool _oedema = false;
  final Set<String> _vaxGiven = {};
  bool? _vitA;
  bool? _dewormed;

  /// The age anchor in days (young infant) or months (sick child), from the
  /// date of birth or from the manual box.
  int? get ageDays => person.ageInDays ?? parseInt(_ageDays);
  int? get ageMonths => person.ageInMonths ?? parseInt(_ageMonths);

  String? get _blocked {
    if (isYoungInfant && ageDays == null) {
      return 'How old is the baby, in days? The young-infant chart treats the '
          'first week differently from the rest — the age must be right.';
    }
    if (!isYoungInfant && ageMonths == null) {
      return 'How old is the child, in months? Every IMCI threshold — fast '
          'breathing, MUAC, feeding — is age-banded.';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    // Every keystroke in a measurement box must re-evaluate the age anchor
    // and the run gate; controllers do not rebuild the form on their own, so
    // the form listens to them directly.
    for (final c in _measurements) {
      c.addListener(_onEdited);
    }
    _bfOneHour = birth?.breastfedWithinOneHour;
  }

  @override
  void dispose() {
    for (final c in _measurements) {
      c.removeListener(_onEdited);
      c.dispose();
    }
    super.dispose();
  }

  /// Every text box the form owns. Kept in one list so a new measurement
  /// field gets the rebuild listener and the dispose pass automatically.
  List<TextEditingController> get _measurements => [
    _ageDays,
    _ageMonths,
    _rr,
    _temp,
    _weight,
    _height,
    _muac,
    _spo2,
    _hb,
    _coughDays,
    _diarrhoeaDays,
    _feverDays,
    _earDays,
  ];

  void _onEdited() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(Gap.lg),
          children: [
            ProtocolHeader(
              name: person.fullName,
              protocol: isYoungInfant
                  ? 'WHO IMCI — Sick Young Infant (0–59 days)'
                  : 'WHO IMCI — Sick Child (2–59 months)',
              anchor: isYoungInfant
                  ? ageDays == null
                        ? 'Age in days not yet known'
                        : '$ageDays day${ageDays == 1 ? '' : 's'} old'
                              '${ageDays! < 7 ? ' — the first week carries most neonatal deaths' : ''}'
                  : ageMonths == null
                  ? 'Age in months not yet known'
                  : '$ageMonths month${ageMonths == 1 ? '' : 's'} old · '
                        'fast breathing at ≥${ageMonths! < 12 ? 50 : 40}/min',
              caveat: person.isDobEstimated
                  ? 'Date of birth is an estimate. Age-banded thresholds below '
                        'carry lower confidence — confirm with the weighing '
                        'card where possible.'
                  : null,
            ),
            const SizedBox(height: Gap.lg),

            if (person.dateOfBirth == null)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.lg),
                child: SectionCard(
                  title: 'Age',
                  subtitle: 'No date of birth on record. Ask, or use the '
                      'weighing card.',
                  icon: Icons.calendar_month_outlined,
                  child: MeasureField(
                    label: isYoungInfant ? 'Age in days' : 'Age in months',
                    controller: isYoungInfant ? _ageDays : _ageMonths,
                    unit: isYoungInfant ? 'days' : 'months',
                    width: 160,
                  ),
                ),
              ),

            if (birth != null && isYoungInfant) ...[
              SectionCard(
                title: 'From the birth record',
                icon: Icons.assignment_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RecordLine(
                      'Birth weight',
                      birth!.birthWeightKg == null
                          ? '—'
                          : '${birth!.birthWeightKg} kg'
                                '${birth!.isLowBirthWeight ? ' — low birth weight' : ''}',
                    ),
                    _RecordLine(
                      'Gestation at birth',
                      birth!.gestationWeeksAtBirth == null
                          ? '—'
                          : '${birth!.gestationWeeksAtBirth} weeks'
                                '${birth!.gestationWeeksAtBirth! < 37 ? ' — preterm' : ''}',
                    ),
                    _RecordLine('Plurality', birth!.plurality.label),
                    _RecordLine('Place', birth!.deliveryPlace?.label ?? '—'),
                    _RecordLine(
                      'Needed resuscitation',
                      birth!.resuscitationNeeded == true ? 'Yes' : 'No',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.lg),
            ],

            if (isYoungInfant) ..._youngInfantSections()
            else ..._childSections(),

            const SizedBox(height: Gap.xxl),
          ],
        ),
      ),
      RunBar(busy: _busy, blocked: _blocked, onRun: _run),
    ],
  );

  // ------------------------------------------------------------ Young infant

  List<Widget> _youngInfantSections() => [
    SectionCard(
      title: 'Measurements',
      subtitle: 'Count the breaths for a full minute while the baby is calm.',
      icon: Icons.monitor_heart_outlined,
      child: Column(
        children: [
          MeasurePair(
            left: MeasureField(
              label: 'Respiratory rate',
              controller: _rr,
              unit: '/min',
              cutoff: 'Fast breathing ≥60 in a young infant',
            ),
            right: MeasureField(
              label: 'Temperature',
              controller: _temp,
              unit: '°C',
              decimal: true,
              cutoff: 'Fever ≥37.5 · hypothermia <35.5',
            ),
          ),
          MeasureField(
            label: 'Weight today',
            controller: _weight,
            unit: 'kg',
            decimal: true,
            cutoff: 'Saved to the growth series',
            width: 180,
          ),
        ],
      ),
    ),
    const SizedBox(height: Gap.lg),

    SectionCard(
      title: 'Danger signs',
      subtitle:
          'In a young infant almost every sign here means refer now. Off '
          'means asked and absent.',
      icon: Icons.warning_amber_rounded,
      accent: AppColors.triageRed,
      child: SignChecklist(
        signs: const [
          ('notFeeding', 'Not feeding well'),
          ('noFeed', 'Unable to feed at all'),
          ('convulsions', 'Convulsions / fits'),
          ('movesStim', 'Moves only when stimulated'),
          ('noMove', 'No movement at all'),
          ('indrawing', 'Severe chest indrawing'),
          ('fontanelle', 'Bulging fontanelle'),
        ],
        selected: _signs,
        onToggle: (k, on) =>
            setState(() => on ? _signs.add(k) : _signs.remove(k)),
      ),
    ),
    const SizedBox(height: Gap.lg),

    SectionCard(
      title: 'Local infection',
      subtitle: 'Check the cord and the skin in good light.',
      icon: Icons.healing_outlined,
      child: Column(
        children: [
          DangerSign(
            label: 'Umbilical cord red or draining pus',
            value: _signs.contains('cordRed'),
            onChanged: (v) => setState(
              () => v == true
                  ? _signs.add('cordRed')
                  : _signs.remove('cordRed'),
            ),
          ),
          DangerSign(
            label: 'Redness extends to the surrounding skin',
            value: _signs.contains('cordSpread'),
            onChanged: (v) => setState(
              () => v == true
                  ? _signs.add('cordSpread')
                  : _signs.remove('cordSpread'),
            ),
          ),
          CountField(
            label: 'Skin pustules',
            value: _pustules,
            onChanged: (v) => setState(() => _pustules = v),
            max: 20,
            why: 'Many or severe pustules are a referral sign.',
          ),
        ],
      ),
    ),
    const SizedBox(height: Gap.lg),

    SectionCard(
      title: 'Jaundice',
      icon: Icons.wb_sunny_outlined,
      child: Column(
        children: [
          DangerSign(
            label: 'Jaundice present',
            value: _signs.contains('jaundice'),
            onChanged: (v) => setState(
              () => v == true
                  ? _signs.add('jaundice')
                  : _signs.remove('jaundice'),
            ),
          ),
          DangerSign(
            label: 'Started within the first 24 hours',
            why: 'Jaundice on day one is never physiological.',
            value: _signs.contains('jaundice24'),
            onChanged: (v) => setState(
              () => v == true
                  ? _signs.add('jaundice24')
                  : _signs.remove('jaundice24'),
            ),
          ),
          DangerSign(
            label: 'Yellow palms or soles',
            value: _signs.contains('yellowPalms'),
            onChanged: (v) => setState(
              () => v == true
                  ? _signs.add('yellowPalms')
                  : _signs.remove('yellowPalms'),
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: Gap.lg),

    SectionCard(
      title: 'Diarrhoea and dehydration',
      icon: Icons.water_drop_outlined,
      child: Column(
        children: [
          DangerSign(
            label: 'Diarrhoea',
            danger: false,
            value: _signs.contains('diarrhoea'),
            onChanged: (v) => setState(
              () => v == true
                  ? _signs.add('diarrhoea')
                  : _signs.remove('diarrhoea'),
            ),
          ),
          DangerSign(
            label: 'Sunken eyes',
            value: _signs.contains('sunkenEyes'),
            onChanged: (v) => setState(
              () => v == true
                  ? _signs.add('sunkenEyes')
                  : _signs.remove('sunkenEyes'),
            ),
          ),
          DangerSign(
            label: 'Skin pinch goes back very slowly (>2 seconds)',
            value: _signs.contains('pinchVerySlow'),
            onChanged: (v) => setState(
              () => v == true
                  ? _signs.add('pinchVerySlow')
                  : _signs.remove('pinchVerySlow'),
            ),
          ),
          DangerSign(
            label: 'Skin pinch goes back slowly',
            value: _signs.contains('pinchSlow'),
            onChanged: (v) => setState(
              () => v == true
                  ? _signs.add('pinchSlow')
                  : _signs.remove('pinchSlow'),
            ),
          ),
          DangerSign(
            label: 'Restless and irritable',
            danger: false,
            value: _signs.contains('restless'),
            onChanged: (v) => setState(
              () => v == true
                  ? _signs.add('restless')
                  : _signs.remove('restless'),
            ),
          ),
          DangerSign(
            label: 'Blood in the stool',
            value: _signs.contains('bloodStool'),
            onChanged: (v) => setState(
              () => v == true
                  ? _signs.add('bloodStool')
                  : _signs.remove('bloodStool'),
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: Gap.lg),

    SectionCard(
      title: 'Feeding',
      subtitle: 'Watch a feed if you can — attachment is easier to see than '
          'to ask about.',
      icon: Icons.child_care_outlined,
      child: Column(
        children: [
          CountField(
            label: 'Breastfeeds in 24 hours',
            value: _feedsPerDay,
            onChanged: (v) => setState(() => _feedsPerDay = v),
            max: 16,
            target: 'Expected: 8 or more',
          ),
          DangerSign(
            label: 'Attachment is poor',
            value: _signs.contains('attachPoor'),
            onChanged: (v) => setState(
              () => v == true
                  ? _signs.add('attachPoor')
                  : _signs.remove('attachPoor'),
            ),
          ),
          DangerSign(
            label: 'Not suckling effectively',
            value: _signs.contains('notSuckling'),
            onChanged: (v) => setState(
              () => v == true
                  ? _signs.add('notSuckling')
                  : _signs.remove('notSuckling'),
            ),
          ),
          DangerSign(
            label: 'Receiving other foods or drinks',
            why: 'Nothing but breast milk before 6 months.',
            value: _signs.contains('otherDrinks'),
            onChanged: (v) => setState(
              () => v == true
                  ? _signs.add('otherDrinks')
                  : _signs.remove('otherDrinks'),
            ),
          ),
          DangerSign(
            label: 'Oral thrush',
            danger: false,
            value: _signs.contains('thrush'),
            onChanged: (v) => setState(
              () => v == true
                  ? _signs.add('thrush')
                  : _signs.remove('thrush'),
            ),
          ),
          DangerSign(
            label: 'Was breastfed within one hour of birth',
            danger: false,
            value: _bfOneHour,
            allowUnknown: true,
            onChanged: (v) => setState(() => _bfOneHour = v),
          ),
        ],
      ),
    ),
  ];

  // -------------------------------------------------------------- Sick child

  List<Widget> _childSections() {
    final months = ageMonths;
    final muacApplies = months != null && months >= 6;

    return [
      SectionCard(
        title: 'General danger signs',
        subtitle: 'Any one of these is a referral, whatever the rest of the '
            'chart finds.',
        icon: Icons.warning_amber_rounded,
        accent: AppColors.triageRed,
        child: SignChecklist(
          signs: const [
            ('noDrink', 'Not able to drink or breastfeed'),
            ('vomitsAll', 'Vomits everything'),
            ('convulsions', 'Had convulsions during this illness'),
            ('convulsingNow', 'Convulsing now'),
            ('lethargic', 'Lethargic or unconscious'),
          ],
          selected: _signs,
          onToggle: (k, on) =>
              setState(() => on ? _signs.add(k) : _signs.remove(k)),
        ),
      ),
      const SizedBox(height: Gap.lg),

      SectionCard(
        title: 'Cough and breathing',
        icon: Icons.air_outlined,
        child: Column(
          children: [
            DangerSign(
              label: 'Cough',
              danger: false,
              value: _signs.contains('cough'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('cough')
                    : _signs.remove('cough'),
              ),
            ),
            MeasureField(
              label: 'Cough for how long?',
              controller: _coughDays,
              unit: 'days',
              cutoff: '14 days or more needs a closer look',
              width: 160,
            ),
            DangerSign(
              label: 'Difficult breathing',
              value: _signs.contains('diffBreath'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('diffBreath')
                    : _signs.remove('diffBreath'),
              ),
            ),
            MeasurePair(
              left: MeasureField(
                label: 'Respiratory rate',
                controller: _rr,
                unit: '/min',
                cutoff: months == null
                    ? 'Fast: ≥50 under 12 months, ≥40 after'
                    : 'Fast at ≥${months < 12 ? 50 : 40}/min for this child',
              ),
              right: MeasureField(
                label: 'Oxygen saturation',
                controller: _spo2,
                unit: '%',
                cutoff: 'Below 90 is a referral',
              ),
            ),
            DangerSign(
              label: 'Chest indrawing',
              value: _signs.contains('indrawing'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('indrawing')
                    : _signs.remove('indrawing'),
              ),
            ),
            DangerSign(
              label: 'Stridor',
              value: _signs.contains('stridor'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('stridor')
                    : _signs.remove('stridor'),
              ),
            ),
            DangerSign(
              label: 'Wheeze',
              danger: false,
              value: _signs.contains('wheeze'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('wheeze')
                    : _signs.remove('wheeze'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: Gap.lg),

      SectionCard(
        title: 'Diarrhoea',
        icon: Icons.water_drop_outlined,
        child: Column(
          children: [
            DangerSign(
              label: 'Diarrhoea',
              danger: false,
              value: _signs.contains('diarrhoea'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('diarrhoea')
                    : _signs.remove('diarrhoea'),
              ),
            ),
            MeasureField(
              label: 'For how long?',
              controller: _diarrhoeaDays,
              unit: 'days',
              cutoff: '14 days or more is persistent diarrhoea',
              width: 160,
            ),
            DangerSign(
              label: 'Blood in the stool',
              value: _signs.contains('bloodStool'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('bloodStool')
                    : _signs.remove('bloodStool'),
              ),
            ),
            DangerSign(
              label: 'Sunken eyes',
              value: _signs.contains('sunkenEyes'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('sunkenEyes')
                    : _signs.remove('sunkenEyes'),
              ),
            ),
            DangerSign(
              label: 'Skin pinch goes back very slowly (>2 seconds)',
              value: _signs.contains('pinchVerySlow'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('pinchVerySlow')
                    : _signs.remove('pinchVerySlow'),
              ),
            ),
            DangerSign(
              label: 'Skin pinch goes back slowly',
              value: _signs.contains('pinchSlow'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('pinchSlow')
                    : _signs.remove('pinchSlow'),
              ),
            ),
            DangerSign(
              label: 'Restless and irritable',
              danger: false,
              value: _signs.contains('restless'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('restless')
                    : _signs.remove('restless'),
              ),
            ),
            DangerSign(
              label: 'Drinks eagerly, thirsty',
              danger: false,
              value: _signs.contains('drinksEagerly'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('drinksEagerly')
                    : _signs.remove('drinksEagerly'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: Gap.lg),

      SectionCard(
        title: 'Fever and malaria',
        subtitle:
            'Malaria is stable in the north — every fever gets an RDT, and '
            'a fever with a stiff neck is meningitis until proven otherwise.',
        icon: Icons.thermostat_outlined,
        child: Column(
          children: [
            DangerSign(
              label: 'Fever (reported or felt)',
              danger: false,
              value: _signs.contains('fever'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('fever')
                    : _signs.remove('fever'),
              ),
            ),
            MeasurePair(
              left: MeasureField(
                label: 'Temperature',
                controller: _temp,
                unit: '°C',
                decimal: true,
                cutoff: 'Fever ≥37.5',
              ),
              right: MeasureField(
                label: 'Fever for how long?',
                controller: _feverDays,
                unit: 'days',
                cutoff: '7 days or more needs investigation',
              ),
            ),
            DangerSign(
              label: 'Malaria RDT done today',
              danger: false,
              value: _rdtDone,
              onChanged: (v) => setState(() => _rdtDone = v ?? false),
            ),
            if (_rdtDone)
              ChoiceChipsField<bool>(
                label: 'RDT result',
                options: const [true, false],
                labelOf: (r) => r ? 'Positive' : 'Negative',
                value: _rdtPositive,
                onChanged: (v) => setState(() => _rdtPositive = v),
              ),
            DangerSign(
              label: 'Stiff neck',
              value: _signs.contains('stiffNeck'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('stiffNeck')
                    : _signs.remove('stiffNeck'),
              ),
            ),
            DangerSign(
              label: 'Runny nose',
              danger: false,
              value: _signs.contains('runnyNose'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('runnyNose')
                    : _signs.remove('runnyNose'),
              ),
            ),
            DangerSign(
              label: 'Measles rash',
              value: _signs.contains('measlesRash'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('measlesRash')
                    : _signs.remove('measlesRash'),
              ),
            ),
            DangerSign(
              label: 'Mouth ulcers',
              danger: false,
              value: _signs.contains('mouthUlcers'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('mouthUlcers')
                    : _signs.remove('mouthUlcers'),
              ),
            ),
            DangerSign(
              label: 'Pus draining from the eye',
              danger: false,
              value: _signs.contains('eyePus'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('eyePus')
                    : _signs.remove('eyePus'),
              ),
            ),
            DangerSign(
              label: 'Clouding of the cornea',
              value: _signs.contains('corneaClouding'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('corneaClouding')
                    : _signs.remove('corneaClouding'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: Gap.lg),

      SectionCard(
        title: 'Ear',
        icon: Icons.hearing_outlined,
        child: Column(
          children: [
            DangerSign(
              label: 'Ear pain',
              danger: false,
              value: _signs.contains('earPain'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('earPain')
                    : _signs.remove('earPain'),
              ),
            ),
            DangerSign(
              label: 'Ear discharge',
              danger: false,
              value: _signs.contains('earDischarge'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('earDischarge')
                    : _signs.remove('earDischarge'),
              ),
            ),
            MeasureField(
              label: 'Discharge for how long?',
              controller: _earDays,
              unit: 'days',
              cutoff: '14 days or more is chronic',
              width: 160,
            ),
            DangerSign(
              label: 'Tender swelling behind the ear',
              value: _signs.contains('mastoid'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('mastoid')
                    : _signs.remove('mastoid'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: Gap.lg),

      if (muacApplies) ...[
        SectionCard(
          title: 'MUAC screening',
          subtitle: 'WHO cutoffs for 6–59 months. Oedema still trumps the tape '
              '— a child with bilateral pitting oedema is SAM whatever MUAC '
              'reads.',
          icon: Icons.straighten_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MuacGauge(controller: _muac),
              const SizedBox(height: Gap.md),
              MeasureField(
                label: 'MUAC',
                controller: _muac,
                unit: 'cm',
                decimal: true,
                cutoff: 'Tap the tape. The needle and zone update as you type.',
                width: 180,
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.lg),
      ],

      SectionCard(
        title: 'Nutrition and anaemia',
        subtitle:
            'Never skipped — stunting runs near 30% in the Northern and '
            'North East regions, and a child who came for a cough can still '
            'be wasted.',
        icon: Icons.restaurant_outlined,
        child: Column(
          children: [
            if (!muacApplies)
              MeasureField(
                label: 'MUAC',
                controller: _muac,
                unit: 'cm',
                decimal: true,
                cutoff: 'MUAC applies from 6 months — use weight for this child',
                width: 180,
              ),
            MeasurePair(
              left: MeasureField(
                label: 'Weight',
                controller: _weight,
                unit: 'kg',
                decimal: true,
                cutoff: 'Saved to the growth series',
              ),
              right: MeasureField(
                label: 'Height / length',
                controller: _height,
                unit: 'cm',
                decimal: true,
              ),
            ),
            DangerSign(
              label: 'Bilateral pitting oedema',
              why: 'Oedema means SAM regardless of what the MUAC tape says.',
              value: _oedema,
              onChanged: (v) => setState(() => _oedema = v ?? false),
            ),
            DangerSign(
              label: 'Severe palmar pallor',
              value: _signs.contains('pallorSevere'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('pallorSevere')
                    : _signs.remove('pallorSevere'),
              ),
            ),
            DangerSign(
              label: 'Some palmar pallor',
              danger: false,
              value: _signs.contains('pallorSome'),
              onChanged: (v) => setState(
                () => v == true
                    ? _signs.add('pallorSome')
                    : _signs.remove('pallorSome'),
              ),
            ),
            MeasureField(
              label: 'Haemoglobin',
              controller: _hb,
              unit: 'g/dL',
              cutoff: 'Anaemia <11 · severe <7',
              width: 180,
            ),
          ],
        ),
      ),
      const SizedBox(height: Gap.lg),

      SectionCard(
        title: 'Feeding',
        subtitle: 'The 6–23 month window is where stunting is set for life.',
        icon: Icons.child_care_outlined,
        child: Column(
          children: [
            DangerSign(
              label: 'Still breastfeeding',
              danger: false,
              value: _stillBf,
              allowUnknown: true,
              onChanged: (v) => setState(() => _stillBf = v),
            ),
            CountField(
              label: 'Meals yesterday',
              value: _mealsPerDay,
              onChanged: (v) => setState(() => _mealsPerDay = v),
              max: 8,
              target: months == null
                  ? null
                  : months < 12
                  ? 'Expected: 2–3 meals plus breastfeeds'
                  : 'Expected: 3–4 meals plus breastfeeds',
            ),
            FieldLabel(
              'Food groups eaten yesterday',
              why: 'Minimum dietary diversity is 4 or more of these 8 groups.',
            ),
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: [
                for (final g in FoodGroup.values)
                  FilterChip(
                    label: Text(g.label),
                    selected: _groups.contains(g),
                    onSelected: (on) => setState(
                      () => on ? _groups.add(g) : _groups.remove(g),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Gap.md),
            DangerSign(
              label: 'Feeding changed during this illness',
              danger: false,
              value: _feedingChanged,
              onChanged: (v) => setState(() => _feedingChanged = v ?? false),
            ),
            DangerSign(
              label: 'Appetite test passed',
              why: 'Decides OTP (home RUTF) versus inpatient care in SAM.',
              value: _appetite,
              allowUnknown: true,
              onChanged: (v) => setState(() => _appetite = v),
            ),
          ],
        ),
      ),
      const SizedBox(height: Gap.lg),

      SectionCard(
        title: 'The weighing card',
        subtitle:
            'Tick what is marked on the card. The catch-up engine works out '
            'what is due today and what can never be given late.',
        icon: Icons.vaccines_outlined,
        child: Column(
          children: [
            _VaxBand(
              title: 'At birth',
              doses: _dosesDueBy(0),
              given: _vaxGiven,
              onToggle: (l, on) => setState(
                () => on ? _vaxGiven.add(l) : _vaxGiven.remove(l),
              ),
            ),
            _VaxBand(
              title: '6, 10 and 14 weeks',
              doses: _dosesDueBy(14),
              given: _vaxGiven,
              onToggle: (l, on) => setState(
                () => on ? _vaxGiven.add(l) : _vaxGiven.remove(l),
              ),
            ),
            _VaxBand(
              title: '6–9 months',
              doses: _dosesDueBy(39),
              given: _vaxGiven,
              onToggle: (l, on) => setState(
                () => on ? _vaxGiven.add(l) : _vaxGiven.remove(l),
              ),
            ),
            _VaxBand(
              title: '18 months',
              doses: _dosesDueBy(78),
              given: _vaxGiven,
              onToggle: (l, on) => setState(
                () => on ? _vaxGiven.add(l) : _vaxGiven.remove(l),
              ),
            ),
            DangerSign(
              label: 'Vitamin A in the last 6 months',
              danger: false,
              value: _vitA,
              allowUnknown: true,
              onChanged: (v) => setState(() => _vitA = v),
            ),
            DangerSign(
              label: 'Dewormed in the last 6 months',
              danger: false,
              value: _dewormed,
              allowUnknown: true,
              onChanged: (v) => setState(() => _dewormed = v),
            ),
          ],
        ),
      ),
    ];
  }

  /// Doses due within a band, excluding ones already shown in an earlier band.
  List<VaccineDose> _dosesDueBy(int weeks) => GhanaEpi.schedule
      .where((d) => d.dueAtWeeks <= weeks)
      .where((d) => weeks < 39 || d.dueAtWeeks > 14)
      .where((d) => weeks < 78 || d.dueAtWeeks > 39)
      .toList(growable: false);

  // --------------------------------------------------------------------- Run

  Future<void> _run() async {
    // Measurement-quality gate: the engines are only as safe as the numbers
    // fed into them, so anything outside a plausible physiological range is
    // surfaced for re-checking before a diagnosis is built on it.
    final flags = MeasurementSafetyEngine.checkAll({
      MeasurementKind.weightKg: parseDouble(_weight),
      MeasurementKind.heightCm: parseDouble(_height),
      MeasurementKind.muacCm: parseDouble(_muac),
      MeasurementKind.temperatureC: parseDouble(_temp),
      MeasurementKind.respiratoryRate: parseInt(_rr)?.toDouble(),
      MeasurementKind.haemoglobin: parseDouble(_hb),
      MeasurementKind.oxygenSaturation: parseInt(_spo2)?.toDouble(),
    });
    if (flags.isNotEmpty) {
      final proceed = await confirmImplausibleMeasurements(context, flags);
      if (!mounted || !proceed) return;
    }

    setState(() => _busy = true);

    final AssessmentResult result;
    final Map<String, Object?> inputs;
    GrowthMeasurement? growth;

    if (isYoungInfant) {
      final input = _youngInfantInput();
      result = YoungInfantEngine.assess(input);
      inputs = _youngInfantInputs();
      growth = _growthMeasurement();
    } else {
      final input = _childInput();
      result = ChildEngine.assess(input);
      inputs = _childInputs();
      growth = _growthMeasurement();
    }

    setState(() => _busy = false);
    widget.onComplete(
      AssessmentDraft(inputs: inputs, result: result, growth: growth),
    );
  }

  GrowthMeasurement? _growthMeasurement() {
    final muac = parseDouble(_muac);
    final weight = parseDouble(_weight);
    final height = parseDouble(_height);
    if (muac == null && weight == null && height == null && !_oedema) {
      return null;
    }
    return GrowthMeasurement(
      id: _uuid.v4(),
      personId: person.id,
      takenAt: DateTime.now(),
      muacCm: muac,
      weightKg: weight,
      heightCm: height,
      hasBilateralOedema: _oedema,
      recordedBy: input.user.id,
    );
  }

  YoungInfantInput _youngInfantInput() => YoungInfantInput(
    ageInDays: ageDays!,
    respiratoryRate: parseInt(_rr),
    temperatureCelsius: parseDouble(_temp),
    weightKg: parseDouble(_weight),
    birthWeightKg: birth?.birthWeightKg,
    gestationWeeksAtBirth: birth?.gestationWeeksAtBirth,
    isMultipleBirth: birth?.plurality != BirthPlurality.singleton,
    deliveryPlace: birth?.deliveryPlace,
    requiredResuscitation: birth?.resuscitationNeeded ?? false,
    notFeedingWell: _signs.contains('notFeeding'),
    unableToFeedAtAll: _signs.contains('noFeed'),
    convulsions: _signs.contains('convulsions'),
    movesOnlyWhenStimulated: _signs.contains('movesStim'),
    noMovementAtAll: _signs.contains('noMove'),
    severeChestIndrawing: _signs.contains('indrawing'),
    bulgingFontanelle: _signs.contains('fontanelle'),
    umbilicusRedOrDraining: _signs.contains('cordRed'),
    umbilicalRednessExtendsToSkin: _signs.contains('cordSpread'),
    skinPustulesCount: _pustules ?? 0,
    jaundicePresent: _signs.contains('jaundice'),
    jaundiceOnsetWithin24Hours: _signs.contains('jaundice24'),
    yellowPalmsOrSoles: _signs.contains('yellowPalms'),
    diarrhoea: _signs.contains('diarrhoea'),
    sunkenEyes: _signs.contains('sunkenEyes'),
    skinPinchGoesBackVerySlowly: _signs.contains('pinchVerySlow'),
    skinPinchGoesBackSlowly: _signs.contains('pinchSlow'),
    restlessOrIrritable: _signs.contains('restless'),
    bloodInStool: _signs.contains('bloodStool'),
    breastfeedsPerDay: _feedsPerDay,
    attachmentPoor: _signs.contains('attachPoor'),
    notSucklingEffectively: _signs.contains('notSuckling'),
    receivesOtherFoodsOrDrinks: _signs.contains('otherDrinks'),
    oralThrush: _signs.contains('thrush'),
    breastfedWithinOneHourOfBirth: _bfOneHour,
  );

  ChildInput _childInput() {
    final days = person.ageInDays ?? ((ageMonths ?? 0) * 30.4375).round();
    final plan = ImmunisationEngine.plan(
      ageInDays: days,
      givenLabels: _vaxGiven,
    );

    return ChildInput(
      ageInMonths: ageMonths!,
      respiratoryRate: parseInt(_rr),
      temperatureCelsius: parseDouble(_temp),
      weightKg: parseDouble(_weight),
      heightCm: parseDouble(_height),
      muacCm: parseDouble(_muac),
      hasBilateralOedema: _oedema,
      unableToDrinkOrBreastfeed: _signs.contains('noDrink'),
      vomitsEverything: _signs.contains('vomitsAll'),
      convulsions: _signs.contains('convulsions'),
      lethargicOrUnconscious: _signs.contains('lethargic'),
      convulsingNow: _signs.contains('convulsingNow'),
      cough: _signs.contains('cough'),
      coughDurationDays: parseInt(_coughDays),
      difficultBreathing: _signs.contains('diffBreath'),
      chestIndrawing: _signs.contains('indrawing'),
      stridor: _signs.contains('stridor'),
      wheeze: _signs.contains('wheeze'),
      oxygenSaturation: parseInt(_spo2),
      diarrhoea: _signs.contains('diarrhoea'),
      diarrhoeaDurationDays: parseInt(_diarrhoeaDays),
      bloodInStool: _signs.contains('bloodStool'),
      sunkenEyes: _signs.contains('sunkenEyes'),
      skinPinchVerySlow: _signs.contains('pinchVerySlow'),
      skinPinchSlow: _signs.contains('pinchSlow'),
      restlessOrIrritable: _signs.contains('restless'),
      drinksEagerly: _signs.contains('drinksEagerly'),
      feverReported: _signs.contains('fever'),
      feverDurationDays: parseInt(_feverDays),
      malariaRdtDone: _rdtDone,
      malariaRdtPositive: _rdtDone ? _rdtPositive : null,
      stiffNeck: _signs.contains('stiffNeck'),
      runnyNose: _signs.contains('runnyNose'),
      measlesRash: _signs.contains('measlesRash'),
      mouthUlcers: _signs.contains('mouthUlcers'),
      pusDrainingFromEye: _signs.contains('eyePus'),
      corneaClouding: _signs.contains('corneaClouding'),
      earPain: _signs.contains('earPain'),
      earDischarge: _signs.contains('earDischarge'),
      earDischargeDurationDays: parseInt(_earDays),
      tenderSwellingBehindEar: _signs.contains('mastoid'),
      severePalmarPallor: _signs.contains('pallorSevere'),
      somePalmarPallor: _signs.contains('pallorSome'),
      haemoglobin: parseDouble(_hb),
      stillBreastfeeding: _stillBf,
      mealsPerDay: _mealsPerDay,
      foodGroupsEatenYesterday: _groups.length,
      feedingChangedDuringIllness: _feedingChanged,
      appetiteTestPassed: _appetite,
      immunisationsUpToDate: plan.isFullyUpToDate,
      overdueVaccines: plan.overdueLabels,
      vitaminALastSixMonths: _vitA,
      dewormedLastSixMonths: _dewormed,
      householdHasValidNhis: input.hasValidNhis,
      walkingMinutesToFacility: input.walkingMinutes,
    );
  }

  Map<String, Object?> _youngInfantInputs() => {
    'protocol': 'young_infant',
    'age_in_days': ageDays,
    'respiratory_rate': parseInt(_rr),
    'temperature_celsius': parseDouble(_temp),
    'weight_kg': parseDouble(_weight),
    'danger_signs': _signs.toList()..sort(),
    'skin_pustules': _pustules,
    'breastfeeds_per_day': _feedsPerDay,
    'breastfed_within_one_hour': _bfOneHour,
  };

  Map<String, Object?> _childInputs() => {
    'protocol': 'imci_child',
    'age_in_months': ageMonths,
    'respiratory_rate': parseInt(_rr),
    'temperature_celsius': parseDouble(_temp),
    'weight_kg': parseDouble(_weight),
    'height_cm': parseDouble(_height),
    'muac_cm': parseDouble(_muac),
    'has_oedema': _oedema,
    'danger_signs': _signs.toList()..sort(),
    'cough_days': parseInt(_coughDays),
    'diarrhoea_days': parseInt(_diarrhoeaDays),
    'fever_days': parseInt(_feverDays),
    'ear_discharge_days': parseInt(_earDays),
    'oxygen_saturation': parseInt(_spo2),
    'haemoglobin': parseDouble(_hb),
    'rdt_done': _rdtDone,
    'rdt_positive': _rdtDone ? _rdtPositive : null,
    'still_breastfeeding': _stillBf,
    'meals_per_day': _mealsPerDay,
    'food_groups': [for (final g in _groups) g.name],
    'feeding_changed': _feedingChanged,
    'appetite_test': _appetite,
    'vaccines_given': _vaxGiven.toList()..sort(),
    'vitamin_a': _vitA,
    'dewormed': _dewormed,
  };
}

/// One band of the EPI schedule on the weighing card.
class _VaxBand extends StatelessWidget {
  const _VaxBand({
    required this.title,
    required this.doses,
    required this.given,
    required this.onToggle,
  });

  final String title;
  final List<VaccineDose> doses;
  final Set<String> given;
  final void Function(String label, bool on) onToggle;

  @override
  Widget build(BuildContext context) {
    if (doses.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: Gap.xs),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (final d in doses)
                FilterChip(
                  label: Text(d.label),
                  selected: given.contains(d.label),
                  onSelected: (on) => onToggle(d.label, on),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One read-only line of record-derived history.
class _RecordLine extends StatelessWidget {
  const _RecordLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
      ],
    ),
  );
}
