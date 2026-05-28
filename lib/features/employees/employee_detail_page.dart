import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../services/notification_bridge.dart';
import '../shared/message_card.dart';

class EmployeeDetailPage extends StatefulWidget {
  final AdminSession session;
  final String employeeId;

  const EmployeeDetailPage({super.key, required this.session, required this.employeeId});

  @override
  State<EmployeeDetailPage> createState() => _EmployeeDetailPageState();
}

class _EmployeeDetailPageState extends State<EmployeeDetailPage> {
  late Future<EmployeeDetailBundle> future;
  DateTime? startDate;
  DateTime? endDate;

  @override
  void initState() {
    super.initState();
    future = loadDetail();
  }

  void refresh() => setState(() => future = loadDetail());

  Future<void> resetFace() async {
    final companyId = widget.session.companyId;
    final uid = widget.employeeId;
    final ok = await _confirm('Reset Data Wajah', 'Karyawan harus mendaftarkan wajah ulang sebelum absensi berikutnya.');
    if (ok != true) return;
    final updates = <String, dynamic>{
      'company_users/$companyId/$uid/face_registered': false,
      'company_users/$companyId/$uid/face_registered_at': null,
      'companies/$companyId/face_descriptors/$uid': null,
    };
    await FirebaseDatabase.instance.ref().update(updates);
    final bridge = NotificationBridge();
    await bridge.writeAuditLog(
      companyId,
      action: 'RESET_FACE_DATA',
      details: 'Menghapus data wajah karyawan $uid',
      userUid: widget.session.uid,
      userName: widget.session.displayName,
      targetPath: 'company_users/$companyId/$uid',
    );
    await bridge.createNotification(
      uid: uid,
      companyId: companyId,
      title: 'Pendaftaran Wajah Ulang Diperlukan',
      message: 'Data wajah Anda telah di-reset oleh admin. Harap mendaftar ulang wajah sebelum absensi berikutnya.',
      type: 'warning',
      refType: 'face_reset',
      refId: uid,
    );
    refresh();
  }

  Future<void> resetDevice() async {
    final companyId = widget.session.companyId;
    final uid = widget.employeeId;
    final ok = await _confirm('Reset Perangkat', 'Data perangkat karyawan akan dikosongkan.');
    if (ok != true) return;
    await FirebaseDatabase.instance.ref().update({
      'company_users/$companyId/$uid/device_id': null,
      'company_users/$companyId/$uid/device_name': null,
    });
    await NotificationBridge().writeAuditLog(
      companyId,
      action: 'RESET_DEVICE_DATA',
      details: 'Mereset device karyawan $uid',
      userUid: widget.session.uid,
      userName: widget.session.displayName,
      targetPath: 'company_users/$companyId/$uid',
    );
    refresh();
  }

  Future<bool?> _confirm(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Lanjutkan')),
        ],
      ),
    );
  }

  Future<EmployeeDetailBundle> loadDetail() async {
    final companyId = widget.session.companyId;
    final uid = widget.employeeId;
    final db = FirebaseDatabase.instance;
    final results = await Future.wait([
      db.ref('company_users/$companyId/$uid').get(),
      db.ref('attendance/$companyId/$uid').get(),
      db.ref('schedule_assignments/$companyId/$uid').get(),
      db.ref('leave_requests/$companyId').get(),
      db.ref('attendance_corrections/$companyId').get(),
      db.ref('overtime_requests/$companyId').get(),
    ]);

    final user = _asMap(results[0].value) ?? const <String, dynamic>{};
    final attendance = _attendanceRows(results[1].value, uid);
    final assignment = _asMap(results[2].value) ?? const <String, dynamic>{};
    final requests = <EmployeeRequestRecord>[];
    requests.addAll(_requestRows(results[3].value, uid, 'Cuti/Izin/Sakit'));
    requests.addAll(_requestRows(results[4].value, uid, 'Koreksi Absensi'));
    requests.addAll(_requestRows(results[5].value, uid, 'Lembur'));
    requests.sort((a, b) => b.sortKey.compareTo(a.sortKey));

    return EmployeeDetailBundle(
      employee: EmployeeProfileRecord(id: uid, data: user),
      attendance: attendance,
      assignment: assignment,
      requests: requests,
    );
  }

  List<EmployeeAttendanceRecord> _attendanceRows(Object? value, String uid) {
    final data = _asMap(value) ?? const <String, dynamic>{};
    final rows = <EmployeeAttendanceRecord>[];
    for (final dayEntry in data.entries) {
      final day = dayEntry.key;
      if (!_dateAllowed(day)) continue;
      final actions = _asMap(dayEntry.value);
      if (actions == null) continue;
      for (final actionEntry in actions.entries) {
        rows.add(EmployeeAttendanceRecord(
          uid: uid,
          date: day,
          actionKey: actionEntry.key,
          data: _asMap(actionEntry.value) ?? const <String, dynamic>{},
        ));
      }
    }
    rows.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    return rows;
  }

  List<EmployeeRequestRecord> _requestRows(Object? value, String uid, String type) {
    final data = _asMap(value) ?? const <String, dynamic>{};
    final rows = <EmployeeRequestRecord>[];
    for (final entry in data.entries) {
      final item = _asMap(entry.value) ?? const <String, dynamic>{};
      final itemUid = _read(item, const ['uid', 'user_id', 'employee_id']);
      if (itemUid != uid) continue;
      rows.add(EmployeeRequestRecord(id: entry.key, type: type, data: item));
    }
    return rows;
  }

  bool _dateAllowed(String rawDate) {
    final parsed = DateTime.tryParse(rawDate);
    if (parsed == null) return true;
    if (startDate != null && parsed.isBefore(DateTime(startDate!.year, startDate!.month, startDate!.day))) return false;
    if (endDate != null && parsed.isAfter(DateTime(endDate!.year, endDate!.month, endDate!.day, 23, 59, 59))) return false;
    return true;
  }

  Future<void> pickStart() async {
    final picked = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2035), initialDate: startDate ?? DateTime.now());
    if (picked != null) {
      setState(() {
        startDate = picked;
        future = loadDetail();
      });
    }
  }

  Future<void> pickEnd() async {
    final picked = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2035), initialDate: endDate ?? DateTime.now());
    if (picked != null) {
      setState(() {
        endDate = picked;
        future = loadDetail();
      });
    }
  }

  void showAttendanceDetail(EmployeeAttendanceRecord row) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text('Detail Absensi', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              _DetailRow('Tanggal', row.date),
              _DetailRow('Aksi', row.actionLabel),
              _DetailRow('Jam', row.time),
              _DetailRow('Status', row.statusLabel),
              _DetailRow('Latitude', row.latitude.toString()),
              _DetailRow('Longitude', row.longitude.toString()),
              _DetailRow('Jarak Meter', row.distance.toStringAsFixed(0)),
              const SizedBox(height: 12),
              ...row.data.entries.map((entry) => _DetailRow(entry.key, entry.value.toString())),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Karyawan'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'face') resetFace();
              if (value == 'device') resetDevice();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'face', child: Text('Reset Data Wajah')),
              PopupMenuItem(value: 'device', child: Text('Reset Perangkat')),
            ],
          ),
          IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: FutureBuilder<EmployeeDetailBundle>(
        future: future,
        builder: (context, snapshot) {
          final bundle = snapshot.data ?? const EmployeeDetailBundle.empty();
          final profile = bundle.employee;
          final checkIn = bundle.attendance.where((row) => row.actionType == 'in').length;
          final checkOut = bundle.attendance.where((row) => row.actionType == 'out').length;
          final late = bundle.attendance.where((row) => row.statusType == 'late').length;
          final outside = bundle.attendance.where((row) => row.statusType == 'outside').length;

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                MessageCard(title: 'Gagal memuat detail karyawan', message: snapshot.error.toString(), icon: Icons.error_outline_rounded)
              else ...[
                MessageCard(
                  title: profile.name,
                  message: '${profile.email.ifEmpty('-')} • ${profile.nip.ifEmpty('-')} • ${profile.role}\n${profile.officeName.ifEmpty('-')} • ${profile.departmentName.ifEmpty('-')} • ${profile.statusLabel}',
                  icon: Icons.person_rounded,
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  _MiniStat('Masuk', checkIn, Icons.login_rounded),
                  _MiniStat('Pulang', checkOut, Icons.logout_rounded),
                  _MiniStat('Terlambat', late, Icons.timer_off_rounded),
                  _MiniStat('Luar Radius', outside, Icons.wrong_location_rounded),
                ]),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.assignment_ind_rounded)),
                    title: const Text('Assignment Jadwal', style: TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text(_assignmentText(bundle.assignment)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: pickStart, icon: const Icon(Icons.date_range_rounded), label: Text(startDate == null ? 'Mulai' : _date(startDate!)))),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton.icon(onPressed: pickEnd, icon: const Icon(Icons.event_rounded), label: Text(endDate == null ? 'Selesai' : _date(endDate!)))),
                ]),
                const SizedBox(height: 18),
                Text('Riwayat Absensi', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                if (bundle.attendance.isEmpty)
                  const MessageCard(title: 'Belum ada absensi', message: 'Riwayat absensi karyawan akan tampil di sini.', icon: Icons.inbox_outlined)
                else
                  ...bundle.attendance.take(40).map((row) => Card(
                        child: ListTile(
                          leading: CircleAvatar(child: Icon(row.icon)),
                          title: Text('${row.date} • ${row.actionLabel}', style: const TextStyle(fontWeight: FontWeight.w900)),
                          subtitle: Text('${row.time} • ${row.statusLabel} • ${row.distance.toStringAsFixed(0)} m'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => showAttendanceDetail(row),
                        ),
                      )),
                const SizedBox(height: 18),
                Text('Pengajuan Terbaru', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                if (bundle.requests.isEmpty)
                  const MessageCard(title: 'Belum ada pengajuan', message: 'Pengajuan karyawan akan tampil di sini.', icon: Icons.fact_check_outlined)
                else
                  ...bundle.requests.take(20).map((req) => Card(
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.request_page_rounded)),
                          title: Text(req.type, style: const TextStyle(fontWeight: FontWeight.w900)),
                          subtitle: Text('${req.date.ifEmpty('-')} • ${req.statusLabel}\n${req.reason.ifEmpty('-')}'),
                          isThreeLine: true,
                        ),
                      )),
              ],
            ],
          );
        },
      ),
    );
  }
}

class EmployeeDetailBundle {
  final EmployeeProfileRecord employee;
  final List<EmployeeAttendanceRecord> attendance;
  final Map<String, dynamic> assignment;
  final List<EmployeeRequestRecord> requests;

  const EmployeeDetailBundle({required this.employee, required this.attendance, required this.assignment, required this.requests});
  const EmployeeDetailBundle.empty() : employee = const EmployeeProfileRecord(id: '', data: {}), attendance = const [], assignment = const {}, requests = const [];
}

class EmployeeProfileRecord {
  final String id;
  final Map<String, dynamic> data;

  const EmployeeProfileRecord({required this.id, required this.data});

  String get name => _read(data, const ['display_name', 'nama_lengkap', 'name']).ifEmpty(id.ifEmpty('Karyawan'));
  String get email => _read(data, const ['email']);
  String get nip => _read(data, const ['nip']);
  String get role => _read(data, const ['role', 'level']).ifEmpty('employee');
  String get officeName => _read(data, const ['office_name', 'kantor', 'nama_kantor']);
  String get departmentName => _read(data, const ['department_name', 'department']);
  bool get active => data['active'] != false && data['status']?.toString().toLowerCase() != 'inactive' && data['status_akun']?.toString().toLowerCase() != 'inactive';
  String get statusLabel => active ? 'Aktif' : 'Nonaktif';
}

class EmployeeAttendanceRecord {
  final String uid;
  final String date;
  final String actionKey;
  final Map<String, dynamic> data;

  const EmployeeAttendanceRecord({required this.uid, required this.date, required this.actionKey, required this.data});

  String get time => _read(data, const ['waktu', 'time', 'created_time', 'jam']).ifEmpty(createdAtText);
  String get sortKey => '$date ${data['created_at'] ?? data['timestamp'] ?? time}$actionKey';
  double get latitude => _toDouble(data['latitude'] ?? data['lat']);
  double get longitude => _toDouble(data['longitude'] ?? data['lng'] ?? data['long']);
  double get distance => _toDouble(data['distance_meter'] ?? data['distance'] ?? data['jarak_meter']);

  String get createdAtText {
    final raw = data['created_at'] ?? data['timestamp'];
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw).toLocal().toString();
    if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt()).toLocal().toString();
    return raw?.toString() ?? '-';
  }

  String get actionType {
    final text = actionKey.toLowerCase();
    if (text.contains('masuk') || text.contains('check_in') || text == 'in') return 'in';
    if (text.contains('pulang') || text.contains('check_out') || text == 'out') return 'out';
    return 'other';
  }

  String get actionLabel {
    if (actionType == 'in') return 'Masuk';
    if (actionType == 'out') return 'Pulang';
    return actionKey.replaceAll('_', ' ');
  }

  String get statusType {
    final text = _read(data, const ['attendance_status', 'status_absen', 'validation_status', 'status']).toLowerCase();
    if (text.contains('late') || text.contains('telat') || text.contains('terlambat')) return 'late';
    if (text.contains('outside') || text.contains('luar')) return 'outside';
    if (text.contains('pending') || text.contains('menunggu')) return 'pending';
    if (text.contains('reject') || text.contains('tolak')) return 'rejected';
    return 'normal';
  }

  String get statusLabel {
    if (statusType == 'late') return 'Terlambat';
    if (statusType == 'outside') return 'Luar Radius';
    if (statusType == 'pending') return 'Pending';
    if (statusType == 'rejected') return 'Ditolak';
    return 'Normal';
  }

  IconData get icon {
    if (statusType == 'late') return Icons.timer_off_rounded;
    if (statusType == 'outside') return Icons.wrong_location_rounded;
    if (actionType == 'out') return Icons.logout_rounded;
    return Icons.login_rounded;
  }
}

class EmployeeRequestRecord {
  final String id;
  final String type;
  final Map<String, dynamic> data;

  const EmployeeRequestRecord({required this.id, required this.type, required this.data});

  String get date => _read(data, const ['date', 'tanggal', 'start_date', 'attendance_date']);
  String get reason => _read(data, const ['reason', 'alasan', 'description', 'note']);
  String get sortKey => '${data['created_at'] ?? data['submitted_at'] ?? date}$id';
  String get statusLabel {
    final text = _read(data, const ['status', 'approval_status']).toLowerCase();
    if (text.contains('approve') || text.contains('valid')) return 'Approved';
    if (text.contains('reject') || text.contains('tolak')) return 'Rejected';
    return 'Pending';
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;

  const _MiniStat(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [CircleAvatar(child: Icon(icon)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$value', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)), Text(label)]))]),
        ),
      ),
    );
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

String _assignmentText(Map<String, dynamic> data) {
  if (data.isEmpty) return 'Belum ada assignment jadwal.';
  final timetable = _read(data, const ['timetable_name', 'timetable_id']);
  final shift = _read(data, const ['shift_name', 'shift_id']);
  return 'Jam kerja: ${timetable.ifEmpty('-')} • Shift: ${shift.ifEmpty('-')}';
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

double _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _date(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
