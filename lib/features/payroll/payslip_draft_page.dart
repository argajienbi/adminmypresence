import 'dart:io';

import 'package:excel/excel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models.dart';
import '../shared/message_card.dart';

class PayslipDraftPage extends StatefulWidget {
  final AdminSession session;

  const PayslipDraftPage({super.key, required this.session});

  @override
  State<PayslipDraftPage> createState() => _PayslipDraftPageState();
}

class _PayslipDraftPageState extends State<PayslipDraftPage> {
  late Future<List<PayslipDraftRecord>> future;
  final search = TextEditingController();
  DateTime startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime endDate = DateTime(DateTime.now().year, DateTime.now().month + 1, 0);
  bool exporting = false;
  bool payrollSettingsConfigured = true;

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

  String get periodLabel => '${_date(startDate)} s/d ${_date(endDate)}';

  Future<List<PayslipDraftRecord>> loadRows() async {
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
    payrollSettingsConfigured = results[4].exists && settings.isNotEmpty;

    final lateAmount = _toInt(settings['late_deduction_amount']);
    final outsideAmount = _toInt(settings['outside_radius_deduction_amount']);
    final rejectedAmount = _toInt(settings['rejected_deduction_amount']);
    final overtimeRate = _toInt(settings['overtime_rate_per_hour']);
    final rows = <String, PayslipDraftRecord>{};

    for (final entry in users.entries) {
      final user = _asMap(entry.value) ?? const <String, dynamic>{};
      rows[entry.key] = PayslipDraftRecord(
        uid: entry.key,
        name: _read(user, const ['display_name', 'nama_lengkap', 'name']).ifEmpty(entry.key),
        email: _read(user, const ['email']),
        nip: _read(user, const ['nip']),
        officeName: _read(user, const ['office_name', 'kantor', 'nama_kantor']),
        departmentName: _read(user, const ['department_name', 'department']),
        period: periodLabel,
        lateDeductionAmount: lateAmount,
        outsideRadiusDeductionAmount: outsideAmount,
        rejectedDeductionAmount: rejectedAmount,
        overtimeRatePerHour: overtimeRate,
      );
    }

    for (final userEntry in attendance.entries) {
      final uid = userEntry.key;
      final days = _asMap(userEntry.value);
      if (days == null) continue;
      final row = rows.putIfAbsent(uid, () => PayslipDraftRecord.empty(uid, periodLabel, lateAmount, outsideAmount, rejectedAmount, overtimeRate));
      for (final dayEntry in days.entries) {
        if (!_dateAllowed(dayEntry.key)) continue;
        final actions = _asMap(dayEntry.value);
        if (actions == null) continue;
        var countedDay = false;
        for (final actionEntry in actions.entries) {
          final data = _asMap(actionEntry.value) ?? const <String, dynamic>{};
          final status = _read(data, const ['attendance_status', 'status_absen', 'validation_status', 'status']).toLowerCase();
          if (!countedDay) {
            row.workDays++;
            countedDay = true;
          }
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
      if (uid.isEmpty || !_dateAllowed(date) || _status(data) != 'approved') continue;
      final row = rows.putIfAbsent(uid, () => PayslipDraftRecord.empty(uid, periodLabel, lateAmount, outsideAmount, rejectedAmount, overtimeRate));
      row.overtimeHours += _toDouble(data['hours'] ?? data['duration_hours'] ?? data['total_hours']);
    }

    for (final entry in leave.entries) {
      final data = _asMap(entry.value) ?? const <String, dynamic>{};
      final uid = _read(data, const ['uid', 'user_id', 'employee_id']);
      final date = _read(data, const ['date', 'tanggal', 'start_date']);
      if (uid.isEmpty || !_dateAllowed(date) || _status(data) != 'approved') continue;
      rows.putIfAbsent(uid, () => PayslipDraftRecord.empty(uid, periodLabel, lateAmount, outsideAmount, rejectedAmount, overtimeRate));
    }

    final list = rows.values.toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  bool _dateAllowed(String rawDate) {
    final parsed = DateTime.tryParse(rawDate);
    if (parsed == null) return true;
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
    return !parsed.isBefore(start) && !parsed.isAfter(end);
  }

  List<PayslipDraftRecord> filtered(List<PayslipDraftRecord> rows) {
    final q = search.text.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows.where((row) => '${row.name} ${row.email} ${row.nip} ${row.officeName} ${row.departmentName}'.toLowerCase().contains(q)).toList();
  }

  Future<void> pickStart() async {
    final picked = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2035), initialDate: startDate);
    if (picked == null) return;
    setState(() {
      startDate = picked;
      if (endDate.isBefore(startDate)) endDate = picked;
      future = loadRows();
    });
  }

  Future<void> pickEnd() async {
    final picked = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2035), initialDate: endDate);
    if (picked == null) return;
    setState(() {
      endDate = picked;
      if (startDate.isAfter(endDate)) startDate = picked;
      future = loadRows();
    });
  }

  Future<void> exportExcel(List<PayslipDraftRecord> rows) async {
    if (exporting || rows.isEmpty) return;
    setState(() => exporting = true);
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Payslip Draft'];
      excel.setDefaultSheet('Payslip Draft');
      if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

      final headers = ['Nama', 'Email', 'NIP', 'Kantor', 'Departemen', 'Periode', 'Total Hari Kerja', 'Total Terlambat', 'Total Luar Radius', 'Total Ditolak', 'Total Potongan', 'Total Jam Lembur', 'Estimasi Lembur', 'Net Adjustment', 'UID'];
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
          row.period,
          row.workDays.toString(),
          row.lateCount.toString(),
          row.outsideRadiusCount.toString(),
          row.rejectedCount.toString(),
          row.totalDeduction.toString(),
          row.overtimeHours.toStringAsFixed(1),
          row.overtimeEstimate.toString(),
          row.netAdjustment.toString(),
          row.uid,
        ];
        for (var col = 0; col < values.length; col++) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: i + 1)).value = TextCellValue(values[col]);
        }
      }

      for (var col = 0; col < headers.length; col++) {
        sheet.setColumnWidth(col, col == 0 ? 24 : 18);
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Gagal membuat file Excel.');
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/payslip_draft_${DateTime.now().millisecondsSinceEpoch}.xlsx');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(file.path)], text: 'Payslip draft MyPresence');
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
      appBar: AppBar(title: const Text('Payslip Draft'), actions: [IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
      body: FutureBuilder<List<PayslipDraftRecord>>(
        future: future,
        builder: (context, snapshot) {
          final rows = filtered(snapshot.data ?? const <PayslipDraftRecord>[]);
          final totalDeduction = rows.fold<int>(0, (sum, row) => sum + row.totalDeduction);
          final totalOvertime = rows.fold<double>(0, (sum, row) => sum + row.overtimeHours);
          final totalNet = rows.fold<int>(0, (sum, row) => sum + row.netAdjustment);

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              MessageCard(
                title: 'Payslip Draft',
                message: 'Periode $periodLabel • Karyawan: ${rows.length}\nPotongan: ${_money(totalDeduction)} • Lembur: ${totalOvertime.toStringAsFixed(1)} jam • Net: ${_money(totalNet)}',
                icon: Icons.receipt_long_rounded,
              ),
              const SizedBox(height: 12),
              if (!payrollSettingsConfigured) ...[
                const MessageCard(
                  title: 'Payroll Settings belum dikonfigurasi',
                  message: 'Draft tetap dibuat dengan nominal potongan dan rate lembur 0.',
                  icon: Icons.info_outline_rounded,
                ),
                const SizedBox(height: 12),
              ],
              TextField(controller: search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Cari nama, NIP, email, kantor, departemen', prefixIcon: Icon(Icons.search_rounded))),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: pickStart, icon: const Icon(Icons.date_range_rounded), label: Text(_date(startDate)))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(onPressed: pickEnd, icon: const Icon(Icons.event_rounded), label: Text(_date(endDate)))),
              ]),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: rows.isEmpty || exporting ? null : () => exportExcel(rows), icon: const Icon(Icons.file_download_rounded), label: Text(exporting ? 'Membuat Excel...' : 'Export Excel Payslip Draft')),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                MessageCard(title: 'Gagal memuat payslip draft', message: snapshot.error.toString(), icon: Icons.error_outline_rounded)
              else if (rows.isEmpty)
                const MessageCard(title: 'Tidak ada draft', message: 'Draft slip gaji sesuai filter akan tampil di sini.', icon: Icons.inbox_outlined)
              else
                ...rows.map((row) => Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text(row.name.isEmpty ? '?' : row.name.characters.first.toUpperCase())),
                        title: Text(row.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text('${row.nip.ifEmpty(row.email)} • ${row.officeName.ifEmpty('-')} • ${row.departmentName.ifEmpty('-')}\nHari ${row.workDays} • Telat ${row.lateCount} • Luar ${row.outsideRadiusCount} • Ditolak ${row.rejectedCount} • Potongan ${_money(row.totalDeduction)} • Lembur ${_money(row.overtimeEstimate)} • Net ${_money(row.netAdjustment)}'),
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

class PayslipDraftRecord {
  final String uid;
  final String name;
  final String email;
  final String nip;
  final String officeName;
  final String departmentName;
  final String period;
  final int lateDeductionAmount;
  final int outsideRadiusDeductionAmount;
  final int rejectedDeductionAmount;
  final int overtimeRatePerHour;
  int workDays = 0;
  int lateCount = 0;
  int outsideRadiusCount = 0;
  int rejectedCount = 0;
  double overtimeHours = 0;

  PayslipDraftRecord({required this.uid, required this.name, required this.email, required this.nip, required this.officeName, required this.departmentName, required this.period, required this.lateDeductionAmount, required this.outsideRadiusDeductionAmount, required this.rejectedDeductionAmount, required this.overtimeRatePerHour});

  factory PayslipDraftRecord.empty(String uid, String period, int lateAmount, int outsideAmount, int rejectedAmount, int overtimeRate) {
    return PayslipDraftRecord(uid: uid, name: uid, email: '', nip: '', officeName: '', departmentName: '', period: period, lateDeductionAmount: lateAmount, outsideRadiusDeductionAmount: outsideAmount, rejectedDeductionAmount: rejectedAmount, overtimeRatePerHour: overtimeRate);
  }

  int get totalDeduction => (lateCount * lateDeductionAmount) + (outsideRadiusCount * outsideRadiusDeductionAmount) + (rejectedCount * rejectedDeductionAmount);
  int get overtimeEstimate => (overtimeHours * overtimeRatePerHour).round();
  int get netAdjustment => overtimeEstimate - totalDeduction;
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
  final rounded = value.round();
  final negative = rounded < 0;
  final text = rounded.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final reverseIndex = text.length - i;
    buffer.write(text[i]);
    if (reverseIndex > 1 && reverseIndex % 3 == 1) buffer.write('.');
  }
  return 'Rp ${negative ? '-' : ''}$buffer';
}

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
