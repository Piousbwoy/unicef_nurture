/// The on-device database, made visible.
///
/// Every record in CareBridge commits to SQLite first — that is the whole
/// offline-first contract. This screen lets a user *see* that contract being
/// kept: all sixteen tables, their row counts, and the most recent rows in
/// each. Nothing here is an abstraction over the database; it is the database.
///
/// Two deliberate guardrails:
///
/// **Read-only.** Browsing must never be able to damage care records, so this
/// screen only ever runs SELECTs.
///
/// **Credentials are masked.** `pin_hash` and `pin_salt` display as dots. A
/// hash is not a password and cannot be reversed into one, but there is also
/// no reason to print it on a screen — and a judge asking "where are the
/// PINs?" gets the answer "stored here, hashed, never synced" with the
/// evidence on screen.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/local/app_database.dart';
import '../shared/ui.dart';

/// Columns that are masked in row views. PIN material never travels to the
/// sync server, and it should not travel to a screenshot either.
const Set<String> _maskedColumns = {'pin_hash', 'pin_salt'};

/// How many recent rows a table view shows. Enough to prove the records are
/// really there; not so many that a busy table takes a moment to render.
const int _rowLimit = 30;

class DataInspectorScreen extends StatefulWidget {
  const DataInspectorScreen({super.key});

  @override
  State<DataInspectorScreen> createState() => _DataInspectorScreenState();
}

class _DataInspectorScreenState extends State<DataInspectorScreen> {
  List<({String table, int count})>? _tables;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await AppDatabase.instance.database;
      // The table list comes from SQLite itself, not a hard-coded constant,
      // so a migration that adds a table shows up here without code changes.
      final meta = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      );
      final tables = <({String table, int count})>[];
      for (final row in meta) {
        final table = row['name'] as String;
        final count = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM "$table"',
        );
        tables.add((table: table, count: (count.first['n'] as num).toInt()));
      }
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('On-device database')),
      body: _error != null
          ? Center(child: ErrorView(error: _error!, onRetry: _load))
          : _tables == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(Gap.lg),
                children: [
                  _infoBanner(),
                  const SizedBox(height: Gap.lg),
                  ..._tables!.map(
                    (t) => _TableTile(
                      table: t.table,
                      count: t.count,
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _TableScreen(table: t.table),
                          ),
                        );
                        // A row count can change while browsing — refresh on
                        // the way back so the list never lies.
                        await _load();
                      },
                    ),
                  ),
                  const SizedBox(height: Gap.xl),
                ],
              ),
            ),
    );
  }

  Widget _infoBanner() {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border.all(color: AppColors.line),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.storage_rounded, size: 17, color: AppColors.inkMuted),
          SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              'This is the SQLite database on this device — the source of '
              'truth. Every record below was saved here first, and uploads '
              'to the district server by itself when there is network. PINs '
              'are stored hashed and never leave this phone.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.inkMuted,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One table row in the list: name, live row count, chevron.
class _TableTile extends StatelessWidget {
  const _TableTile({
    required this.table,
    required this.count,
    required this.onTap,
  });

  final String table;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border.all(color: AppColors.line),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Gap.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.md,
              vertical: Gap.md,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.table_chart_outlined,
                  size: 18,
                  color: count > 0 ? AppColors.primary : AppColors.inkFaint,
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Text(
                    table,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '$count ${count == 1 ? 'record' : 'records'}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: count > 0 ? AppColors.primary : AppColors.inkFaint,
                  ),
                ),
                const SizedBox(width: Gap.xs),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.inkFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The recent rows of one table, newest first.
class _TableScreen extends StatefulWidget {
  const _TableScreen({required this.table});

  final String table;

  @override
  State<_TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<_TableScreen> {
  List<Map<String, Object?>>? _rows;
  int? _total;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await AppDatabase.instance.database;
      final count = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM "${widget.table}"',
      );
      List<Map<String, Object?>> rows;
      try {
        rows = await db.rawQuery(
          'SELECT * FROM "${widget.table}" ORDER BY rowid DESC '
          'LIMIT $_rowLimit',
        );
      } catch (_) {
        // A WITHOUT ROWID table cannot order by rowid. Fall back to whatever
        // order SQLite gives — seeing the rows matters more than the order.
        rows = await db.rawQuery(
          'SELECT * FROM "${widget.table}" LIMIT $_rowLimit',
        );
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _total = (count.first['n'] as num).toInt();
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _total;
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(title: Text(widget.table)),
      body: _error != null
          ? Center(
              child: ErrorView(error: _error!, onRetry: _load),
            )
          : rows == null || total == null
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(Gap.lg),
              itemCount: rows.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: Gap.md),
                    child: Text(
                      total == 0
                          ? 'No records yet.'
                          : 'Showing the ${rows.length} newest of '
                                '$total record${total == 1 ? '' : 's'}, '
                                'newest first.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.inkMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }
                return _RowCard(row: rows[i - 1]);
              },
            ),
    );
  }
}

/// One record rendered as labelled fields. Long payloads (JSON blobs, pipe
/// lists) are clipped so one referral's care plan does not fill the screen.
class _RowCard extends StatelessWidget {
  const _RowCard({required this.row});

  final Map<String, Object?> row;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Gap.radiusSm),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in row.entries) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: Text(
                    e.key,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    _display(e.key, e.value),
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      fontFamily: _monoKeys.contains(e.key)
                          ? 'monospace'
                          : null,
                      color: _maskedColumns.contains(e.key)
                          ? AppColors.inkFaint
                          : AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            if (e.key != row.keys.last) const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  /// Identifiers and timestamps read better in a fixed-width face; everything
  /// else stays in the app's type.
  static const Set<String> _monoKeys = {
    'id',
    'entity_id',
    'person_id',
    'household_id',
    'visit_id',
    'assessment_id',
    'referral_id',
    'mother_id',
    'reference_code',
  };

  static String _display(String column, Object? value) {
    if (value == null) return '—';
    if (_maskedColumns.contains(column)) return '••••••';
    final text = '$value';
    // JSON payloads and pipe-joined lists can be enormous; clip them so the
    // row stays glanceable. The full value is still in the database.
    return text.length > 240 ? '${text.substring(0, 240)}…' : text;
  }
}
