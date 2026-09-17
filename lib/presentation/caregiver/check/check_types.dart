import 'package:flutter/material.dart';
import 'package:carebridge_ai/core/theme/app_theme.dart';

// ---------------------------------------------------------------- Tri-state

/// One answer to a danger-sign question.
///
/// The third state is the whole point: a mother who is "not sure" is not
/// lying, and a system that forces her into yes or no will get the wrong
/// answer. Counting "not sure" as caution is what makes the recommendation
/// a real three-way decision.
enum CaregiverSignAnswer { unset, yes, no, unsure }

extension CaregiverSignAnswerStyle on CaregiverSignAnswer {
  Color get colour => switch (this) {
    CaregiverSignAnswer.unset => AppColors.line,
    CaregiverSignAnswer.yes => AppColors.triageRed,
    CaregiverSignAnswer.no => AppColors.triageGreen,
    CaregiverSignAnswer.unsure => AppColors.triageAmber,
  };
}

/// The five screens of the caregiver Quick Home Check — master flow
/// [40-C] → [44-C]. They live inside one route so a caregiver never sees a
/// back stack: only forward, one calm step at a time, with the app bar back
/// arrow walking the stages in reverse.
enum CaregiverStage { pick, questions, result, clinicPass, watchFor }

/// The three outcomes the triage can end in.
enum CaregiverTriageVerdict { urgent, caution, fine }

extension CaregiverTriageVerdictStyle on CaregiverTriageVerdict {
  String get headline => switch (this) {
    CaregiverTriageVerdict.urgent => 'Go to the health facility now',
    CaregiverTriageVerdict.caution => 'Visit your CHW soon',
    CaregiverTriageVerdict.fine => 'Continue routine care',
  };

  String get advice => switch (this) {
    CaregiverTriageVerdict.urgent =>
      'Danger signs are present. Do not wait until tomorrow. If the CHPS '
          'compound is closed, go to the health centre or district hospital.',
    CaregiverTriageVerdict.caution =>
      'Some answers are not clear. Bring this person to the clinic at the '
          'next scheduled contact and ask the nurse to look. Watch closely '
          'for the next two days.',
    CaregiverTriageVerdict.fine =>
      'None of the danger signs are present. Keep feeding, keep drinking, '
          'and check again tomorrow.',
  };

  Color get colour => switch (this) {
    CaregiverTriageVerdict.urgent => AppColors.triageRed,
    CaregiverTriageVerdict.caution => AppColors.triageAmber,
    CaregiverTriageVerdict.fine => AppColors.triageGreen,
  };
}
