import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../shared/message_card.dart';

class LeaveManagementPage extends StatefulWidget {
  final AdminSession session;

  const LeaveManagementPage({super.key, required this.session});

  @override
  State<LeaveManagementPage> createState() => _LeaveManagementPageState();
}

class _LeaveManagementPageState extends State<LeaveManagementPage> {
  late Future<LeaveBundle> future;
  String tab = 'types';
  String query = '';

  @override
  void initState() {
    super.initState();
    future = loadBundle();
  }

  void refresh() => setState(() => future = loadBundle());

  Future<LeaveBundle> loadBundle() async {
    final companyId = widget.session.companyId;
    final db = FirebaseDatabase.instance;
    final results = await Future.wait([
      db.ref('leave_types/$companyId').get(),
      db.ref('leave_balances/$companyId').get(),
      db.ref('leave_rules/$companyId').get(),
      db.ref('company_users/$companyId').get(),
      db.ref('leave_requests/$companyId').get(),
    ]);

    return LeaveBundle(
      types: _items(results[0].value, 'type'),
      balances: _items(results[1].value, 'balance'),
      rules: _items(results[2].value, 'rule'),
      users: _items(results[3].value, 'user'),
      requests: _items(results[4].value, 'request'),
    );
  }

  List<LeaveItem> selectedRows(LeaveBundle bundle) {
    final source = switch (tab) {
      'types' => bundle.types,
      'balances' => bundle.balances,
      'rules' => bundle.rules,
      'requests' => bundle.requests,
      _ => bundle.types,
    };
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return source;
    return source.where((row) => '${row.title} ${row.subtitle} ${row.rawText}'.toLowerCase().contains(q)).toList();
  }

  Future<void> openTypeForm([LeaveItem? item]) async {
    final name = TextEditingController(text: item?.title == item?.id ? '' : item?.title ?? '');
    final quota = TextEditingController(text: _read(item?.data ?? const {}, const ['quota_days', 'quota', 'jatah']).ifEmpty('12'));
    final desc = TextEditingController(text: _read(item?.data ?? const {}, const ['description', 'note', 'keterangan']));
    var paid = _bool(item?.data['paid'], true);
    var requireAttachment = _bool(item?.data['require_attachment'], false);
    var active = item?.active ?? true;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Text(item == null ? 'Tambah Jenis Cuti' : 'Edit Jenis Cuti', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                _field(name, 'Nama jenis cuti/izin/sakit'),
                const SizedBox(height: 10),
                _field(quota, 'Default kuota hari', number: true),
                const SizedBox(height: 10),
                _field(desc, 'Deskripsi'),
                SwitchListTile(value: paid, onChanged: (v) => setSheetState(() => paid = v), title: const Text('Paid leave')),
                SwitchListTile(value: requireAttachment, onChanged: (v) => setSheetState(() => requireAttachment = v), title: const Text('Wajib lampiran')),
                SwitchListTile(value: active, onChanged: (v) => setSheetState(() => active = v), title: const Text('Aktif')),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Simpan')),
              ]),
            ),
          ),
        ),
      ),
    );

    if (ok == true && name.text.trim().isNotEmpty) {
      final id = item?.id ?? FirebaseDatabase.instance.ref('leave_types/${widget.session.companyId}').push().key!;
      await _save('leave_types/${widget.session.companyId}/$id', item == null ? 'create_leave_type' : 'update_leave_type', id, {
        'id': id,
        'name': name.text.trim(),
        'title': name.text.trim(),
        'quota_days': int.tryParse(quota.text.trim()) ?? 12,
        'description': desc.text.trim(),
        'paid': paid,
        'require_attachment': requireAttachment,
        'active': active,
        'status': active ? 'active' : 'inactive',
      });
    }
  }

  Future<void> openBalanceForm(LeaveBundle bundle, [LeaveItem? item]) async {
    String userId = _read(item?.data ?? const {}, const ['uid', 'user_id', 'employee_id']);
    String leaveTypeId = _read(item?.data ?? const {}, const ['leave_type_id', 'type_id']);
    final year = TextEditingController(text: _read(item?.data ?? const {}, const ['year', 'tahun']).ifEmpty(DateTime.now().year.toString()));
    final quota = TextEditingController(text: _read(item?.data ?? const {}, const ['quota_days', 'quota']).ifEmpty('12'));
    final used = TextEditingController(text: _read(item?.data ?? const {}, const ['used_days', 'used']).ifEmpty('0'));

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Text(item == null ? 'Tambah Saldo Cuti' : 'Edit Saldo Cuti', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                _dropdown('Karyawan', bundle.users, userId, (v) => setSheetState(() => userId = v)),
                const SizedBox(height: 10),
                _dropdown('Jenis Cuti', bundle.types, leaveTypeId, (v) => setSheetState(() => leaveTypeId = v)),
                const SizedBox(height: 10),
                _field(year, 'Tahun', number: true),
                const SizedBox(height: 10),
                _field(quota, 'Kuota hari', number: true),
                const SizedBox(height: 10),
                _field(used, 'Terpakai hari', number: true),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Simpan')),
              ]),
            ),
          ),
        ),
      ),
    );

    if (ok == true && userId.isNotEmpty) {
      final id = item?.id ?? '${userId}_${leaveTypeId}_${year.text.trim()}';
      final user = bundle.find(bundle.users, userId);
      final type = bundle.find(bundle.types, leaveTypeId);
      final quotaDays = int.tryParse(quota.text.trim()) ?? 0;
      final usedDays = int.tryParse(used.text.trim()) ?? 0;
      await _save('leave_balances/${widget.session.companyId}/$id', item == null ? 'create_leave_balance' : 'update_leave_balance', id, {
        'id': id,
        'uid': userId,
        'user_id': userId,
        'employee_name': user?.title ?? '',
        'leave_type_id': leaveTypeId,
        'leave_type_name': type?.title ?? '',
        'year': int.tryParse(year.text.trim()) ?? DateTime.now().year,
        'quota_days': quotaDays,
        'used_days': usedDays,
        'remaining_days': quotaDays - usedDays,
        'active': true,
      });
    }
  }

  Future<void> openRuleForm([LeaveItem? item]) async {
    final title = TextEditingController(text: item?.title == item?.id ? '' : item?.title ?? '');
    final minDays = TextEditingController(text: _read(item?.data ?? const {}, const ['min_notice_days']).ifEmpty('1'));
    final maxDays = TextEditingController(text: _read(item?.data ?? const {}, const ['max_days_per_request']).ifEmpty('12'));
    var approvalRequired = _bool(item?.data['approval_required'], true);
    var active = item?.active ?? true;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Text(item == null ? 'Tambah Rule Cuti' : 'Edit Rule Cuti', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                _field(title, 'Nama rule'),
                const SizedBox(height: 10),
                _field(minDays, 'Minimal pengajuan H-berapa', number: true),
                const SizedBox(height: 10),
                _field(maxDays, 'Maksimal hari per request', number: true),
                SwitchListTile(value: approvalRequired, onChanged: (v) => setSheetState(() => approvalRequired = v), title: const Text('Wajib approval')),
                SwitchListTile(value: active, onChanged: (v) => setSheetState(() => active = v), title: const Text('Aktif')),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Simpan')),
              ]),
            ),
          ),
        ),
      ),
    );

    if (ok == true && title.text.trim().isNotEmpty) {
      final id = item?.id ?? FirebaseDatabase.instance.ref('leave_rules/${widget.session.companyId}').push().key!;
      await _save('leave_rules/${widget.session.companyId}/$id', item == null ? 'create_leave_rule' : 'update_leave_rule', id, {
        'id': id,
        'title': title.text.trim(),
        'name': title.text.trim(),
        'min_notice_days': int.tryParse(minDays.text.trim()) ?? 1,
        'max_days_per_request': int.tryParse(maxDays.text.trim()) ?? 12,
        'approval_required': approvalRequired,
        'active': active,
        'status': active ? 'active' : 'inactive',
      });
    }
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

  void openCurrentForm(LeaveBundle bundle, [LeaveItem? item]) {
    if (tab == 'types') openTypeForm(item);
    if (tab == 'balances') openBalanceForm(bundle, item);
    if (tab == 'rules') openRuleForm(item);
  }

  String get currentLabel {
    return switch (tab) {
      'types' => 'Jenis Cuti',
      'balances' => 'Saldo Cuti',
      'rules' => 'Rule Cuti',
      'requests' => 'Request',
      _ => 'Cuti',
    };
  }

  Widget _field(TextEditingController controller, String label, {bool number = false}) {
    return TextField(controller: controller, keyboardType: number ? TextInputType.number : TextInputType.text, decoration: InputDecoration(labelText: label));
  }

  Widget _dropdown(String label, List<LeaveItem> items, String value, ValueChanged<String> onChanged) {
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

  ChoiceChip _chip(String value, String label) {
    return ChoiceChip(label: Text(label), selected: tab == value, onSelected: (_) => setState(() => tab = value));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leave Management'), actions: [IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
      body: FutureBuilder<LeaveBundle>(
        future: future,
        builder: (context, snapshot) {
          final bundle = snapshot.data ?? const LeaveBundle.empty();
          final rows = selectedRows(bundle);
          final pending = bundle.requests.where((item) => item.statusType == 'pending').length;
          final approved = bundle.requests.where((item) => item.statusType == 'approved').length;
          final rejected = bundle.requests.where((item) => item.statusType == 'rejected').length;

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              MessageCard(
                title: 'Leave Management',
                message: 'Jenis: ${bundle.types.length} • Saldo: ${bundle.balances.length} • Rule: ${bundle.rules.length} • Pending: $pending • Approved: $approved • Rejected: $rejected',
                icon: Icons.event_available_rounded,
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _chip('types', 'Jenis'),
                _chip('balances', 'Saldo'),
                _chip('rules', 'Rules'),
                _chip('requests', 'Requests'),
              ]),
              const SizedBox(height: 12),
              TextField(onChanged: (value) => setState(() => query = value), decoration: const InputDecoration(labelText: 'Cari cuti, karyawan, status', prefixIcon: Icon(Icons.search_rounded))),
              const SizedBox(height: 12),
              if (tab != 'requests') FilledButton.icon(onPressed: () => openCurrentForm(bundle), icon: const Icon(Icons.add_rounded), label: Text('Tambah $currentLabel')),
              if (tab != 'requests') const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                MessageCard(title: 'Gagal memuat leave management', message: snapshot.error.toString(), icon: Icons.error_outline_rounded)
              else if (rows.isEmpty)
                MessageCard(title: 'Belum ada data', message: '$currentLabel akan tampil di sini.', icon: Icons.inbox_outlined)
              else
                ...rows.map((item) => Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Icon(item.icon)),
                        title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text(item.subtitle),
                        isThreeLine: item.subtitle.contains('\n'),
                        trailing: tab == 'requests' ? null : const Icon(Icons.chevron_right_rounded),
                        onTap: tab == 'requests' ? null : () => openCurrentForm(bundle, item),
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }
}

class LeaveBundle {
  final List<LeaveItem> types;
  final List<LeaveItem> balances;
  final List<LeaveItem> rules;
  final List<LeaveItem> users;
  final List<LeaveItem> requests;

  const LeaveBundle({required this.types, required this.balances, required this.rules, required this.users, required this.requests});
  const LeaveBundle.empty() : types = const [], balances = const [], rules = const [], users = const [], requests = const [];

  LeaveItem? find(List<LeaveItem> items, String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }
}

class LeaveItem {
  final String id;
  final String type;
  final Map<String, dynamic> data;

  const LeaveItem({required this.id, required this.type, required this.data});

  String get title => _read(data, const ['name', 'title', 'employee_name', 'display_name', 'nama_lengkap', 'leave_type_name']).ifEmpty(id);
  String get rawText => data.values.join(' ');
  bool get active => data['active'] != false && data['status']?.toString().toLowerCase() != 'inactive';
  String get statusType {
    final text = _read(data, const ['status', 'approval_status']).toLowerCase();
    if (text.contains('approve') || text.contains('valid')) return 'approved';
    if (text.contains('reject') || text.contains('tolak')) return 'rejected';
    if (text.contains('inactive')) return 'inactive';
    return 'pending';
  }

  String get subtitle {
    if (type == 'type') return 'Kuota ${_read(data, const ['quota_days', 'quota']).ifEmpty('-')} hari • ${active ? 'Aktif' : 'Nonaktif'}';
    if (type == 'balance') return '${_read(data, const ['employee_name', 'uid', 'user_id'])}\n${_read(data, const ['leave_type_name', 'leave_type_id'])} • Sisa ${_read(data, const ['remaining_days']).ifEmpty('-')} dari ${_read(data, const ['quota_days']).ifEmpty('-')} hari';
    if (type == 'rule') return 'Minimal H-${_read(data, const ['min_notice_days']).ifEmpty('-')} • Max ${_read(data, const ['max_days_per_request']).ifEmpty('-')} hari • ${active ? 'Aktif' : 'Nonaktif'}';
    return '${_read(data, const ['date', 'tanggal', 'start_date']).ifEmpty('-')} • $statusType\n${_read(data, const ['reason', 'alasan', 'description', 'note']).ifEmpty('-')}';
  }

  IconData get icon {
    if (type == 'type') return Icons.category_rounded;
    if (type == 'balance') return Icons.account_balance_wallet_rounded;
    if (type == 'rule') return Icons.rule_rounded;
    return Icons.event_available_rounded;
  }
}

List<LeaveItem> _items(Object? value, String type) {
  final data = _asMap(value) ?? const <String, dynamic>{};
  final rows = data.entries.map((entry) => LeaveItem(id: entry.key, type: type, data: _asMap(entry.value) ?? const <String, dynamic>{})).toList();
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

bool _bool(Object? value, bool fallback) {
  if (value is bool) return value;
  if (value == null) return fallback;
  final text = value.toString().toLowerCase();
  if (text == 'true' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == '0' || text == 'no') return false;
  return fallback;
}

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
