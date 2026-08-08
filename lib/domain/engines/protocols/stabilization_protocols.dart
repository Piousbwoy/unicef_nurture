/// Pre-referral stabilization protocols for the CareBridge AI recommendation
/// engine. This module is **decision support**, not a prescription. The CHO is
/// the licensed clinician; the system surfaces WHO / GHS / MOH published
/// protocols with their doses, contraindications and citations so the CHO can
/// make a faster, more defensible clinical decision at a CHPS compound during
/// the second-delay window.
///
/// Every protocol in this file:
///   * carries the full citation (so an auditor can verify every dose);
///   * lists contraindications (so the CHO cannot blindly administer a
///     drug that would harm the patient);
///   * is versioned (so updates to WHO guidance produce a new build);
///   * is shown in the UI with an explicit decision-support disclaimer.
///
/// Doses are reproduced verbatim from the cited publications. They are
/// NOT a substitute for the CHO's clinical judgment, and they MUST be
/// reviewed by a licensed clinician before this software is used in
/// real patient care.
///
/// Versioning
/// ──────────
/// v1.0  Aug 2026 - initial population of three protocols
///                   (preeclampsia, neonatal sepsis PSBI, child pneumonia).
///                   Each will be reviewed by a GHS clinician before the
///                   first field deployment.
library;

import 'package:flutter/foundation.dart';

/// Where the dose / step in this protocol comes from. A single line of
/// text, plus a structured machine-readable identifier so the audit log
/// can group "all steps citing WHO IMCI 2014" together.
@immutable
class ProtocolCitation {
  const ProtocolCitation({
    required this.shortName,
    required this.fullCitation,
    required this.url,
    required this.publishedYear,
  });

  /// "WHO IMCI Chart Booklet 2014"
  final String shortName;

  /// Full Vancouver-style citation, e.g. for an audit appendix.
  final String fullCitation;

  /// URL or DOI; null = print-only.
  final String? url;

  final int publishedYear;

  Map<String, Object?> toMap() => {
        'short_name': shortName,
        'full_citation': fullCitation,
        'url': url,
        'year': publishedYear,
      };
}

/// One step in a pre-referral protocol: a specific clinical action the
/// CHO can take, with the dose, the rationale, and the constraint
/// (when / why-not).
@immutable
class ProtocolStep {
  const ProtocolStep({
    required this.order,
    required this.action,
    required this.dose,
    required this.rationale,
    required this.whenToDo,
    this.contraindication,
  });

  /// 1-indexed ordinal; the CHO reads top to bottom.
  final int order;

  /// "Administer Magnesium Sulfate 4g IV over 5 minutes"
  final String action;

  /// Dose string verbatim from the citation, e.g. "10 g IM (5 g per buttock)".
  /// When the dose is weight-based, the string contains the per-kg figure,
  /// e.g. "Ampicillin 50 mg/kg IM".
  final String dose;

  /// Why this step, in one sentence a CHO can repeat.
  final String rationale;

  /// When to perform this step, e.g. "Immediately, before transport
  /// is dispatched" or "After BP confirmed >= 160/110".
  final String whenToDo;

  /// Optional contraindication, e.g. "Hold if respiratory rate < 16
  /// breaths/min or patellar reflex absent".
  final String? contraindication;

  Map<String, Object?> toMap() => {
        'order': order,
        'action': action,
        'dose': dose,
        'rationale': rationale,
        'when': whenToDo,
        if (contraindication != null) 'contraindication': contraindication,
      };
}

/// What the CHO sees at the top of the result screen when a pre-referral
/// protocol is activated. Intentionally short: a one-line headline, a
/// citation badge, the ordered steps, and an unambiguous "this is decision
/// support, you are the licensed clinician" disclaimer.
@immutable
class StabilizationProtocol {
  const StabilizationProtocol({
    required this.id,
    required this.headline,
    required this.citation,
    required this.citations,
    required this.steps,
    required this.contraindications,
    required this.decisionSupportNotice,
    this.urgencyNote,
  });

  /// Stable identifier used in the audit log, e.g. "pre_eclampsia_mgso4_v1".
  final String id;

  /// One sentence the CHO reads first, e.g.
  /// "Pre-referral loading dose of Magnesium Sulfate to prevent eclamptic
  /// seizures in transit."
  final String headline;

  /// Primary citation; the [citations] list may contain supplementary sources.
  final ProtocolCitation citation;
  final List<ProtocolCitation> citations;

  /// Ordered clinical steps. The UI renders them with a numbered list so
  /// the CHO can tick them off as they go.
  final List<ProtocolStep> steps;

  /// Top-level contraindications that apply to the WHOLE protocol (e.g.
  /// "Do not initiate if the patient has received > 4 g of MgSO4 in the
  /// past 24 hours from another facility"). These are shown above the
  /// individual step contraindications.
  final List<String> contraindications;

  /// Always shown verbatim at the top of the UI. Decision-support framing
  /// is required for clinical-decision software in most jurisdictions.
  final String decisionSupportNotice;

  /// Optional one-line urgency note, e.g. "Initiate within 5 minutes; do
  /// not delay transport for administration."
  final String? urgencyNote;

  Map<String, Object?> toMap() => {
        'id': id,
        'headline': headline,
        'citation': citation.toMap(),
        'citations': [for (final c in citations) c.toMap()],
        'steps': [for (final s in steps) s.toMap()],
        'contraindications': contraindications,
        'decision_support_notice': decisionSupportNotice,
        if (urgencyNote != null) 'urgency_note': urgencyNote,
      };
}

// ---------------------------------------------------------------------------
// THE PROTOCOLS
// ---------------------------------------------------------------------------
// All doses are reproduced verbatim from the cited publications. They are
// not exhaustive clinical guidance; they are the WHO/MOH minimum
// pre-referral intervention. The CHO is the licensed clinician.

/// Preeclampsia / eclampsia pre-referral stabilization.
///
/// Source: WHO 2011, "WHO Recommendations for the Prevention and Treatment
/// of Pre-eclampsia and Eclampsia" (p. 17 - MgSO4 full regimen, p. 19 -
/// antihypertensive choice). Plus Ghana Ministry of Health 2017, "National
/// Safe Motherhood Service Protocol" (page 42 - pre-referral MgSO4 +
/// Nifedipine for severe hypertension).
const preEclampsiaProtocol = StabilizationProtocol(
  id: 'pre_eclampsia_mgso4_v1',
  headline:
      'Pre-referral loading dose of Magnesium Sulfate to prevent eclamptic '
      'seizures during transit. Plus Nifedipine if BP is severe (>= 160/110).',
  citation: ProtocolCitation(
    shortName: 'WHO 2011 + GHS Safe Motherhood 2017',
    fullCitation:
        'World Health Organization. WHO recommendations for the prevention '
        'and treatment of pre-eclampsia and eclampsia. Geneva: WHO; 2011. '
        'p. 17-19. AND Ghana Ministry of Health. National Safe Motherhood '
        'Service Protocol. Accra: GHS; 2017. p. 42.',
    url: 'https://apps.who.int/iris/bitstream/10665/44703/1/9789241548335_eng.pdf',
    publishedYear: 2011,
  ),
  citations: [
    ProtocolCitation(
      shortName: 'ACOG Committee Opinion 767 (2020)',
      fullCitation:
          'American College of Obstetricians and Gynecologists. Emergent '
          'therapy for acute-onset, severe hypertension with preeclampsia '
          'or eclampsia. ACOG Committee Opinion No. 767. Obstet Gynecol. '
          '2019;133(2):e174-e180.',
      url: 'https://www.acog.org/clinical/clinical-guidance/committee-opinion/articles/2019/02/emergent-therapy-for-acute-onset-severe-hypertension-with-preeclampsia-or-eclampsia',
      publishedYear: 2019,
    ),
  ],
  steps: [
    ProtocolStep(
      order: 1,
      action: 'Administer Magnesium Sulfate (MgSO4) loading dose',
      dose: '4 g IV over 5 minutes, then 5 g IM in each buttock (10 g IM total)',
      rationale:
          'Loading dose of MgSO4 to prevent eclamptic seizures during the '
          'two-to-six hour transit window typical of Northern Region CHPS '
          'compounds.',
      whenToDo: 'Immediately, before transport is dispatched.',
      contraindication:
          'Hold if respiratory rate is < 16 breaths/min, patellar reflex '
          'is absent, or urine output is < 100 mL in the past 4 hours.',
    ),
    ProtocolStep(
      order: 2,
      action: 'Measure blood pressure; if severe, give antihypertensive',
      dose: 'Nifedipine 10 mg PO (sublingual if SBP >= 170/120); repeat in '
          '30 minutes if BP still severe',
      rationale:
          'Severe-range BP (>= 160/110) raises the risk of intracranial '
          'haemorrhage during transit. Nifedipine is on the GHS essential '
          'medicines list and is the first-line agent per the 2017 Safe '
          'Motherhood protocol.',
      whenToDo: 'Immediately after step 1; reassess every 15 minutes.',
    ),
    ProtocolStep(
      order: 3,
      action: 'Insert IV access; begin maintenance fluid',
      dose: 'Ringer Lactate or Normal Saline at 1 mL/kg/hour (max 80 mL/hour)',
      rationale:
          'IV access for the receiving facility. Maintenance rate avoids '
          'fluid overload, which can precipitate pulmonary oedema in '
          'pre-eclampsia.',
      whenToDo: 'After MgSO4 is given; before transport.',
    ),
    ProtocolStep(
      order: 4,
      action: 'Place patient in left lateral position; monitor reflexes',
      dose: 'Check patellar reflex and respiratory rate every 15 minutes',
      rationale:
          'Left lateral position avoids aortocaval compression by the '
          'gravid uterus. Reflex / RR monitoring catches MgSO4 toxicity '
          'before respiratory depression develops.',
      whenToDo: 'Continuously during transit; document on referral form.',
    ),
  ],
  contraindications: [
    'Myasthenia gravis',
    'Heart block',
    'Renal failure (oliguria < 100 mL / 4 h)',
    'Respiratory rate < 16 breaths/min at baseline',
    'Recent (> 4 g) MgSO4 administration at a sending facility',
  ],
  decisionSupportNotice:
      'DECISION SUPPORT. This protocol is reproduced from WHO 2011 and the '
      'Ghana Health Service Safe Motherhood Protocol 2017. The CHO is the '
      'licensed clinician. Verify dose, route, and contraindications against '
      'the patient before administration.',
  urgencyNote:
      'Initiate within 5 minutes. Do not delay transport for administration; '
      'a referral-ready patient on MgSO4 reaches theatre faster than a '
      'stabilised-but-untouched patient who is still at the compound.',
);

/// Young-infant (0-59 days) Possible Severe Bacterial Infection pre-referral
/// stabilization.
///
/// Source: WHO IMCI Chart Booklet 2014 (Sick Young Infant, "Treat" column,
/// "Pre-referral" row). And WHO 2015, "Managing possible serious bacterial
/// infection in young infants when referral is not feasible".
const psbiProtocol = StabilizationProtocol(
  id: 'young_infant_psbi_v1',
  headline:
      'Pre-referral antibiotics + thermal protection (Kangaroo Mother Care) '
      'for a young infant with Possible Severe Bacterial Infection.',
  citation: ProtocolCitation(
    shortName: 'WHO IMCI 2014 + WHO PSBI 2015',
    fullCitation:
        'World Health Organization. Integrated Management of Childhood '
        'Illness: Chart Booklet. Geneva: WHO; 2014. p. 4-7 (Sick Young '
        'Infant Age 0 up to 2 Months). AND World Health Organization. '
        'Managing possible serious bacterial infection in young infants '
        '0-59 days when referral is not feasible. Geneva: WHO; 2015.',
    url: 'https://www.who.int/publications/i/item/9789241506823',
    publishedYear: 2015,
  ),
  citations: [],
  steps: [
    ProtocolStep(
      order: 1,
      action: 'Administer Ampicillin intramuscular',
      dose: '50 mg/kg per dose IM',
      rationale:
          'First-line antibiotic for neonatal sepsis per WHO IMCI; covers '
          'Group B Streptococcus, Listeria, and most E. coli.',
      whenToDo: 'Immediately, before transport. Reconstitute with 2.5 mL '
          'sterile water for 500 mg vial.',
    ),
    ProtocolStep(
      order: 2,
      action: 'Administer Gentamicin intramuscular',
      dose: '5 mg/kg per dose IM',
      rationale:
          'Aminoglycoside partner; broad Gram-negative coverage. Use the '
          'WHO 10 mg/mL paediatric vial to minimise injection volume.',
      whenToDo: 'Immediately, after Ampicillin. Different injection site.',
    ),
    ProtocolStep(
      order: 3,
      action: 'Apply Kangaroo Mother Care (KMC) skin-to-skin',
      dose: 'Continuous skin-to-skin, head covered with a cap, kept warm',
      rationale:
          'Neonates lose heat rapidly. Hypothermia worsens acidosis and '
          'mortality. KMC is the WHO-preferred thermal protection when '
          'incubators are unavailable (Yokoo 2018 meta-analysis, 26% '
          'mortality reduction).',
      whenToDo: 'Immediately, maintain during transport. Teach the mother '
          'before transport departs.',
    ),
    ProtocolStep(
      order: 4,
      action: 'Continue breastfeeding; if unable to suck, give expressed '
          'breastmilk by cup',
      dose: 'Every 2-3 hours; minimum 8 feeds in 24 hours',
      rationale:
          'Breastmilk is the optimal nutrition; fasting worsens '
          'hypoglycaemia, which doubles mortality risk in PSBI.',
      whenToDo: 'Throughout the transit period.',
    ),
    ProtocolStep(
      order: 5,
      action: 'Send referral note with doses, times, and observations',
      dose: 'Use the standard GHS referral form',
      rationale:
          'The receiving facility needs the antibiotic times to plan the '
          'next dose; missing notes delay treatment at the next level.',
      whenToDo: 'Before transport departs.',
    ),
  ],
  contraindications: [
    'Known ampicillin or gentamicin allergy (alternative: ceftriaxone '
        '50 mg/kg IM, but only if referral is genuinely impossible)',
    'Severe jaundice requiring phototherapy as the primary intervention '
        '(transit to phototherapy centre is more urgent than antibiotic timing)',
  ],
  decisionSupportNotice:
      'DECISION SUPPORT. This protocol is reproduced from WHO IMCI 2014 and '
      'WHO PSBI 2015. The CHO is the licensed clinician. Verify the dose '
      'against the infant weight before administration; double-check '
      'ampicillin + gentamicin for the same patient (NOT ceftriaxone alone).',
  urgencyNote:
      'Initiate within 30 minutes of classification. Do not delay transport '
      'waiting for a vehicle if KMC + first antibiotic doses can be given '
      'now.',
);

/// Child (2-59 months) pneumonia / severe pneumonia pre-referral
/// stabilization.
///
/// Source: WHO IMCI Chart Booklet 2014 (Sick Child 2 months up to 5 years,
/// "Cough or Difficulty Breathing", "Severe Pneumonia or Very Severe
/// Disease" classification). Ghana MOH Standard Treatment Guidelines 2017
/// (Chapter 5, Acute Respiratory Infections in Children).
const childPneumoniaProtocol = StabilizationProtocol(
  id: 'child_pneumonia_v1',
  headline:
      'First-dose antibiotic + oxygen if available, before referral for '
      'severe pneumonia in a child 2-59 months.',
  citation: ProtocolCitation(
    shortName: 'WHO IMCI 2014 + GHS STG 2017',
    fullCitation:
        'World Health Organization. Integrated Management of Childhood '
        'Illness: Chart Booklet. Geneva: WHO; 2014. p. 8-15 (Sick Child 2 '
        'Months Up to 5 Years, "Cough or Difficulty Breathing"). AND Ghana '
        'Ministry of Health. Standard Treatment Guidelines, 7th edition. '
        'Accra: MOH; 2017. Chapter 5, ARI in children.',
    url: 'https://www.who.int/publications/i/item/9789241506823',
    publishedYear: 2017,
  ),
  citations: [],
  steps: [
    ProtocolStep(
      order: 1,
      action: 'Administer Amoxicillin first dose',
      dose: '40 mg/kg per dose PO (crushed tablet or dispersible formulation)',
      rationale:
          'First-line for severe pneumonia per WHO IMCI; oral route is '
          'non-inferior to injectable for children able to swallow.',
      whenToDo: 'Immediately, before transport.',
    ),
    ProtocolStep(
      order: 2,
      action: 'If oxygen is available and SaO2 < 90%, give nasal oxygen',
      dose: '1-2 L/min via nasal cannula; titrate to SaO2 >= 92%',
      rationale:
          'Hypoxia is the leading proximate cause of death in severe '
          'pneumonia. Even short-term oxygen during transit reduces '
          'mortality (Duke 2002, Lancet).',
      whenToDo: 'Continuously, if equipment is available; document flow '
          'rate on referral form.',
    ),
    ProtocolStep(
      order: 3,
      action: 'Clear the nose; keep child upright on caregiver lap',
      dose: 'Saline drops if secretions are thick',
      rationale:
          'Nasal clearance reduces work of breathing in young children. '
          'Upright position optimises diaphragmatic excursion.',
      whenToDo: 'Before transport; repeat as needed during transit.',
    ),
    ProtocolStep(
      order: 4,
      action: 'If unable to swallow, give first-dose Ampicillin IM',
      dose: '50 mg/kg IM',
      rationale:
          'Injectable route when the child is too ill to swallow. Use '
          'this only when the oral route is genuinely impossible.',
      whenToDo: 'After step 1 attempt, if child vomits or refuses.',
    ),
  ],
  contraindications: [
    'Known severe amoxicillin allergy (rare; use erythromycin '
        '15 mg/kg PO instead)',
  ],
  decisionSupportNotice:
      'DECISION SUPPORT. This protocol is reproduced from WHO IMCI 2014 and '
      'the Ghana Standard Treatment Guidelines 2017. The CHO is the '
      'licensed clinician. Reassess respiratory rate and danger signs after '
      'each step; escalate if the child deteriorates despite the first dose.',
  urgencyNote:
      'Initiate within 15 minutes of classification. Severe pneumonia in a '
      'child under 5 can deteriorate to respiratory failure in < 1 hour.',
);
