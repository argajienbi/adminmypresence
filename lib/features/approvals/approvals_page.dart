import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../services/admin_service.dart';
import '../shared/message_card.dart';

class ApprovalsPage extends StatefulWidget {
  final AdminSession session;
  final AdminService service;

  const ApprovalsPage({super.key, required this.session, required this.service});

  @override
  State<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends State<ApprovalsPage> {
  late Future<List<ApprovalRecord>> future;
  String typeFilter = 'all';
  String statusFilter = 'pending';
  String query = '';
  bool deciding = false;

  @override
  void initState() {
    super.initState();
    future = loadApprovals();
  }

  void refresh() => setState(() => future = loadApprovals());

  Future<List<ApprovalRecord>> loadApprovals() async {
    final companyId = widget.session.companyId;
    final db = FirebaseDatabase.instance;
    final results = await Future.wait([
      db.ref('leave_requests/$companyId').get(),
      db.ref('qr_attendance_requests/$companyId').get(),
      db.ref('attendance_corrections/$companyId').get(),
      db.ref('overtime_requests/$companyId').get(),
      db.ref('company_users/$companyId').get(),
    ]);

    final users = _asMap(results[4].value) ?? const <String, dynamic>{};
    final rows = <ApprovalRecord>[];
    rows.addAll(_recordsFrom(results[0].value, 'leave', 'Cuti/Izin/Sakit', users));
    rows.addAll(_recordsFrom(results[1].value, 'qr', 'QR', users));
    rows.addAll(_recordsFrom(results[2].value, 'correction', 'Koreksi', users));
    rows.addAll(_recordsFrom(results[3].value, 'overtime', 'Lembur', users));
    rows.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    return rows;
  }

  List<ApprovalRecord> _recordsFrom(Object? value, String module, String label, Map<String, dynamic> users) {
    final data = _asMap(value) ?? const <String, dynamic>{};
    final rows = <ApprovalRecord>[];
    for (final entry in data.entries) {
      final item = _asMap(entry.value) ?? const <String, dynamic>{};
      final uid = _read(item, const ['uid', 'user_id', 'employee_id']);
      final user = _asMap(users[uid]) ?? const <String, dynamic>{};
      rows.add(ApprovalRecord(id: entry.key, module: module, label: _inferLabel(module, label, item), data: item, user: user));
    }
    return rows;
  }

  String _inferLabel(String module, String fallback, Map<String, dynamic> data) {
    if (module == 'leave') {
      final type = _read(data, const ['type', 'jenis', 'leave_type', 'request_type']).toLowerCase();
      if (type.contains('sakit')) return 'Sakit';
      if (type.contains('izin')) return 'Izin';
      if (type.contains('lembur')) return 'Lembur';
      return 'Cuti';
    }
    return fallback;
  }

  List<ApprovalRecord> filterRows(List<ApprovalRecord> rows) {
    final q = query.trim().toLowerCase();
    return rows.where((item) {
      if (typeFilter != 'all' && item.module != typeFilter && item.label.toLowerCase() != typeFilter) return false;
      if (statusFilter != 'all' && item.normalizedStatus != statusFilter) return false;
      if (q.isEmpty) return true;
      final text = '${item.userName} ${item.email} ${item.label} ${item.reason} ${item.date} ${item.rawText}'.toLowerCase();
      return text.contains(q);
    }).toList();
  }

  Future<void> decide(ApprovalRecord item, String status) async {
    final note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NoteSheet(title: '${status == 'approved' ? 'Setujui' : 'Tolak'} ${item.label}'),
    );
    if (note == null) return;
    if (deciding) return;

    setState(() => deciding = true);
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final path = item.path(widget.session.companyId);
      await FirebaseDatabase.instance.ref(path).update({
        'status': status,
        'approval_status': status,
        'approved': status == 'approved',
        'admin_note': note,
        'review_note': note,
        'reviewed_at': now,
        'reviewed_by': widget.session.uid,
        'reviewed_by_email': widget.session.email,
        'reviewed_by_name': widget.session.displayName,
      });
      await FirebaseDatabase.instance.ref('audit_logs/${widget.session.companyId}').push().set({
        'action': '${item.module}_$status',
        'target_id': item.id,
        'target_path': path,
        'actor_uid': widget.session.uid,
        'actor_email': widget.session.email,
        'created_at': now,
      });
      refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => deciding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<ApprovalRecord>>(
      future: future,
      builder: (context, snap) {
        final all = snap.data ?? const <ApprovalRecord>[];
        final rows = filterRows(all);
        final pending = all.where((e) => e.normalizedStatus == 'pending').length;
        final approved = all.where((e) => e.normalizedStatus == 'approved').length;
        final rejected = all.where((e) => e.normalizedStatus == 'rejected').length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          children: [
            Row(children: [Expanded(child: Text('Approval', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900))), IconButton.filledTonal(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
            const SizedBox(height: 12),
            MessageCard(title: 'Approval Center', message: 'Pending: $pending • Approved: $approved • Rejected: $rejected', icon: Icons.fact_check_rounded),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: const [
              _FilterChipData('all', 'Semua'),
              _FilterChipData('leave', 'Cuti/Izin/Sakit'),
              _FilterChipData('qr', 'QR'),
              _FilterChipData('correction', 'Koreksi'),
              _FilterChipData('overtime', 'Lembur'),
            ].map((chip) => ChoiceChip(label: Text(chip.label), selected: typeFilter == chip.value, onSelected: (_) => setState(() => typeFilter = chip.value))).toList()),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: statusFilter,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'pending', child: Text('Pending')),
                DropdownMenuItem(value: 'approved', child: Text('Approved')),
                DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                DropdownMenuItem(value: 'all', child: Text('Semua')),
              ],
              onChanged: (value) => setState(() => statusFilter = value ?? 'pending'),
            ),
            const SizedBox(height: 12),
            TextField(onChanged: (v) => setState(() => query = v), decoration: const InputDecoration(labelText: 'Cari nama, email, tanggal, alasan', prefixIcon: Icon(Icons.search_rounded))),
            const SizedBox(height: 12),
            if (snap.connectionState == ConnectionState.waiting)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (snap.hasError)
              MessageCard(title: 'Gagal memuat approval', message: snap.error.toString(), icon: Icons.error_outline_rounded)
            else if (rows.isEmpty)
              const MessageCard(title: 'Tidak ada approval', message: 'Tidak ada pengajuan sesuai filter.', icon: Icons.fact_check_outlined)
            else
              ...rows.map((item) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          CircleAvatar(child: Icon(item.icon)),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.userName, style: const TextStyle(fontWeight: FontWeight.w900)), Text('${item.label} • ${item.date} • ${item.normalizedStatus}')]))
                        ]),
                        if (item.reason.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(item.reason)),
                        const SizedBox(height: 12),
                        if (item.normalizedStatus == 'pending')
                          Row(children: [
                            Expanded(child: OutlinedButton.icon(onPressed: deciding ? null : () => decide(item, 'rejected'), icon: const Icon(Icons.close_rounded), label: const Text('Tolak'))),
                            const SizedBox(width: 10),
                            Expanded(child: FilledButton.icon(onPressed: deciding ? null : () => decide(item, 'approved'), icon: const Icon(Icons.check_rounded), label: const Text('Setujui'))),
                          ]),
                      ]),
                    ),
                  )),
          ],
        );
      },
    );
  }
}

class _FilterChipData {
  final String value;
  final String label;

  const _FilterChipData(this.value, this.label);
}

class ApprovalRecord {
  final String id;
  final String module;
  final String label;
  final Map<String, dynamic> data;
  final Map<String, dynamic> user;

  const ApprovalRecord({required this.id, required this.module, required this.label, required this.data, required this.user});

  String get uid => _read(data, const ['uid', 'user_id', 'employee_id']);
  String get userName => _read(data, const ['employee_name', 'user_name', 'nama_lengkap', 'name']).ifEmpty(_read(user, const ['nama_lengkap', 'display_name', 'name']).ifEmpty(uid.ifEmpty(id)));
  String get email => _read(data, const ['email']).ifEmpty(_read(user, const ['email']));
  String get date => _read(data, const ['date', 'tanggal', 'start_date', 'attendance_date']).ifEmpty('-');
  String get reason => _read(data, const ['reason', 'alasan', 'description', 'note']);
  String get rawText => data.values.join(' ');
  String get sortKey => '${data['created_at'] ?? data['submitted_at'] ?? data['date'] ?? ''}$id';
  String get normalizedStatus {
    final text = _read(data, const ['status', 'approval_status']).toLowerCase();
    if (text.contains('approve') || text.contains('valid') || text.contains('terima')) return 'approved';
    if (text.contains('reject') || text.contains('tolak')) return 'rejected';
    return 'pending';
  }

  String path(String companyId) {
    if (module == 'leave') return 'leave_requests/$companyId/$id';
    if (module == 'qr') return 'qr_attendance_requests/$companyId/$id';
    if (module == 'correction') return 'attendance_corrections/$companyId/$id';
    return 'overtime_requests/$companyId/$id';
  }

  IconData get icon {
    if (module == 'leave') return Icons.event_available_rounded;
    if (module == 'qr') return Icons.qr_code_rounded;
    if (module == 'correction') return Icons.edit_calendar_rounded;
    return Icons.more_time_rounded;
  }
}

class _NoteSheet extends StatefulWidget {
  final String title;

  const _NoteSheet({required this.title});

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final note = TextEditingController();

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Catatan admin')),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.of(context).pop(note.text), child: const Text('Simpan')),
        ]),
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
