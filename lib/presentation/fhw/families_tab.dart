/// The household register's shared building blocks.
///
/// This file used to be the Families tab. The tab itself was folded into the
/// Assess tab (`assess_tab.dart`) — assessment is the reason a CHO browses the
/// register, so the two now live together — but the two reusable pieces stay
/// here:
///
///  * [HouseholdTile] — one row of the register, with an optional quick
///    "start assessment" action, shared by every household list.
///  * [HouseholdFormSheet] — the household registration form. There is exactly
///    one way to register a household, and every "add household" entry point
///    launches this sheet.
///
/// The register is deliberately a flat list rather than a tree of region →
/// district → community. A CHO's zone is one community; the hierarchy matters
/// at registration time (it drives the referral ladder and the language list)
/// and not at browsing time. Search is by name, head, community or landmark —
/// the way a CHO actually thinks about a household.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/reference/northern_ghana.dart';
import '../../data/repositories/care_repository.dart';
import '../../domain/entities/core.dart';
import '../shared/ui.dart';

const _uuid = Uuid();

/// One row of the household register.
///
/// Tapping the row opens the household; the optional trailing [onAssess] action
/// jumps straight into that household's assessment session. Callers are responsible for
/// only supplying [onAssess] when the current user can run a clinical
/// assessment — the button is rendered if, and only if, it is non-null.
class HouseholdTile extends ConsumerWidget {
  const HouseholdTile({
    super.key,
    required this.household,
    required this.onTap,
    this.onAssess,
  });

  final Household household;
  final VoidCallback onTap;

  /// Quick "start assessment" shortcut for this household. Null hides it.
  final VoidCallback? onAssess;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(householdMembersProvider(household.id));
    final count = members.valueOrNull?.length;

    return Card(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Gap.radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Row(
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(Gap.radiusSm),
                ),
                child: const Icon(
                  Icons.home_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      household.name,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${household.community} · ${household.district}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                      ),
                    ),
                    if (household.landmark != null &&
                        household.landmark!.isNotEmpty)
                      Text(
                        household.landmark!,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.inkFaint,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
              if (count != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.sm,
                    vertical: Gap.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              if (onAssess != null) ...[
                const SizedBox(width: Gap.sm),
                _QuickAssessButton(onTap: onAssess!),
              ],
              const SizedBox(width: Gap.sm),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The per-row quick "start assessment" action.
///
/// A quiet tonal button rather than a gradient CTA — the gradient is reserved
/// for the tab's single signature action, and a whole register of gradient
/// buttons would shout. The play glyph matches the household screen's
/// "Start assessment" so the two entry points read as the same action.
class _QuickAssessButton extends StatelessWidget {
  const _QuickAssessButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Start assessment',
    child: InkWell(
      borderRadius: BorderRadius.circular(Gap.radiusSm),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(Gap.radiusSm),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.22),
          ),
        ),
        child: const Icon(
          Icons.play_circle_outline_rounded,
          color: AppColors.primary,
          size: 22,
        ),
      ),
    ),
  );
}

/// The household registration form.
///
/// Region, district and community are cascading pickers over the reference
/// dataset, because a free-text district is a referral ladder that is already
/// broken. Everything else is optional at creation — a household is registered
/// first and enriched over successive contacts.
/// Public so the dashboard's "Add Household" quick action can launch the same
/// form — there is exactly one way to register a household.
class HouseholdFormSheet extends ConsumerStatefulWidget {
  const HouseholdFormSheet({super.key});

  @override
  ConsumerState<HouseholdFormSheet> createState() =>
      _HouseholdFormSheetState();
}

class _HouseholdFormSheetState extends ConsumerState<HouseholdFormSheet> {
  String? _region;
  String? _district;
  String? _community;
  final _name = TextEditingController();
  final _head = TextEditingController();
  final _phone = TextEditingController();
  final _landmark = TextEditingController();
  final _walk = TextEditingController();
  final _size = TextEditingController();
  bool? _nhis;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _head, _phone, _landmark, _walk, _size]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _districts =>
      _region == null ? const [] : NorthernGhana.districtsOf(_region!).map(
        (d) => d.name,
      ).toList(growable: false);

  List<String> get _communities => (_region == null || _district == null)
      ? const []
      : NorthernGhana.communitiesOf(_region!, _district!);

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    if (_region == null || _district == null || _community == null) {
      setState(() => _error = 'Pick the region, district and community.');
      return;
    }
    final name = _name.text.trim().isEmpty
        ? '${_head.text.trim().isEmpty ? 'New' : _head.text.trim()}'
              '${_head.text.trim().isEmpty ? ' household' : "'s household"}'
        : _name.text.trim();

    setState(() {
      _busy = true;
      _error = null;
    });

    final household = Household(
      id: _uuid.v4(),
      name: name,
      region: _region!,
      district: _district!,
      community: _community!,
      createdBy: user.id,
      headName: _head.text.trim().isEmpty ? null : _head.text.trim(),
      contactPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      landmark: _landmark.text.trim().isEmpty ? null : _landmark.text.trim(),
      walkingMinutesToFacility: int.tryParse(_walk.text.trim()),
      familySize: int.tryParse(_size.text.trim()),
      hasValidNhis: _nhis,
    );

    try {
      await ref.read(careRepositoryProvider).registerHousehold(user, household);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AccessDenied catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: Gap.lg,
      right: Gap.lg,
      bottom: MediaQuery.of(context).viewInsets.bottom + Gap.lg,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Register a household',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: Gap.sm),
          const Text(
            'The location sets the referral ladder and the language list, so '
            'it must be exact. Everything else can be filled in later.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.inkMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: Gap.lg),

          DropdownButtonFormField<String>(
            initialValue: _region,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Region *',
            ),
            items: [
              for (final r in NorthernGhana.regionNames)
                DropdownMenuItem(value: r, child: Text(r)),
            ],
            onChanged: (r) => setState(() {
              _region = r;
              _district = null;
              _community = null;
            }),
          ),
          const SizedBox(height: Gap.md),
          DropdownButtonFormField<String>(
            // The form field owns its selection once built, so the cascade
            // reset works by rebuilding it under a new key when the parent
            // picker changes.
            key: ValueKey('district-$_region'),
            initialValue: _district,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'District / Municipal *',
            ),
            items: [
              for (final d in _districts)
                DropdownMenuItem(value: d, child: Text(d)),
            ],
            onChanged: _region == null
                ? null
                : (d) => setState(() {
                    _district = d;
                    _community = null;
                  }),
          ),
          const SizedBox(height: Gap.md),
          DropdownButtonFormField<String>(
            key: ValueKey('community-$_district'),
            initialValue: _community,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Community *',
            ),
            items: [
              for (final c in _communities)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: _district == null
                ? null
                : (c) => setState(() => _community = c),
          ),
          const SizedBox(height: Gap.md),

          TextField(
            controller: _head,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Head of household',
              hintText: 'e.g. Mariama',
            ),
          ),
          const SizedBox(height: Gap.md),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Household name',
              hintText: 'Defaults to the head\u2019s name',
            ),
          ),
          const SizedBox(height: Gap.md),
          TextField(
            controller: _landmark,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Landmark',
              hintText: 'e.g. behind the mosque, past the shea tree',
            ),
          ),
          const SizedBox(height: Gap.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _walk,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Walk to facility',
                    suffixText: 'min',
                  ),
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: TextField(
                  controller: _size,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Family size',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Contact phone',
            ),
          ),
          const SizedBox(height: Gap.md),

          YesNoField(
            value: _nhis,
            yesLabel: 'Valid NHIS',
            noLabel: 'No / expired',
            allowUnknown: true,
            dangerOnYes: false,
            onChanged: (v) => setState(() => _nhis = v),
          ),
          const SizedBox(height: Gap.md),

          if (_error != null) ...[
            Text(
              _error!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.triageRed,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Gap.md),
          ],

          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_busy ? 'Saving…' : 'Save household'),
          ),
          const SizedBox(height: Gap.lg),
        ],
      ),
    ),
  );
}
