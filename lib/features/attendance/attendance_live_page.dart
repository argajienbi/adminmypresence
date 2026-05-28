import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../shared/message_card.dart';

class AttendanceLivePage extends StatefulWidget {
  final AdminSession session;

  const AttendanceLivePage({super.key, required this.session});

  @override
  State<AttendanceLivePage> createState() => _AttendanceLivePageState();
}

class _AttendanceLivePageState extends State<AttendanceLivePage> {
  String date = _date(DateTime.now());
  String statusFilter = 'all';
  String actionFilter = 'all';
  String query = '';

  DatabaseReference get attendanceRef => FirebaseDatabase.instance.ref('attendance/${widget.session.companyId}');

  Future<_LiveBundle> loadBundle() async {
    final results = await Future.wait([
      attendanceRef.get(),
      FirebaseDatabase.instance.ref('company_users/${widget.session.companyId}').get(),
      FirebaseDatabase.instance.ref('offices/${widget.session.companyId}').get(),
    ]);

    final attendance = _asMap(results[0].value) ?? const <String, dynamic>{};
    final users = _asMap(results[1].value) ?? const <String, dynamic>{};
    final offices = _asMap(results[2].value) ?? const <String, dynamic>{};
    final rows = <AttendanceLiveRecord>[];

    for (final userEntry in attendance.entries) {
      final uid = userEntry.key;
      final days = _asMap(userEntry.value);
      if (days == null) continue;
      final actions = _asMap(days[date]);
      if (actions == null) continue;
      final user = _asMap(users[uid]) ?? const <String, dynamic>{};

      for (final actionEntry in actions.entries) {
        final data = _asMap(actionEntry.value) ?? const <String, dynamic>{};
        final officeId = _read(data, const ['office_id', 'officeId', 'kantor_id']);
        final office = _asMap(offices[officeId]) ?? const <String, dynamic>{};
        rows.add(AttendanceLiveRecord(
          id: '${uid}_${actionEntry.key}',
          uid: uid,
          actionKey: actionEntry.key,
          data: data,
          user: user,
          office: office,
        ));
      }
    }

    rows.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    return _LiveBundle(rows: rows, employeeCount: users.length);
  }

  List<AttendanceLiveRecord> filtered(List<AttendanceLiveRecord> rows) {
    final q = query.trim().toLowerCase();
    return rows.where((row) {
      if (actionFilter != 'all' && row.actionType != actionFilter) return false;
      if (statusFilter != 'all' && row.statusType != statusFilter) return false;
      if (q.isEmpty) return true;
      final text = '${row.name} ${row.email} ${row.nip} ${row.actionLabel} ${row.statusLabel} ${row.officeName} ${row.rawText}'.toLowerCase();
      return text.contains(q);
    }).toList();
  }

  Future<void> pickDate() async {
    final current = DateTime.tryParse(date) ?? DateTime.now();
    final picked = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2035), initialDate: current);
    if (picked != null) setState(() => date = _date(picked));
  }

  void showDetail(AttendanceLiveRecord row) {
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
                Text('Detail Absensi', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                _DetailRow('Nama', row.name),
                _DetailRow('Email', row.email),
                _DetailRow('NIP', row.nip),
                _DetailRow('Tanggal', date),
                _DetailRow('Aksi', row.actionLabel),
                _DetailRow('Jam', row.time),
                _DetailRow('Status', row.statusLabel),
                _DetailRow('Kantor', row.officeName),
                _DetailRow('Latitude', row.latitude.toString()),
                _DetailRow('Longitude', row.longitude.toString()),
                _DetailRow('Distance Meter', row.distance.toStringAsFixed(0)),
                _DetailRow('Radius Meter', row.radius.toStringAsFixed(0)),
                const SizedBox(height: 12),
                Text('Raw Data', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                ...row.data.entries.map((entry) => _DetailRow(entry.key, entry.value.toString())),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Absensi'), actions: [IconButton(onPressed: () => setState(() {}), icon: const Icon(Icons.refresh_rounded))]),
      body: StreamBuilder<DatabaseEvent>(
        stream: attendanceRef.onValue,
        builder: (context, streamSnapshot) {
          return FutureBuilder<_LiveBundle>(
            future: loadBundle(),
            builder: (context, snapshot) {
              final bundle = snapshot.data ?? const _LiveBundle.empty();
              final rows = filtered(bundle.rows);
              final checkIn = bundle.rows.where((row) => row.actionType == 'in').length;
              final checkOut = bundle.rows.where((row) => row.actionType == 'out').length;
              final late = bundle.rows.where((row) => row.statusType == 'late').length;
              final outside = bundle.rows.where((row) => row.statusType == 'outside').length;

              return ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  MessageCard(
                    title: 'Live Monitor Absensi',
                    message: 'Tanggal $date • Masuk: $checkIn • Pulang: $checkOut • Terlambat: $late • Luar Radius: $outside',
                    icon: Icons.monitor_heart_rounded,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(onPressed: pickDate, icon: const Icon(Icons.date_range_rounded), label: Text(date)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: actionFilter,
                        decoration: const InputDecoration(labelText: 'Aksi'),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('Semua')),
                          DropdownMenuItem(value: 'in', child: Text('Masuk')),
                          DropdownMenuItem(value: 'out', child: Text('Pulang')),
                          DropdownMenuItem(value: 'other', child: Text('Lainnya')),
                        ],
                        onChanged: (value) => setState(() => actionFilter = value ?? 'all'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: statusFilter,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('Semua')),
                          DropdownMenuItem(value: 'normal', child: Text('Normal')),
                          DropdownMenuItem(value: 'late', child: Text('Terlambat')),
                          DropdownMenuItem(value: 'outside', child: Text('Luar Radius')),
                          DropdownMenuItem(value: 'pending', child: Text('Pending')),
                          DropdownMenuItem(value: 'rejected', child: Text('Ditolak')),
                        ],
                        onChanged: (value) => setState(() => statusFilter = value ?? 'all'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  TextField(onChanged: (value) => setState(() => query = value), decoration: const InputDecoration(labelText: 'Cari nama, NIP, kantor, status', prefixIcon: Icon(Icons.search_rounded))),
                  const SizedBox(height: 12),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                  else if (snapshot.hasError)
                    MessageCard(title: 'Gagal memuat absensi', message: snapshot.error.toString(), icon: Icons.error_outline_rounded)
                  else if (rows.isEmpty)
                    const MessageCard(title: 'Belum ada absensi', message: 'Data absensi sesuai filter akan tampil di sini.', icon: Icons.inbox_outlined)
                  else
                    ...rows.map((row) => Card(
                          child: ListTile(
                            leading: CircleAvatar(child: Icon(row.icon)),
                            title: Text(row.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                            subtitle: Text('${row.time} • ${row.actionLabel} • ${row.statusLabel}\n${row.officeName.ifEmpty('-')} • ${row.distance.toStringAsFixed(0)} / ${row.radius.toStringAsFixed(0)} m'),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => showDetail(row),
                          ),
                        )),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _LiveBundle {
  final List<AttendanceLiveRecord> rows;
  final int employeeCount;

  const _LiveBundle({required this.rows, required this.employeeCount});
  const _LiveBundle.empty() : rows = const [], employeeCount = 0;
}

class AttendanceLiveRecord {
  final String id;
  final String uid;
  final String actionKey;
  final Map<String, dynamic> data;
  final Map<String, dynamic> user;
  final Map<String, dynamic> office;

  const AttendanceLiveRecord({required this.id, required this.uid, required this.actionKey, required this.data, required this.user, required this.office});

  String get name => _read(data, const ['employee_name', 'user_name', 'nama_lengkap', 'name']).ifEmpty(_read(user, const ['nama_lengkap', 'display_name', 'name']).ifEmpty(uid));
  String get email => _read(data, const ['email']).ifEmpty(_read(user, const ['email']));
  String get nip => _read(data, const ['nip']).ifEmpty(_read(user, const ['nip']));
  String get time => _read(data, const ['waktu', 'time', 'created_time', 'jam']).ifEmpty(createdAtText);
  String get officeName => _read(data, const ['office_name', 'kantor', 'nama_kantor']).ifEmpty(_read(office, const ['name', 'office_name']));
  String get rawText => data.values.join(' ');
  String get sortKey => '${data['created_at'] ?? data['timestamp'] ?? time}$id';
  double get latitude => _toDouble(data['latitude'] ?? data['lat']);
  double get longitude => _toDouble(data['longitude'] ?? data['lng'] ?? data['long']);
  double get distance => _toDouble(data['distance_meter'] ?? data['distance'] ?? data['jarak_meter']);
  double get radius => _toDouble(data['radius_meter'] ?? data['radius'] ?? data['geofence_radius'] ?? office['radius_meter'] ?? office['radius']);

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

double _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _date(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
