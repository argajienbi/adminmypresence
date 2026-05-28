import 'dart:io';

import 'package:excel/excel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models.dart';
import '../shared/message_card.dart';

class WorkRecapPage extends StatefulWidget {
  final AdminSession session;

  const WorkRecapPage({super.key, required this.session});

  @override
  State<WorkRecapPage> createState() => _WorkRecapPageState();
}

class _WorkRecapPageState extends State<WorkRecapPage> {
  late Future<List<WorkRecapRecord>> future;
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

  void refresh() => setState(() => future = loadRows());

  Future<List<WorkRecapRecord>> loadRows() async {
    final companyId = widget.session.companyId;
    final db = FirebaseDatabase.instance;
    final results = await Future.wait([
      db.ref('company_users/$companyId').get(),
      db.ref('attendance/$companyId').get(),
      db.ref('overtime_requests/$companyId').get(),
      db.ref('leave_requests/$companyId').get(),
      db.ref('payroll_settings/$companyId').get(),
    ]);

    final users = _asMap(results[0].value) ?? const <String, dynamic>{};
    final attendance = _asMap(results[1].value) ?? const <String, dynamic>{};
    final overtime = _asMap(results[2].value) ?? const <String, dynamic>{};
    final leave = _asMap(results[3].value) ?? const <String, dynamic>{};
    final settings = _asMap(results[4].value) ?? const <String, dynamic>{};
    final rows = <String, WorkRecapRecord>{};

    for (final entry in users.entries) {
      final user = _asMap(entry.value) ?? const <String, dynamic>{};
      rows[entry.key] = WorkRecapRecord(
        uid: entry.key,
        name: _read(user, const ['display_name', 'nama_lengkap', 'name']).ifEmpty(entry.key),
        email: _read(user, const ['email']),
        nip: _read(user, const ['nip']),
        officeName: _read(user, const ['office_name', 'kantor', 'nama_kantor']),
        departmentName: _read(user, const ['department_name', 'department']),
      );
    }

    for (final userEntry in attendance.entries) {
      final uid = userEntry.key;
      final row = rows.putIfAbsent(uid, () => WorkRecapRecord(uid: uid, name: uid, email: '', nip: '', officeName: '', departmentName: ''));
      final days = _asMap(userEntry.value);
      if (days == null) continue;
      for (final dayEntry in days.entries) {
        final date = dayEntry.key;
        if (!_dateAllowed(date)) continue;
        final actions = _asMap(dayEntry.value);
        if (actions == null) continue;
        var countedDay = false;
        for (final actionEntry in actions.entries) {
          final action = actionEntry.key.toLowerCase();
          final data = _asMap(actionEntry.value) ?? const <String, dynamic>{};
          final status = _read(data, const ['attendance_status', 'status_absen', 'validation_status', 'status']).toLowerCase();
          if (!countedDay) {
            row.workDays++;
            countedDay = true;
          }
          if (action.contains('masuk') || action.contains('check_in') || action == 'in') row.checkIn++;
          if (action.contains('pulang') || action.contains('check_out') || action == 'out') row.checkOut++;
          if (status.contains('late') || status.contains('telat') || status.contains('terlambat')) row.lateCount++;
          if (status.contains('outside') || status.contains('luar')) row.outsideRadiusCount++;
          if (status.contains('reject') || status.contains('tolak')) row.rejectedCount++;
        }
      }
    }

    for (final entry in overtime.entries) {
      final data = _asMap(entry.value) ?? const <String, dynamic>{};
      final uid = _read(data, const ['uid', 'user_id', 'employee_id']);
      final date = _read(data, const ['date', 'tanggal', 'start_date']);
      if (uid.isEmpty || !_dateAllowed(date)) continue;
      final row = rows.putIfAbsent(uid, () => WorkRecapRecord(uid: uid, name: uid, email: '', nip: '', officeName: '', departmentName: ''));
      row.overtimeRequests++;
      if (_status(data) == 'approved') row.approvedOvertime++;
      row.overtimeHours += _toDouble(data['hours'] ?? data['duration_hours'] ?? data['total_hours']);
    }

    for (final entry in leave.entries) {
      final data = _asMap(entry.value) ?? const <String, dynamic>{};
      final uid = _read(data, const ['uid', 'user_id', 'employee_id']);
      final date = _read(data, const ['date', 'tanggal', 'start_date']);
      if (uid.isEmpty || !_dateAllowed(date)) continue;
      final row = rows.putIfAbsent(uid, () => WorkRecapRecord(uid: uid, name: uid, email: '', nip: '', officeName: '', departmentName: ''));
      row.leaveRequests++;
      if (_status(data) == 'approved') row.approvedLeave++;
    }

    final lateAmount = _toInt(settings['late_deduction_amount']);
    final outsideAmount = _toInt(settings['outside_radius_deduction_amount']);
    final rejectedAmount = _toInt(settings['rejected_deduction_amount']);
    final overtimeRate = _toInt(settings['overtime_rate_per_hour']);
    for (final row in rows.values) {
      row.lateDeductionAmount = lateAmount;
      row.outsideRadiusDeductionAmount = outsideAmount;
      row.rejectedDeductionAmount = rejectedAmount;
      row.overtimeRatePerHour = overtimeRate;
    }

    final list = rows.values.toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  bool _dateAllowed(String rawDate) {
    final parsed = DateTime.tryParse(rawDate);
    if (parsed == null) return true;
    if (startDate != null && parsed.isBefore(DateTime(startDate!.year, startDate!.month, startDate!.day))) return false;
    if (endDate != null && parsed.isAfter(DateTime(endDate!.year, endDate!.month, endDate!.day, 23, 59, 59))) return false;
    return true;
  }

  List<WorkRecapRecord> filtered(List<WorkRecapRecord> rows) {
    final q = search.text.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows.where((row) => '${row.name} ${row.email} ${row.nip} ${row.officeName} ${row.departmentName}'.toLowerCase().contains(q)).toList();
  }

  Future<void> pickStart() async {
    final picked = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2035), initialDate: startDate ?? DateTime.now());
    if (picked != null) {
      setState(() {
        startDate = picked;
        future = loadRows();
      });
    }
  }

  Future<void> pickEnd() async {
    final picked = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2035), initialDate: endDate ?? DateTime.now());
    if (picked != null) {
      setState(() {
        endDate = picked;
        future = loadRows();
      });
    }
  }

  Future<void> exportExcel(List<WorkRecapRecord> rows) async {
    if (exporting || rows.isEmpty) return;
    setState(() => exporting = true);
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Work Recap'];
      excel.setDefaultSheet('Work Recap');
      if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

      final headers = ['Nama', 'Email', 'NIP', 'Kantor', 'Departemen', 'Hari Kerja', 'Masuk', 'Pulang', 'Terlambat', 'Luar Radius', 'Ditolak', 'Skor Potongan', 'Potongan IDR', 'Request Lembur', 'Lembur Approved', 'Jam Lembur', 'Estimasi Lembur IDR', 'Net Adjustment IDR', 'Request Cuti', 'Cuti Approved', 'UID'];
      for (var col = 0; col < headers.length; col++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
        cell.value = TextCellValue(headers[col]);
        cell.cellStyle = CellStyle(bold: true);
      }

      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final values = [
          row.name,
          row.email,
          row.nip,
          row.officeName,
          row.departmentName,
          row.workDays.toString(),
          row.checkIn.toString(),
          row.checkOut.toString(),
          row.lateCount.toString(),
          row.outsideRadiusCount.toString(),
          row.rejectedCount.toString(),
          row.deductionScore.toString(),
          row.deductionAmount.toString(),
          row.overtimeRequests.toString(),
          row.approvedOvertime.toString(),
          row.overtimeHours.toStringAsFixed(1),
          row.overtimeEstimate.toString(),
          row.netAdjustment.toString(),
          row.leaveRequests.toString(),
          row.approvedLeave.toString(),
          row.uid,
        ];
        for (var col = 0; col < values.length; col++) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: i + 1)).value = TextCellValue(values[col]);
        }
      }

      for (var col = 0; col < headers.length; col++) {
        sheet.setColumnWidth(col, col == 0 ? 24 : 16);
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Gagal membuat file Excel.');
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/work_recap_${DateTime.now().millisecondsSinceEpoch}.xlsx');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(file.path)], text: 'Work recap MyPresence');
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
      appBar: AppBar(title: const Text('Work Recap'), actions: [IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
      body: FutureBuilder<List<WorkRecapRecord>>(
        future: future,
        builder: (context, snapshot) {
          final rows = filtered(snapshot.data ?? const <WorkRecapRecord>[]);
          final totalLate = rows.fold<int>(0, (sum, row) => sum + row.lateCount);
          final totalOvertime = rows.fold<double>(0, (sum, row) => sum + row.overtimeHours);
          final totalOutside = rows.fold<int>(0, (sum, row) => sum + row.outsideRadiusCount);
          final totalDeduction = rows.fold<int>(0, (sum, row) => sum + row.deductionAmount);
          final totalOvertimeEstimate = rows.fold<int>(0, (sum, row) => sum + row.overtimeEstimate);

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              MessageCard(title: 'Work Recap', message: 'Karyawan: ${rows.length} • Telat: $totalLate • Luar radius: $totalOutside • Jam lembur: ${totalOvertime.toStringAsFixed(1)}\nPotongan: ${_money(totalDeduction)} • Estimasi lembur: ${_money(totalOvertimeEstimate)}', icon: Icons.summarize_rounded),
              const SizedBox(height: 12),
              TextField(controller: search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Cari nama, NIP, email, kantor, departemen', prefixIcon: Icon(Icons.search_rounded))),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: pickStart, icon: const Icon(Icons.date_range_rounded), label: Text(startDate == null ? 'Mulai' : _date(startDate!)))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(onPressed: pickEnd, icon: const Icon(Icons.event_rounded), label: Text(endDate == null ? 'Selesai' : _date(endDate!)))),
              ]),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: rows.isEmpty || exporting ? null : () => exportExcel(rows), icon: const Icon(Icons.file_download_rounded), label: Text(exporting ? 'Membuat Excel...' : 'Export Excel Work Recap')),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                MessageCard(title: 'Gagal memuat work recap', message: snapshot.error.toString(), icon: Icons.error_outline_rounded)
              else if (rows.isEmpty)
                const MessageCard(title: 'Tidak ada data', message: 'Data rekap kerja sesuai filter akan tampil di sini.', icon: Icons.inbox_outlined)
              else
                ...rows.map((row) => Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text(row.name.isEmpty ? '?' : row.name.characters.first.toUpperCase())),
                        title: Text(row.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text('${row.nip.ifEmpty(row.email)} • ${row.officeName.ifEmpty('-')}\nTelat ${row.lateCount} • Luar ${row.outsideRadiusCount} • Ditolak ${row.rejectedCount} • Potongan ${_money(row.deductionAmount)} • Lembur ${_money(row.overtimeEstimate)}'),
                        isThreeLine: true,
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }
}

class WorkRecapRecord {
  final String uid;
  final String name;
  final String email;
  final String nip;
  final String officeName;
  final String departmentName;
  int workDays = 0;
  int checkIn = 0;
  int checkOut = 0;
  int lateCount = 0;
  int outsideRadiusCount = 0;
  int rejectedCount = 0;
  int overtimeRequests = 0;
  int approvedOvertime = 0;
  double overtimeHours = 0;
  int leaveRequests = 0;
  int approvedLeave = 0;
  int lateDeductionAmount = 0;
  int outsideRadiusDeductionAmount = 0;
  int rejectedDeductionAmount = 0;
  int overtimeRatePerHour = 0;

  WorkRecapRecord({required this.uid, required this.name, required this.email, required this.nip, required this.officeName, required this.departmentName});

  int get deductionScore => lateCount + (outsideRadiusCount * 2) + (rejectedCount * 3);
  int get deductionAmount => (lateCount * lateDeductionAmount) + (outsideRadiusCount * outsideRadiusDeductionAmount) + (rejectedCount * rejectedDeductionAmount);
  int get overtimeEstimate => (overtimeHours * overtimeRatePerHour).round();
  int get netAdjustment => overtimeEstimate - deductionAmount;
}

Map<String, dynamic>? _asMap(Object? value) => value is Map ? value.map((key, item) => MapEntry(key.toString(), item)) : null;

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

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString().replaceAll('.', '').replaceAll(',', '') ?? '') ?? 0;
}

String _status(Map<String, dynamic> data) {
  final text = _read(data, const ['status', 'approval_status']).toLowerCase();
  if (text.contains('approve') || text.contains('valid')) return 'approved';
  if (text.contains('reject') || text.contains('tolak')) return 'rejected';
  return 'pending';
}

String _date(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _money(num value) {
  final text = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final reverseIndex = text.length - i;
    buffer.write(text[i]);
    if (reverseIndex > 1 && reverseIndex % 3 == 1) buffer.write('.');
  }
  return 'Rp $buffer';
}

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
