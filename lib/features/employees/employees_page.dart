import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../services/admin_service.dart';
import '../shared/message_card.dart';
import 'employee_detail_page.dart';

class EmployeesPage extends StatefulWidget {
  final AdminSession session;
  final AdminService service;

  const EmployeesPage({super.key, required this.session, required this.service});

  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  late Future<_EmployeeBundle> future;
  String query = '';
  String statusFilter = 'all';
  String roleFilter = 'employee';

  @override
  void initState() {
    super.initState();
    future = loadBundle();
  }

  void refresh() => setState(() => future = loadBundle());

  Future<_EmployeeBundle> loadBundle() async {
    final companyId = widget.session.companyId;
    final db = FirebaseDatabase.instance;
    final results = await Future.wait([
      db.ref('company_users/$companyId').get(),
      db.ref('offices/$companyId').get(),
      db.ref('departments/$companyId').get(),
      db.ref('sub_departments/$companyId').get(),
      db.ref('employee_groups/$companyId').get(),
      db.ref('timetables/$companyId').get(),
      db.ref('shifts/$companyId').get(),
    ]);

    final users = _asMap(results[0].value) ?? const <String, dynamic>{};
    final rows = users.entries.map((entry) => ManagedEmployee(id: entry.key, data: _asMap(entry.value) ?? const <String, dynamic>{})).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return _EmployeeBundle(
      employees: rows,
      offices: _options(results[1].value),
      departments: _options(results[2].value),
      subDepartments: _options(results[3].value),
      groups: _options(results[4].value),
      timetables: _options(results[5].value),
      shifts: _options(results[6].value),
    );
  }

  List<ManagedEmployee> filter(List<ManagedEmployee> rows) {
    final q = query.trim().toLowerCase();
    return rows.where((employee) {
      if (statusFilter == 'active' && !employee.active) return false;
      if (statusFilter == 'inactive' && employee.active) return false;
      if (roleFilter != 'all' && employee.role.toLowerCase() != roleFilter) return false;
      if (q.isEmpty) return true;
      final text = '${employee.name} ${employee.email} ${employee.nip} ${employee.phone} ${employee.jobTitle} ${employee.officeName} ${employee.departmentName} ${employee.groupName}'.toLowerCase();
      return text.contains(q);
    }).toList();
  }

  Future<void> openForm(_EmployeeBundle bundle, [ManagedEmployee? employee]) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EmployeeSheet(session: widget.session, service: widget.service, bundle: bundle, employee: employee),
    );
    if (ok == true) refresh();
  }

  Future<void> openDetail(ManagedEmployee employee) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EmployeeDetailPage(session: widget.session, employeeId: employee.id)));
    refresh();
  }

  Future<void> setActive(ManagedEmployee employee, bool active) async {
    await FirebaseDatabase.instance.ref('company_users/${widget.session.companyId}/${employee.id}').update({
      'active': active,
      'status': active ? 'active' : 'inactive',
      'status_akun': active ? 'active' : 'inactive',
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'updated_by': widget.session.uid,
    });
    await FirebaseDatabase.instance.ref('audit_logs/${widget.session.companyId}').push().set({
      'action': active ? 'activate_employee' : 'deactivate_employee',
      'target_id': employee.id,
      'actor_uid': widget.session.uid,
      'actor_email': widget.session.email,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<_EmployeeBundle>(
      future: future,
      builder: (context, snap) {
        final bundle = snap.data ?? const _EmployeeBundle.empty();
        final all = bundle.employees;
        final list = filter(all);
        final active = all.where((e) => e.active).length;
        final inactive = all.length - active;
        final admins = all.where((e) => e.role.toLowerCase().contains('admin') || e.role.toLowerCase().contains('owner')).length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          children: [
            Row(children: [Expanded(child: Text('Karyawan', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900))), IconButton.filledTonal(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _MiniStat('Total', all.length, Icons.people_rounded),
              _MiniStat('Aktif', active, Icons.verified_user_rounded),
              _MiniStat('Nonaktif', inactive, Icons.block_rounded),
              _MiniStat('Admin', admins, Icons.admin_panel_settings_rounded),
            ]),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: () => openForm(bundle), icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('Tambah Karyawan')),
            const SizedBox(height: 12),
            TextField(onChanged: (v) => setState(() => query = v), decoration: const InputDecoration(labelText: 'Cari nama, email, NIP, kantor, jabatan', prefixIcon: Icon(Icons.search_rounded))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: statusFilter,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Semua')),
                    DropdownMenuItem(value: 'active', child: Text('Aktif')),
                    DropdownMenuItem(value: 'inactive', child: Text('Nonaktif')),
                  ],
                  onChanged: (v) => setState(() => statusFilter = v ?? 'all'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: roleFilter,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: 'employee', child: Text('Employee')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'owner', child: Text('Owner')),
                    DropdownMenuItem(value: 'all', child: Text('Semua')),
                  ],
                  onChanged: (v) => setState(() => roleFilter = v ?? 'employee'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            if (snap.connectionState == ConnectionState.waiting)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (snap.hasError)
              MessageCard(title: 'Gagal memuat karyawan', message: snap.error.toString(), icon: Icons.error_outline_rounded)
            else if (list.isEmpty)
              const MessageCard(title: 'Belum ada karyawan', message: 'Karyawan akan tampil di sini.', icon: Icons.people_outline_rounded)
            else
              ...list.map((e) => Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text(e.name.isEmpty ? '?' : e.name.characters.first.toUpperCase())),
                      title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: Text('${e.email}\n${[e.nip, e.role, e.officeName, e.departmentName, e.groupName].where((v) => v.isNotEmpty).join(' • ')}'),
                      isThreeLine: true,
                      trailing: Switch(value: e.active, onChanged: (v) => setActive(e, v)),
                      onTap: () => openDetail(e),
                      onLongPress: () => openForm(bundle, e),
                    ),
                  )),
          ],
        );
      },
    );
  }
}

class _EmployeeSheet extends StatefulWidget {
  final AdminSession session;
  final AdminService service;
  final _EmployeeBundle bundle;
  final ManagedEmployee? employee;

  const _EmployeeSheet({required this.session, required this.service, required this.bundle, this.employee});

  @override
  State<_EmployeeSheet> createState() => _EmployeeSheetState();
}

class _EmployeeSheetState extends State<_EmployeeSheet> {
  late final TextEditingController name = TextEditingController(text: widget.employee?.name ?? '');
  late final TextEditingController email = TextEditingController(text: widget.employee?.email ?? '');
  final password = TextEditingController();
  late final TextEditingController nip = TextEditingController(text: widget.employee?.nip ?? '');
  late final TextEditingController phone = TextEditingController(text: widget.employee?.phone ?? '');
  late final TextEditingController job = TextEditingController(text: widget.employee?.jobTitle ?? '');
  late String role = widget.employee?.role.isNotEmpty == true ? widget.employee!.role : 'employee';
  late String officeId = widget.employee?.officeId ?? '';
  late String departmentId = widget.employee?.departmentId ?? '';
  late String subDepartmentId = widget.employee?.subDepartmentId ?? '';
  late String groupId = widget.employee?.groupId ?? '';
  late String timetableId = widget.employee?.timetableId ?? '';
  late String shiftId = widget.employee?.shiftId ?? '';
  late bool active = widget.employee?.active ?? true;
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    nip.dispose();
    phone.dispose();
    job.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty || email.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nama dan email wajib diisi.')));
      return;
    }

    setState(() => saving = true);
    try {
      final office = widget.bundle.optionById(widget.bundle.offices, officeId);
      final department = widget.bundle.optionById(widget.bundle.departments, departmentId);
      final subDepartment = widget.bundle.optionById(widget.bundle.subDepartments, subDepartmentId);
      final group = widget.bundle.optionById(widget.bundle.groups, groupId);
      final timetable = widget.bundle.optionById(widget.bundle.timetables, timetableId);
      final shift = widget.bundle.optionById(widget.bundle.shifts, shiftId);

      await widget.service.saveEmployee(
        widget.session,
        old: widget.employee?.toEmployeeRecord(),
        name: name.text,
        email: email.text,
        password: password.text,
        nip: nip.text,
        phone: phone.text,
        jobTitle: job.text,
        officeName: office?.name ?? '',
        groupName: group?.name ?? '',
        active: active,
      );

      final uid = widget.employee?.id ?? email.text.trim().replaceAll('.', '_').replaceAll('@', '_');
      await FirebaseDatabase.instance.ref('company_users/${widget.session.companyId}/$uid').update({
        'uid': uid,
        'company_id': widget.session.companyId,
        'display_name': name.text.trim(),
        'nama_lengkap': name.text.trim(),
        'email': email.text.trim(),
        'nip': nip.text.trim(),
        'phone': phone.text.trim(),
        'job_title': job.text.trim(),
        'jabatan': job.text.trim(),
        'role': role,
        'level': role,
        'office_id': officeId,
        'office_name': office?.name ?? '',
        'department_id': departmentId,
        'department_name': department?.name ?? '',
        'sub_department_id': subDepartmentId,
        'sub_department_name': subDepartment?.name ?? '',
        'employee_group_id': groupId,
        'group_id': groupId,
        'group_name': group?.name ?? '',
        'timetable_id': timetableId,
        'timetable_name': timetable?.name ?? '',
        'shift_id': shiftId,
        'shift_name': shift?.name ?? '',
        'active': active,
        'status': active ? 'active' : 'inactive',
        'status_akun': active ? 'active' : 'inactive',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'updated_by': widget.session.uid,
        if (widget.employee == null) 'created_at': DateTime.now().millisecondsSinceEpoch,
        if (widget.employee == null) 'created_by': widget.session.uid,
      });

      await FirebaseDatabase.instance.ref('audit_logs/${widget.session.companyId}').push().set({
        'action': widget.employee == null ? 'create_employee' : 'update_employee',
        'target_id': uid,
        'actor_uid': widget.session.uid,
        'actor_email': widget.session.email,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.employee != null;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(editing ? 'Edit Karyawan' : 'Tambah Karyawan', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            _field(name, 'Nama lengkap'),
            const SizedBox(height: 10),
            _field(email, 'Email login', readOnly: editing),
            if (!editing) ...[const SizedBox(height: 10), _field(password, 'Password awal', obscure: true)],
            const SizedBox(height: 10),
            _field(nip, 'NIP'),
            const SizedBox(height: 10),
            _field(phone, 'Nomor HP'),
            const SizedBox(height: 10),
            _field(job, 'Jabatan'),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: const [
                DropdownMenuItem(value: 'employee', child: Text('Employee')),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
                DropdownMenuItem(value: 'owner', child: Text('Owner')),
              ],
              onChanged: (v) => setState(() => role = v ?? 'employee'),
            ),
            const SizedBox(height: 10),
            _optionDropdown('Kantor', widget.bundle.offices, officeId, (v) => setState(() => officeId = v)),
            const SizedBox(height: 10),
            _optionDropdown('Departemen', widget.bundle.departments, departmentId, (v) => setState(() => departmentId = v)),
            const SizedBox(height: 10),
            _optionDropdown('Sub Departemen', widget.bundle.subDepartments, subDepartmentId, (v) => setState(() => subDepartmentId = v)),
            const SizedBox(height: 10),
            _optionDropdown('Grup Karyawan', widget.bundle.groups, groupId, (v) => setState(() => groupId = v)),
            const SizedBox(height: 10),
            _optionDropdown('Jam Kerja', widget.bundle.timetables, timetableId, (v) => setState(() => timetableId = v)),
            const SizedBox(height: 10),
            _optionDropdown('Shift', widget.bundle.shifts, shiftId, (v) => setState(() => shiftId = v)),
            SwitchListTile(value: active, onChanged: (v) => setState(() => active = v), title: const Text('Akun aktif')),
            FilledButton.icon(onPressed: saving ? null : save, icon: const Icon(Icons.save_rounded), label: Text(saving ? 'Menyimpan...' : 'Simpan')),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {bool readOnly = false, bool obscure = false}) => TextField(controller: c, readOnly: readOnly, obscureText: obscure, decoration: InputDecoration(labelText: label));

  Widget _optionDropdown(String label, List<_Option> options, String value, ValueChanged<String> onChanged) {
    final current = options.any((option) => option.id == value) ? value : '';
    return DropdownButtonFormField<String>(
      value: current,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem(value: '', child: Text('-')),
        ...options.map((option) => DropdownMenuItem(value: option.id, child: Text(option.name))),
      ],
      onChanged: (v) => onChanged(v ?? ''),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;

  const _MiniStat(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [CircleAvatar(child: Icon(icon)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$value', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)), Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)]))]),
        ),
      ),
    );
  }
}

class _EmployeeBundle {
  final List<ManagedEmployee> employees;
  final List<_Option> offices;
  final List<_Option> departments;
  final List<_Option> subDepartments;
  final List<_Option> groups;
  final List<_Option> timetables;
  final List<_Option> shifts;

  const _EmployeeBundle({required this.employees, required this.offices, required this.departments, required this.subDepartments, required this.groups, required this.timetables, required this.shifts});
  const _EmployeeBundle.empty() : employees = const [], offices = const [], departments = const [], subDepartments = const [], groups = const [], timetables = const [], shifts = const [];

  _Option? optionById(List<_Option> options, String id) {
    for (final option in options) {
      if (option.id == id) return option;
    }
    return null;
  }
}

class ManagedEmployee {
  final String id;
  final Map<String, dynamic> data;

  const ManagedEmployee({required this.id, required this.data});

  String get name => _read(data, const ['display_name', 'nama_lengkap', 'name']).ifEmpty(id);
  String get email => _read(data, const ['email']);
  String get nip => _read(data, const ['nip']);
  String get phone => _read(data, const ['phone', 'phone_number', 'nomor_hp']);
  String get jobTitle => _read(data, const ['job_title', 'jabatan', 'position']);
  String get role => _read(data, const ['role', 'level']).ifEmpty('employee');
  String get officeId => _read(data, const ['office_id', 'kantor_id']);
  String get officeName => _read(data, const ['office_name', 'kantor', 'nama_kantor']);
  String get departmentId => _read(data, const ['department_id']);
  String get departmentName => _read(data, const ['department_name', 'department']);
  String get subDepartmentId => _read(data, const ['sub_department_id']);
  String get groupId => _read(data, const ['employee_group_id', 'group_id']);
  String get groupName => _read(data, const ['group_name', 'employee_group_name']);
  String get timetableId => _read(data, const ['timetable_id']);
  String get shiftId => _read(data, const ['shift_id']);
  bool get active => data['active'] != false && data['status']?.toString().toLowerCase() != 'inactive' && data['status_akun']?.toString().toLowerCase() != 'inactive';

  EmployeeRecord toEmployeeRecord() {
    return EmployeeRecord(id: id, name: name, email: email, nip: nip, phone: phone, jobTitle: jobTitle, officeName: officeName, groupName: groupName, active: active);
  }
}

class _Option {
  final String id;
  final String name;

  const _Option(this.id, this.name);
}

List<_Option> _options(Object? value) {
  final data = _asMap(value) ?? const <String, dynamic>{};
  final rows = data.entries.map((entry) {
    final item = _asMap(entry.value) ?? const <String, dynamic>{};
    return _Option(entry.key, _read(item, const ['name', 'title', 'office_name', 'department_name', 'group_name']).ifEmpty(entry.key));
  }).toList();
  rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
