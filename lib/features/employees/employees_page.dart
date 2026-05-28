import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../services/admin_service.dart';
import '../shared/message_card.dart';

class EmployeesPage extends StatefulWidget {
  final AdminSession session;
  final AdminService service;
  const EmployeesPage({super.key, required this.session, required this.service});
  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  late Future<List<EmployeeRecord>> future;
  String query = '';
  @override
  void initState() { super.initState(); future = widget.service.loadEmployees(widget.session); }
  void refresh() => setState(() => future = widget.service.loadEmployees(widget.session));
  List<EmployeeRecord> filter(List<EmployeeRecord> list) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((e) => '${e.name} ${e.email} ${e.nip} ${e.groupName} ${e.officeName}'.toLowerCase().contains(q)).toList();
  }
  Future<void> openForm([EmployeeRecord? employee]) async {
    final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => _EmployeeSheet(session: widget.session, service: widget.service, employee: employee));
    if (ok == true) refresh();
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<EmployeeRecord>>(future: future, builder: (context, snap) {
      final list = filter(snap.data ?? const []);
      return ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 24), children: [
        Row(children: [Expanded(child: Text('Karyawan', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900))), IconButton.filledTonal(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: () => openForm(), icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('Tambah Karyawan')),
        const SizedBox(height: 12),
        TextField(onChanged: (v) => setState(() => query = v), decoration: const InputDecoration(labelText: 'Cari karyawan', prefixIcon: Icon(Icons.search_rounded))),
        const SizedBox(height: 12),
        if (snap.connectionState == ConnectionState.waiting) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else if (snap.hasError) MessageCard(title: 'Gagal memuat karyawan', message: snap.error.toString(), icon: Icons.error_outline_rounded)
        else if (list.isEmpty) const MessageCard(title: 'Belum ada karyawan', message: 'Karyawan akan tampil di sini.', icon: Icons.people_outline_rounded)
        else ...list.map((e) => Card(child: ListTile(leading: CircleAvatar(child: Text(e.name.isEmpty ? '?' : e.name.characters.first.toUpperCase())), title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Text('${e.email}\n${[e.nip, e.officeName, e.groupName].where((v) => v.isNotEmpty).join(' • ')}'), isThreeLine: true, trailing: Switch(value: e.active, onChanged: (v) async { await widget.service.setEmployeeActive(widget.session, e, v); refresh(); }), onTap: () => openForm(e))))
      ]);
    });
  }
}

class _EmployeeSheet extends StatefulWidget {
  final AdminSession session; final AdminService service; final EmployeeRecord? employee;
  const _EmployeeSheet({required this.session, required this.service, this.employee});
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
  late final TextEditingController office = TextEditingController(text: widget.employee?.officeName ?? '');
  late final TextEditingController group = TextEditingController(text: widget.employee?.groupName ?? '');
  late bool active = widget.employee?.active ?? true;
  bool saving = false;
  @override
  Widget build(BuildContext context) {
    final editing = widget.employee != null;
    return SafeArea(child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(editing ? 'Edit Karyawan' : 'Tambah Karyawan', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 12), _field(name, 'Nama lengkap'), const SizedBox(height: 10), _field(email, 'Email login', readOnly: editing), if (!editing) ...[const SizedBox(height: 10), _field(password, 'Password awal', obscure: true)], const SizedBox(height: 10), _field(nip, 'NIP'), const SizedBox(height: 10), _field(phone, 'Nomor HP'), const SizedBox(height: 10), _field(job, 'Jabatan'), const SizedBox(height: 10), _field(office, 'Nama kantor'), const SizedBox(height: 10), _field(group, 'Grup karyawan'), SwitchListTile(value: active, onChanged: (v) => setState(() => active = v), title: const Text('Akun aktif')),
      FilledButton.icon(onPressed: saving ? null : () async { setState(() => saving = true); try { await widget.service.saveEmployee(widget.session, old: widget.employee, name: name.text, email: email.text, password: password.text, nip: nip.text, phone: phone.text, jobTitle: job.text, officeName: office.text, groupName: group.text, active: active); if (mounted) Navigator.of(context).pop(true); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); } finally { if (mounted) setState(() => saving = false); } }, icon: const Icon(Icons.save_rounded), label: Text(saving ? 'Menyimpan...' : 'Simpan')),
    ])));
  }
  Widget _field(TextEditingController c, String label, {bool readOnly = false, bool obscure = false}) => TextField(controller: c, readOnly: readOnly, obscureText: obscure, decoration: InputDecoration(labelText: label));
}
