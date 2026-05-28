import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../shared/message_card.dart';

class ScheduleManagementPage extends StatelessWidget {
  final AdminSession session;

  const ScheduleManagementPage({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final modules = [
      _ScheduleModule('Jam Kerja', 'timetables/${session.companyId}', Icons.schedule_rounded, ['name', 'start_time', 'end_time', 'late_tolerance_minutes', 'status']),
      _ScheduleModule('Shift', 'shifts/${session.companyId}', Icons.view_week_rounded, ['name', 'description', 'status']),
      _ScheduleModule('Terapkan Jadwal', 'schedule_assignments/${session.companyId}', Icons.assignment_ind_rounded, ['name', 'employee_id', 'timetable_id', 'shift_id', 'start_date', 'end_date', 'status']),
      _ScheduleModule('Jadwal Khusus', 'schedule_specials/${session.companyId}', Icons.event_repeat_rounded, ['name', 'date', 'employee_id', 'timetable_id', 'reason', 'status']),
      _ScheduleModule('Hari Libur', 'holidays/${session.companyId}', Icons.celebration_rounded, ['name', 'date', 'description', 'status']),
      _ScheduleModule('Jadwal Lembur', 'overtime_schedules/${session.companyId}', Icons.more_time_rounded, ['name', 'date', 'start_time', 'end_time', 'employee_ids', 'status']),
      _ScheduleModule('Change Log', 'schedule_change_logs/${session.companyId}', Icons.history_rounded, ['title', 'action', 'target_id', 'actor_email', 'created_at']),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Manajemen Jadwal')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const MessageCard(
            title: 'Manajemen Jadwal',
            message: 'Port dari admin_web untuk jam kerja, shift, assignment, jadwal khusus, holiday, lembur, dan log perubahan.',
            icon: Icons.event_note_rounded,
          ),
          const SizedBox(height: 12),
          ...modules.map((module) => Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(module.icon)),
                  title: Text(module.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text(module.path),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScheduleModulePage(session: session, module: module))),
                ),
              )),
        ],
      ),
    );
  }
}

class ScheduleModulePage extends StatefulWidget {
  final AdminSession session;
  final _ScheduleModule module;

  const ScheduleModulePage({super.key, required this.session, required this.module});

  @override
  State<ScheduleModulePage> createState() => _ScheduleModulePageState();
}

class _ScheduleModulePageState extends State<ScheduleModulePage> {
  late Future<List<_ScheduleRecord>> future;
  String query = '';

  @override
  void initState() {
    super.initState();
    future = loadRecords();
  }

  void refresh() => setState(() => future = loadRecords());

  Future<List<_ScheduleRecord>> loadRecords() async {
    final snap = await FirebaseDatabase.instance.ref(widget.module.path).get();
    final data = _asMap(snap.value) ?? const <String, dynamic>{};
    final rows = <_ScheduleRecord>[];
    for (final entry in data.entries) {
      final item = _asMap(entry.value) ?? const <String, dynamic>{};
      rows.add(_ScheduleRecord(id: entry.key, data: item));
    }
    rows.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    return rows;
  }

  List<_ScheduleRecord> filter(List<_ScheduleRecord> rows) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows.where((row) => row.data.values.join(' ').toLowerCase().contains(q)).toList();
  }

  Future<void> openForm([_ScheduleRecord? record]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ScheduleFormSheet(session: widget.session, module: widget.module, record: record),
    );
    if (!mounted) return;
    if (saved == true) refresh();
  }

  Future<void> setActive(_ScheduleRecord record, bool active) async {
    await FirebaseDatabase.instance.ref('${widget.module.path}/${record.id}').update({
      'active': active,
      'status': active ? 'active' : 'inactive',
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'updated_by': widget.session.uid,
    });
    await _writeScheduleLog(widget.session, 'toggle_${widget.module.title}', widget.module.path, record.id);
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = widget.module.title != 'Change Log';
    return Scaffold(
      appBar: AppBar(title: Text(widget.module.title), actions: [IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
      floatingActionButton: canCreate ? FloatingActionButton.extended(onPressed: () => openForm(), icon: const Icon(Icons.add_rounded), label: const Text('Tambah')) : null,
      body: FutureBuilder<List<_ScheduleRecord>>(
        future: future,
        builder: (context, snapshot) {
          final rows = filter(snapshot.data ?? const <_ScheduleRecord>[]);
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              MessageCard(title: widget.module.title, message: 'Kelola data ${widget.module.title}.', icon: widget.module.icon),
              const SizedBox(height: 12),
              TextField(onChanged: (value) => setState(() => query = value), decoration: const InputDecoration(labelText: 'Cari data', prefixIcon: Icon(Icons.search_rounded))),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                MessageCard(title: 'Gagal memuat data', message: snapshot.error.toString(), icon: Icons.error_outline_rounded)
              else if (rows.isEmpty)
                const MessageCard(title: 'Belum ada data', message: 'Tambahkan data baru untuk modul ini.', icon: Icons.inbox_outlined)
              else
                ...rows.map((record) => Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Icon(widget.module.icon)),
                        title: Text(record.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text(record.subtitle),
                        trailing: canCreate ? Switch(value: record.active, onChanged: (value) => setActive(record, value)) : null,
                        onTap: canCreate ? () => openForm(record) : null,
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }
}

class _ScheduleFormSheet extends StatefulWidget {
  final AdminSession session;
  final _ScheduleModule module;
  final _ScheduleRecord? record;

  const _ScheduleFormSheet({required this.session, required this.module, this.record});

  @override
  State<_ScheduleFormSheet> createState() => _ScheduleFormSheetState();
}

class _ScheduleFormSheetState extends State<_ScheduleFormSheet> {
  late final Map<String, TextEditingController> controllers = {
    for (final field in widget.module.fields) field: TextEditingController(text: widget.record?.data[field]?.toString() ?? _defaultValue(field)),
  };
  bool saving = false;

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      final db = FirebaseDatabase.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = widget.record?.id ?? db.ref(widget.module.path).push().key!;
      final payload = <String, dynamic>{
        '${widget.module.title.toLowerCase().replaceAll(' ', '_')}_id': id,
        'id': id,
        'company_id': widget.session.companyId,
        for (final entry in controllers.entries) entry.key: _coerce(entry.value.text),
        'updated_at': now,
        'updated_by': widget.session.uid,
        if (widget.record == null) 'created_at': now,
        if (widget.record == null) 'created_by': widget.session.uid,
      };
      if (payload['status'] == null || payload['status'].toString().isEmpty) payload['status'] = 'active';
      payload['active'] = payload['status'].toString().toLowerCase() != 'inactive';
      await db.ref('${widget.module.path}/$id').update(payload);
      await _writeScheduleLog(widget.session, widget.record == null ? 'create_${widget.module.title}' : 'update_${widget.module.title}', widget.module.path, id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.record == null ? 'Tambah ${widget.module.title}' : 'Edit ${widget.module.title}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            ...controllers.entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(controller: entry.value, decoration: InputDecoration(labelText: entry.key)),
                )),
            FilledButton.icon(onPressed: saving ? null : save, icon: const Icon(Icons.save_rounded), label: Text(saving ? 'Menyimpan...' : 'Simpan')),
          ],
        ),
      ),
    );
  }
}

class _ScheduleModule {
  final String title;
  final String path;
  final IconData icon;
  final List<String> fields;

  const _ScheduleModule(this.title, this.path, this.icon, this.fields);
}

class _ScheduleRecord {
  final String id;
  final Map<String, dynamic> data;

  const _ScheduleRecord({required this.id, required this.data});

  String get title => _read(data, const ['name', 'title', 'date', 'employee_id', 'action']).ifEmpty(id);
  String get subtitle => _read(data, const ['description', 'start_time', 'date', 'status', 'actor_email']).ifEmpty(data.entries.take(3).map((e) => '${e.key}: ${e.value}').join(' • '));
  bool get active => data['active'] != false && data['status']?.toString().toLowerCase() != 'inactive';
  String get sortKey => '${data['date'] ?? ''}${data['created_at'] ?? ''}${data['updated_at'] ?? ''}$id';
}

Future<void> _writeScheduleLog(AdminSession session, String action, String path, String id) async {
  final ref = FirebaseDatabase.instance.ref('schedule_change_logs/${session.companyId}').push();
  await ref.set({
    'id': ref.key,
    'title': action,
    'action': action,
    'target_path': path,
    'target_id': id,
    'actor_uid': session.uid,
    'actor_email': session.email,
    'created_at': DateTime.now().millisecondsSinceEpoch,
  });
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

Object _coerce(String value) {
  final text = value.trim();
  if (text.toLowerCase() == 'true') return true;
  if (text.toLowerCase() == 'false') return false;
  final intValue = int.tryParse(text);
  if (intValue != null) return intValue;
  final doubleValue = double.tryParse(text);
  if (doubleValue != null) return doubleValue;
  return text;
}

String _defaultValue(String field) {
  if (field == 'status') return 'active';
  if (field == 'start_time') return '08:00';
  if (field == 'end_time') return '16:00';
  if (field == 'late_tolerance_minutes') return '15';
  return '';
}

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
