import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../shared/message_card.dart';

class OwnerToolsPage extends StatefulWidget {
  final AdminSession session;

  const OwnerToolsPage({super.key, required this.session});

  @override
  State<OwnerToolsPage> createState() => _OwnerToolsPageState();
}

class _OwnerToolsPageState extends State<OwnerToolsPage> {
  late Future<_OwnerBundle> future;
  String query = '';

  @override
  void initState() {
    super.initState();
    future = load();
  }

  void refresh() {
    setState(() => future = load());
  }

  Future<_OwnerBundle> load() async {
    final db = FirebaseDatabase.instance;
    final results = await Future.wait([
      db.ref('companies').get(),
      db.ref('users').get(),
      db.ref('company_invites').get(),
    ]);

    final companiesData = _asMap(results[0].value) ?? const <String, dynamic>{};
    final usersData = _asMap(results[1].value) ?? const <String, dynamic>{};
    final invitesData = _asMap(results[2].value) ?? const <String, dynamic>{};

    final companies = companiesData.entries.map((entry) => OwnerCompany(id: entry.key, data: _asMap(entry.value) ?? const <String, dynamic>{})).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final admins = usersData.entries.map((entry) => OwnerUser(id: entry.key, data: _asMap(entry.value) ?? const <String, dynamic>{})).where((user) => user.isAdmin).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final invites = invitesData.entries.map((entry) => OwnerInvite(id: entry.key, data: _asMap(entry.value) ?? const <String, dynamic>{})).toList()
      ..sort((a, b) => b.sortKey.compareTo(a.sortKey));

    return _OwnerBundle(companies: companies, admins: admins, invites: invites);
  }

  List<OwnerCompany> filterCompanies(List<OwnerCompany> rows) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows.where((row) => '${row.name} ${row.email} ${row.status}'.toLowerCase().contains(q)).toList();
  }

  Future<void> setCompanyActive(OwnerCompany company, bool active) async {
    await FirebaseDatabase.instance.ref('companies/${company.id}').update({
      'active': active,
      'status': active ? 'active' : 'inactive',
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'updated_by': widget.session.uid,
    });
    refresh();
  }

  Future<void> createInvite() async {
    final email = TextEditingController();
    final companyId = TextEditingController(text: widget.session.companyId);
    final role = TextEditingController(text: 'admin');

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Buat Invite Admin', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              TextField(controller: email, decoration: const InputDecoration(labelText: 'Email admin')),
              const SizedBox(height: 10),
              TextField(controller: companyId, decoration: const InputDecoration(labelText: 'Company ID')),
              const SizedBox(height: 10),
              TextField(controller: role, decoration: const InputDecoration(labelText: 'Role')),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Buat Invite')),
            ],
          ),
        ),
      ),
    );

    if (ok == true && email.text.trim().isNotEmpty && companyId.text.trim().isNotEmpty) {
      final ref = FirebaseDatabase.instance.ref('company_invites').push();
      await ref.set({
        'id': ref.key,
        'email': email.text.trim(),
        'company_id': companyId.text.trim(),
        'role': role.text.trim().isEmpty ? 'admin' : role.text.trim(),
        'status': 'pending',
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'created_by': widget.session.uid,
        'created_by_email': widget.session.email,
      });
      refresh();
    }
  }

  Future<void> openCompanyForm([OwnerCompany? company]) async {
    final name = TextEditingController(text: company?.name ?? '');
    final email = TextEditingController(text: company?.email ?? '');
    final status = TextEditingController(text: company?.status ?? 'active');

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(company == null ? 'Tambah Company' : 'Edit Company', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nama company')),
              const SizedBox(height: 10),
              TextField(controller: email, decoration: const InputDecoration(labelText: 'Email owner/admin')),
              const SizedBox(height: 10),
              TextField(controller: status, decoration: const InputDecoration(labelText: 'Status')),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Simpan')),
            ],
          ),
        ),
      ),
    );

    if (ok == true && name.text.trim().isNotEmpty) {
      final db = FirebaseDatabase.instance;
      final id = company?.id ?? db.ref('companies').push().key!;
      await db.ref('companies/$id').update({
        'id': id,
        'company_id': id,
        'name': name.text.trim(),
        'company_name': name.text.trim(),
        'owner_email': email.text.trim(),
        'email': email.text.trim(),
        'status': status.text.trim().isEmpty ? 'active' : status.text.trim(),
        'active': status.text.trim().toLowerCase() != 'inactive',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'updated_by': widget.session.uid,
        if (company == null) 'created_at': DateTime.now().millisecondsSinceEpoch,
        if (company == null) 'created_by': widget.session.uid,
      });
      refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.session.role != 'owner') {
      return Scaffold(
        appBar: AppBar(title: const Text('Owner Tools')),
        body: const Padding(
          padding: EdgeInsets.all(18),
          child: MessageCard(title: 'Akses Ditolak', message: 'Halaman ini hanya untuk role owner.', icon: Icons.lock_rounded),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Owner Tools'), actions: [IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
      floatingActionButton: FloatingActionButton.extended(onPressed: createInvite, icon: const Icon(Icons.mail_rounded), label: const Text('Invite')),
      body: FutureBuilder<_OwnerBundle>(
        future: future,
        builder: (context, snapshot) {
          final bundle = snapshot.data ?? const _OwnerBundle.empty();
          final companies = filterCompanies(bundle.companies);

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              MessageCard(
                title: 'Owner Control Center',
                message: 'Companies: ${bundle.companies.length} • Admins: ${bundle.admins.length} • Invites: ${bundle.invites.length}',
                icon: Icons.admin_panel_settings_rounded,
              ),
              const SizedBox(height: 12),
              TextField(onChanged: (value) => setState(() => query = value), decoration: const InputDecoration(labelText: 'Cari company', prefixIcon: Icon(Icons.search_rounded))),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: () => openCompanyForm(), icon: const Icon(Icons.add_business_rounded), label: const Text('Tambah Company')),
              const SizedBox(height: 18),
              Text('Companies', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                MessageCard(title: 'Gagal memuat owner tools', message: snapshot.error.toString(), icon: Icons.error_outline_rounded)
              else if (companies.isEmpty)
                const MessageCard(title: 'Belum ada company', message: 'Company akan tampil di sini.', icon: Icons.business_outlined)
              else
                ...companies.map((company) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.business_rounded)),
                        title: Text(company.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text('${company.email.ifEmpty('-')} • ${company.status}'),
                        trailing: Switch(value: company.active, onChanged: (value) => setCompanyActive(company, value)),
                        onTap: () => openCompanyForm(company),
                      ),
                    )),
              const SizedBox(height: 18),
              Text('Company Admins', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              if (bundle.admins.isEmpty)
                const MessageCard(title: 'Belum ada admin', message: 'Admin company akan tampil di sini.', icon: Icons.people_outline_rounded)
              else
                ...bundle.admins.take(30).map((admin) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                        title: Text(admin.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text('${admin.email.ifEmpty('-')} • ${admin.companyId.ifEmpty('-')} • ${admin.role}'),
                      ),
                    )),
              const SizedBox(height: 18),
              Text('Invites', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              if (bundle.invites.isEmpty)
                const MessageCard(title: 'Belum ada invite', message: 'Invite admin akan tampil di sini.', icon: Icons.mail_outline_rounded)
              else
                ...bundle.invites.take(30).map((invite) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.mail_rounded)),
                        title: Text(invite.email, style: const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text('${invite.companyId} • ${invite.role} • ${invite.status}'),
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }
}

class _OwnerBundle {
  final List<OwnerCompany> companies;
  final List<OwnerUser> admins;
  final List<OwnerInvite> invites;

  const _OwnerBundle({required this.companies, required this.admins, required this.invites});
  const _OwnerBundle.empty() : companies = const [], admins = const [], invites = const [];
}

class OwnerCompany {
  final String id;
  final Map<String, dynamic> data;

  const OwnerCompany({required this.id, required this.data});

  String get name => _read(data, const ['name', 'company_name', 'nama_perusahaan']).ifEmpty(id);
  String get email => _read(data, const ['owner_email', 'email']);
  String get status => _read(data, const ['status']).ifEmpty(active ? 'active' : 'inactive');
  bool get active => data['active'] != false && data['status']?.toString().toLowerCase() != 'inactive';
}

class OwnerUser {
  final String id;
  final Map<String, dynamic> data;

  const OwnerUser({required this.id, required this.data});

  String get name => _read(data, const ['display_name', 'nama_lengkap', 'name']).ifEmpty(id);
  String get email => _read(data, const ['email']);
  String get role => _read(data, const ['role', 'level']);
  String get companyId => _read(data, const ['company_id', 'companyId']);
  bool get isAdmin {
    final text = role.toLowerCase();
    return text.contains('admin') || text.contains('owner');
  }
}

class OwnerInvite {
  final String id;
  final Map<String, dynamic> data;

  const OwnerInvite({required this.id, required this.data});

  String get email => _read(data, const ['email']).ifEmpty(id);
  String get companyId => _read(data, const ['company_id', 'companyId']);
  String get role => _read(data, const ['role']).ifEmpty('admin');
  String get status => _read(data, const ['status']).ifEmpty('pending');
  String get sortKey => '${data['created_at'] ?? ''}$id';
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
