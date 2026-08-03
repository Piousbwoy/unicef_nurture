/// The maternal assessment: ANC for the pregnant woman, PNC for the mother
/// after delivery, and a danger-sign screen for the woman who is neither.
///
/// Three deliberate choices:
///
/// **The anchor is the first question, and the form will not run without it.**
/// Every threshold in both charts is anchored to gestational week or day after
/// delivery — "is 34 weeks" or "is day 3" changes what a fever means. Where the
/// record already knows the LMP or the delivery date, the anchor is computed
/// and shown, never re-asked.
///
/// **History comes from the record, not the conversation.** Gravida, losses,
/// caesarean history and delivery facts were captured at registration; the form
/// reads them and shows them, because re-asking them wastes the CHO's standing
/// time and teaches the record not to be kept.
///
/// **The minor complaint gets its own box.** A mother who walked an hour to say
/// "my head has been hurting since the delivery" is the hackathon's central
/// scenario. The complaint is recorded verbatim and the full danger-sign screen
/// still runs over it — a headache is also how eclampsia announces itself.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/engines/anc_engine.dart';
import '../../domain/engines/measurement_safety_engine.dart';
import '../../domain/engines/pnc_engine.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../shared/ui.dart';
import 'form_kit.dart';
import 'types.dart';

enum _Path { pregnant, delivered, general }

class MaternalProtocolForm extends StatefulWidget {
  const MaternalProtocolForm({
    super.key,
    required this.input,
    required this.onComplete,
  });

  final AssessmentContext input;
  final ValueChanged<AssessmentDraft> onComplete;

  @override
  State<MaternalProtocolForm> createState() => _MaternalProtocolFormState();
}

class _MaternalProtocolFormState extends State<MaternalProtocolForm> {
  AssessmentContext get input => widget.input;
  MaternalRecord? get record => input.maternal;

  _Path _path = _Path.pregnant;
  bool _busy = false;

  // ------------------------------------------------------------ Anchor fields
  final _weeks = TextEditingController();
  final _days = TextEditingController();

  // ------------------------------------------------------------- Measurements
  final _systolic = TextEditingController();
  final _diastolic = TextEditingController();
  final _hb = TextEditingController();
  final _weight = TextEditingController();
  final _muac = TextEditingController();
  final _fundal = TextEditingController();
  final _fhr = TextEditingController();
  final _temp = TextEditingController();
  final _pulse = TextEditingController();
  int? _proteinuria;

  // ------------------------------------------------------------ Danger signs
  final Set<String> _signs = {};

  // ------------------------------------------------------------------ History
  bool _prevStillbirth = false;
  bool _prevPph = false;
  bool? _skilledSupport;

  // ---------------------------------------------------------------- Coverage
  int? _ancContacts;
  int? _iptp;
  int? _td;
  bool? _iron;
  bool? _llin;
  bool? _hiv;
  bool? _syphilis;
  bool? _birthPlan;
  DeliveryPlace? _plannedPlace;

  // --------------------------------------------------------------------- PNC
  bool _babyAlive = true;
  final _complaint = TextEditingController();
  bool? _sad;
  bool? _noInterest;
  bool _selfHarm = false;
  bool? _bfEstablished;
  bool? _bfOneHour;
  bool _otherFoods = false;
  bool? _fpDiscussed;
  bool? _fpAccepted;
  bool? _vitA;
  int? _pncContacts;
  bool _hadPph = false;

  @override
  void initState() {
    super.initState();
    // Every keystroke in a measurement box must re-evaluate the anchor and
    // the run gate; controllers do not rebuild the form on their own, so the
    // form listens to them directly.
    for (final c in _measurements) {
      c.addListener(_onEdited);
    }
    _path = switch (input.person.effectiveClientType) {
      ClientType.pregnantWoman => _Path.pregnant,
      ClientType.postpartumWoman => _Path.delivered,
      _ => _Path.pregnant,
    };
    _ancContacts = record?.ancContactsCompleted;
    _iptp = record?.iptpDoses;
    _td = record?.tdDoses;
    _iron = record?.ironFolateSupplied;
    _llin = record?.llinSupplied;
    _hiv = record?.hivTested;
    _prevStillbirth = false;
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
    _weeks,
    _days,
    _systolic,
    _diastolic,
    _hb,
    _weight,
    _muac,
    _fundal,
    _fhr,
    _temp,
    _pulse,
    _complaint,
  ];

  void _onEdited() {
    if (mounted) setState(() {});
  }

  /// The gestational week from the record's LMP, or from the manual box.
  int? get gestationalWeeks =>
      record?.gestationalWeeks ?? parseInt(_weeks);

  /// The day after delivery from the record, or from the manual box.
  int? get postpartumDays => record?.postpartumDays ?? parseInt(_days);

  String? get _blocked {
    if (_path == _Path.pregnant && gestationalWeeks == null) {
      return 'How many weeks pregnant is she? Every threshold in the ANC chart '
          'is anchored to the week — without it the chart cannot run.';
    }
    if (_path == _Path.delivered && postpartumDays == null) {
      return 'How many days since she delivered? The first 24 hours, the first '
          'week and the rest of the puerperium each have their own risks.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final person = input.person;
    final isGeneralWoman =
        person.effectiveClientType == ClientType.womanOfReproductiveAge;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Gap.lg),
            children: [
              ProtocolHeader(
                name: person.fullName,
                protocol: switch (_path) {
                  _Path.pregnant => 'WHO ANC 2016 · 8-contact model',
                  _Path.delivered => 'Ghana PNC · days 1, 3, 7 and 42',
                  _Path.general => 'Danger-sign screen · no dedicated chart',
                },
                anchor: switch (_path) {
                  _Path.pregnant => gestationalWeeks == null
                      ? 'Gestational age not yet known'
                      : '$gestationalWeeks weeks pregnant '
                            '(${_trimester(gestationalWeeks!)} trimester)',
                  _Path.delivered => postpartumDays == null
                      ? 'Day after delivery not yet known'
                      : 'Day $postpartumDays after delivery'
                            '${postpartumDays! <= 1 ? ' — the highest-risk day' : postpartumDays! <= 7 ? ' — the highest-risk week' : ''}',
                  _Path.general =>
                    'Neither pregnant nor recently delivered — running the '
                        'danger-sign screen over her complaint',
                },
                caveat: person.isDobEstimated
                    ? 'Her age is an estimate. Age-banded recommendations below '
                          'carry lower confidence.'
                    : null,
              ),
              const SizedBox(height: Gap.lg),

              if (isGeneralWoman) ...[
                SectionCard(
                  title: 'Why is she being seen today?',
                  subtitle:
                      'The record says she is not currently pregnant or '
                      'postpartum. If that is wrong, say so — the right chart '
                      'matters more than the label.',
                  icon: Icons.help_outline_rounded,
                  child: ChoiceChipsField<_Path>(
                    label: 'Her situation',
                    options: const [
                      _Path.pregnant,
                      _Path.delivered,
                      _Path.general,
                    ],
                    labelOf: (p) => switch (p) {
                      _Path.pregnant => 'She is pregnant',
                      _Path.delivered => 'She delivered recently',
                      _Path.general => 'Neither — general check',
                    },
                    value: _path,
                    onChanged: (p) => setState(() => _path = p ?? _path),
                  ),
                ),
                const SizedBox(height: Gap.lg),
              ],

              if (_path == _Path.pregnant) ..._ancSections()
              else if (_path == _Path.delivered) ..._pncSections()
              else ..._generalSections(),

              const SizedBox(height: Gap.xxl),
            ],
          ),
        ),
        RunBar(
          busy: _busy,
          blocked: _blocked,
          onRun: _run,
        ),
      ],
    );
  }

  // --------------------------------------------------------------------- ANC

  List<Widget> _ancSections() {
    final weeks = gestationalWeeks;
    final expectedContacts = weeks == null
        ? null
        : PregnancyInput(gestationalWeeks: weeks).expectedContactsByNow;
    final expectedIptp = weeks == null
        ? null
        : PregnancyInput(gestationalWeeks: weeks).expectedIptpDoses;

    return [
      if (record?.gestationalWeeks == null)
        SectionCard(
          title: 'Gestational age',
          subtitle:
              'No last menstrual period on record. Ask her, or measure fundal '
              'height and estimate — then record the LMP at the next contact '
              'so this box disappears.',
          icon: Icons.calendar_month_outlined,
          child: MeasureField(
            label: 'Weeks pregnant',
            controller: _weeks,
            unit: 'wks',
            cutoff: 'Full term is 37–42 weeks',
            width: 160,
          ),
        )
      else
        SectionCard(
          title: 'From her record',
          icon: Icons.assignment_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RecordLine(
                'Last menstrual period',
                _pretty(record!.lastMenstrualPeriod),
              ),
              _RecordLine('Gravida / Para',
                  '${record?.gravida ?? '—'} / ${record?.parity ?? '—'}'),
              _RecordLine('Previous losses', '${record?.previousLosses ?? 0}'),
              _RecordLine(
                'Previous caesarean',
                record?.previousCaesarean == true ? 'Yes' : 'No',
              ),
              _RecordLine('Plurality', record?.plurality.label ?? '—'),
            ],
          ),
        ),
      const SizedBox(height: Gap.lg),

      SectionCard(
        title: 'Measurements',
        subtitle: 'Blank boxes are allowed — the engine says what it could not '
            'check, instead of pretending it did.',
        icon: Icons.monitor_heart_outlined,
        child: Column(
          children: [
            MeasurePair(
              left: MeasureField(
                label: 'Systolic BP',
                controller: _systolic,
                unit: 'mmHg',
                cutoff: 'High ≥140 · severe ≥160',
              ),
              right: MeasureField(
                label: 'Diastolic BP',
                controller: _diastolic,
                unit: 'mmHg',
                cutoff: 'High ≥90 · severe ≥110',
              ),
            ),
            MeasurePair(
              left: MeasureField(
                label: 'Haemoglobin',
                controller: _hb,
                unit: 'g/dL',
                cutoff: 'Anaemia <11 · severe <7',
              ),
              right: MeasureField(
                label: 'MUAC',
                controller: _muac,
                unit: 'cm',
                cutoff: 'Undernutrition <23 in pregnancy',
              ),
            ),
            MeasurePair(
              left: MeasureField(
                label: 'Weight',
                controller: _weight,
                unit: 'kg',
                decimal: true,
              ),
              right: MeasureField(
                label: 'Fundal height',
                controller: _fundal,
                unit: 'cm',
                cutoff: 'Should roughly match the week from ~20 wks',
              ),
            ),
            MeasurePair(
              left: MeasureField(
                label: 'Foetal heart rate',
                controller: _fhr,
                unit: 'bpm',
                cutoff: 'Normal 120–160',
              ),
              right: ChoiceChipsField<int>(
                label: 'Protein in urine',
                why: 'With high BP this separates gestational hypertension '
                    'from pre-eclampsia.',
                options: const [0, 1, 2, 3, 4],
                labelOf: (v) => v == 0 ? 'Nil' : '+$v',
                value: _proteinuria,
                onChanged: (v) => setState(() => _proteinuria = v),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: Gap.lg),

      SectionCard(
        title: 'Danger signs',
        subtitle: 'Any one of these is a referral today. Off means asked and '
            'absent — do not tick off what was not asked.',
        icon: Icons.warning_amber_rounded,
        accent: AppColors.triageRed,
        child: SignChecklist(
          signs: const [
            ('bleeding', 'Vaginal bleeding'),
            ('headache', 'Severe headache'),
            ('vision', 'Blurred vision'),
            ('convulsions', 'Convulsions / fits'),
            ('abdoPain', 'Severe abdominal pain'),
            ('reducedFM', 'Reduced foetal movement'),
            ('noFM', 'No foetal movement felt'),
            ('leaking', 'Leaking fluid'),
            ('fever', 'Fever'),
            ('swelling', 'Swelling of face and hands'),
            ('breathing', 'Difficulty breathing'),
            ('urination', 'Painful urination'),
            ('vomiting', 'Persistent vomiting'),
          ],
          selected: _signs,
          onToggle: (k, on) =>
              setState(() => on ? _signs.add(k) : _signs.remove(k)),
        ),
      ),
      const SizedBox(height: Gap.lg),

      SectionCard(
        title: 'History the chart needs',
        subtitle: 'Two things the registration form does not ask, because they '
            'only matter once she is pregnant.',
        icon: Icons.history_outlined,
        child: Column(
          children: [
            DangerSign(
              label: 'A previous baby was stillborn',
              why: 'The strongest single predictor of the next outcome.',
              value: _prevStillbirth,
              onChanged: (v) => setState(() => _prevStillbirth = v ?? false),
            ),
            DangerSign(
              label: 'She bled heavily after a previous delivery',
              value: _prevPph,
              onChanged: (v) => setState(() => _prevPph = v ?? false),
            ),
            DangerSign(
              label: 'Someone skilled will be with her at the delivery',
              danger: false,
              value: _skilledSupport,
              allowUnknown: true,
              onChanged: (v) => setState(() => _skilledSupport = v),
            ),
          ],
        ),
      ),
      const SizedBox(height: Gap.lg),

      SectionCard(
        title: 'Coverage so far',
        subtitle: 'What the record shows, corrected if today\u2019s visit '
            'changes it.',
        icon: Icons.shield_outlined,
        child: Column(
          children: [
            CountField(
              label: 'ANC contacts completed',
              value: _ancContacts,
              onChanged: (v) => setState(() => _ancContacts = v),
              max: 8,
              target: expectedContacts == null
                  ? 'WHO schedule: 8 contacts'
                  : 'Expected by week $weeks: $expectedContacts',
            ),
            CountField(
              label: 'IPTp doses (malaria)',
              value: _iptp,
              onChanged: (v) => setState(() => _iptp = v),
              max: 6,
              target: expectedIptp == null
                  ? 'From 16 weeks, monthly'
                  : 'Expected by now: $expectedIptp',
            ),
            CountField(
              label: 'Td doses',
              value: _td,
              onChanged: (v) => setState(() => _td = v),
              max: 5,
            ),
            DangerSign(
              label: 'Taking iron and folate',
              danger: false,
              value: _iron,
              allowUnknown: true,
              onChanged: (v) => setState(() => _iron = v),
            ),
            DangerSign(
              label: 'Sleeps under a treated net',
              danger: false,
              value: _llin,
              allowUnknown: true,
              onChanged: (v) => setState(() => _llin = v),
            ),
            DangerSign(
              label: 'HIV test done this pregnancy',
              danger: false,
              value: _hiv,
              allowUnknown: true,
              onChanged: (v) => setState(() => _hiv = v),
            ),
            DangerSign(
              label: 'Syphilis test done this pregnancy',
              danger: false,
              value: _syphilis,
              allowUnknown: true,
              onChanged: (v) => setState(() => _syphilis = v),
            ),
            DangerSign(
              label: 'A birth plan has been made',
              danger: false,
              value: _birthPlan,
              allowUnknown: true,
              onChanged: (v) => setState(() => _birthPlan = v),
            ),
            ChoiceChipsField<DeliveryPlace>(
              label: 'Where does she plan to deliver?',
              options: DeliveryPlace.values,
              labelOf: (p) => p.label,
              value: _plannedPlace,
              dangerIf: (p) => p.isUnattendedBySkilledProvider,
              onChanged: (v) => setState(() => _plannedPlace = v),
            ),
          ],
        ),
      ),
    ];
  }

  // --------------------------------------------------------------------- PNC

  List<Widget> _pncSections() {
    final days = postpartumDays;
    final expectedContacts = days == null
        ? null
        : PostpartumInput(daysSinceDelivery: days).expectedContactsByNow;

    return [
      if (record?.postpartumDays == null)
        SectionCard(
          title: 'When did she deliver?',
          subtitle:
              'No delivery date on record. The day count decides which risks '
              'the chart looks for.',
          icon: Icons.calendar_month_outlined,
          child: MeasureField(
            label: 'Days since delivery',
            controller: _days,
            unit: 'days',
            cutoff: 'Day 1 and days 2–7 carry most maternal deaths',
            width: 160,
          ),
        )
      else
        SectionCard(
          title: 'From her record',
          icon: Icons.assignment_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RecordLine('Delivery date', _pretty(record!.deliveryDate)),
              _RecordLine('Place', record?.deliveryPlace?.label ?? '—'),
              _RecordLine('Mode', record?.deliveryMode?.label ?? '—'),
              _RecordLine('Plurality', record?.plurality.label ?? '—'),
              if (record?.deliveryPlace?.isUnattendedBySkilledProvider == true)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.sm),
                  child: Text(
                    'Delivered without a skilled provider — the newborn '
                    'checks and vitamin K must be verified.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: AppColors.triageAmber,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      const SizedBox(height: Gap.lg),

      SectionCard(
        title: 'First — is her baby alive?',
        subtitle:
            'This changes the whole conversation. A bereaved mother gets '
            'grief support and her own care, not breastfeeding coaching.',
        icon: Icons.favorite_outline_rounded,
        accent: _babyAlive ? null : AppColors.triageAmber,
        child: YesNoField(
          value: _babyAlive,
          yesLabel: 'Alive',
          noLabel: 'Died',
          dangerOnYes: false,
          onChanged: (v) => setState(() => _babyAlive = v ?? true),
        ),
      ),
      const SizedBox(height: Gap.lg),

      SectionCard(
        title: 'What she came with',
        subtitle:
            'Her own words. The danger-sign screen below still runs over it — '
            'a "minor" headache is also how eclampsia starts.',
        icon: Icons.chat_bubble_outline_rounded,
        child: TextField(
          controller: _complaint,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'e.g. headache since the delivery, burning when urinating',
          ),
        ),
      ),
      const SizedBox(height: Gap.lg),

      SectionCard(
        title: 'Measurements',
        subtitle: 'Blank boxes are allowed — the engine says what it could not '
            'check.',
        icon: Icons.monitor_heart_outlined,
        child: Column(
          children: [
            MeasurePair(
              left: MeasureField(
                label: 'Systolic BP',
                controller: _systolic,
                unit: 'mmHg',
                cutoff: 'High ≥140 · severe ≥160',
              ),
              right: MeasureField(
                label: 'Diastolic BP',
                controller: _diastolic,
                unit: 'mmHg',
                cutoff: 'High ≥90 · severe ≥110',
              ),
            ),
            MeasurePair(
              left: MeasureField(
                label: 'Temperature',
                controller: _temp,
                unit: '°C',
                decimal: true,
                cutoff: 'Fever ≥38.0',
              ),
              right: MeasureField(
                label: 'Pulse',
                controller: _pulse,
                unit: 'bpm',
                cutoff: 'Fast >110',
              ),
            ),
            MeasurePair(
              left: MeasureField(
                label: 'Haemoglobin',
                controller: _hb,
                unit: 'g/dL',
                cutoff: 'Anaemia <11 · severe <7',
              ),
              right: MeasureField(
                label: 'MUAC',
                controller: _muac,
                unit: 'cm',
                cutoff: 'Undernutrition <23 while breastfeeding',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: Gap.lg),

      SectionCard(
        title: 'Danger signs',
        subtitle: 'Any one of these is a referral today.',
        icon: Icons.warning_amber_rounded,
        accent: AppColors.triageRed,
        child: SignChecklist(
          signs: const [
            ('heavyBleeding', 'Heavy vaginal bleeding'),
            ('foulDischarge', 'Foul-smelling discharge'),
            ('fever', 'Fever'),
            ('headache', 'Severe headache'),
            ('vision', 'Blurred vision'),
            ('convulsions', 'Convulsions / fits'),
            ('abdoPain', 'Severe abdominal pain'),
            ('legPain', 'Painful, swollen leg'),
            ('breathing', 'Difficulty breathing'),
            ('breastPain', 'Breast pain or lump'),
            ('crackedNipples', 'Cracked nipples'),
            ('urination', 'Painful urination'),
            ('perineal', 'Perineal pain or pus'),
            ('csWound', 'Caesarean wound red or draining'),
            ('leakage', 'Faecal or urinary leakage'),
            ('dizziness', 'Dizziness or fainting'),
          ],
          selected: _signs,
          onToggle: (k, on) =>
              setState(() => on ? _signs.add(k) : _signs.remove(k)),
        ),
      ),
      const SizedBox(height: Gap.lg),

      SectionCard(
        title: 'How is she feeling?',
        subtitle:
            'Postnatal depression is routinely missed and quietly undermines '
            'every feeding decision she makes. Ask gently, in her language.',
        icon: Icons.psychology_outlined,
        child: Column(
          children: [
            DangerSign(
              label: 'Sad or tearful most days',
              danger: false,
              value: _sad,
              allowUnknown: true,
              onChanged: (v) => setState(() => _sad = v),
            ),
            DangerSign(
              label: 'Lost interest in the baby',
              danger: false,
              value: _noInterest,
              allowUnknown: true,
              onChanged: (v) => setState(() => _noInterest = v),
            ),
            DangerSign(
              label: 'Thoughts of harming herself',
              why: 'A yes is an urgent referral, whatever else is normal.',
              value: _selfHarm,
              onChanged: (v) => setState(() => _selfHarm = v ?? false),
            ),
          ],
        ),
      ),

      if (_babyAlive) ...[
        const SizedBox(height: Gap.lg),
        SectionCard(
          title: 'Feeding the baby',
          icon: Icons.child_care_outlined,
          child: Column(
            children: [
              DangerSign(
                label: 'Breastfeeding is established',
                danger: false,
                value: _bfEstablished,
                allowUnknown: true,
                onChanged: (v) => setState(() => _bfEstablished = v),
              ),
              DangerSign(
                label: 'Baby was put to the breast within one hour of birth',
                danger: false,
                value: _bfOneHour,
                allowUnknown: true,
                onChanged: (v) => setState(() => _bfOneHour = v),
              ),
              DangerSign(
                label: 'Giving the baby water or other foods',
                why: 'Before 6 months this displaces breast milk and carries '
                    'infection.',
                value: _otherFoods,
                onChanged: (v) => setState(() => _otherFoods = v ?? false),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: Gap.lg),

      SectionCard(
        title: 'Services',
        icon: Icons.medical_services_outlined,
        child: Column(
          children: [
            CountField(
              label: 'PNC contacts completed',
              value: _pncContacts,
              onChanged: (v) => setState(() => _pncContacts = v),
              max: 6,
              target: expectedContacts == null
                  ? 'Schedule: day 1, 3, 7, 42'
                  : 'Expected by day $days: $expectedContacts',
            ),
            DangerSign(
              label: 'She bled heavily after this delivery',
              value: _hadPph,
              onChanged: (v) => setState(() => _hadPph = v ?? false),
            ),
            DangerSign(
              label: 'Family planning discussed',
              danger: false,
              value: _fpDiscussed,
              allowUnknown: true,
              onChanged: (v) => setState(() => _fpDiscussed = v),
            ),
            DangerSign(
              label: 'A method accepted',
              danger: false,
              value: _fpAccepted,
              allowUnknown: true,
              onChanged: (v) => setState(() => _fpAccepted = v),
            ),
            DangerSign(
              label: 'Taking iron and folate',
              danger: false,
              value: _iron,
              allowUnknown: true,
              onChanged: (v) => setState(() => _iron = v),
            ),
            DangerSign(
              label: 'Vitamin A given after delivery',
              danger: false,
              value: _vitA,
              allowUnknown: true,
              onChanged: (v) => setState(() => _vitA = v),
            ),
          ],
        ),
      ),
    ];
  }

  // ----------------------------------------------------------------- General

  List<Widget> _generalSections() => [
    SectionCard(
      title: 'Her complaint',
      icon: Icons.chat_bubble_outline_rounded,
      child: TextField(
        controller: _complaint,
        maxLines: 2,
        decoration: const InputDecoration(
          hintText: 'What brought her today, in her own words',
        ),
      ),
    ),
    const SizedBox(height: Gap.lg),
    SectionCard(
      title: 'Measurements',
      icon: Icons.monitor_heart_outlined,
      child: Column(
        children: [
          MeasurePair(
            left: MeasureField(
              label: 'Systolic BP',
              controller: _systolic,
              unit: 'mmHg',
              cutoff: 'High ≥140 · severe ≥160',
            ),
            right: MeasureField(
              label: 'Diastolic BP',
              controller: _diastolic,
              unit: 'mmHg',
              cutoff: 'High ≥90 · severe ≥110',
            ),
          ),
          MeasurePair(
            left: MeasureField(
              label: 'Temperature',
              controller: _temp,
              unit: '°C',
              decimal: true,
              cutoff: 'Fever ≥38.0',
            ),
            right: MeasureField(
              label: 'Haemoglobin',
              controller: _hb,
              unit: 'g/dL',
              cutoff: 'Anaemia <11',
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: Gap.lg),
    SectionCard(
      title: 'Danger signs',
      subtitle: 'The signs that kill, screened over whatever she came with.',
      icon: Icons.warning_amber_rounded,
      accent: AppColors.triageRed,
      child: SignChecklist(
        signs: const [
          ('heavyBleeding', 'Heavy or irregular vaginal bleeding'),
          ('fever', 'Fever'),
          ('headache', 'Severe headache'),
          ('vision', 'Blurred vision'),
          ('convulsions', 'Convulsions / fits'),
          ('abdoPain', 'Severe abdominal pain'),
          ('breathing', 'Difficulty breathing'),
          ('dizziness', 'Dizziness or fainting'),
        ],
        selected: _signs,
        onToggle: (k, on) =>
            setState(() => on ? _signs.add(k) : _signs.remove(k)),
      ),
    ),
    const SizedBox(height: Gap.lg),
    SectionCard(
      title: 'How is she feeling?',
      icon: Icons.psychology_outlined,
      child: Column(
        children: [
          DangerSign(
            label: 'Sad or tearful most days',
            danger: false,
            value: _sad,
            allowUnknown: true,
            onChanged: (v) => setState(() => _sad = v),
          ),
          DangerSign(
            label: 'Thoughts of harming herself',
            value: _selfHarm,
            onChanged: (v) => setState(() => _selfHarm = v ?? false),
          ),
        ],
      ),
    ),
  ];

  // --------------------------------------------------------------------- Run

  Future<void> _run() async {
    // Measurement-quality gate: the engines are only as safe as the numbers
    // fed into them, so anything outside a plausible physiological range is
    // surfaced for re-checking before a diagnosis is built on it.
    final systolic = parseInt(_systolic)?.toDouble();
    final diastolic = parseInt(_diastolic)?.toDouble();
    final flags = MeasurementSafetyEngine.checkAll({
      MeasurementKind.systolicBp: systolic,
      MeasurementKind.diastolicBp: diastolic,
      MeasurementKind.haemoglobin: parseDouble(_hb),
      MeasurementKind.weightKg: parseDouble(_weight),
      MeasurementKind.muacCm: parseDouble(_muac),
      MeasurementKind.temperatureC: parseDouble(_temp),
      MeasurementKind.heartRate: parseInt(_pulse)?.toDouble(),
      MeasurementKind.gestationalWeeks: gestationalWeeks?.toDouble(),
    });
    final bp = MeasurementSafetyEngine.checkBloodPressure(
      systolic: systolic,
      diastolic: diastolic,
    );
    if (bp != null) flags.add(bp);
    if (flags.isNotEmpty) {
      final proceed = await confirmImplausibleMeasurements(context, flags);
      if (!mounted || !proceed) return;
    }

    setState(() => _busy = true);

    final AssessmentResult result;
    final Map<String, Object?> inputs;

    switch (_path) {
      case _Path.pregnant:
        result = AncEngine.assess(_pregnancyInput());
        inputs = _pregnancyInputs();
      case _Path.delivered:
        result = PncEngine.assess(_postpartumInput());
        inputs = _postpartumInputs();
      case _Path.general:
        // No dedicated chart exists for a woman who is neither pregnant nor
        // recently delivered, and inventing one here would be worse than saying
        // so. The PNC engine at day 60 — past the 42-day puerperium — still
        // screens the danger signs that kill, and its puerperium-specific
        // advice falls away on its own.
        result = PncEngine.assess(_generalInput());
        inputs = _generalInputs();
    }

    setState(() => _busy = false);
    widget.onComplete(AssessmentDraft(inputs: inputs, result: result));
  }

  PregnancyInput _pregnancyInput() => PregnancyInput(
    gestationalWeeks: gestationalWeeks!,
    maternalAgeYears: input.person.ageInYears,
    gravida: record?.gravida,
    parity: record?.parity,
    previousLosses: record?.previousLosses ?? 0,
    previousCaesarean: record?.previousCaesarean ?? false,
    previousStillbirth: _prevStillbirth,
    previousPostpartumHaemorrhage: _prevPph,
    plurality: record?.plurality ?? BirthPlurality.singleton,
    systolic: parseInt(_systolic),
    diastolic: parseInt(_diastolic),
    haemoglobin: parseDouble(_hb),
    weightKg: parseDouble(_weight),
    muacCm: parseDouble(_muac),
    fundalHeightCm: parseInt(_fundal),
    foetalHeartRate: parseInt(_fhr),
    proteinuria: _proteinuria,
    vaginalBleeding: _signs.contains('bleeding'),
    severeHeadache: _signs.contains('headache'),
    blurredVision: _signs.contains('vision'),
    convulsions: _signs.contains('convulsions'),
    severeAbdominalPain: _signs.contains('abdoPain'),
    reducedFoetalMovement: _signs.contains('reducedFM'),
    noFoetalMovement: _signs.contains('noFM'),
    leakingFluid: _signs.contains('leaking'),
    fever: _signs.contains('fever'),
    swellingOfFaceAndHands: _signs.contains('swelling'),
    difficultyBreathing: _signs.contains('breathing'),
    painfulUrination: _signs.contains('urination'),
    persistentVomiting: _signs.contains('vomiting'),
    ancContactsCompleted: _ancContacts ?? 0,
    iptpDoses: _iptp ?? 0,
    tdDoses: _td ?? 0,
    ironFolateTaken: _iron,
    sleepsUnderTreatedNet: _llin,
    hivTested: _hiv,
    syphilisTested: _syphilis,
    birthPlanMade: _birthPlan,
    plannedDeliveryPlace: _plannedPlace,
    householdHasValidNhis: input.hasValidNhis,
    walkingMinutesToFacility: input.walkingMinutes,
    hasSkilledSupportAtHome: _skilledSupport,
  );

  PostpartumInput _postpartumInput() => PostpartumInput(
    daysSinceDelivery: postpartumDays!,
    maternalAgeYears: input.person.ageInYears,
    deliveryPlace: record?.deliveryPlace,
    deliveryMode: record?.deliveryMode,
    plurality: record?.plurality ?? BirthPlurality.singleton,
    hadPostpartumHaemorrhage: _hadPph,
    babyAlive: _babyAlive,
    systolic: parseInt(_systolic),
    diastolic: parseInt(_diastolic),
    temperatureCelsius: parseDouble(_temp),
    haemoglobin: parseDouble(_hb),
    muacCm: parseDouble(_muac),
    pulse: parseInt(_pulse),
    heavyBleeding: _signs.contains('heavyBleeding'),
    foulSmellingDischarge: _signs.contains('foulDischarge'),
    fever: _signs.contains('fever'),
    severeHeadache: _signs.contains('headache'),
    blurredVision: _signs.contains('vision'),
    convulsions: _signs.contains('convulsions'),
    severeAbdominalPain: _signs.contains('abdoPain'),
    painfulSwollenLeg: _signs.contains('legPain'),
    difficultyBreathing: _signs.contains('breathing'),
    breastPainOrLump: _signs.contains('breastPain'),
    crackedNipples: _signs.contains('crackedNipples'),
    painfulUrination: _signs.contains('urination'),
    perinealPainOrPus: _signs.contains('perineal'),
    caesareanWoundRedOrDraining: _signs.contains('csWound'),
    faecalOrUrinaryLeakage: _signs.contains('leakage'),
    dizzinessOrFainting: _signs.contains('dizziness'),
    presentingComplaint: _complaint.text.trim().isEmpty
        ? null
        : _complaint.text.trim(),
    feelingSadMostDays: _sad,
    lostInterestInBaby: _noInterest,
    thoughtsOfSelfHarm: _selfHarm,
    breastfeedingEstablished: _babyAlive ? _bfEstablished : null,
    breastfedWithinOneHourOfBirth: _babyAlive ? _bfOneHour : null,
    givingOtherFoodsOrWater: _babyAlive ? _otherFoods : false,
    familyPlanningDiscussed: _fpDiscussed,
    familyPlanningAccepted: _fpAccepted,
    ironFolateTaken: _iron,
    vitaminAGivenPostpartum: _vitA,
    householdHasValidNhis: input.hasValidNhis,
    walkingMinutesToFacility: input.walkingMinutes,
    pncContactsCompleted: _pncContacts ?? 0,
  );

  /// The general screen borrows the PNC engine at day 60, past the puerperium.
  PostpartumInput _generalInput() => PostpartumInput(
    daysSinceDelivery: 60,
    maternalAgeYears: input.person.ageInYears,
    babyAlive: true,
    systolic: parseInt(_systolic),
    diastolic: parseInt(_diastolic),
    temperatureCelsius: parseDouble(_temp),
    haemoglobin: parseDouble(_hb),
    heavyBleeding: _signs.contains('heavyBleeding'),
    fever: _signs.contains('fever'),
    severeHeadache: _signs.contains('headache'),
    blurredVision: _signs.contains('vision'),
    convulsions: _signs.contains('convulsions'),
    severeAbdominalPain: _signs.contains('abdoPain'),
    difficultyBreathing: _signs.contains('breathing'),
    dizzinessOrFainting: _signs.contains('dizziness'),
    presentingComplaint: complaintOrNull(),
    feelingSadMostDays: _sad,
    thoughtsOfSelfHarm: _selfHarm,
    householdHasValidNhis: input.hasValidNhis,
    walkingMinutesToFacility: input.walkingMinutes,
  );

  String? complaintOrNull() =>
      _complaint.text.trim().isEmpty ? null : _complaint.text.trim();

  Map<String, Object?> _pregnancyInputs() => {
    'protocol': 'anc',
    'gestational_weeks': gestationalWeeks,
    'anchor_from_record': record?.gestationalWeeks != null,
    'systolic': parseInt(_systolic),
    'diastolic': parseInt(_diastolic),
    'haemoglobin': parseDouble(_hb),
    'weight_kg': parseDouble(_weight),
    'muac_cm': parseDouble(_muac),
    'fundal_height_cm': parseInt(_fundal),
    'foetal_heart_rate': parseInt(_fhr),
    'proteinuria': _proteinuria,
    'danger_signs': _signs.toList()..sort(),
    'previous_stillbirth': _prevStillbirth,
    'previous_pph': _prevPph,
    'skilled_support_at_home': _skilledSupport,
    'anc_contacts_completed': _ancContacts,
    'iptp_doses': _iptp,
    'td_doses': _td,
    'iron_folate': _iron,
    'llin': _llin,
    'hiv_tested': _hiv,
    'syphilis_tested': _syphilis,
    'birth_plan': _birthPlan,
    'planned_delivery_place': _plannedPlace?.name,
  };

  Map<String, Object?> _postpartumInputs() => {
    'protocol': 'pnc',
    'days_since_delivery': postpartumDays,
    'anchor_from_record': record?.postpartumDays != null,
    'baby_alive': _babyAlive,
    'presenting_complaint': complaintOrNull(),
    'systolic': parseInt(_systolic),
    'diastolic': parseInt(_diastolic),
    'temperature_celsius': parseDouble(_temp),
    'haemoglobin': parseDouble(_hb),
    'muac_cm': parseDouble(_muac),
    'pulse': parseInt(_pulse),
    'danger_signs': _signs.toList()..sort(),
    'had_pph_this_delivery': _hadPph,
    'sad_most_days': _sad,
    'lost_interest_in_baby': _noInterest,
    'thoughts_of_self_harm': _selfHarm,
    'breastfeeding_established': _bfEstablished,
    'breastfed_within_one_hour': _bfOneHour,
    'other_foods_or_water': _otherFoods,
    'fp_discussed': _fpDiscussed,
    'fp_accepted': _fpAccepted,
    'iron_folate': _iron,
    'vitamin_a': _vitA,
    'pnc_contacts_completed': _pncContacts,
  };

  Map<String, Object?> _generalInputs() => {
    'protocol': 'general',
    'presenting_complaint': complaintOrNull(),
    'systolic': parseInt(_systolic),
    'diastolic': parseInt(_diastolic),
    'temperature_celsius': parseDouble(_temp),
    'haemoglobin': parseDouble(_hb),
    'danger_signs': _signs.toList()..sort(),
    'sad_most_days': _sad,
    'thoughts_of_self_harm': _selfHarm,
  };

  String _trimester(int weeks) =>
      weeks < 13 ? '1st' : (weeks < 28 ? '2nd' : '3rd');

  String _pretty(DateTime? d) => d == null
      ? '—'
      : '${d.day} ${_months[d.month - 1]} ${d.year}';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
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
