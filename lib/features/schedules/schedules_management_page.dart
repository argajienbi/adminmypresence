import 'dart:io';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../services/schedule_resolver.dart';
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
  String diagnosticUid = '';
  String diagnosticDate = _date(DateTime.now());
  ScheduleResolveResult? diagnosticResult;
  bool diagnosticLoading = false;
  bool holidaySyncing = false;

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
      db.ref('employee_groups/$companyId').get(),
    ]);

    return ScheduleBundle(
      timetables: _items(results[0].value, 'timetable'),
      shifts: _items(results[1].value, 'shift'),
      assignments: _items(results[2].value, 'assignment'),
      specials: _items(results[3].value, 'special'),
      holidays: _items(results[4].value, 'holiday'),
      overtime: _items(results[5].value, 'overtime'),
      users: _items(results[6].value, 'user'),
      groups: _items(results[7].value, 'group'),
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
      'diagnostic' => const <ScheduleItem>[],
      _ => bundle.timetables,
    };
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return source;
    return source.where((row) => '${row.title} ${row.subtitle} ${row.rawText}'.toLowerCase().contains(q)).toList();
  }

  Future<void> openTimetableForm([ScheduleItem? item]) async {
    final name = TextEditingController(text: item?.title == item?.id ? '' : item?.title ?? '');
    final start = TextEditingController(text: item == null ? '08:00' : item.workStart.ifEmpty('08:00'));
    final end = TextEditingController(text: item == null ? '17:00' : item.workEnd.ifEmpty('17:00'));
    final checkInStart = TextEditingController(text: _read(item?.data ?? const {}, const ['check_in_start']).ifEmpty(start.text));
    final checkInEnd = TextEditingController(text: _read(item?.data ?? const {}, const ['check_in_end']).ifEmpty(start.text));
    final checkOutStart = TextEditingController(text: _read(item?.data ?? const {}, const ['check_out_start']).ifEmpty(end.text));
    final checkOutEnd = TextEditingController(text: _read(item?.data ?? const {}, const ['check_out_end']).ifEmpty(end.text));
    final late = TextEditingController(text: _read(item?.data ?? const {}, const ['late_tolerance_minute', 'late_tolerance_minutes']).ifEmpty('15'));
    final early = TextEditingController(text: _read(item?.data ?? const {}, const ['early_out_tolerance_minute', 'early_out_tolerance_minutes']).ifEmpty('0'));

    final ok = await _formSheet(
      title: item == null ? 'Tambah Jam Kerja' : 'Edit Jam Kerja',
      children: [
        _field(name, 'Nama jam kerja'),
        _field(start, 'Work start HH:mm'),
        _field(end, 'Work end HH:mm'),
        _field(checkInStart, 'Check-in start HH:mm'),
        _field(checkInEnd, 'Check-in end HH:mm'),
        _field(checkOutStart, 'Check-out start HH:mm'),
        _field(checkOutEnd, 'Check-out end HH:mm'),
        _field(late, 'Toleransi terlambat menit', number: true),
        _field(early, 'Toleransi pulang awal menit', number: true),
      ],
    );

    if (ok == true && name.text.trim().isNotEmpty) {
      final id = item?.id ?? FirebaseDatabase.instance.ref('timetables/${widget.session.companyId}').push().key!;
      await _save('timetables/${widget.session.companyId}/$id', item == null ? 'create_timetable' : 'update_timetable', id, {
        'id': id,
        'timetable_id': id,
        'name': name.text.trim(),
        'title': name.text.trim(),
        'work_start': start.text.trim(),
        'work_end': end.text.trim(),
        'start_time': start.text.trim(),
        'end_time': end.text.trim(),
        'check_in_start': checkInStart.text.trim(),
        'check_in_end': checkInEnd.text.trim(),
        'check_out_start': checkOutStart.text.trim(),
        'check_out_end': checkOutEnd.text.trim(),
        'late_tolerance_minute': int.tryParse(late.text.trim()) ?? 15,
        'late_tolerance_minutes': int.tryParse(late.text.trim()) ?? 15,
        'early_out_tolerance_minute': int.tryParse(early.text.trim()) ?? 0,
        'crosses_midnight': false,
        'status': 'active',
        'active': true,
      });
    }
  }

  Future<void> openShiftForm(ScheduleBundle bundle, [ScheduleItem? item]) async {
    final name = TextEditingController(text: item?.title == item?.id ? '' : item?.title ?? '');
    final dayActive = <String, bool>{};
    final dayTimetable = <String, String>{};
    for (final day in _days) {
      final days = _asMap(item == null ? null : item.data['days']) ?? const <String, dynamic>{};
      final data = _asMap(days[day.key]) ?? const <String, dynamic>{};
      dayActive[day.key] = _bool(data['active'], day.defaultActive);
      dayTimetable[day.key] = _read(data, const ['timetable_id']);
    }

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(item == null ? 'Tambah Shift' : 'Edit Shift', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  _field(name, 'Nama shift'),
                  const SizedBox(height: 10),
                  ..._days.map((day) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SwitchListTile(
                              value: dayActive[day.key] ?? false,
                              title: Text(day.label),
                              onChanged: (value) => setSheetState(() => dayActive[day.key] = value),
                            ),
                            _dropdown('Timetable ${day.label}', bundle.timetables, dayTimetable[day.key] ?? '', (value) => setSheetState(() => dayTimetable[day.key] = value)),
                          ],
                        ),
                      )),
                  FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Simpan')),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (ok == true && name.text.trim().isNotEmpty) {
      final id = item?.id ?? FirebaseDatabase.instance.ref('shifts/${widget.session.companyId}').push().key!;
      await _save('shifts/${widget.session.companyId}/$id', item == null ? 'create_shift' : 'update_shift', id, {
        'id': id,
        'shift_id': id,
        'name': name.text.trim(),
        'shift_name': name.text.trim(),
        'days': {
          for (final day in _days)
            day.key: {
              'active': dayActive[day.key] ?? false,
              'timetable_id': dayTimetable[day.key] ?? '',
            },
        },
        'status': 'active',
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

  Future<void> openSpecialForm(ScheduleBundle bundle, [ScheduleItem? item]) async {
    final title = TextEditingController(text: item?.title == item?.id ? '' : item?.title ?? '');
    final date = TextEditingController(text: item == null ? _date(DateTime.now()) : item.date.ifEmpty(_date(DateTime.now())));
    String type = _read(item?.data ?? const {}, const ['type']).ifEmpty('user');
    String targetId = _read(item?.data ?? const {}, const ['target_id']);
    String shiftId = _read(item?.data ?? const {}, const ['shift_id']);

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) {
          final targets = type == 'group' ? bundle.groups : bundle.users;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(item == null ? 'Tambah Jadwal Khusus' : 'Edit Jadwal Khusus', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 12),
                    _field(title, 'Nama jadwal'),
                    const SizedBox(height: 10),
                    _field(date, 'Tanggal YYYY-MM-DD'),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: type,
                      decoration: const InputDecoration(labelText: 'Target type'),
                      items: const [DropdownMenuItem(value: 'user', child: Text('User')), DropdownMenuItem(value: 'group', child: Text('Group'))],
                      onChanged: (value) => setSheetState(() {
                        type = value ?? 'user';
                        targetId = '';
                      }),
                    ),
                    const SizedBox(height: 10),
                    _dropdown(type == 'group' ? 'Grup' : 'Karyawan', targets, targetId, (value) => setSheetState(() => targetId = value)),
                    const SizedBox(height: 10),
                    _dropdown('Shift', bundle.shifts, shiftId, (value) => setSheetState(() => shiftId = value)),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Simpan')),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (ok == true && title.text.trim().isNotEmpty && targetId.isNotEmpty) {
      final id = item?.id ?? FirebaseDatabase.instance.ref('schedule_specials/${widget.session.companyId}').push().key!;
      final target = bundle.find(type == 'group' ? bundle.groups : bundle.users, targetId);
      final shift = bundle.find(bundle.shifts, shiftId);
      await _save('schedule_specials/${widget.session.companyId}/$id', item == null ? 'create_special_schedule' : 'update_special_schedule', id, {
        'id': id,
        'title': title.text.trim(),
        'name': title.text.trim(),
        'date': date.text.trim(),
        'type': type,
        'target_id': targetId,
        'target_name': target?.title ?? '',
        'shift_id': shiftId,
        'shift_name': shift?.title ?? '',
        'status': 'active',
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
    String type = _read(item?.data ?? const {}, const ['type']).ifEmpty('user');
    String targetId = _read(item?.data ?? const {}, const ['target_id', 'uid', 'user_id', 'employee_id']);
    String shiftId = _read(item?.data ?? const {}, const ['shift_id']);
    final startDate = TextEditingController(text: _read(item?.data ?? const {}, const ['start_date']).ifEmpty(_date(DateTime.now())));
    final endDate = TextEditingController(text: _read(item?.data ?? const {}, const ['end_date']));

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) {
          final targets = type == 'group' ? bundle.groups : bundle.users;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(item == null ? 'Assign Jadwal' : 'Edit Assignment', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: type,
                      decoration: const InputDecoration(labelText: 'Target type'),
                      items: const [DropdownMenuItem(value: 'user', child: Text('User')), DropdownMenuItem(value: 'group', child: Text('Group'))],
                      onChanged: (value) => setSheetState(() {
                        type = value ?? 'user';
                        targetId = '';
                      }),
                    ),
                    const SizedBox(height: 10),
                    _dropdown(type == 'group' ? 'Grup' : 'Karyawan', targets, targetId, (value) => setSheetState(() => targetId = value)),
                    const SizedBox(height: 10),
                    _dropdown('Shift', bundle.shifts, shiftId, (value) => setSheetState(() => shiftId = value)),
                    const SizedBox(height: 10),
                    _field(startDate, 'Start date YYYY-MM-DD'),
                    const SizedBox(height: 10),
                    _field(endDate, 'End date YYYY-MM-DD (opsional)'),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Simpan')),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (ok == true && targetId.isNotEmpty && shiftId.isNotEmpty) {
      final id = item?.id ?? FirebaseDatabase.instance.ref('schedule_assignments/${widget.session.companyId}').push().key!;
      final target = bundle.find(type == 'group' ? bundle.groups : bundle.users, targetId);
      final shift = bundle.find(bundle.shifts, shiftId);
      await _save('schedule_assignments/${widget.session.companyId}/$id', item == null ? 'create_schedule_assignment' : 'update_schedule_assignment', id, {
        'id': id,
        'assignment_id': id,
        'type': type,
        'target_id': targetId,
        'target_name': target?.title ?? '',
        'shift_id': shiftId,
        'shift_name': shift?.title ?? '',
        'start_date': startDate.text.trim(),
        'end_date': endDate.text.trim(),
        'uid': type == 'user' ? targetId : '',
        'user_id': type == 'user' ? targetId : '',
        'employee_name': type == 'user' ? target?.title ?? '' : '',
        'status': 'active',
        'active': true,
      });
    }
  }

  Future<void> runDiagnostic() async {
    if (diagnosticUid.isEmpty || diagnosticDate.trim().isEmpty) return;
    setState(() {
      diagnosticLoading = true;
      diagnosticResult = null;
    });
    try {
      final result = await ScheduleResolver().resolveScheduleForUser(companyId: widget.session.companyId, uid: diagnosticUid, date: diagnosticDate.trim());
      if (mounted) setState(() => diagnosticResult = result);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => diagnosticLoading = false);
    }
  }

  Future<void> syncGoogleCalendarHolidays() async {
    if (holidaySyncing) return;
    setState(() => holidaySyncing = true);
    try {
      final events = await _fetchIndonesianHolidayEvents();
      final companyId = widget.session.companyId;
      final now = DateTime.now().millisecondsSinceEpoch;
      final updates = <String, dynamic>{};
      for (final event in events) {
        if (event.date.compareTo(_date(DateTime.now().subtract(const Duration(days: 30)))) < 0) continue;
        updates['holidays/$companyId/${event.date}'] = {
          'id': event.date,
          'date': event.date,
          'title': event.title,
          'name': event.title,
          'source': 'google_calendar',
          'active': true,
          'updated_at': now,
          'updated_by': widget.session.uid,
        };
      }
      if (updates.isNotEmpty) await FirebaseDatabase.instance.ref().update(updates);
      await FirebaseDatabase.instance.ref('schedule_change_logs/$companyId').push().set({
        'action': 'sync_google_calendar_holidays',
        'count': updates.length,
        'actor_uid': widget.session.uid,
        'actor_email': widget.session.email,
        'created_at': now,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync hari libur selesai: ${updates.length} event.')));
      refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => holidaySyncing = false);
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
    if (tab == 'shifts') openShiftForm(bundle, item);
    if (tab == 'assignments') openAssignmentForm(bundle, item);
    if (tab == 'specials') openSpecialForm(bundle, item);
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
      'diagnostic' => 'Diagnostic',
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
                  _chip('diagnostic', 'Diagnostic'),
                ],
              ),
              const SizedBox(height: 12),
              if (tab == 'diagnostic')
                _diagnosticPanel(bundle)
              else ...[
                TextField(onChanged: (value) => setState(() => query = value), decoration: const InputDecoration(labelText: 'Cari jadwal', prefixIcon: Icon(Icons.search_rounded))),
                const SizedBox(height: 12),
                if (tab == 'holidays') ...[
                  FilledButton.icon(onPressed: holidaySyncing ? null : syncGoogleCalendarHolidays, icon: const Icon(Icons.event_available_rounded), label: Text(holidaySyncing ? 'Sync...' : 'Sync Libur Google Calendar')),
                  const SizedBox(height: 8),
                ],
                FilledButton.icon(onPressed: () => openCurrentForm(bundle), icon: const Icon(Icons.add_rounded), label: Text('Tambah $currentLabel')),
              ],
              const SizedBox(height: 12),
              if (tab == 'diagnostic')
                const SizedBox.shrink()
              else if (snapshot.connectionState == ConnectionState.waiting)
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

  Widget _diagnosticPanel(ScheduleBundle bundle) {
    final selected = bundle.find(bundle.users, diagnosticUid);
    final result = diagnosticResult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dropdown('Karyawan', bundle.users, diagnosticUid, (value) => setState(() => diagnosticUid = value)),
        const SizedBox(height: 10),
        TextFormField(
          initialValue: diagnosticDate,
          decoration: const InputDecoration(labelText: 'Tanggal YYYY-MM-DD'),
          onChanged: (value) => diagnosticDate = value,
        ),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: diagnosticLoading || diagnosticUid.isEmpty ? null : runDiagnostic, icon: const Icon(Icons.rule_rounded), label: Text(diagnosticLoading ? 'Mengecek...' : 'Cek Jadwal Karyawan')),
        const SizedBox(height: 12),
        if (selected != null) MessageCard(title: selected.title, message: selected.subtitle, icon: Icons.person_rounded),
        if (result != null)
          MessageCard(
            title: result.todayActive ? 'Siap digunakan untuk absen' : (result.scheduleReady ? 'Jadwal ditemukan, hari tidak aktif' : 'Belum bisa digunakan untuk absen'),
            message: 'Sumber: ${result.scheduleSource}\nShift: ${result.shiftName ?? '-'}\nTimetable: ${result.timetableName ?? '-'}\nJam kerja: ${result.workStart ?? '-'} - ${result.workEnd ?? '-'}\nCheck-in: ${result.checkInStart ?? '-'} - ${result.checkInEnd ?? '-'}\nCheck-out: ${result.checkOutStart ?? '-'} - ${result.checkOutEnd ?? '-'}',
            icon: result.todayActive ? Icons.check_circle_rounded : Icons.info_outline_rounded,
          ),
      ],
    );
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
  final List<ScheduleItem> groups;

  const ScheduleBundle({required this.timetables, required this.shifts, required this.assignments, required this.specials, required this.holidays, required this.overtime, required this.users, required this.groups});
  const ScheduleBundle.empty() : timetables = const [], shifts = const [], assignments = const [], specials = const [], holidays = const [], overtime = const [], users = const [], groups = const [];

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

  String get title => _read(data, const ['name', 'title', 'shift_name', 'target_name', 'employee_name', 'nama_lengkap', 'display_name']).ifEmpty(id);
  String get date => _read(data, const ['date', 'tanggal', 'start_date']);
  String get workStart => _read(data, const ['work_start', 'start_time', 'jam_masuk', 'time_in']);
  String get workEnd => _read(data, const ['work_end', 'end_time', 'jam_pulang', 'time_out']);
  String get startTime => workStart;
  String get endTime => workEnd;
  String get rawText => data.values.join(' ');
  String get subtitle {
    if (type == 'assignment') return '${_read(data, const ['target_name', 'employee_name', 'uid', 'user_id'])}\n${_read(data, const ['type']).ifEmpty('user')} | ${_read(data, const ['shift_name'])} | ${_read(data, const ['start_date'])}';
    if (type == 'special') return '$date | ${_read(data, const ['target_name', 'target_id'])} | ${_read(data, const ['shift_name', 'shift_id'])}';
    if (type == 'shift') {
      final days = _asMap(data['days']) ?? const <String, dynamic>{};
      return _days.map((day) {
        final dayData = _asMap(days[day.key]) ?? const <String, dynamic>{};
        return _bool(dayData['active'], false) ? '${day.label}: ${_read(dayData, const ['timetable_id']).ifEmpty('-')}' : '';
      }).where((text) => text.isNotEmpty).join('\n').ifEmpty('Belum ada day pattern');
    }
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

const _days = [
  _ScheduleDay('sunday', 'Minggu', false),
  _ScheduleDay('monday', 'Senin', true),
  _ScheduleDay('tuesday', 'Selasa', true),
  _ScheduleDay('wednesday', 'Rabu', true),
  _ScheduleDay('thursday', 'Kamis', true),
  _ScheduleDay('friday', 'Jumat', true),
  _ScheduleDay('saturday', 'Sabtu', false),
];

class _ScheduleDay {
  const _ScheduleDay(this.key, this.label, this.defaultActive);

  final String key;
  final String label;
  final bool defaultActive;
}

bool _bool(Object? value, bool fallback) {
  if (value is bool) return value;
  if (value == null) return fallback;
  final text = value.toString().toLowerCase();
  if (text == 'true' || text == '1' || text == 'yes' || text == 'active') return true;
  if (text == 'false' || text == '0' || text == 'no' || text == 'inactive') return false;
  return fallback;
}

Future<List<_HolidayEvent>> _fetchIndonesianHolidayEvents() async {
  const url = 'https://calendar.google.com/calendar/ical/id.indonesian%23holiday%40group.v.calendar.google.com/public/basic.ics';
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Google Calendar HTTP ${response.statusCode}');
    final content = await response.transform(systemEncoding.decoder).join();
    return _parseIcsHolidays(content);
  } finally {
    client.close(force: true);
  }
}

List<_HolidayEvent> _parseIcsHolidays(String content) {
  final normalized = content.replaceAll('\r\n ', '').replaceAll('\n ', '');
  final events = <_HolidayEvent>[];
  for (final block in normalized.split('BEGIN:VEVENT').skip(1)) {
    final dateMatch = RegExp(r'DTSTART(?:;VALUE=DATE)?:([0-9]{8})').firstMatch(block);
    final summaryMatch = RegExp(r'SUMMARY:(.+)').firstMatch(block);
    if (dateMatch == null || summaryMatch == null) continue;
    final raw = dateMatch.group(1)!;
    final title = summaryMatch.group(1)!.trim().replaceAll(r'\,', ',');
    events.add(_HolidayEvent(date: '${raw.substring(0, 4)}-${raw.substring(4, 6)}-${raw.substring(6, 8)}', title: title));
  }
  events.sort((a, b) => a.date.compareTo(b.date));
  return events;
}

class _HolidayEvent {
  const _HolidayEvent({required this.date, required this.title});

  final String date;
  final String title;
}

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
