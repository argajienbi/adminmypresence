import 'dart:io';

import 'package:excel/excel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/models.dart';
import '../shared/message_card.dart';

class ReportsSummaryPage extends StatefulWidget {
  final AdminSession session;

  const ReportsSummaryPage({super.key, required this.session});

  @override
  State<ReportsSummaryPage> createState() => _ReportsSummaryPageState();
}

class _ReportsSummaryPageState extends State<ReportsSummaryPage> {
  late Future<List<EmployeeReportSummary>> future;
  final search = TextEditingController();
  DateTime? startDate;
  DateTime? endDate;
  bool exporting = false;

  @override
  void initState() {
    super.initState();
    future = loadSummary();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void refresh() => setState(() => future = loadSummary());

  Future<List<EmployeeReportSummary>> loadSummary() async {
    final companyId = widget.session.companyId;
    final db = FirebaseDatabase.instance;
    final results = await Future.wait([
      db.ref('attendance/$companyId').get(),
      db.ref('company_users/$companyId').get(),
    ]);

    final attendance = _asMap(results[0].value) ?? const <String, dynamic>{};
    final users = _asMap(results[1].value) ?? const <String, dynamic>{};
    final summaries = <String, EmployeeReportSummary>{};

    for (final userEntry in users.entries) {
      final user = _asMap(userEntry.value) ?? const <String, dynamic>{};
      summaries[userEntry.key] = EmployeeReportSummary(
        uid: userEntry.key,
        name: _read(user, const ['nama_lengkap', 'display_name', 'name']).ifEmpty(userEntry.key),
        email: _read(user, const ['email']),
        nip: _read(user, const ['nip']),
        officeName: _read(user, const ['office_name', 'kantor', 'nama_kantor']),
        groupName: _read(user, const ['group_name', 'employee_group_name']),
      );
    }

    for (final userEntry in attendance.entries) {
      final uid = userEntry.key;
      final summary = summaries.putIfAbsent(uid, () => EmployeeReportSummary(uid: uid, name: uid, email: '', nip: '', officeName: '', groupName: ''));
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
            summary.totalDays++;
            countedDay = true;
          }
          if (action.contains('masuk') || action.contains('check_in') || action == 'in') summary.checkIn++;
          if (action.contains('pulang') || action.contains('check_out') || action == 'out') summary.checkOut++;
          if (action.contains('izin')) summary.permission++;
          if (action.contains('sakit')) summary.sick++;
          if (action.contains('cuti')) summary.leave++;
          if (action.contains('lembur')) summary.overtime++;
          if (status.contains('late') || status.contains('terlambat') || status.contains('telat')) summary.late++;
          if (status.contains('outside') || status.contains('luar')) summary.outsideRadius++;
        }
      }
    }

    final rows = summaries.values.toList();
    rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return rows;
  }

  bool _dateAllowed(String rawDate) {
    final parsed = DateTime.tryParse(rawDate);
    if (parsed == null) return true;
    if (startDate != null && parsed.isBefore(DateTime(startDate!.year, startDate!.month, startDate!.day))) return false;
    if (endDate != null && parsed.isAfter(DateTime(endDate!.year, endDate!.month, endDate!.day, 23, 59, 59))) return false;
    return true;
  }

  List<EmployeeReportSummary> filterRows(List<EmployeeReportSummary> rows) {
    final q = search.text.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows.where((row) => '${row.name} ${row.email} ${row.nip} ${row.officeName} ${row.groupName}'.toLowerCase().contains(q)).toList();
  }

  Future<void> pickStart() async {
    final picked = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2035), initialDate: startDate ?? DateTime.now());
    if (picked != null) {
      setState(() {
        startDate = picked;
        future = loadSummary();
      });
    }
  }

  Future<void> pickEnd() async {
    final picked = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2035), initialDate: endDate ?? DateTime.now());
    if (picked != null) {
      setState(() {
        endDate = picked;
        future = loadSummary();
      });
    }
  }

  Future<void> exportExcel(List<EmployeeReportSummary> rows) async {
    if (exporting || rows.isEmpty) return;
    setState(() => exporting = true);
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Summary'];
      excel.setDefaultSheet('Summary');
      if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

      final headers = ['Nama', 'Email', 'NIP', 'Kantor', 'Grup', 'Total Hari', 'Masuk', 'Pulang', 'Terlambat', 'Luar Radius', 'Izin', 'Sakit', 'Cuti', 'Lembur', 'UID'];
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
          row.groupName,
          row.totalDays.toString(),
          row.checkIn.toString(),
          row.checkOut.toString(),
          row.late.toString(),
          row.outsideRadius.toString(),
          row.permission.toString(),
          row.sick.toString(),
          row.leave.toString(),
          row.overtime.toString(),
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
      final file = File('${directory.path}/summary_absensi_${DateTime.now().millisecondsSinceEpoch}.xlsx');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(file.path)], text: 'Summary absensi MyPresence');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<void> exportPdf(List<EmployeeReportSummary> rows) async {
    if (exporting || rows.isEmpty) return;
    setState(() => exporting = true);
    try {
      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          build: (_) => [
            pw.Text('Summary Absensi', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Text('Company: ${widget.session.companyName} | Total karyawan: ${rows.length}'),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headers: const ['Nama', 'NIP', 'Kantor', 'Hari', 'Masuk', 'Pulang', 'Telat', 'Luar', 'Izin', 'Sakit', 'Cuti', 'Lembur'],
              data: rows
                  .map((row) => [
                        row.name,
                        row.nip,
                        row.officeName,
                        row.totalDays.toString(),
                        row.checkIn.toString(),
                        row.checkOut.toString(),
                        row.late.toString(),
                        row.outsideRadius.toString(),
                        row.permission.toString(),
                        row.sick.toString(),
                        row.leave.toString(),
                        row.overtime.toString(),
                      ])
                  .toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
            ),
          ],
        ),
      );
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/summary_absensi_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(await doc.save(), flush: true);
      await Share.shareXFiles([XFile(file.path)], text: 'Summary absensi MyPresence');
      await FirebaseDatabase.instance.ref('audit_logs/${widget.session.companyId}').push().set({
        'action': 'EXPORT_SUMMARY_PDF',
        'details': 'Export summary report PDF',
        'actor_uid': widget.session.uid,
        'actor_email': widget.session.email,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
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
      appBar: AppBar(title: const Text('Reports Summary'), actions: [IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
      body: FutureBuilder<List<EmployeeReportSummary>>(
        future: future,
        builder: (context, snapshot) {
          final rows = filterRows(snapshot.data ?? const <EmployeeReportSummary>[]);
          final totalLate = rows.fold<int>(0, (sum, row) => sum + row.late);
          final totalOutside = rows.fold<int>(0, (sum, row) => sum + row.outsideRadius);
          final totalCheckIn = rows.fold<int>(0, (sum, row) => sum + row.checkIn);

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              MessageCard(title: 'Summary Absensi', message: 'Karyawan: ${rows.length} • Masuk: $totalCheckIn • Terlambat: $totalLate • Luar Radius: $totalOutside', icon: Icons.summarize_rounded),
              const SizedBox(height: 12),
              TextField(controller: search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Cari nama, NIP, email, kantor, grup', prefixIcon: Icon(Icons.search_rounded))),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: pickStart, icon: const Icon(Icons.date_range_rounded), label: Text(startDate == null ? 'Mulai' : _date(startDate!)))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(onPressed: pickEnd, icon: const Icon(Icons.event_rounded), label: Text(endDate == null ? 'Selesai' : _date(endDate!)))),
              ]),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: FilledButton.icon(onPressed: rows.isEmpty || exporting ? null : () => exportExcel(rows), icon: const Icon(Icons.file_download_rounded), label: Text(exporting ? 'Membuat...' : 'Export Excel'))),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton.icon(onPressed: rows.isEmpty || exporting ? null : () => exportPdf(rows), icon: const Icon(Icons.picture_as_pdf_rounded), label: Text(exporting ? 'Membuat...' : 'Export PDF'))),
                ],
              ),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                MessageCard(title: 'Gagal memuat summary', message: snapshot.error.toString(), icon: Icons.error_outline_rounded)
              else if (rows.isEmpty)
                const MessageCard(title: 'Tidak ada data', message: 'Tidak ada summary sesuai filter.', icon: Icons.inbox_outlined)
              else
                ...rows.map((row) => Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text(row.name.isEmpty ? '?' : row.name.characters.first.toUpperCase())),
                        title: Text(row.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text('${row.nip.ifEmpty(row.email)} • ${row.officeName.ifEmpty('-')}\nHari ${row.totalDays} • Masuk ${row.checkIn} • Pulang ${row.checkOut} • Telat ${row.late} • Luar ${row.outsideRadius}'),
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

class EmployeeReportSummary {
  final String uid;
  final String name;
  final String email;
  final String nip;
  final String officeName;
  final String groupName;
  int totalDays = 0;
  int checkIn = 0;
  int checkOut = 0;
  int late = 0;
  int outsideRadius = 0;
  int permission = 0;
  int sick = 0;
  int leave = 0;
  int overtime = 0;

  EmployeeReportSummary({required this.uid, required this.name, required this.email, required this.nip, required this.officeName, required this.groupName});
}

Map<String, dynamic>? _asMap(Object? value) => value is Map ? value.map((key, item) => MapEntry(key.toString(), item)) : null;

String _read(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value != null && value.toString().trim().isNotEmpty) return value.toString();
  }
  return '';
}

String _date(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
