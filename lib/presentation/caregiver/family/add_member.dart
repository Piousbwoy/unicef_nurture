import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:carebridge_ai/app/providers.dart';
import 'package:carebridge_ai/core/theme/app_theme.dart';
import 'package:carebridge_ai/data/repositories/care_repository.dart';
import 'package:carebridge_ai/domain/entities/core.dart';
import 'package:carebridge_ai/domain/enums.dart';

/// Opens the add-member sheet. Deliberately one small widget: it appears in
/// the family card, and the same affordance must exist wherever the family
/// list is empty.
class CaregiverAddMemberButton extends StatelessWidget {
  const CaregiverAddMemberButton({
    super.key,
    required this.householdId,
    this.dark = false,
  });

  final String householdId;

  /// On a navy surface the outline turns white so it keeps its contrast.
  final bool dark;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: () => _openAddMember(context, householdId),
    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
    label: const Text('Add a family member'),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, Gap.tapTarget),
      foregroundColor: dark ? Colors.white : AppColors.primary,
      side: dark
          ? const BorderSide(color: AppColors.white70, width: 1.4)
          : const BorderSide(color: AppColors.primary, width: 1.4),
    ),
  );
}

/// One entry point to the add-member sheet so both callers stay identical.
void _openAddMember(BuildContext context, String householdId) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AddMemberSheet(householdId: householdId),
  );
}

// ---------------------------------------------------------------- Add member

/// Adding someone to the family's own list.
///
/// The categories mirror who this app exists for: babies and young children
/// — the date of birth powers every age-banded thing the app does (danger
/// signs, vaccine days, milestones) — and the women of the family. The write
/// goes through [CareRepository.addFamilyMember], which refuses anything
/// outside this family's household and records the add in the audit log.
class _AddMemberSheet extends ConsumerStatefulWidget {
  const _AddMemberSheet({required this.householdId});

  final String householdId;

  @override
  ConsumerState<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends ConsumerState<_AddMemberSheet> {
  static const _categories = [
    'Baby or young child (0–5 years)',
    'Mother or woman of the family',
  ];

  final _name = TextEditingController();
  final _ageYears = TextEditingController();
  int _category = 0;
  DateTime? _dob;
  Sex? _sex;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _ageYears.dispose();
    super.dispose();
  }

  bool get _isChild => _category == 0;

  String? _validate() {
    if (_name.text.trim().length < 2) return 'Enter their name.';
    if (_isChild && _dob == null) return 'Choose the date of birth.';
    return null;
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? now.subtract(const Duration(days: 365)),
      firstDate: now.subtract(const Duration(days: 365 * 5 + 30)),
      lastDate: now,
      helpText: 'When were they born?',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    final problem = user == null ? 'You are not signed in.' : _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final days = _dob == null ? null : DateTime.now().difference(_dob!).inDays;
    final person = Person(
      id: const Uuid().v4(),
      householdId: widget.householdId,
      fullName: _name.text.trim(),
      clientType: _isChild
          ? ClientType.forChildAgeInDays(days!) ?? ClientType.childUnderFive
          : ClientType.womanOfReproductiveAge,
      sex: _isChild ? _sex : Sex.female,
      dateOfBirth: _dob,
      ageYearsApprox: _isChild ? null : int.tryParse(_ageYears.text.trim()),
    );

    try {
      await ref.read(careRepositoryProvider).addFamilyMember(user!, person);
      ref.invalidate(householdMembersProvider(widget.householdId));
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is AccessDenied ? e.message : 'Could not save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: Gap.lg,
        right: Gap.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + Gap.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add a family member', style: AppType.title),
            const SizedBox(height: Gap.xs),
            const Text(
              'Everyone you add stays on this phone and joins your '
              'family\u2019s record when the health worker meets you.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.inkMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: Gap.md),
            for (var i = 0; i < _categories.length; i++)
              InkWell(
                onTap: () => setState(() => _category = i),
                borderRadius: BorderRadius.circular(Gap.radiusSm),
                child: Container(
                  margin: const EdgeInsets.only(bottom: Gap.xs),
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.md,
                    vertical: Gap.sm,
                  ),
                  decoration: BoxDecoration(
                    color: _category == i
                        ? AppColors.primaryLight
                        : Colors.white,
                    border: Border.all(
                      color: _category == i
                          ? AppColors.primary
                          : AppColors.line,
                    ),
                    borderRadius: BorderRadius.circular(Gap.radiusSm),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _category == i
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 20,
                        color: _category == i
                            ? AppColors.primary
                            : AppColors.inkFaint,
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Text(
                          _categories[i],
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: Gap.sm),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            if (_isChild) ...[
              const SizedBox(height: Gap.md),
              OutlinedButton.icon(
                onPressed: _pickDob,
                icon: const Icon(Icons.cake_outlined, size: 18),
                label: Text(
                  _dob == null
                      ? 'Choose the date of birth'
                      : 'Born ${DateFormat('d MMMM yyyy').format(_dob!)}',
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, Gap.tapTarget),
                ),
              ),
              const SizedBox(height: Gap.md),
              Row(
                children: [
                  const Text(
                    'Boy or girl?',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  for (final s in Sex.values)
                    Padding(
                      padding: const EdgeInsets.only(right: Gap.xs),
                      child: ChoiceChip(
                        label: Text(s.label),
                        selected: _sex == s,
                        onSelected: (_) => setState(() => _sex = s),
                      ),
                    ),
                ],
              ),
            ] else ...[
              const SizedBox(height: Gap.md),
              TextField(
                controller: _ageYears,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'About how old? (years, optional)',
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: Gap.md),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.triageRed,
                ),
              ),
            ],
            const SizedBox(height: Gap.lg),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: const Text('Save'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, Gap.tapTarget),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
