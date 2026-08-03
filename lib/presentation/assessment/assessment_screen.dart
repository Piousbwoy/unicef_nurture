/// The assessment shell: load what the record already knows, hand the person
/// to the right protocol form, and carry the draft to the result screen.
///
/// The protocol is chosen from [Person.effectiveClientType] — the age-derived
/// type — so a baby registered as a newborn who has since turned three months
/// is assessed on the sick-child chart without anyone having to relabel them.
///
/// Access is enforced twice on this screen and never in the UI alone: the
/// repository re-checks [Permission.runClinicalAssessment] on every write, and
/// the screen itself refuses to render for a user without it. A caregiver can
/// never reach this screen through the router, and even a forged deep link
/// would stop at the repository.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/care_repository.dart';
import '../../domain/entities/core.dart';
import '../../domain/entities/visit.dart';
import '../../domain/enums.dart';
import '../shared/ui.dart';
import 'child_form.dart';
import 'maternal_form.dart';
import 'result_screen.dart';
import 'types.dart';

class AssessmentScreen extends ConsumerWidget {
  const AssessmentScreen({
    super.key,
    required this.visit,
    required this.personId,
  });

  final Visit visit;
  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null || !user.can(Permission.runClinicalAssessment)) {
      return const Scaffold(
        body: AccessDeniedView(
          message:
              'Only a frontline health worker can run a clinical assessment. '
              'This account does not have that permission.',
        ),
      );
    }

    final household = ref.watch(householdProvider(visit.householdId));
    final person = ref.watch(personProvider(personId));
    final maternal = ref.watch(maternalRecordProvider(personId));
    final birth = ref.watch(birthRecordProvider(personId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assessment'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(
              left: Gap.lg,
              right: Gap.lg,
              bottom: Gap.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                household.valueOrNull?.name ?? '',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
      body: household.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e is AccessDenied ? e.message : e,
        ),
        data: (h) => person.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(
            error: e is AccessDenied ? e.message : e,
          ),
          data: (p) {
            if (h == null || p == null) {
              return const EmptyState(
                icon: Icons.person_off_outlined,
                title: 'Record not found',
                message:
                    'This person or household could not be loaded. It may have '
                    'been removed, or this account may not have access to it.',
              );
            }

            final ctx = AssessmentContext(
              user: user,
              household: h,
              person: p,
              maternal: maternal.valueOrNull,
              birth: birth.valueOrNull,
            );

            final form = switch (p.effectiveClientType) {
              ClientType.pregnantWoman ||
              ClientType.postpartumWoman ||
              ClientType.womanOfReproductiveAge =>
                MaternalProtocolForm(
                  key: ValueKey('maternal-${p.id}'),
                  input: ctx,
                  onComplete: (draft) => _showResult(context, ref, ctx, draft),
                ),
              ClientType.newborn || ClientType.childUnderFive =>
                ChildProtocolForm(
                  key: ValueKey('child-${p.id}'),
                  input: ctx,
                  onComplete: (draft) => _showResult(context, ref, ctx, draft),
                ),
            };

            return form;
          },
        ),
      ),
    );
  }

  Future<void> _showResult(
    BuildContext context,
    WidgetRef ref,
    AssessmentContext ctx,
    AssessmentDraft draft,
  ) async {
    // Load the child's saved growth series now, before navigation, so the
    // result screen can compute treatment response (weight-gain rate)
    // synchronously. The verdict that seeds the referral toggle must already
    // know whether a child on feeding is losing weight — that cannot wait on
    // an async load after the screen is built.
    var priorGrowth = const <GrowthMeasurement>[];
    try {
      priorGrowth = await ref
          .read(careRepositoryProvider)
          .growthSeries(ctx.user, ctx.person.id);
    } on AccessDenied {
      // No growth history this account may see; treatment response simply
      // does not run. The assessment itself is unaffected.
    }
    if (!context.mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AssessmentResultScreen(
          input: ctx,
          draft: draft,
          visitId: visit.id,
          priorGrowth: priorGrowth,
        ),
      ),
    );
    if (saved == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }
}
