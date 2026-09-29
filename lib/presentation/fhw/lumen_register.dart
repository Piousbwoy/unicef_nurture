/// LumenRegister — the open clinic queue as a carved ledger.
///
/// Sits directly beneath the [LumenHero] and continues the sanctuary: one
/// alabaster sheet, planed and top-lit, holding the day's open sessions. Every
/// row is a household; the thin bar under its name is the honest progress the
/// ticket actually carries — the people with a saved assessment out of the
/// people received. When the fill reaches the far edge, the household is done.
///
/// Deliberate honesty constraints (unchanged from the surface it replaces):
///  * No triage colours. [ClinicQueueTicket] holds no clinical verdict, so none
///    is implied — every fill is the same liquid sapphire. Sapphire here is the
///    brand's light, not a status.
///  * No wall-clock "waiting since" strings; arrival order on a shared phone is
///    not a promise about the queue and it would make tests time-dependent.
///  * A row only ever encodes data the ticket actually holds.
///
/// The motion budget is spent in the hero, not here. This ledger is still stone:
/// it reads the same with animation off as on, so it always settles in tests.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/fhw_luxe.dart';
import '../../core/theme/lumen.dart';
import 'home_tab.dart' show ClinicQueueTicket;

class LumenRegister extends StatelessWidget {
  const LumenRegister({
    super.key,
    required this.tickets,
    required this.onOpenQueue,
  });

  final List<ClinicQueueTicket> tickets;
  final VoidCallback onOpenQueue;

  @override
  Widget build(BuildContext context) {
    if (tickets.isEmpty) return const SizedBox.shrink();
    final waiting = tickets.fold<int>(0, (sum, t) => sum + t.pending);

    return AlabasterSheet(
      key: const ValueKey('lumen-register'),
      radius: Gap.radiusLg,
      padding: const EdgeInsets.fromLTRB(Lux.md, Lux.md, Lux.sm, Lux.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The ledger head: a cold eyebrow and the way into the full queue.
          Row(
            children: [
              const _LedgerMark(),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'CLINIC QUEUE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.eyebrow.copyWith(
                    color: FhwLuxePalette.textSecondary,
                    letterSpacing: 1.6,
                    fontSize: 10.5,
                  ),
                ),
              ),
              Flexible(
                child: TextButton(
                  onPressed: onOpenQueue,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Open clinic queue',
                    textAlign: TextAlign.end,
                    style: AppType.label.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: FhwLuxePalette.sapphireRoyal,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Lux.sm),
          // The one honest total for the whole queue, set as quiet structure.
          Text(
            waiting == 0
                ? 'Every household is assessed'
                : '$waiting ${waiting == 1 ? 'person' : 'people'} still to assess',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.title.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: FhwLuxePalette.textPrimary,
            ),
          ),
          const SizedBox(height: Lux.md),
          const Divider(
            height: 1,
            thickness: 1,
            color: FhwLuxePalette.hairLine,
          ),
          for (final ticket in tickets)
            _LedgerRow(ticket: ticket, onTap: onOpenQueue),
        ],
      ),
    );
  }
}

/// The mark at the head of the ledger — a small lit sapphire pool, the same
/// substance as the hero's focal, so the two surfaces read as one instrument.
class _LedgerMark extends StatelessWidget {
  const _LedgerMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: Lumen.sapphireLiquid,
      boxShadow: Chiaroscuro.bloom(FhwLuxePalette.sapphireRoyal, alpha: 0.4),
    ),
    child: const Icon(Icons.groups_rounded, size: 13, color: Colors.white),
  );
}

/// One open session as a ledger line: household above, the honest progress
/// beneath. Tapping opens the queue — the row reports, it is never the
/// assessment itself.
class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.ticket, required this.onTap});

  final ClinicQueueTicket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = ticket.allAssessed;
    final progress = ticket.presentCount == 0
        ? 0.0
        : (ticket.assessedCount / ticket.presentCount).clamp(0.0, 1.0);
    final status = done
        ? 'All ${ticket.presentCount} assessed'
        : '${ticket.assessedCount} of ${ticket.presentCount} assessed'
              '${ticket.pending == 1 ? ' · 1 to assess' : ' · ${ticket.pending} to assess'}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Semantics(
        button: true,
        label: '${ticket.householdName}: $status',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      ticket.householdName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.label.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: FhwLuxePalette.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Flexible + wrap: at the 320px / 200% accessibility floor the
                  // honest status bends to the line below the name, never
                  // overflows the sheet.
                  Flexible(
                    child: Text(
                      status,
                      textAlign: TextAlign.end,
                      style: AppType.caption.copyWith(
                        fontSize: 11.5,
                        color: done
                            ? FhwLuxePalette.sapphireRoyal
                            : FhwLuxePalette.textSecondary,
                        fontWeight: done ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              _ProgressPool(fraction: progress),
            ],
          ),
        ),
      ),
    );
  }
}

/// A thin bar of liquid sapphire poured into a glacial groove — the assessed
/// share of the people received. Purely a measure; the colour is constant so a
/// full bar never reads as a clinical verdict.
class _ProgressPool extends StatelessWidget {
  const _ProgressPool({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(4);
    return ClipRRect(
      borderRadius: r,
      child: Container(
        height: 7,
        width: double.infinity,
        decoration: const BoxDecoration(gradient: Lumen.glacialIce),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: fraction.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: Lumen.sapphireLiquid,
                borderRadius: BorderRadius.circular(4),
                boxShadow: fraction > 0.02
                    ? Chiaroscuro.bloom(
                        FhwLuxePalette.sapphireElectric,
                        alpha: 0.45,
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
