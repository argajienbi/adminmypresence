import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../shared/message_card.dart';

class SchedulesManagementPage extends StatefulWidget {
  final AdminSession session;

  const SchedulesManagementPage({super.key, required this.session});

  @override
  State<SchedulesManagementPage> createState() => _SchedulesManagementPageState();
}

class _SchedulesManagementPageState extends State<SchedulesManagementPage> {
  late Future<ScheduleBundle> future;
  String tab = 'timetables';
  String query = '';

  @override
  void initState() {
    super.initState();
    future = loadBundle();
  }

  void refresh() => setState(() => future = loadBundle());

  Future<ScheduleBundle> loadBundle() async {
    final companyId = widget.session.companyId;
    final db = FirebaseDatabase.instance;
    final results = await Future.wait([
      db.ref('timetables/$companyId').get(),
      db.ref('shifts/$companyId').get(),
      db.ref('schedule_assignments/$companyId').get(),
      db.ref('schedule_specials/$companyId').get(),
      db.ref('holidays/$companyId').get(),
      db.ref('overtime_schedules/$companyId').get(),
      db.ref('company_users/$companyId').get(),
    ]);

    return ScheduleBundle(
      timetables: _items(results[0].value, 'timetable'),
      shifts: _items(results[1].value, 'shift'),
      assignments: _items(results[2].value, 'assignment'),
      specials: _items(results[3].value, 'special'),
      holidays: _items(results[4].value, 'holiday'),
      overtime: _items(results[5].value, 'overtime'),
      users: _items(results[6].value, 'user'),
    );
  }

  List<ScheduleItem> selectedRows(ScheduleBundle bundle) {
    final source = switch (tab) {
      'timetables' => bundle.timetables,
      'shifts' => bundle.shifts,
      'assignments' => bundle.assignments,
      'specials' => bundle.specials,
      'holidays' => bundle.holidays,
      'overtime' => bundle.overtime,
      _ => bundle.timetables,
    };
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return source;
    return source.where((row) => '${row.title} ${row.subtitle} ${row.rawText}'.toLowerCase().contains(q)).toList();
  }

  Future<void> openTimetableForm([ScheduleItem? item]) async {
    final name = TextEditingController(text: item?.title == item?.id ? '' : item?.title ?? '');
    final start = TextEditingController(text: item == null ? '08:00' : item.startTime.ifEmpty('08:00'));
    final end = TextEditingController(text: item == null ? '17:00' : item.endTime.ifEmpty('17:00'));
    final late = TextEditingController(text: _read(item?.data ?? const {}, const ['late_tolerance_minutes']).ifEmpty('15'));

    final ok = await _formSheet(
      title: item == null ? 'Tambah Jam Kerja' : 'Edit Jam Kerja',
      children: [
        _field(name, 'Nama jam kerja'),
        _field(start, 'Jam masuk HH:mm'),
        _field(end, 'Jam pulang HH:mm'),
        _field(late, 'Toleransi terlambat menit', number: true),
      ],
    );

    if (ok == true && name.text.trim().isNotEmpty) {
      final id = item?.id ?? FirebaseDatabase.instance.ref('timetables/${widget.session.companyId}').push().key!;
      await _save('timetables/${widget.session.companyId}/$id', item == null ? 'create_timetable' : 'update_timetable', id, {
        'id': id,
        'name': name.text.trim(),
        'title': name.text.trim(),
        'start_time': start.text.trim(),
        'end_time': end.text.trim(),
        'late_tolerance_minutes': int.tryParse(late.text.trim()) ?? 15,
        'active': true,
      });
    }
  }

  Future<void> openShiftForm([ScheduleItem? item]) async {
    final name = TextEditingController(text: item?.title == item?.id ? '' : item?.title ?? '');
    final start = TextEditingController(text: item == null ? '08:00' : item.startTime.ifEmpty('08:00'));
    final end = TextEditingController(text: item == null ? '17:00' : item.endTime.ifEmpty('17:00'));

    final ok = await _formSheet(
      title: item == null ? 'Tambah Shift' : 'Edit Shift',
      children: [_field(name, 'Nama shift'), _field(start, 'Mulai HH:mm'), _field(end, 'Selesai HH:mm')],
    );

    if (ok == true && name.text.trim().isNotEmpty) {
      final id = item?.id ?? FirebaseDatabase.instance.ref('shifts/${widget.session.companyId}').push().key!;
      await _save('shifts/${widget.session.companyId}/$id', item == null ? 'create_shift' : 'update_shift', id, {
        'id': id,
        'name': name.text.trim(),
        'shift_name': name.text.trim(),
        'start_time': start.text.trim(),
        'end_time': end.text.trim(),
        'active': true,
      });
    }
  }

  Future<void> openHolidayForm([ScheduleItem? item]) async {
    final title = TextEditingController(text: item?.title == item?.id ? '' : item?.title ?? '');
    final date = TextEditingController(text: item == null ? _date(DateTime.now()) : item.date.ifEmpty(_date(DateTime.now())));
    final note = TextEditingController(text: _read(item?.data ?? const {}, const ['note', 'description', 'keterangan']));

    final ok = await _formSheet(
      title: item == null ? 'Tambah Hari Libur' : 'Edit Hari Libur',
      children: [_field(title, 'Nama libur'), _field(date, 'Tanggal YYYY-MM-DD'), _field(note, 'Catatan')],
    );

    if (ok == true && title.text.trim().isNotEmpty) {
      final id = item?.id ?? FirebaseDatabase.instance.ref('holidays/${widget.session.companyId}').push().key!;
      await _save('holidays/${widget.session.companyId}/$id', item == null ? 'create_holiday' : 'update_holiday', id, {
        'id': id,
        'title': title.text.trim(),
        'name': title.text.trim(),
        'date': date.text.trim(),
        'note': note.text.trim(),
        'active': true,
      });
    }
  }

  Future<void> openSpecialForm([ScheduleItem? item]) async {
    final title = TextEditingController(text: item?.title == item?.id ? '' : item?.title ?? '');
    final date = TextEditingController(text: item == null ? _date(DateTime.now()) : item.date.ifEmpty(_date(DateTime.now())));
    final start = TextEditingController(text: item == null ? '08:00' : item.startTime.ifEmpty('08:00'));
    final end = TextEditingController(text: item == null ? '17:00' : item.endTime.ifEmpty('17:00'));

    final ok = await _formSheet(
      title: item == null ? 'Tambah Jadwal Khusus' : 'Edit Jadwal Khusus',
      children: [_field(title, 'Nama jadwal'), _field(date, 'Tanggal YYYY-MM-DD'), _field(start, 'Mulai HH:mm'), _field(end, 'Selesai HH:mm')],
    );

    if (ok == true && title.text.trim().isNotEmpty) {
      final id = item?.id ?? FirebaseDatabase.instance.ref('schedule_specials/${widget.session.companyId}').push().key!;
      await _save('schedule_specials/${widget.session.companyId}/$id', item == null ? 'create_special_schedule' : 'update_special_schedule', id, {
        'id': id,
        'title': title.text.trim(),
        'name': title.text.trim(),
        'date': date.text.trim(),
        'start_time': start.text.trim(),
        'end_time': end.text.trim(),
        'active': true,
      });
    }
  }

  Future<void> openOvertimeForm([ScheduleItem? item]) async {
    final title = TextEditingController(text: item?.title == item?.id ? '' : item?.title ?? '');
    final date = TextEditingController(text: item == null ? _date(DateTime.now()) : item.date.ifEmpty(_date(DateTime.now())));
    final start = TextEditingController(text: item == null ? '18:00' : item.startTime.ifEmpty('18:00'));
    final end = TextEditingController(text: item == null ? '21:00' : item.endTime.ifEmpty('21:00'));

    final ok = await _formSheet(
      title: item == null ? 'Tambah Jadwal Lembur' : 'Edit Jadwal Lembur',
      children: [_field(title, 'Nama lembur'), _field(date, 'Tanggal YYYY-MM-DD'), _field(start, 'Mulai HH:mm'), _field(end, 'Selesai HH:mm')],
    );

    if (ok == true && title.text.trim().isNotEmpty) {
      final id = item?.id ?? FirebaseDatabase.instance.ref('overtime_schedules/${widget.session.companyId}').push().key!;
      await _save('overtime_schedules/${widget.session.companyId}/$id', item == null ? 'create_overtime_schedule' : 'update_overtime_schedule', id, {
        'id': id,
        'title': title.text.trim(),
        'name': title.text.trim(),
        'date': date.text.trim(),
        'start_time': start.text.trim(),
        'end_time': end.text.trim(),
        'active': true,
      });
    }
  }

  Future<void> openAssignmentForm(ScheduleBundle bundle, [ScheduleItem? item]) async {
    String userId = _read(item?.data ?? const {}, const ['uid', 'user_id', 'employee_id']);
    String timetableId = _read(item?.data ?? const {}, const ['timetable_id']);
    String shiftId = _read(item?.data ?? const {}, const ['shift_id']);

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(item == null ? 'Assign Jadwal' : 'Edit Assignment', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                _dropdown('Karyawan', bundle.users, userId, (value) => setSheetState(() => userId = value)),
                const SizedBox(height: 10),
                _dropdown('Jam Kerja', bundle.timetables, timetableId, (value) => setSheetState(() => timetableId = value)),
                const SizedBox(height: 10),
                _dropdown('Shift', bundle.shifts, shiftId, (value) => setSheetState(() => shiftId = value)),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Simpan')),
              ],
            ),
          ),
        ),
      ),
    );

    if (ok == true && userId.isNotEmpty) {
      final id = item?.id ?? userId;
      final user = bundle.find(bundle.users, userId);
      final timetable = bundle.find(bundle.timetables, timetableId);
      final shift = bundle.find(bundle.shifts, shiftId);
      await _save('schedule_assignments/${widget.session.companyId}/$id', item == null ? 'create_schedule_assignment' : 'update_schedule_assignment', id, {
        'id': id,
        'uid': userId,
        'user_id': userId,
        'employee_name': user?.title ?? '',
        'timetable_id': timetableId,
        'timetable_name': timetable?.title ?? '',
        'shift_id': shiftId,
        'shift_name': shift?.title ?? '',
        'active': true,
      });
    }
  }

  Future<bool?> _formSheet({required String title, required List<Widget> children}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                ...children.expand((child) => [child, const SizedBox(height: 10)]),
                FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Simpan')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, {bool number = false}) {
    return TextField(controller: controller, keyboardType: number ? TextInputType.number : TextInputType.text, decoration: InputDecoration(labelText: label));
  }

  Widget _dropdown(String label, List<ScheduleItem> items, String value, ValueChanged<String> onChanged) {
    final current = items.any((item) => item.id == value) ? value : '';
    return DropdownButtonFormField<String>(
      value: current,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem(value: '', child: Text('-')),
        ...items.map((item) => DropdownMenuItem(value: item.id, child: Text(item.title))),
      ],
      onChanged: (value) => onChanged(value ?? ''),
    );
  }

  Future<void> _save(String path, String action, String targetId, Map<String, dynamic> payload) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await FirebaseDatabase.instance.ref(path).update({
      ...payload,
      'company_id': widget.session.companyId,
      'updated_at': now,
      'updated_by': widget.session.uid,
    });
    await FirebaseDatabase.instance.ref('audit_logs/${widget.session.companyId}').push().set({
      'action': action,
      'target_id': targetId,
      'target_path': path,
      'actor_uid': widget.session.uid,
      'actor_email': widget.session.email,
      'created_at': now,
    });
    refresh();
  }

  void openCurrentForm(ScheduleBundle bundle, [ScheduleItem? item]) {
    if (tab == 'timetables') openTimetableForm(item);
    if (tab == 'shifts') openShiftForm(item);
    if (tab == 'assignments') openAssignmentForm(bundle, item);
    if (tab == 'specials') openSpecialForm(item);
    if (tab == 'holidays') openHolidayForm(item);
    if (tab == 'overtime') openOvertimeForm(item);
  }

  String get currentLabel {
    return switch (tab) {
      'timetables' => 'Jam Kerja',
      'shifts' => 'Shift',
      'assignments' => 'Assignment',
      'specials' => 'Jadwal Khusus',
      'holidays' => 'Libur',
      'overtime' => 'Lembur',
      _ => 'Jadwal',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Schedules'), actions: [IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
      body: FutureBuilder<ScheduleBundle>(
        future: future,
        builder: (context, snapshot) {
          final bundle = snapshot.data ?? const ScheduleBundle.empty();
          final rows = selectedRows(bundle);

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              MessageCard(
                title: 'Schedules Center',
                message: 'Jam kerja: ${bundle.timetables.length} • Shift: ${bundle.shifts.length} • Assignment: ${bundle.assignments.length} • Khusus: ${bundle.specials.length} • Libur: ${bundle.holidays.length}',
                icon: Icons.calendar_month_rounded,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip('timetables', 'Jam Kerja'),
                  _chip('shifts', 'Shift'),
                  _chip('assignments', 'Assignment'),
                  _chip('specials', 'Khusus'),
                  _chip('holidays', 'Libur'),
                  _chip('overtime', 'Lembur'),
                ],
              ),
              const SizedBox(height: 12),
              TextField(onChanged: (value) => setState(() => query = value), decoration: const InputDecoration(labelText: 'Cari jadwal', prefixIcon: Icon(Icons.search_rounded))),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: () => openCurrentForm(bundle), icon: const Icon(Icons.add_rounded), label: Text('Tambah $currentLabel')),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                MessageCard(title: 'Gagal memuat jadwal', message: snapshot.error.toString(), icon: Icons.error_outline_rounded)
              else if (rows.isEmpty)
                MessageCard(title: 'Belum ada data', message: '$currentLabel akan tampil di sini.', icon: Icons.event_busy_rounded)
              else
                ...rows.map((item) => Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Icon(item.icon)),
                        title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text(item.subtitle),
                        isThreeLine: item.subtitle.contains('\n'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => openCurrentForm(bundle, item),
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }

  ChoiceChip _chip(String value, String label) {
    return ChoiceChip(label: Text(label), selected: tab == value, onSelected: (_) => setState(() => tab = value));
  }
}

class ScheduleBundle {
  final List<ScheduleItem> timetables;
  final List<ScheduleItem> shifts;
  final List<ScheduleItem> assignments;
  final List<ScheduleItem> specials;
  final List<ScheduleItem> holidays;
  final List<ScheduleItem> overtime;
  final List<ScheduleItem> users;

  const ScheduleBundle({required this.timetables, required this.shifts, required this.assignments, required this.specials, required this.holidays, required this.overtime, required this.users});
  const ScheduleBundle.empty() : timetables = const [], shifts = const [], assignments = const [], specials = const [], holidays = const [], overtime = const [], users = const [];

  ScheduleItem? find(List<ScheduleItem> items, String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }
}

class ScheduleItem {
  final String id;
  final String type;
  final Map<String, dynamic> data;

  const ScheduleItem({required this.id, required this.type, required this.data});

  String get title => _read(data, const ['name', 'title', 'shift_name', 'employee_name', 'nama_lengkap', 'display_name']).ifEmpty(id);
  String get date => _read(data, const ['date', 'tanggal', 'start_date']);
  String get startTime => _read(data, const ['start_time', 'jam_masuk', 'time_in']);
  String get endTime => _read(data, const ['end_time', 'jam_pulang', 'time_out']);
  String get rawText => data.values.join(' ');
  String get subtitle {
    if (type == 'assignment') return '${_read(data, const ['employee_name', 'uid', 'user_id'])}\n${_read(data, const ['timetable_name'])} • ${_read(data, const ['shift_name'])}';
    if (date.isNotEmpty) return '$date • ${startTime.ifEmpty('-')} - ${endTime.ifEmpty('-')}';
    return '${startTime.ifEmpty('-')} - ${endTime.ifEmpty('-')}';
  }

  IconData get icon {
    if (type == 'timetable') return Icons.access_time_rounded;
    if (type == 'shift') return Icons.work_history_rounded;
    if (type == 'assignment') return Icons.assignment_ind_rounded;
    if (type == 'special') return Icons.event_repeat_rounded;
    if (type == 'holiday') return Icons.beach_access_rounded;
    if (type == 'overtime') return Icons.more_time_rounded;
    return Icons.event_rounded;
  }
}

List<ScheduleItem> _items(Object? value, String type) {
  final data = _asMap(value) ?? const <String, dynamic>{};
  final rows = data.entries.map((entry) => ScheduleItem(id: entry.key, type: type, data: _asMap(entry.value) ?? const <String, dynamic>{})).toList();
  rows.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return rows;
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

String _date(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
