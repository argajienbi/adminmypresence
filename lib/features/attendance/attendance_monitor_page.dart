import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../shared/message_card.dart';

class AttendanceMonitorPage extends StatefulWidget {
  final AdminSession session;

  const AttendanceMonitorPage({super.key, required this.session});

  @override
  State<AttendanceMonitorPage> createState() => _AttendanceMonitorPageState();
}

class _AttendanceMonitorPageState extends State<AttendanceMonitorPage> {
  late Future<List<AttendanceRecord>> future;
  final search = TextEditingController();
  DateTime date = DateTime.now();
  String statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    future = load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void refresh() => setState(() => future = load());

  Future<List<AttendanceRecord>> load() async {
    final companyId = widget.session.companyId;
    final db = FirebaseDatabase.instance;
    final results = await Future.wait([
      db.ref('attendance/$companyId').get(),
      db.ref('company_users/$companyId').get(),
      db.ref('offices/$companyId').get(),
    ]);

    final attendance = _asMap(results[0].value) ?? const <String, dynamic>{};
    final users = _asMap(results[1].value) ?? const <String, dynamic>{};
    final offices = _asMap(results[2].value) ?? const <String, dynamic>{};
    final dateKey = _dateKey(date);
    final rows = <AttendanceRecord>[];

    for (final userEntry in attendance.entries) {
      final uid = userEntry.key;
      final user = _asMap(users[uid]) ?? const <String, dynamic>{};
      final days = _asMap(userEntry.value);
      if (days == null) continue;
      final actions = _asMap(days[dateKey]);
      if (actions == null) continue;

      for (final actionEntry in actions.entries) {
        final data = _asMap(actionEntry.value) ?? const <String, dynamic>{};
        final officeId = _read(data, const ['office_id', 'officeId', 'kantor_id']);
        final officeData = _asMap(offices[officeId]) ?? const <String, dynamic>{};
        final distance = _toDouble(data['distance_meter'] ?? data['distance'] ?? data['jarak_meter']);
        final radius = _toDouble(data['radius_meter'] ?? data['radius'] ?? data['geofence_radius'] ?? officeData['radius_meter'] ?? officeData['radius'] ?? officeData['geofence_radius']);
        final status = _statusLabel(_read(data, const ['attendance_status', 'status_absen', 'validation_status', 'status']));
        final geofence = radius > 0 ? (distance <= radius ? 'Di dalam radius' : 'Di luar radius') : 'Tidak diketahui';

        rows.add(
          AttendanceRecord(
            uid: uid,
            name: _read(user, const ['nama_lengkap', 'display_name', 'name']).ifEmpty(uid),
            email: _read(user, const ['email']),
            nip: _read(user, const ['nip']),
            date: dateKey,
            action: _actionLabel(actionEntry.key),
            time: _read(data, const ['time', 'waktu', 'created_time', 'jam']).ifEmpty('-'),
            status: status,
            geofence: geofence,
            officeName: _read(officeData, const ['name', 'office_name', 'nama']).ifEmpty(_read(data, const ['office_name', 'kantor'])),
            distance: distance,
            radius: radius,
          ),
        );
      }
    }

    rows.sort((a, b) => '${a.name}${a.time}'.compareTo('${b.name}${b.time}'));
    return rows;
  }

  List<AttendanceRecord> filterRows(List<AttendanceRecord> rows) {
    final q = search.text.trim().toLowerCase();
    return rows.where((row) {
      if (q.isNotEmpty) {
        final text = '${row.name} ${row.email} ${row.nip} ${row.action} ${row.status} ${row.officeName}'.toLowerCase();
        if (!text.contains(q)) return false;
      }
      if (statusFilter == 'outside' && row.geofence != 'Di luar radius') return false;
      if (statusFilter == 'late' && row.status != 'Terlambat') return false;
      if (statusFilter == 'valid' && row.status != 'approved' && row.status != 'Tepat Waktu') return false;
      return true;
    }).toList();
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2035), initialDate: date);
    if (picked != null) {
      setState(() {
        date = picked;
        future = load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AttendanceRecord>>(
      future: future,
      builder: (context, snapshot) {
        final allRows = snapshot.data ?? const <AttendanceRecord>[];
        final rows = filterRows(allRows);
        final outside = allRows.where((row) => row.geofence == 'Di luar radius').length;
        final late = allRows.where((row) => row.status == 'Terlambat').length;

        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                Expanded(child: Text('Absensi', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900))),
                IconButton.filledTonal(onPressed: refresh, icon: const Icon(Icons.refresh_rounded)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _StatCard(label: 'Record', value: allRows.length.toString(), icon: Icons.access_time_filled_rounded),
                _StatCard(label: 'Luar Radius', value: outside.toString(), icon: Icons.wrong_location_rounded),
                _StatCard(label: 'Terlambat', value: late.toString(), icon: Icons.timer_off_rounded),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: OutlinedButton.icon(onPressed: pickDate, icon: const Icon(Icons.date_range_rounded), label: Text(_dateKey(date)))),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: statusFilter,
                    decoration: const InputDecoration(labelText: 'Filter'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Semua')),
                      DropdownMenuItem(value: 'outside', child: Text('Luar radius')),
                      DropdownMenuItem(value: 'late', child: Text('Terlambat')),
                      DropdownMenuItem(value: 'valid', child: Text('Valid')),
                    ],
                    onChanged: (value) => setState(() => statusFilter = value ?? 'all'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(controller: search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Cari nama, NIP, email, kantor', prefixIcon: Icon(Icons.search_rounded))),
            const SizedBox(height: 12),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (snapshot.hasError)
              MessageCard(title: 'Gagal memuat absensi', message: snapshot.error.toString(), icon: Icons.error_outline_rounded)
            else if (rows.isEmpty)
              const MessageCard(title: 'Tidak ada absensi', message: 'Tidak ada data sesuai tanggal dan filter.', icon: Icons.inbox_outlined)
            else
              ...rows.map((row) => Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Icon(row.geofence == 'Di luar radius' ? Icons.wrong_location_rounded : Icons.check_circle_rounded)),
                      title: Text(row.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: Text('${row.date} ${row.time} | ${row.action}\n${row.nip.ifEmpty(row.email)} | ${row.status} | ${row.geofence}\n${row.officeName.ifEmpty('-')} • ${row.distance.toStringAsFixed(0)} / ${row.radius.toStringAsFixed(0)} m'),
                      isThreeLine: true,
                    ),
                  )),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 155,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(child: Icon(icon)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)), Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)])),
            ],
          ),
        ),
      ),
    );
  }
}

class AttendanceRecord {
  final String uid;
  final String name;
  final String email;
  final String nip;
  final String date;
  final String action;
  final String time;
  final String status;
  final String geofence;
  final String officeName;
  final double distance;
  final double radius;

  const AttendanceRecord({required this.uid, required this.name, required this.email, required this.nip, required this.date, required this.action, required this.time, required this.status, required this.geofence, required this.officeName, required this.distance, required this.radius});
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

String _statusLabel(String value) {
  final text = value.toLowerCase();
  if (text.contains('late') || text.contains('terlambat') || text.contains('telat')) return 'Terlambat';
  if (text.contains('outside') || text.contains('luar')) return 'Luar Radius';
  if (text.contains('pending') || text.contains('menunggu')) return 'Menunggu';
  if (text.contains('reject') || text.contains('ditolak')) return 'rejected';
  if (text.contains('approved') || text.contains('valid') || text.contains('success')) return 'approved';
  if (text.contains('on_time') || text.contains('tepat')) return 'Tepat Waktu';
  return value.isEmpty ? 'Menunggu' : value.replaceAll('_', ' ');
}

String _actionLabel(String value) {
  final text = value.toLowerCase();
  if (text.contains('masuk') || text.contains('check_in') || text == 'in') return 'Masuk';
  if (text.contains('pulang') || text.contains('check_out') || text == 'out') return 'Pulang';
  if (text.contains('izin')) return 'Izin';
  if (text.contains('sakit')) return 'Sakit';
  if (text.contains('cuti')) return 'Cuti';
  if (text.contains('lembur')) return 'Lembur';
  return value.isEmpty ? 'Presensi' : value.replaceAll('_', ' ');
}

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
