import 'dart:io';

import 'package:excel/excel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
  bool exporting = false;

  @override
  void initState() {
    super.initState();
    future = loadRows();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
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
      db.ref('offices/$companyId').get(),
    ]);

    final attendance = _asMap(results[0].value) ?? const <String, dynamic>{};
    final users = _asMap(results[1].value) ?? const <String, dynamic>{};
    final offices = _asMap(results[2].value) ?? const <String, dynamic>{};
    final rows = <_ReportRow>[];

    for (final userEntry in attendance.entries) {
      final uid = userEntry.key;
      final user = _asMap(users[uid]) ?? const <String, dynamic>{};
      final userName = _read(user, const ['nama_lengkap', 'display_name', 'name']).ifEmpty(uid);
      final nip = _read(user, const ['nip']);
      final email = _read(user, const ['email']);
      final days = _asMap(userEntry.value);
      if (days == null) continue;

      for (final dayEntry in days.entries) {
        final date = dayEntry.key;
        final actions = _asMap(dayEntry.value);
        if (actions == null) continue;

        for (final actionEntry in actions.entries) {
          final data = _asMap(actionEntry.value) ?? const <String, dynamic>{};
          final action = actionEntry.key;
          final officeId = _read(data, const ['office_id', 'officeId', 'kantor_id']);
          final officeData = _asMap(offices[officeId]) ?? const <String, dynamic>{};
          final officeName = _read(officeData, const ['name', 'office_name', 'nama']).ifEmpty(_read(data, const ['office_name', 'kantor']));
          final time = _read(data, const ['waktu', 'time', 'created_time', 'jam']);
          final status = _statusLabel(_read(data, const ['attendance_status', 'status_absen', 'validation_status', 'status']));
          final distance = _toDouble(data['distance_meter'] ?? data['distance'] ?? data['jarak_meter']);
          final radius = _toDouble(data['radius_meter'] ?? data['radius'] ?? data['geofence_radius'] ?? officeData['radius_meter'] ?? officeData['radius']);
          final geofence = radius > 0 ? (distance <= radius ? 'Di dalam radius' : 'Di luar radius') : 'Tidak diketahui';
          rows.add(_ReportRow(
            uid: uid,
            name: userName,
            email: email,
            nip: nip,
            date: date,
            time: time,
            action: _actionLabel(action),
            status: status,
            geofence: geofence,
            officeName: officeName,
            distance: distance,
            radius: radius,
          ));
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
        final haystack = '${row.name} ${row.email} ${row.nip} ${row.date} ${row.action} ${row.status} ${row.officeName}'.toLowerCase();
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

  Future<void> exportExcel(List<_ReportRow> rows) async {
    if (exporting || rows.isEmpty) return;
    setState(() => exporting = true);

    try {
      final excel = Excel.createExcel();
      final sheet = excel['Laporan Absensi'];
      excel.setDefaultSheet('Laporan Absensi');
      if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

      final headers = ['Tanggal', 'Jam', 'Nama', 'Email', 'NIP', 'Aksi', 'Status', 'Geofence', 'Kantor', 'Jarak Meter', 'Radius Meter', 'UID'];
      for (var col = 0; col < headers.length; col++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
        cell.value = TextCellValue(headers[col]);
        cell.cellStyle = CellStyle(bold: true);
      }

      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final values = [
          row.date,
          row.time,
          row.name,
          row.email,
          row.nip,
          row.action,
          row.status,
          row.geofence,
          row.officeName,
          row.distance.toStringAsFixed(0),
          row.radius.toStringAsFixed(0),
          row.uid,
        ];
        for (var col = 0; col < values.length; col++) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: i + 1)).value = TextCellValue(values[col]);
        }
      }

      for (var col = 0; col < headers.length; col++) {
        sheet.setColumnWidth(col, col == 2 ? 24 : 18);
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Gagal membuat file Excel.');

      final directory = await getTemporaryDirectory();
      final fileName = 'laporan_absensi_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles([XFile(file.path)], text: 'Laporan absensi MyPresence');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => exporting = false);
    }
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
              MessageCard(title: 'Reports', message: 'Laporan absensi dengan filter tanggal, kantor, geofence, dan export Excel. Total: ${rows.length}', icon: Icons.table_chart_rounded),
              const SizedBox(height: 12),
              TextField(controller: search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Cari nama, NIP, email, kantor, status', prefixIcon: Icon(Icons.search_rounded))),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: pickStart, icon: const Icon(Icons.date_range_rounded), label: Text(startDate == null ? 'Mulai' : _date(startDate!)))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(onPressed: pickEnd, icon: const Icon(Icons.event_rounded), label: Text(endDate == null ? 'Selesai' : _date(endDate!)))),
              ]),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: rows.isEmpty || exporting ? null : () => exportExcel(rows),
                icon: const Icon(Icons.file_download_rounded),
                label: Text(exporting ? 'Membuat Excel...' : 'Export Excel'),
              ),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                MessageCard(title: 'Gagal memuat laporan', message: snapshot.error.toString(), icon: Icons.error_outline_rounded)
              else if (rows.isEmpty)
                const MessageCard(title: 'Tidak ada data', message: 'Tidak ada data sesuai filter.', icon: Icons.inbox_outlined)
              else
                ...rows.map((row) => Card(child: ListTile(title: Text(row.name, style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Text('${row.date} ${row.time} | ${row.action}\n${row.nip.ifEmpty(row.email)} | ${row.status} | ${row.geofence}\n${row.officeName.ifEmpty('-')} • ${row.distance.toStringAsFixed(0)} / ${row.radius.toStringAsFixed(0)} m'), isThreeLine: true))),
            ],
          );
        },
      ),
    );
  }
}

class _ReportRow {
  const _ReportRow({required this.uid, required this.name, required this.email, required this.nip, required this.date, required this.time, required this.action, required this.status, required this.geofence, required this.officeName, required this.distance, required this.radius});
  final String uid;
  final String name;
  final String email;
  final String nip;
  final String date;
  final String time;
  final String action;
  final String status;
  final String geofence;
  final String officeName;
  final double distance;
  final double radius;
}

Map<String, dynamic>? _asMap(Object? value) => value is Map ? value.map((key, item) => MapEntry(key.toString(), item)) : null;

double _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

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
