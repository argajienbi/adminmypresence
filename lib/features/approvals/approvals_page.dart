import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/firebase_paths.dart';
import '../../core/models.dart';
import '../../services/admin_service.dart';
import '../../services/notification_bridge.dart';
import '../../services/schedule_resolver.dart';
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
    if (status == 'rejected' && note.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alasan penolakan wajib diisi.')));
      return;
    }
    if (deciding) return;

    setState(() => deciding = true);
    try {
      if (item.module == 'leave') {
        await _decideLeave(item, status, note.trim());
      } else if (item.module == 'qr') {
        await _decideQr(item, status, note.trim());
      } else {
        await _decideGeneric(item, status, note.trim());
      }
      refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => deciding = false);
    }
  }

  Future<void> _decideLeave(ApprovalRecord item, String status, String note) async {
    final companyId = widget.session.companyId;
    final now = DateTime.now().millisecondsSinceEpoch;
    final path = FirebasePaths.leaveRequest(companyId, item.id);
    final updates = <String, dynamic>{
      '$path/status': status,
      '$path/approval_status': status,
      '$path/admin_note': note,
      '$path/updated_at': now,
    };
    if (status == 'approved') {
      updates['$path/approved_by'] = widget.session.uid;
      updates['$path/approved_by_name'] = widget.session.displayName;
      updates['$path/approved_at'] = now;
    } else {
      updates['$path/rejected_by'] = widget.session.uid;
      updates['$path/rejected_by_name'] = widget.session.displayName;
      updates['$path/rejected_at'] = now;
    }

    await FirebaseDatabase.instance.ref().update(updates);
    final bridge = NotificationBridge();
    await bridge.writeAuditLog(
      companyId,
      action: status == 'approved' ? 'APPROVE_LEAVE' : 'REJECT_LEAVE',
      details: 'Request ${item.id}, type ${item.leaveType}, status $status. Admin note: ${note.ifEmpty('-')}',
      userUid: widget.session.uid,
      userName: widget.session.displayName,
      targetPath: path,
    );
    if (item.uid.isNotEmpty) {
      final label = item.label;
      await bridge.createNotification(
        uid: item.uid,
        companyId: companyId,
        title: status == 'approved' ? '$label Disetujui' : '$label Ditolak',
        message: note.isNotEmpty ? 'Admin note: $note' : (status == 'approved' ? 'Pengajuan ${label.toLowerCase()} Anda disetujui.' : 'Pengajuan ${label.toLowerCase()} Anda ditolak.'),
        type: status == 'approved' ? 'success' : 'danger',
        refType: 'leave_request',
        refId: item.id,
      );
    }
  }

  Future<void> _decideQr(ApprovalRecord item, String status, String note) async {
    final companyId = widget.session.companyId;
    final now = DateTime.now().millisecondsSinceEpoch;
    final path = FirebasePaths.qrRequest(companyId, item.id);
    final updates = <String, dynamic>{
      '$path/status': status,
      '$path/approval_status': status,
      '$path/admin_note': note,
      '$path/updated_at': now,
    };
    final targetUid = item.targetUid;
    if (targetUid.isEmpty) throw Exception('Target UID QR request kosong.');

    if (status == 'approved') {
      final safeDate = item.date == '-' ? '' : item.date;
      if (safeDate.isEmpty) throw Exception('Tanggal QR request kosong.');
      final safeTime = item.time.ifEmpty(_timeKey(DateTime.now()));
      final safeAction = item.actionType.ifEmpty('masuk');
      final attendancePath = FirebasePaths.attendanceRecord(companyId, targetUid, safeDate, safeAction);
      final existingAttendance = await FirebaseDatabase.instance.ref(attendancePath).get();
      if (existingAttendance.exists) {
        throw Exception('Attendance untuk user, tanggal, dan action ini sudah ada.');
      }

      final employeeSnap = await FirebaseDatabase.instance.ref(FirebasePaths.companyUser(companyId, targetUid)).get();
      final employee = _asMap(employeeSnap.value) ?? const <String, dynamic>{};
      final schedule = await ScheduleResolver().resolveScheduleForUser(companyId: companyId, uid: targetUid, date: safeDate);
      final radius = _toDouble(item.data['radius_meter'], 0);
      final distance = _toDouble(item.data['distance_meter'], 0);

      updates['$path/approved_by'] = widget.session.uid;
      updates['$path/approved_by_name'] = widget.session.displayName;
      updates['$path/approved_at'] = now;
      updates[attendancePath] = {
        'company_id': _read(item.data, const ['company_id']).ifEmpty(companyId),
        'uid': targetUid,
        'date': safeDate,
        'tanggal': safeDate,
        'time': safeTime,
        'waktu': safeTime,
        'action_type': safeAction,
        'method': 'qr',
        'source': 'admin_web',
        'status': 'approved',
        'validation_status': 'approved',
        'attendance_status': schedule.attendanceStatus ?? 'hadir',
        'photo_url': _read(item.data, const ['photo_url']),
        'photo_path': _read(item.data, const ['photo_path']),
        'office_id': _read(item.data, const ['office_id']).ifEmpty(_read(employee, const ['office_id'])),
        'department_id': _read(item.data, const ['department_id']).ifEmpty(_read(employee, const ['department_id'])),
        'sub_department_id': _read(item.data, const ['sub_department_id']).ifEmpty(_read(employee, const ['sub_department_id'])),
        'group_id': _read(item.data, const ['group_id']).ifEmpty(_read(employee, const ['group_id'])),
        'assignment_id': schedule.assignmentId ?? '',
        'shift_id': schedule.shiftId ?? '',
        'shift_name': schedule.shiftName ?? '',
        'timetable_id': schedule.timetableId ?? '',
        'timetable_name': schedule.timetableName ?? '',
        'schedule_source': schedule.scheduleSource,
        'work_start': schedule.workStart ?? '',
        'work_end': schedule.workEnd ?? '',
        'check_in_start': schedule.checkInStart ?? '',
        'check_in_end': schedule.checkInEnd ?? '',
        'check_out_start': schedule.checkOutStart ?? '',
        'check_out_end': schedule.checkOutEnd ?? '',
        'late_tolerance_minute': schedule.lateToleranceMinute ?? 0,
        'latitude': _toNullableDouble(item.data['latitude']),
        'longitude': _toNullableDouble(item.data['longitude']),
        'accuracy': _toDouble(item.data['accuracy'], 0),
        'office_latitude': _toNullableDouble(item.data['office_latitude']),
        'office_longitude': _toNullableDouble(item.data['office_longitude']),
        'distance_meter': distance,
        'radius_meter': radius,
        'geofence_status': radius > 0 && distance <= radius ? 'inside' : 'outside',
        'created_by_qr': true,
        'proxy_request_id': item.id,
        'qr_request_id': item.id,
        'qr_helper_uid': _read(item.data, const ['helper_uid']),
        'qr_helper_name': _read(item.data, const ['helper_name']),
        'approved_by': widget.session.uid,
        'approved_by_name': widget.session.displayName,
        'approved_at': now,
        'created_at': now,
        'updated_at': now,
      };
    } else {
      updates['$path/rejected_by'] = widget.session.uid;
      updates['$path/rejected_by_name'] = widget.session.displayName;
      updates['$path/rejected_at'] = now;
    }

    await FirebaseDatabase.instance.ref().update(updates);
    final bridge = NotificationBridge();
    await bridge.writeAuditLog(
      companyId,
      action: status == 'approved' ? 'APPROVE_QR' : 'REJECT_QR',
      details: 'Admin note: ${note.ifEmpty('-')}',
      userUid: widget.session.uid,
      userName: widget.session.displayName,
      targetPath: path,
    );
    await bridge.createNotification(
      uid: targetUid,
      companyId: companyId,
      title: status == 'approved' ? 'QR Attendance Disetujui' : 'QR Attendance Ditolak',
      message: note.isNotEmpty ? 'Admin note: $note' : (status == 'approved' ? 'Kehadiran melalui QR teman disetujui.' : 'Kehadiran melalui QR ditolak.'),
      type: status == 'approved' ? 'success' : 'danger',
      refType: 'qr_request',
      refId: item.id,
    );

    final helperUid = _read(item.data, const ['helper_uid']);
    if (helperUid.isNotEmpty) {
      await bridge.createNotification(
        uid: helperUid,
        companyId: companyId,
        title: status == 'approved' ? 'Approve Scanner QR' : 'Reject Scanner QR',
        message: 'Pengajuan scan untuk ${item.userName} telah ${status == 'approved' ? 'disetujui' : 'ditolak'}.',
        type: 'info',
        refType: 'qr_request',
        refId: item.id,
      );
    }
  }

  Future<void> _decideGeneric(ApprovalRecord item, String status, String note) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final path = item.path(widget.session.companyId);
    await FirebaseDatabase.instance.ref(path).update({
      'status': status,
      if (item.module == 'correction') 'correction_status': status,
      'approval_status': status,
      'approved': status == 'approved',
      'admin_note': note,
      'review_note': note,
      'reviewed_at': now,
      'reviewed_by': widget.session.uid,
      'reviewed_by_email': widget.session.email,
      'reviewed_by_name': widget.session.displayName,
    });
    await FirebaseDatabase.instance.ref(FirebasePaths.auditLogs(widget.session.companyId)).push().set({
      'action': '${item.module}_$status',
      'target_id': item.id,
      'target_path': path,
      'actor_uid': widget.session.uid,
      'actor_email': widget.session.email,
      'created_at': now,
    });
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

  String get uid => _read(data, const ['uid', 'target_uid', 'user_id', 'employee_id']);
  String get targetUid => _read(data, const ['target_uid', 'uid', 'user_id', 'employee_id']);
  String get userName => _read(data, const ['target_name', 'employee_name', 'user_name', 'nama_lengkap', 'name']).ifEmpty(_read(user, const ['nama_lengkap', 'display_name', 'name']).ifEmpty(uid.ifEmpty(id)));
  String get email => _read(data, const ['email']).ifEmpty(_read(user, const ['email']));
  String get date => _read(data, const ['date', 'tanggal', 'start_date', 'attendance_date']).ifEmpty('-');
  String get time => _read(data, const ['time', 'waktu']);
  String get actionType => _read(data, const ['action_type', 'action']).ifEmpty('masuk');
  String get leaveType => _read(data, const ['type', 'jenis', 'leave_type', 'request_type']).ifEmpty('izin').toLowerCase();
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

double _toDouble(Object? value, double fallback) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

double? _toNullableDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

String _timeKey(DateTime value) {
  String two(int item) => item.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
