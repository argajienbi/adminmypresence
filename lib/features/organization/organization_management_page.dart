import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../shared/message_card.dart';

class OrganizationManagementPage extends StatelessWidget {
  final AdminSession session;

  const OrganizationManagementPage({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final modules = [
      _OrgModule('Area', 'areas/${session.companyId}', Icons.map_rounded, ['name', 'description', 'status']),
      _OrgModule('Kantor', 'offices/${session.companyId}', Icons.business_rounded, ['name', 'address', 'latitude', 'longitude', 'radius_meter', 'status']),
      _OrgModule('Departemen', 'departments/${session.companyId}', Icons.apartment_rounded, ['name', 'description', 'status']),
      _OrgModule('Sub Departemen', 'sub_departments/${session.companyId}', Icons.account_tree_rounded, ['name', 'department_id', 'description', 'status']),
      _OrgModule('Grup Karyawan', 'employee_groups/${session.companyId}', Icons.groups_rounded, ['name', 'description', 'status']),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Organisasi')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const MessageCard(
            title: 'Manajemen Organisasi',
            message: 'Port dari admin_web untuk mengatur area, kantor, departemen, sub departemen, dan grup karyawan.',
            icon: Icons.account_tree_rounded,
          ),
          const SizedBox(height: 12),
          ...modules.map((module) => Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(module.icon)),
                  title: Text(module.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text(module.path),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrganizationModulePage(session: session, module: module))),
                ),
              )),
        ],
      ),
    );
  }
}

class OrganizationModulePage extends StatefulWidget {
  final AdminSession session;
  final _OrgModule module;

  const OrganizationModulePage({super.key, required this.session, required this.module});

  @override
  State<OrganizationModulePage> createState() => _OrganizationModulePageState();
}

class _OrganizationModulePageState extends State<OrganizationModulePage> {
  late Future<List<_OrgRecord>> future;
  String query = '';

  @override
  void initState() {
    super.initState();
    future = loadRecords();
  }

  void refresh() => setState(() => future = loadRecords());

  Future<List<_OrgRecord>> loadRecords() async {
    final snap = await FirebaseDatabase.instance.ref(widget.module.path).get();
    final data = _asMap(snap.value) ?? const <String, dynamic>{};
    final rows = <_OrgRecord>[];
    for (final entry in data.entries) {
      final item = _asMap(entry.value) ?? const <String, dynamic>{};
      rows.add(_OrgRecord(id: entry.key, data: item));
    }
    rows.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return rows;
  }

  List<_OrgRecord> filter(List<_OrgRecord> rows) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows.where((row) => row.data.values.join(' ').toLowerCase().contains(q)).toList();
  }

  Future<void> openForm([_OrgRecord? record]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _OrgFormSheet(session: widget.session, module: widget.module, record: record),
    );
    if (!mounted) return;
    if (saved == true) refresh();
  }

  Future<void> setActive(_OrgRecord record, bool active) async {
    await FirebaseDatabase.instance.ref('${widget.module.path}/${record.id}').update({
      'active': active,
      'status': active ? 'active' : 'inactive',
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'updated_by': widget.session.uid,
    });
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.module.title), actions: [IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => openForm(), icon: const Icon(Icons.add_rounded), label: const Text('Tambah')),
      body: FutureBuilder<List<_OrgRecord>>(
        future: future,
        builder: (context, snapshot) {
          final rows = filter(snapshot.data ?? const <_OrgRecord>[]);
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
                        trailing: Switch(value: record.active, onChanged: (value) => setActive(record, value)),
                        onTap: () => openForm(record),
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }
}

class _OrgFormSheet extends StatefulWidget {
  final AdminSession session;
  final _OrgModule module;
  final _OrgRecord? record;

  const _OrgFormSheet({required this.session, required this.module, this.record});

  @override
  State<_OrgFormSheet> createState() => _OrgFormSheetState();
}

class _OrgFormSheetState extends State<_OrgFormSheet> {
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
    final name = controllers['name']?.text.trim() ?? '';
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nama wajib diisi.')));
      return;
    }

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

class _OrgModule {
  final String title;
  final String path;
  final IconData icon;
  final List<String> fields;

  const _OrgModule(this.title, this.path, this.icon, this.fields);
}

class _OrgRecord {
  final String id;
  final Map<String, dynamic> data;

  const _OrgRecord({required this.id, required this.data});

  String get title => _read(data, const ['name', 'nama', 'office_name', 'department_name', 'group_name']).ifEmpty(id);
  String get subtitle => _read(data, const ['address', 'alamat', 'description', 'status']).ifEmpty(data.entries.take(3).map((e) => '${e.key}: ${e.value}').join(' • '));
  bool get active => data['active'] != false && data['status']?.toString().toLowerCase() != 'inactive';
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
  if (field == 'radius_meter') return '100';
  return '';
}

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
