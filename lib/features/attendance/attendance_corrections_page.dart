import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../shared/message_card.dart';

class AttendanceCorrectionsListPage extends StatefulWidget {
  final AdminSession session;

  const AttendanceCorrectionsListPage({super.key, required this.session});

  @override
  State<AttendanceCorrectionsListPage> createState() => _AttendanceCorrectionsListPageState();
}

class _AttendanceCorrectionsListPageState extends State<AttendanceCorrectionsListPage> {
  late Future<List<CorrectionItem>> future;
  String filter = 'pending';
  String query = '';

  @override
  void initState() {
    super.initState();
    future = loadItems();
  }

  void refresh() {
    setState(() => future = loadItems());
  }

  Future<List<CorrectionItem>> loadItems() async {
    final snap = await FirebaseDatabase.instance.ref('attendance_corrections/${widget.session.companyId}').get();
    final data = _asMap(snap.value) ?? const <String, dynamic>{};
    final rows = <CorrectionItem>[];
    for (final entry in data.entries) {
      final value = _asMap(entry.value) ?? const <String, dynamic>{};
      rows.add(CorrectionItem(id: entry.key, data: value));
    }
    rows.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    return rows;
  }

  List<CorrectionItem> filtered(List<CorrectionItem> rows) {
    final q = query.trim().toLowerCase();
    return rows.where((item) {
      if (filter != 'all' && item.normalizedStatus != filter) return false;
      if (q.isEmpty) return true;
      final text = '${item.title} ${item.subtitle} ${item.rawText}'.toLowerCase();
      return text.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Koreksi Absensi'),
        actions: [IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: FutureBuilder<List<CorrectionItem>>(
        future: future,
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <CorrectionItem>[];
          final rows = filtered(all);
          final pending = all.where((item) => item.normalizedStatus == 'pending').length;
          final approved = all.where((item) => item.normalizedStatus == 'approved').length;
          final rejected = all.where((item) => item.normalizedStatus == 'rejected').length;

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              MessageCard(
                title: 'Koreksi Absensi',
                message: 'Pending: $pending • Approved: $approved • Rejected: $rejected',
                icon: Icons.edit_calendar_rounded,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: filter,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'approved', child: Text('Approved')),
                  DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                  DropdownMenuItem(value: 'all', child: Text('Semua')),
                ],
                onChanged: (value) => setState(() => filter = value ?? 'pending'),
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (value) => setState(() => query = value),
                decoration: const InputDecoration(labelText: 'Cari karyawan, tanggal, alasan', prefixIcon: Icon(Icons.search_rounded)),
              ),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                MessageCard(title: 'Gagal memuat koreksi', message: snapshot.error.toString(), icon: Icons.error_outline_rounded)
              else if (rows.isEmpty)
                const MessageCard(title: 'Tidak ada data', message: 'Tidak ada koreksi sesuai filter.', icon: Icons.inbox_outlined)
              else
                ...rows.map(
                  (item) => Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Icon(item.icon)),
                      title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: Text(item.subtitle),
                      isThreeLine: true,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class CorrectionItem {
  final String id;
  final Map<String, dynamic> data;

  const CorrectionItem({required this.id, required this.data});

  String get title => _read(data, const ['employee_name', 'nama_lengkap', 'name', 'display_name', 'uid']).ifEmpty(id);
  String get date => _read(data, const ['date', 'tanggal', 'attendance_date']).ifEmpty('-');
  String get type => _read(data, const ['type', 'action_type', 'jenis']).ifEmpty('koreksi');
  String get reason => _read(data, const ['reason', 'alasan', 'description']).ifEmpty('-');
  String get normalizedStatus {
    final text = _read(data, const ['status', 'approval_status']).toLowerCase();
    if (text.contains('approve') || text.contains('valid') || text.contains('terima')) return 'approved';
    if (text.contains('reject') || text.contains('tolak')) return 'rejected';
    return 'pending';
  }

  String get subtitle => '$date • $type • $reason\nStatus: $normalizedStatus';
  String get rawText => data.values.join(' ');
  String get sortKey => '${data['created_at'] ?? ''}${data['date'] ?? ''}$id';
  IconData get icon {
    if (normalizedStatus == 'approved') return Icons.check_circle_rounded;
    if (normalizedStatus == 'rejected') return Icons.cancel_rounded;
    return Icons.pending_actions_rounded;
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
