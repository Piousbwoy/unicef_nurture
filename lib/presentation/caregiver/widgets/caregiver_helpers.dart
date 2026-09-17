import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:carebridge_ai/core/theme/app_theme.dart';
import 'package:carebridge_ai/domain/entities/visit.dart';
import 'package:carebridge_ai/domain/enums.dart';

// ------------------------------------------------------------------- Helpers

extension CaregiverHomeCheckStyle on HomeCheckVerdict {
  Color get colour => switch (this) {
    HomeCheckVerdict.urgent => AppColors.triageRed,
    HomeCheckVerdict.caution => AppColors.triageAmber,
    HomeCheckVerdict.fine => AppColors.triageGreen,
  };
}

/// "today", "yesterday", or "3 days ago" — the way a family talks about
/// time, never a date format. Older than a week falls back to the date.
String caregiverAgo(DateTime when) {
  final days = DateTime.now().dateOnly.difference(when.dateOnly).inDays;
  return switch (days) {
    <= 0 => 'today',
    1 => 'yesterday',
    < 7 => '$days days ago',
    _ => DateFormat('d MMM').format(when),
  };
}
