import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/firebase_paths.dart';
import '../../core/models.dart';
import '../../services/admin_service.dart';
import '../../services/notification_bridge.dart';
import '../shared/message_card.dart';

class NotificationLogsPage extends StatefulWidget {
  final AdminSession session;
  final AdminService service;

  const NotificationLogsPage({super.key, required this.session, required this.service});

  @override
  State<NotificationLogsPage> createState() => _NotificationLogsPageState();
}

class _NotificationLogsPageState extends State<NotificationLogsPage> {
  late Future<_NotificationLogBundle> future;
  String sourceFilter = 'queue';
  String statusFilter = 'all';
  String query = '';

  @override
  void initState() {
    super.initState();
    future = loadBundle();
  }

  void refresh() => setState(() => future = loadBundle());

  Future<_NotificationLogBundle> loadBundle() async {
    final companyId = widget.session.companyId;
    final results = await Future.wait([
      FirebaseFirestore.instance.collection(FirestorePaths.notificationQueue(companyId)).get(),
      FirebaseFirestore.instance.collection(FirestorePaths.notificationLogs(companyId)).get(),
      FirebaseDatabase.instance.ref('notification_logs/$companyId').get(),
    ]);

    final queueSnap = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final logsSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final legacyLogsData = _asMap((results[2] as DataSnapshot).value) ?? const <String, dynamic>{};

    final queue = queueSnap.docs.map((doc) => NotificationLogItem(id: doc.id, source: 'queue', data: doc.data())).toList()
      ..sort((a, b) => b.sortKey.compareTo(a.sortKey));
    final logs = logsSnap.docs.map((doc) => NotificationLogItem(id: doc.id, source: 'logs', data: doc.data())).toList()
      ..sort((a, b) => b.sortKey.compareTo(a.sortKey));
    if (logs.isEmpty) {
      logs.addAll(legacyLogsData.entries.map((entry) => NotificationLogItem(id: entry.key, source: 'logs', data: _asMap(entry.value) ?? const <String, dynamic>{})));
      logs.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    }

    return _NotificationLogBundle(queue: queue, logs: logs);
  }

  List<NotificationLogItem> filtered(_NotificationLogBundle bundle) {
    final sourceRows = sourceFilter == 'logs' ? bundle.logs : sourceFilter == 'all' ? [...bundle.queue, ...bundle.logs] : bundle.queue;
    final q = query.trim().toLowerCase();
    return sourceRows.where((item) {
      if (statusFilter != 'all' && item.status != statusFilter) return false;
      if (q.isEmpty) return true;
      final text = '${item.title} ${item.body} ${item.type} ${item.target} ${item.status} ${item.rawText}'.toLowerCase();
      return text.contains(q);
    }).toList()..sort((a, b) => b.sortKey.compareTo(a.sortKey));
  }

  Future<void> retryQueue(NotificationLogItem item) async {
    final companyId = widget.session.companyId;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (item.source == 'queue') {
      await FirebaseFirestore.instance.doc(FirestorePaths.notificationQueueItem(companyId, item.id)).set({
        'status': 'pending',
        'retry_count': item.retryCount + 1,
        'updated_at': now,
        'updated_by': widget.session.uid,
      }, SetOptions(merge: true));
    } else {
      final uid = item.target;
      if (uid == 'all' || uid.isEmpty) throw Exception('Log ini tidak punya uid target untuk queue ulang.');
      await NotificationBridge().createNotificationQueue(
        companyId: companyId,
        uid: uid,
        title: item.title,
        message: item.body,
        type: item.type,
        refType: _read(item.data, const ['ref_type']).ifEmpty('notification_log'),
        refId: _read(item.data, const ['ref_id']).ifEmpty(item.id),
        data: {'source_log_id': item.id},
      );
    }

    await FirebaseDatabase.instance.ref(FirebasePaths.auditLogs(companyId)).push().set({
      'action': 'retry_notification',
      'target_id': item.id,
      'actor_uid': widget.session.uid,
      'actor_email': widget.session.email,
      'created_at': now,
    });
    refresh();
  }

  void showDetail(NotificationLogItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text('Detail Notifikasi', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              _DetailRow('ID', item.id),
              _DetailRow('Source', item.source),
              _DetailRow('Status', item.status),
              _DetailRow('Type', item.type),
              _DetailRow('Target', item.target),
              _DetailRow('Title', item.title),
              _DetailRow('Body', item.body),
              _DetailRow('Created', item.createdAtText),
              const SizedBox(height: 12),
              Text('Raw Data', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              ...item.data.entries.map((entry) => _DetailRow(entry.key, entry.value.toString())),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: () => retryQueue(item), icon: const Icon(Icons.refresh_rounded), label: const Text('Retry / Queue ulang')),
            ]),
          ),
        ),
      ),
    );
  }

  Map<String, int> counts(List<NotificationLogItem> rows) {
    final data = <String, int>{'pending': 0, 'sent': 0, 'failed': 0, 'other': 0};
    for (final row in rows) {
      data[row.status] = (data[row.status] ?? 0) + 1;
    }
    return data;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log Notifikasi'), actions: [IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
      body: FutureBuilder<_NotificationLogBundle>(
        future: future,
        builder: (context, snap) {
          final bundle = snap.data ?? const _NotificationLogBundle.empty();
          final rows = filtered(bundle);
          final all = [...bundle.queue, ...bundle.logs];
          final c = counts(all);

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              MessageCard(
                title: 'Notification Monitor',
                message: 'Queue: ${bundle.queue.length} • Logs: ${bundle.logs.length} • Pending: ${c['pending']} • Sent: ${c['sent']} • Failed: ${c['failed']}',
                icon: Icons.notifications_active_rounded,
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: sourceFilter,
                    decoration: const InputDecoration(labelText: 'Sumber'),
                    items: const [
                      DropdownMenuItem(value: 'queue', child: Text('Queue')),
                      DropdownMenuItem(value: 'logs', child: Text('Logs')),
                      DropdownMenuItem(value: 'all', child: Text('Semua')),
                    ],
                    onChanged: (value) => setState(() => sourceFilter = value ?? 'queue'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: statusFilter,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Semua')),
                      DropdownMenuItem(value: 'pending', child: Text('Pending')),
                      DropdownMenuItem(value: 'sent', child: Text('Sent')),
                      DropdownMenuItem(value: 'failed', child: Text('Failed')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (value) => setState(() => statusFilter = value ?? 'all'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(onChanged: (value) => setState(() => query = value), decoration: const InputDecoration(labelText: 'Cari title, body, type, target', prefixIcon: Icon(Icons.search_rounded))),
              const SizedBox(height: 12),
              if (snap.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (snap.hasError)
                MessageCard(title: 'Gagal memuat log', message: snap.error.toString(), icon: Icons.error_outline_rounded)
              else if (rows.isEmpty)
                const MessageCard(title: 'Belum ada log', message: 'Queue dan log push notification akan tampil di sini.', icon: Icons.notifications_outlined)
              else
                ...rows.map((item) => Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Icon(item.icon)),
                        title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text('${item.source.toUpperCase()} • ${item.status.toUpperCase()} • ${item.type}\n${item.body}'),
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

class _NotificationLogBundle {
  final List<NotificationLogItem> queue;
  final List<NotificationLogItem> logs;

  const _NotificationLogBundle({required this.queue, required this.logs});
  const _NotificationLogBundle.empty() : queue = const [], logs = const [];
}

class NotificationLogItem {
  final String id;
  final String source;
  final Map<String, dynamic> data;

  const NotificationLogItem({required this.id, required this.source, required this.data});

  String get title => _read(data, const ['title', 'judul', 'event']).ifEmpty(id);
  String get body => _read(data, const ['body', 'message', 'pesan']).ifEmpty('-');
  String get type => _read(data, const ['type', 'notification_type']).ifEmpty('notification');
  String get target => _read(data, const ['target', 'target_audience', 'uid', 'topic']).ifEmpty('all');
  String get rawStatus => _read(data, const ['status', 'state']).toLowerCase();
  String get status {
    if (rawStatus.contains('pending') || rawStatus.contains('queue')) return 'pending';
    if (rawStatus.contains('sent') || rawStatus.contains('success') || rawStatus.contains('delivered')) return 'sent';
    if (rawStatus.contains('fail') || rawStatus.contains('error')) return 'failed';
    return 'other';
  }

  int get retryCount {
    final value = data['retry_count'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String get rawText => data.values.join(' ');
  String get sortKey => '${data['created_at'] ?? data['sent_at'] ?? data['updated_at'] ?? ''}$id';
  String get createdAtText {
    final raw = data['created_at'] ?? data['sent_at'] ?? data['updated_at'];
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw).toLocal().toString();
    if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt()).toLocal().toString();
    return raw?.toString() ?? '-';
  }

  IconData get icon {
    if (status == 'pending') return Icons.pending_actions_rounded;
    if (status == 'sent') return Icons.check_circle_rounded;
    if (status == 'failed') return Icons.error_rounded;
    return Icons.notifications_rounded;
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        SelectableText(value.isEmpty ? '-' : value),
      ]),
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
