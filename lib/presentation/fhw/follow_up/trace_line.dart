/// The desk's memory, drawn.
///
/// Every referral here was issued by a person who believed a child needed a
/// facility. What happened after that is not the lifecycle label — it is a
/// sequence of afternoons: a knock nobody answered, a mother at the compound
/// gate, a queue from 6am that ended with no treatment. The four-state
/// `referrals.status` column cannot show any of that, and a worker reading a
/// list of labels cannot tell "we never went" from "we went three times and
/// the facility turned us away" — which is the difference between a scheduling
/// problem and a health-system failure.
///
/// So the desk draws the chase instead of describing it. One node per visit
/// that happened, in order, on a single thread:
///
///   • an unanswered visit is a hollow bead and a **frayed** thread, because
///     nothing was established;
///   • an answer is a filled bead and a whole thread;
///   • "attended, not treated" is a bead with a core, which is the case the
///     old chase list silently dropped;
///   • a confirmed treatment ties off in a **knot**;
///   • an answer that raised a fresh referral leaves the thread in a **fork**;
///   • and an urgent case past 48 hours with no answer frays **red** at the
///     end, which is what an open wound on a register looks like.
///
/// Nothing here decides anything. [readTrace] translates what the policy
/// already concluded; the painter only draws it.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/fhw_luxe.dart';
import '../../../domain/enums.dart';
import '../../../domain/services/follow_up_policy.dart';

/// One visit that happened, as the thread sees it.
enum TraceBead {
  /// A knock that found nobody. An attempt, not an outcome.
  attempt,

  /// The family went; nobody established that care followed.
  arrived,

  /// The family went, and the answer was explicitly not "treated".
  untreated,

  /// Care confirmed delivered.
  treated,

  /// The family did not go at all.
  declined,

  /// The patient died. A full stop on the thread, not a pause.
  died,
}

/// How the thread leaves the last bead.
enum TraceTail {
  /// Still running. A dashed extension, waiting for the next visit.
  running,

  /// Urgent, unanswered, past 48 hours.
  fraying,

  /// Care confirmed. Tied off.
  knot,

  /// The answer raised a fresh referral; the line forks to it.
  fork,

  /// Closed without care — declined or cancelled. Cut flat.
  cut,
}

/// Everything the painter needs, already derived from the case.
class TraceReading {
  const TraceReading({required this.beads, required this.tail});

  final List<TraceBead> beads;
  final TraceTail tail;

  /// Whether any visit is recorded at all.
  bool get isEmpty => beads.isEmpty;

  /// Read the case. Pure, so the sentence a screen reader speaks is the same
  /// sentence the thread draws.
  static TraceReading of(FollowUpCase item) {
    final beads = [
      for (final contact in item.trace)
        if (!contact.isAnswered)
          TraceBead.attempt
        else if (contact.condition == FollowUpCondition.died)
          TraceBead.died
        else if (contact.reached == FollowUpReach.didNotGo ||
            contact.reached == FollowUpReach.declined)
          TraceBead.declined
        else if (contact.care == FollowUpCare.seenTreated)
          TraceBead.treated
        else if (contact.care == FollowUpCare.none)
          TraceBead.untreated
        else
          TraceBead.arrived,
    ];
    final tail = item.handedOver
        ? TraceTail.fork
        : item.referral.status == ReferralStatus.treated
        ? TraceTail.knot
        : item.isOverdue
        ? TraceTail.fraying
        : item.referral.status == ReferralStatus.refused ||
              item.referral.status == ReferralStatus.cancelled ||
              item.referral.status == ReferralStatus.died
        ? TraceTail.cut
        : TraceTail.running;
    return TraceReading(beads: beads, tail: tail);
  }
}

/// The width the thread needs, so a card can reserve the gutter once rather
/// than measuring a painter.
const double kTraceGutter = 34;

/// The thread itself.
class TraceLine extends StatelessWidget {
  const TraceLine({
    super.key,
    required this.reading,
    required this.height,
    this.onDark = true,
  });

  final TraceReading reading;
  final double height;

  /// The desk hangs the thread on a sapphire spine; the check-in screen shows
  /// it on white, so both need their own ink.
  final bool onDark;

  /// Spoken rather than drawn for anyone who cannot see the rail. Deliberately
  /// counts attempts separately from answers: "3 visits" would let two knocks
  /// that found nobody read as progress.
  String get semanticsLabel {
    if (reading.isEmpty) {
      return switch (reading.tail) {
        TraceTail.fraying =>
          'Referral issued. No visit recorded yet, and it is overdue.',
        TraceTail.cut => 'Referral closed without care.',
        _ => 'Referral issued. No visit recorded yet.',
      };
    }
    final answers = reading.beads.where((b) => b != TraceBead.attempt).length;
    final attempts = reading.beads.length - answers;
    final parts = <String>[
      '$answers ${answers == 1 ? 'answer' : 'answers'}',
      if (attempts > 0)
        '$attempts unanswered ${attempts == 1 ? 'visit' : 'visits'}',
    ];
    final last = reading.beads.last;
    return 'Chase history: ${parts.join(', ')}. Last visit: '
        '${switch (last) {
          TraceBead.attempt => 'nobody reached.',
          TraceBead.arrived => 'attended the facility.',
          TraceBead.untreated => 'attended, no treatment.',
          TraceBead.treated => 'treatment confirmed.',
          TraceBead.declined => 'did not attend.',
          TraceBead.died => 'the patient died.',
        }}'
        '${switch (reading.tail) {
          TraceTail.knot => ' The line is tied off.',
          TraceTail.fork => ' A new referral was raised from this answer.',
          TraceTail.fraying => ' Urgent and unanswered for over two days.',
          TraceTail.cut => ' Closed without care.',
          TraceTail.running => '',
        }}';
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticsLabel,
    child: SizedBox(
      width: kTraceGutter,
      height: height,
      child: CustomPaint(painter: _ThreadPainter(reading, onDark: onDark)),
    ),
  );
}

class _ThreadPainter extends CustomPainter {
  _ThreadPainter(this.reading, {required this.onDark});

  final TraceReading reading;
  final bool onDark;

  Color get _whole => onDark
      ? FhwLuxePalette.sapphireIce.withValues(alpha: 0.92)
      : FhwLuxePalette.sapphireRoyal;
  Color get _worn => onDark
      ? FhwLuxePalette.sapphireIce.withValues(alpha: 0.30)
      : FhwLuxePalette.sapphireRoyal.withValues(alpha: 0.28);
  Color get _hollow => onDark
      ? FhwLuxePalette.sapphireIce.withValues(alpha: 0.55)
      : FhwLuxePalette.textSecondary;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final top = 8.0;
    final bottom = size.height - _tailDepth();
    final stops = _stopAt(top, bottom, size);

    // Issue tick — the line exists before anyone visited.
    _tick(canvas, x, top - 3.5, _worn);

    for (var i = 0; i < reading.beads.length; i++) {
      if (i > 0) {
        _run(
          canvas,
          x,
          stops[i - 1] + _radius(reading.beads[i - 1]),
          stops[i] - _radius(reading.beads[i]),
          reading.beads[i],
        );
      }
      _bead(canvas, x, stops[i], reading.beads[i]);
    }

    final last = stops.isEmpty
        ? top
        : stops.last +
              _radius(
                reading.beads.isEmpty ? TraceBead.attempt : reading.beads.last,
              );
    _tail(canvas, x, last.clamp(top, size.height - 6), size.height);
  }

  /// Evenly spaced beads, anchored to the top so a 2-answer case and a
  /// 6-answer case start at the same height.
  List<double> _stopAt(double top, double bottom, Size size) {
    if (reading.beads.isEmpty) return const [];
    if (reading.beads.length == 1) return [top + 10];
    final step = (bottom - top) / (reading.beads.length - 1);
    return [for (var i = 0; i < reading.beads.length; i++) top + step * i];
  }

  double _radius(TraceBead bead) => switch (bead) {
    TraceBead.treated => 7.5,
    TraceBead.attempt => 3.5,
    _ => 5.5,
  };

  void _tick(Canvas canvas, double x, double y, Color color) => canvas.drawLine(
    Offset(x - 4, y),
    Offset(x + 4, y),
    Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round,
  );

  /// The thread between two beads. Unanswered links fray: the same vertical
  /// run broken into short strokes, each nudged sideways by a deterministic
  /// wobble so the fraying is a property of the case, not of the frame rate.
  void _run(Canvas canvas, double x, double from, double to, TraceBead into) {
    if (to <= from) return;
    if (into == TraceBead.attempt) {
      _fray(canvas, x, from, to, worn: true);
      return;
    }
    canvas.drawLine(
      Offset(x, from),
      Offset(x, to),
      Paint()
        ..color = _whole
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
  }

  void _fray(
    Canvas canvas,
    double x,
    double from,
    double to, {
    bool worn = false,
  }) {
    const stride = 5.0;
    final paint = Paint()
      ..color = worn ? _worn : _whole
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    var i = 0;
    for (var y = from; y < to; y += stride, i++) {
      final wobble = math.sin((from + y) * 0.9 + i) * 2.0;
      canvas.drawLine(
        Offset(x + wobble, y),
        Offset(x + wobble * 0.5, math.min(y + 2.6, to)),
        paint,
      );
    }
  }

  void _bead(Canvas canvas, double x, double y, TraceBead bead) {
    switch (bead) {
      case TraceBead.attempt:
        canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = _hollow);
        canvas.drawCircle(
          Offset(x, y),
          3.5,
          Paint()
            ..color = _hollow
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      case TraceBead.arrived:
        canvas.drawCircle(Offset(x, y), 5.5, Paint()..color = _whole);
        canvas.drawCircle(
          Offset(x, y),
          2.2,
          Paint()
            ..color = onDark
                ? FhwLuxePalette.sapphireDeep
                : FhwLuxePalette.pureWhite,
        );
      case TraceBead.untreated:
        // The bead that must not be confused with a settled one: a ring with a
        // core, read as "we got there, nothing followed".
        canvas.drawCircle(Offset(x, y), 6.5, Paint()..color = _whole);
        canvas.drawCircle(
          Offset(x, y),
          3.0,
          Paint()
            ..color = onDark
                ? FhwLuxePalette.sapphireDeep
                : FhwLuxePalette.pureWhite,
        );
        _tick(canvas, x, y, _whole);
      case TraceBead.treated:
        canvas.drawCircle(Offset(x, y), 7.5, Paint()..color = _whole);
        canvas.drawCircle(
          Offset(x, y),
          7.5,
          Paint()
            ..color = _whole
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6,
        );
        canvas.drawCircle(
          Offset(x, y),
          3.2,
          Paint()
            ..color = onDark
                ? FhwLuxePalette.sapphireDeep
                : FhwLuxePalette.pureWhite,
        );
      case TraceBead.declined:
        canvas.drawCircle(
          Offset(x, y),
          5.5,
          Paint()
            ..color = _hollow
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8,
        );
        canvas.drawLine(
          Offset(x - 3.4, y - 3.4),
          Offset(x + 3.4, y + 3.4),
          Paint()
            ..color = _hollow
            ..strokeWidth = 1.8
            ..strokeCap = StrokeCap.round,
        );
      case TraceBead.died:
        // A full stop: a closed, filled bead struck through — an ending, not a
        // pause the next visit resumes.
        canvas.drawCircle(Offset(x, y), 6.5, Paint()..color = _whole);
        canvas.drawLine(
          Offset(x - 3.4, y),
          Offset(x + 3.4, y),
          Paint()
            ..color = onDark
                ? FhwLuxePalette.sapphireDeep
                : FhwLuxePalette.pureWhite
            ..strokeWidth = 1.8
            ..strokeCap = StrokeCap.round,
        );
    }
  }

  double _tailDepth() => switch (reading.tail) {
    TraceTail.knot => 20,
    TraceTail.fork => 22,
    TraceTail.fraying => 18,
    TraceTail.cut => 12,
    TraceTail.running => 14,
  };

  void _tail(Canvas canvas, double x, double from, double height) {
    final to = height - 4;
    if (to <= from) return;
    switch (reading.tail) {
      case TraceTail.running:
        _fray(canvas, x, from, to);
      case TraceTail.fraying:
        // Red at the loose end, and only there: the bead colours stay neutral
        // so the alert cannot be read off hue alone.
        _frayRed(canvas, x, from, to);
      case TraceTail.knot:
        canvas.drawLine(
          Offset(x, from),
          Offset(x, to - 9),
          Paint()
            ..color = _whole
            ..strokeWidth = 2.2,
        );
        _knot(canvas, Offset(x, to - 4.5));
      case TraceTail.fork:
        _knot(canvas, Offset(x, from + 6), small: true);
        canvas.drawArc(
          Rect.fromCircle(center: Offset(x + 7, from + 6), radius: 7),
          -math.pi / 2,
          math.pi,
          false,
          Paint()
            ..color = _whole
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke,
        );
        canvas.drawCircle(
          Offset(x + 14, from + 6),
          2.4,
          Paint()..color = _whole,
        );
      case TraceTail.cut:
        _tick(canvas, x, from + 5, _worn);
    }
  }

  void _frayRed(Canvas canvas, double x, double from, double to) {
    const stride = 5.0;
    final paint = Paint()
      ..color = FhwLuxePalette.clinicalRed
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    var i = 0;
    for (var y = from; y < to; y += stride, i++) {
      final wobble = math.sin(y * 0.9 + i) * 2.4;
      canvas.drawLine(
        Offset(x + wobble, y),
        Offset(x + wobble * 0.4, math.min(y + 2.8, to)),
        paint,
      );
    }
  }

  void _knot(Canvas canvas, Offset centre, {bool small = false}) {
    final r = small ? 4.0 : 5.6;
    final paint = Paint()
      ..color = _whole
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(centre, r, paint);
    canvas.drawCircle(centre, r - 2.4, paint);
  }

  @override
  bool shouldRepaint(_ThreadPainter old) =>
      old.reading.beads != reading.beads ||
      old.reading.tail != reading.tail ||
      old.onDark != onDark;
}
