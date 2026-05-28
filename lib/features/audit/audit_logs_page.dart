import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../shared/message_card.dart';

class AuditLogsPage extends StatefulWidget {
  final AdminSession session;

  const AuditLogsPage({super.key, required this.session});

  @override
  State<AuditLogsPage> createState() => _AuditLogsPageState();
}

class _AuditLogsPageState extends State<AuditLogsPage> {
  late Future<List<AuditItem>> future;
  String query = '';
  String actionFilter = 'all';

  @override
  void initState() {
    super.initState();
    future = loadItems();
  }

  void refresh() {
    setState(() => future = loadItems());
  }

  Future<List<AuditItem>> loadItems() async {
    final snap = await FirebaseDatabase.instance.ref('audit_logs/${widget.session.companyId}').get();
    final data = _asMap(snap.value) ?? const <String, dynamic>{};
    final rows = <AuditItem>[];
    for (final entry in data.entries) {
      final value = _asMap(entry.value) ?? const <String, dynamic>{};
      rows.add(AuditItem(id: entry.key, data: value));
    }
    rows.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    return rows;
  }

  List<AuditItem> filtered(List<AuditItem> rows) {
    final q = query.trim().toLowerCase();
    return rows.where((item) {
      if (actionFilter != 'all' && item.category != actionFilter) return false;
      if (q.isEmpty) return true;
      final text = '${item.action} ${item.actor} ${item.target} ${item.rawText}'.toLowerCase();
      return text.contains(q);
    }).toList();
  }

  void showDetail(AuditItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Detail Audit', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                _DetailRow('ID', item.id),
                _DetailRow('Action', item.action),
                _DetailRow('Category', item.category),
                _DetailRow('Actor', item.actor),
                _DetailRow('Target', item.target),
                _DetailRow('Created At', item.createdAtText),
                const SizedBox(height: 12),
                Text('Raw Data', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                ...item.data.entries.map((entry) => _DetailRow(entry.key, entry.value.toString())),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Map<String, int> categoryCounts(List<AuditItem> rows) {
    final counts = <String, int>{};
    for (final row in rows) {
      counts[row.category] = (counts[row.category] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audit Logs'), actions: [IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
      body: FutureBuilder<List<AuditItem>>(
        future: future,
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <AuditItem>[];
          final rows = filtered(all);
          final counts = categoryCounts(all);

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              MessageCard(
                title: 'Audit Logs',
                message: 'Total: ${all.length} • Create: ${counts['create'] ?? 0} • Update: ${counts['update'] ?? 0} • Delete: ${counts['delete'] ?? 0} • Approval: ${counts['approval'] ?? 0}',
                icon: Icons.history_edu_rounded,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: actionFilter,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Semua')),
                  DropdownMenuItem(value: 'create', child: Text('Create')),
                  DropdownMenuItem(value: 'update', child: Text('Update')),
                  DropdownMenuItem(value: 'delete', child: Text('Delete')),
                  DropdownMenuItem(value: 'approval', child: Text('Approval')),
                  DropdownMenuItem(value: 'auth', child: Text('Auth')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (value) => setState(() => actionFilter = value ?? 'all'),
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (value) => setState(() => query = value),
                decoration: const InputDecoration(labelText: 'Cari action, actor, target', prefixIcon: Icon(Icons.search_rounded)),
              ),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                MessageCard(title: 'Gagal memuat audit', message: snapshot.error.toString(), icon: Icons.error_outline_rounded)
              else if (rows.isEmpty)
                const MessageCard(title: 'Tidak ada log', message: 'Tidak ada audit log sesuai filter.', icon: Icons.inbox_outlined)
              else
                ...rows.map((item) => Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Icon(item.icon)),
                        title: Text(item.action, style: const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text('${item.actor}\n${item.target.ifEmpty('-')} • ${item.createdAtText}'),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => showDetail(item),
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }
}

class AuditItem {
  final String id;
  final Map<String, dynamic> data;

  const AuditItem({required this.id, required this.data});

  String get action => _read(data, const ['action', 'event', 'type', 'title']).ifEmpty('audit_event');
  String get actor => _read(data, const ['actor_email', 'actor_name', 'actor_uid', 'created_by_email', 'created_by']).ifEmpty('-');
  String get target => _read(data, const ['target_path', 'target_id', 'target', 'path']).ifEmpty('-');
  String get rawText => data.values.join(' ');
  String get sortKey => '${data['created_at'] ?? data['timestamp'] ?? data['updated_at'] ?? ''}$id';
  String get createdAtText {
    final raw = data['created_at'] ?? data['timestamp'] ?? data['updated_at'];
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw).toLocal().toString();
    if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt()).toLocal().toString();
    return raw?.toString() ?? '-';
  }

  String get category {
    final text = action.toLowerCase();
    if (text.contains('create') || text.contains('add') || text.contains('buat')) return 'create';
    if (text.contains('update') || text.contains('edit') || text.contains('ubah')) return 'update';
    if (text.contains('delete') || text.contains('remove') || text.contains('hapus')) return 'delete';
    if (text.contains('approve') || text.contains('reject') || text.contains('approval') || text.contains('correction')) return 'approval';
    if (text.contains('login') || text.contains('logout') || text.contains('auth')) return 'auth';
    return 'other';
  }

  IconData get icon {
    switch (category) {
      case 'create':
        return Icons.add_circle_rounded;
      case 'update':
        return Icons.edit_rounded;
      case 'delete':
        return Icons.delete_rounded;
      case 'approval':
        return Icons.fact_check_rounded;
      case 'auth':
        return Icons.login_rounded;
      default:
        return Icons.history_rounded;
    }
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          SelectableText(value.isEmpty ? '-' : value),
        ],
      ),
    );
  }
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map) return value.map((key, item) => MapEntry(key.toString(), item));
  return null;
}

String _read(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value != null && value.toString().trim().isNotEmpty) return value.toString();
  }
  return '';
}

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
