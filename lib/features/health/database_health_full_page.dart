import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../shared/message_card.dart';

class DatabaseHealthFullPage extends StatefulWidget {
  final AdminSession session;

  const DatabaseHealthFullPage({super.key, required this.session});

  @override
  State<DatabaseHealthFullPage> createState() => _DatabaseHealthFullPageState();
}

class _DatabaseHealthFullPageState extends State<DatabaseHealthFullPage> {
  late Future<List<DatabaseHealthItem>> future;
  String filter = 'all';
  String query = '';
  bool resetting = false;

  @override
  void initState() {
    super.initState();
    future = loadItems();
  }

  void refresh() {
    setState(() => future = loadItems());
  }

  List<String> get paths {
    final companyId = widget.session.companyId;
    return [
      'companies',
      'companies/$companyId',
      'companies/$companyId/settings',
      'companies/$companyId/notification_settings',
      'companies/$companyId/notification_queue',
      'users',
      'company_users/$companyId',
      'company_admins/$companyId',
      'company_invites',
      'attendance/$companyId',
      'leave_requests/$companyId',
      'qr_attendance_requests/$companyId',
      'attendance_corrections/$companyId',
      'overtime_requests/$companyId',
      'timetables/$companyId',
      'shifts/$companyId',
      'schedule_assignments/$companyId',
      'schedule_specials/$companyId',
      'schedule_change_logs/$companyId',
      'holidays/$companyId',
      'overtime_schedules/$companyId',
      'offices/$companyId',
      'areas/$companyId',
      'departments/$companyId',
      'sub_departments/$companyId',
      'employee_groups/$companyId',
      'announcements/$companyId',
      'notification_logs/$companyId',
      'audit_logs/$companyId',
      'app_config',
    ];
  }

  Future<List<DatabaseHealthItem>> loadItems() async {
    final db = FirebaseDatabase.instance;
    final rows = <DatabaseHealthItem>[];
    for (final path in paths) {
      try {
        final snap = await db.ref(path).get();
        final value = snap.value;
        rows.add(DatabaseHealthItem(path: path, exists: snap.exists, value: value, error: null));
      } catch (error) {
        rows.add(DatabaseHealthItem(path: path, exists: false, value: null, error: error.toString()));
      }
    }
    rows.sort((a, b) => a.path.compareTo(b.path));
    return rows;
  }

  List<DatabaseHealthItem> filtered(List<DatabaseHealthItem> rows) {
    final q = query.trim().toLowerCase();
    return rows.where((item) {
      if (filter != 'all' && item.status != filter) return false;
      if (q.isEmpty) return true;
      return item.path.toLowerCase().contains(q) || item.preview.toLowerCase().contains(q);
    }).toList();
  }

  void showDetail(DatabaseHealthItem item) {
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
                Text(item.path, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                _DetailRow('Status', item.status.toUpperCase()),
                _DetailRow('Count', item.count.toString()),
                _DetailRow('Type', item.typeLabel),
                if (item.error != null) _DetailRow('Error', item.error!),
                const SizedBox(height: 12),
                Text('Preview', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                SelectableText(item.preview.isEmpty ? '-' : item.preview),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Map<String, int> counts(List<DatabaseHealthItem> rows) {
    final result = <String, int>{'ok': 0, 'empty': 0, 'missing': 0, 'error': 0};
    for (final row in rows) {
      result[row.status] = (result[row.status] ?? 0) + 1;
    }
    return result;
  }

  Future<void> openResetDummyData() async {
    if (!widget.session.isOwner) return;
    final selected = {for (final option in _resetOptions) option.key: option.defaultChecked};
    final confirm = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Reset Data Dummy', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  ..._resetOptions.map((option) => CheckboxListTile(
                        value: selected[option.key] ?? false,
                        title: Text(option.label),
                        subtitle: Text(option.path(widget.session.companyId)),
                        onChanged: (value) => setSheetState(() => selected[option.key] = value ?? false),
                      )),
                  const SizedBox(height: 12),
                  TextField(controller: confirm, decoration: const InputDecoration(labelText: 'Ketik RESET DATABASE')),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      if (confirm.text.trim() == 'RESET DATABASE') Navigator.of(context).pop(true);
                    },
                    child: const Text('Reset Data Dummy'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (ok != true) return;
    setState(() => resetting = true);
    try {
      final companyId = widget.session.companyId;
      final deleted = <String>[];
      for (final option in _resetOptions.where((option) => selected[option.key] == true)) {
        final path = option.path(companyId);
        if (option.firestore) {
          final snap = await FirebaseFirestore.instance.collection(path).get();
          final batch = FirebaseFirestore.instance.batch();
          for (final doc in snap.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();
          deleted.add('firestore:$path');
        } else {
          await FirebaseDatabase.instance.ref(path).remove();
          deleted.add(path);
        }
      }
      await FirebaseDatabase.instance.ref('audit_logs/$companyId/owner_reset_${DateTime.now().millisecondsSinceEpoch}').set({
        'action': 'OWNER_RESET_DUMMY_DATA',
        'deleted_paths': deleted,
        'actor_uid': widget.session.uid,
        'actor_email': widget.session.email,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reset selesai: ${deleted.length} path.')));
      refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => resetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Database Health'), actions: [IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
      body: FutureBuilder<List<DatabaseHealthItem>>(
        future: future,
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <DatabaseHealthItem>[];
          final rows = filtered(all);
          final c = counts(all);

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              MessageCard(
                title: 'Database Health Full',
                message: 'OK: ${c['ok']} • Empty: ${c['empty']} • Missing: ${c['missing']} • Error: ${c['error']}',
                icon: Icons.health_and_safety_rounded,
              ),
              if (resetting) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
              if (widget.session.isOwner) ...[
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: resetting ? null : openResetDummyData, icon: const Icon(Icons.delete_sweep_rounded), label: const Text('Reset Data Dummy')),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: filter,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Semua')),
                  DropdownMenuItem(value: 'ok', child: Text('OK')),
                  DropdownMenuItem(value: 'empty', child: Text('Empty')),
                  DropdownMenuItem(value: 'missing', child: Text('Missing')),
                  DropdownMenuItem(value: 'error', child: Text('Error')),
                ],
                onChanged: (value) => setState(() => filter = value ?? 'all'),
              ),
              const SizedBox(height: 12),
              TextField(onChanged: (value) => setState(() => query = value), decoration: const InputDecoration(labelText: 'Cari path / preview', prefixIcon: Icon(Icons.search_rounded))),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                MessageCard(title: 'Gagal memuat database health', message: snapshot.error.toString(), icon: Icons.error_outline_rounded)
              else if (rows.isEmpty)
                const MessageCard(title: 'Tidak ada path', message: 'Tidak ada path sesuai filter.', icon: Icons.inbox_outlined)
              else
                ...rows.map((item) => Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Icon(item.icon)),
                        title: Text(item.path, style: const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text('${item.status.toUpperCase()} • ${item.typeLabel} • ${item.count} item(s)'),
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

class DatabaseHealthItem {
  final String path;
  final bool exists;
  final Object? value;
  final String? error;

  const DatabaseHealthItem({required this.path, required this.exists, required this.value, required this.error});

  String get status {
    if (error != null) return 'error';
    if (!exists) return 'missing';
    if (value == null) return 'empty';
    if (value is Map && (value as Map).isEmpty) return 'empty';
    if (value is List && (value as List).isEmpty) return 'empty';
    if (value is String && (value as String).trim().isEmpty) return 'empty';
    return 'ok';
  }

  int get count {
    if (value is Map) return (value as Map).length;
    if (value is List) return (value as List).length;
    if (value == null) return 0;
    return 1;
  }

  String get typeLabel {
    if (value == null) return 'null';
    if (value is Map) return 'Map';
    if (value is List) return 'List';
    if (value is String) return 'String';
    if (value is num) return 'Number';
    if (value is bool) return 'Boolean';
    return value.runtimeType.toString();
  }

  String get preview {
    if (error != null) return error!;
    final text = value.toString();
    if (text.length <= 2000) return text;
    return '${text.substring(0, 2000)}...';
  }

  IconData get icon {
    switch (status) {
      case 'ok':
        return Icons.check_circle_rounded;
      case 'empty':
        return Icons.inbox_rounded;
      case 'missing':
        return Icons.help_outline_rounded;
      case 'error':
        return Icons.error_rounded;
      default:
        return Icons.storage_rounded;
    }
  }
}

const _resetOptions = [
  _ResetOption('attendance', 'Absensi', false, false, _rtdbAttendance),
  _ResetOption('leave_requests', 'Pengajuan Cuti/Izin', false, false, _rtdbLeave),
  _ResetOption('qr_requests', 'QR Attendance Requests', false, false, _rtdbQr),
  _ResetOption('corrections', 'Koreksi Absensi', false, false, _rtdbCorrections),
  _ResetOption('overtime_requests', 'Overtime Requests', false, false, _rtdbOvertimeRequests),
  _ResetOption('notifications', 'Notification Logs RTDB', false, false, _rtdbNotificationLogs),
  _ResetOption('notification_queue', 'Notification Queue Firestore', true, false, _firestoreNotificationQueue),
  _ResetOption('report_cache', 'Report Cache RTDB', false, false, _rtdbReportCache),
  _ResetOption('storage_index', 'Storage Index RTDB', false, false, _rtdbStorageIndex),
];

class _ResetOption {
  const _ResetOption(this.key, this.label, this.firestore, this.defaultChecked, this.path);

  final String key;
  final String label;
  final bool firestore;
  final bool defaultChecked;
  final String Function(String companyId) path;
}

String _rtdbAttendance(String companyId) => 'attendance/$companyId';
String _rtdbLeave(String companyId) => 'leave_requests/$companyId';
String _rtdbQr(String companyId) => 'qr_attendance_requests/$companyId';
String _rtdbCorrections(String companyId) => 'attendance_corrections/$companyId';
String _rtdbOvertimeRequests(String companyId) => 'overtime_requests/$companyId';
String _rtdbNotificationLogs(String companyId) => 'notification_logs/$companyId';
String _rtdbReportCache(String companyId) => 'report_cache/$companyId';
String _rtdbStorageIndex(String companyId) => 'storage_index/$companyId';
String _firestoreNotificationQueue(String companyId) => 'companies/$companyId/notification_queue';

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
