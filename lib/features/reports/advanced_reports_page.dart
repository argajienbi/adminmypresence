import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../shared/message_card.dart';

class AdvancedReportsPage extends StatefulWidget {
  final AdminSession session;
  const AdvancedReportsPage({super.key, required this.session});

  @override
  State<AdvancedReportsPage> createState() => _AdvancedReportsPageState();
}

class _AdvancedReportsPageState extends State<AdvancedReportsPage> {
  late Future<List<_ReportRow>> future;
  final search = TextEditingController();
  DateTime? startDate;
  DateTime? endDate;

  @override
  void initState() {
    super.initState();
    future = loadRows();
  }

  void refresh() {
    setState(() => future = loadRows());
  }

  Future<List<_ReportRow>> loadRows() async {
    final db = FirebaseDatabase.instance;
    final companyId = widget.session.companyId;
    final results = await Future.wait([
      db.ref('attendance/$companyId').get(),
      db.ref('company_users/$companyId').get(),
    ]);

    final attendance = _asMap(results[0].value) ?? const <String, dynamic>{};
    final users = _asMap(results[1].value) ?? const <String, dynamic>{};
    final rows = <_ReportRow>[];

    for (final userEntry in attendance.entries) {
      final uid = userEntry.key;
      final user = _asMap(users[uid]) ?? const <String, dynamic>{};
      final userName = _read(user, const ['nama_lengkap', 'display_name', 'name']).ifEmpty(uid);
      final nip = _read(user, const ['nip']);
      final days = _asMap(userEntry.value);
      if (days == null) continue;

      for (final dayEntry in days.entries) {
        final date = dayEntry.key;
        final actions = _asMap(dayEntry.value);
        if (actions == null) continue;

        for (final actionEntry in actions.entries) {
          final data = _asMap(actionEntry.value) ?? const <String, dynamic>{};
          final action = actionEntry.key;
          final time = _read(data, const ['waktu', 'time', 'created_time']);
          final status = _statusLabel(_read(data, const ['attendance_status', 'status_absen', 'validation_status', 'status']));
          final distance = double.tryParse(_read(data, const ['distance_meter'])) ?? 0;
          final radius = double.tryParse(_read(data, const ['radius_meter'])) ?? 0;
          final geofence = radius > 0 ? (distance <= radius ? 'Di dalam radius' : 'Di luar radius') : 'Tidak diketahui';
          rows.add(_ReportRow(uid: uid, name: userName, nip: nip, date: date, time: time, action: _actionLabel(action), status: status, geofence: geofence));
        }
      }
    }

    rows.sort((a, b) => '${b.date} ${b.time}'.compareTo('${a.date} ${a.time}'));
    return rows;
  }

  List<_ReportRow> filterRows(List<_ReportRow> rows) {
    final term = search.text.trim().toLowerCase();
    return rows.where((row) {
      if (term.isNotEmpty) {
        final haystack = '${row.name} ${row.nip} ${row.date} ${row.action} ${row.status}'.toLowerCase();
        if (!haystack.contains(term)) return false;
      }
      final parsed = DateTime.tryParse(row.date);
      if (parsed != null && startDate != null && parsed.isBefore(DateTime(startDate!.year, startDate!.month, startDate!.day))) return false;
      if (parsed != null && endDate != null && parsed.isAfter(DateTime(endDate!.year, endDate!.month, endDate!.day, 23, 59, 59))) return false;
      return true;
    }).toList();
  }

  Future<void> pickStart() async {
    final picked = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2035), initialDate: startDate ?? DateTime.now());
    if (picked != null) setState(() => startDate = picked);
  }

  Future<void> pickEnd() async {
    final picked = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2035), initialDate: endDate ?? DateTime.now());
    if (picked != null) setState(() => endDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Advanced Reports'), actions: [IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
      body: FutureBuilder<List<_ReportRow>>(
        future: future,
        builder: (context, snapshot) {
          final rows = filterRows(snapshot.data ?? const <_ReportRow>[]);
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const MessageCard(title: 'Reports', message: 'Port laporan absensi dari admin web dengan filter pencarian dan tanggal.', icon: Icons.table_chart_rounded),
              const SizedBox(height: 12),
              TextField(controller: search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Cari nama, NIP, tanggal, status', prefixIcon: Icon(Icons.search_rounded))),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: pickStart, icon: const Icon(Icons.date_range_rounded), label: Text(startDate == null ? 'Mulai' : _date(startDate!)))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(onPressed: pickEnd, icon: const Icon(Icons.event_rounded), label: Text(endDate == null ? 'Selesai' : _date(endDate!)))),
              ]),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                MessageCard(title: 'Gagal memuat laporan', message: snapshot.error.toString(), icon: Icons.error_outline_rounded)
              else if (rows.isEmpty)
                const MessageCard(title: 'Tidak ada data', message: 'Tidak ada data sesuai filter.', icon: Icons.inbox_outlined)
              else
                ...rows.map((row) => Card(child: ListTile(title: Text(row.name, style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Text('${row.date} ${row.time} | ${row.action}\n${row.nip} | ${row.status} | ${row.geofence}'), isThreeLine: true))),
            ],
          );
        },
      ),
    );
  }
}

class _ReportRow {
  const _ReportRow({required this.uid, required this.name, required this.nip, required this.date, required this.time, required this.action, required this.status, required this.geofence});
  final String uid;
  final String name;
  final String nip;
  final String date;
  final String time;
  final String action;
  final String status;
  final String geofence;
}

Map<String, dynamic>? _asMap(Object? value) => value is Map ? value.map((key, item) => MapEntry(key.toString(), item)) : null;

String _read(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value != null && value.toString().trim().isNotEmpty) return value.toString();
  }
  return '';
}

String _statusLabel(String value) {
  final text = value.toLowerCase();
  if (text.contains('late') || text.contains('terlambat') || text.contains('telat')) return 'Terlambat';
  if (text.contains('outside') || text.contains('luar')) return 'Luar Radius';
  if (text.contains('pending')) return 'Menunggu';
  if (text.contains('reject') || text.contains('ditolak')) return 'Ditolak';
  if (text.contains('approved') || text.contains('valid') || text.contains('success')) return 'Disetujui';
  if (text.contains('on_time') || text.contains('tepat')) return 'Tepat Waktu';
  return value.isEmpty ? 'Belum diketahui' : value.replaceAll('_', ' ');
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

String _date(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
