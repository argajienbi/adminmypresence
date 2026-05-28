import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/firebase_paths.dart';
import '../../core/models.dart';
import '../../services/admin_service.dart';
import '../../services/notification_bridge.dart';
import '../shared/message_card.dart';

class AnnouncementsPage extends StatefulWidget {
  final AdminSession session;
  final AdminService service;

  const AnnouncementsPage({super.key, required this.session, required this.service});

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  late Future<List<AnnouncementItem>> future;
  String query = '';
  String statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    future = loadItems();
  }

  void refresh() {
    setState(() => future = loadItems());
  }

  Future<List<AnnouncementItem>> loadItems() async {
    final rows = <AnnouncementItem>[];
    final firestoreSnap = await FirebaseFirestore.instance.collection(FirestorePaths.announcements(widget.session.companyId)).get();
    for (final doc in firestoreSnap.docs) {
      rows.add(AnnouncementItem(id: doc.id, data: doc.data(), source: 'firestore'));
    }

    if (rows.isEmpty) {
      final snap = await FirebaseDatabase.instance.ref(FirebasePaths.announcements(widget.session.companyId)).get();
      final data = _asMap(snap.value) ?? const <String, dynamic>{};
      for (final entry in data.entries) {
        rows.add(AnnouncementItem(id: entry.key, data: _asMap(entry.value) ?? const <String, dynamic>{}, source: 'rtdb'));
      }
    }
    rows.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    return rows;
  }

  List<AnnouncementItem> filterRows(List<AnnouncementItem> rows) {
    final q = query.trim().toLowerCase();
    return rows.where((item) {
      if (statusFilter == 'published' && !item.published) return false;
      if (statusFilter == 'draft' && item.published) return false;
      if (statusFilter == 'inactive' && item.active) return false;
      if (q.isEmpty) return true;
      final text = '${item.title} ${item.message} ${item.targetType} ${item.targetIds.join(' ')} ${item.status}'.toLowerCase();
      return text.contains(q);
    }).toList();
  }

  Future<void> openForm([AnnouncementItem? item]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AnnouncementSheet(session: widget.session, item: item),
    );
    if (saved == true) refresh();
  }

  Future<void> setPublished(AnnouncementItem item, bool published) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await FirebaseFirestore.instance.doc(FirestorePaths.announcement(widget.session.companyId, item.id)).set({
      'status': published ? 'published' : 'draft',
      'active': published,
      'published_at': published ? now : null,
      'updated_at': now,
      'updated_by': widget.session.uid,
    }, SetOptions(merge: true));
    if (published && item.sendPush) {
      final targetUids = await _resolveTargetUids(item.targetType, item.targetIds);
      await NotificationBridge().createNotificationForUsers(
        companyId: widget.session.companyId,
        uids: targetUids,
        title: item.title,
        message: item.message,
        type: item.type,
        refType: 'announcement',
        refId: item.id,
        data: {'announcement_id': item.id, 'target_type': item.targetType},
      );
      await NotificationBridge().writeNotificationLog(widget.session.companyId, {
        'action': 'announcement_push_queue_created',
        'announcement_id': item.id,
        'target_count': targetUids.length,
        'queue_count': targetUids.length,
        'created_by': widget.session.uid,
        'created_by_name': widget.session.displayName,
      });
    }
    await _audit(published ? 'announcement_publish' : 'announcement_unpublish', item.id);
    refresh();
  }

  Future<List<String>> _resolveTargetUids(String targetType, List<String> targetIds) async {
    final snap = await FirebaseDatabase.instance.ref(FirebasePaths.companyUsers(widget.session.companyId)).get();
    final data = _asMap(snap.value) ?? const <String, dynamic>{};
    final safeIds = targetIds.map((item) => item.toString()).toSet();
    final uids = <String>[];
    for (final entry in data.entries) {
      final employee = _asMap(entry.value) ?? const <String, dynamic>{};
      if (!_isActiveEmployee(employee)) continue;
      final uid = _read(employee, const ['uid']).ifEmpty(entry.key);
      if (targetType == 'all') {
        uids.add(uid);
      } else if (targetType == 'user' && safeIds.contains(uid)) {
        uids.add(uid);
      } else if (targetType == 'office' && safeIds.contains(_read(employee, const ['office_id', 'officeId']))) {
        uids.add(uid);
      } else if (targetType == 'area' && safeIds.contains(_read(employee, const ['area_id', 'areaId']))) {
        uids.add(uid);
      } else if (targetType == 'department' && safeIds.contains(_read(employee, const ['department_id', 'departmentId']))) {
        uids.add(uid);
      } else if (targetType == 'sub_department' && safeIds.contains(_read(employee, const ['sub_department_id', 'subDepartmentId']))) {
        uids.add(uid);
      } else if (targetType == 'group' && safeIds.contains(_read(employee, const ['group_id', 'groupId']))) {
        uids.add(uid);
      }
    }
    return uids.toSet().toList();
  }

  Future<void> _audit(String action, String id) async {
    await FirebaseDatabase.instance.ref(FirebasePaths.auditLogs(widget.session.companyId)).push().set({
      'action': action,
      'target_id': id,
      'target_path': FirestorePaths.announcement(widget.session.companyId, id),
      'actor_uid': widget.session.uid,
      'actor_email': widget.session.email,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengumuman'), actions: [IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => openForm(), icon: const Icon(Icons.add_rounded), label: const Text('Buat')),
      body: FutureBuilder<List<AnnouncementItem>>(
        future: future,
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <AnnouncementItem>[];
          final rows = filterRows(all);
          final published = all.where((e) => e.published).length;
          final draft = all.where((e) => !e.published).length;
          final inactive = all.where((e) => !e.active).length;

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              MessageCard(title: 'Announcement Center', message: 'Published: $published • Draft: $draft • Inactive: $inactive', icon: Icons.campaign_rounded),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: statusFilter,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Semua')),
                  DropdownMenuItem(value: 'published', child: Text('Published')),
                  DropdownMenuItem(value: 'draft', child: Text('Draft')),
                  DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                ],
                onChanged: (value) => setState(() => statusFilter = value ?? 'all'),
              ),
              const SizedBox(height: 12),
              TextField(onChanged: (v) => setState(() => query = v), decoration: const InputDecoration(labelText: 'Cari judul, isi, target', prefixIcon: Icon(Icons.search_rounded))),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                MessageCard(title: 'Gagal memuat pengumuman', message: snapshot.error.toString(), icon: Icons.error_outline_rounded)
              else if (rows.isEmpty)
                const MessageCard(title: 'Belum ada pengumuman', message: 'Pengumuman akan tampil di sini.', icon: Icons.campaign_outlined)
              else
                ...rows.map((item) => Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Icon(item.published ? Icons.campaign_rounded : Icons.drafts_rounded)),
                        title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text('${item.status} • target: ${item.targetLabel}\n${item.message}'),
                        isThreeLine: true,
                        trailing: Switch(value: item.published, onChanged: (value) => setPublished(item, value)),
                        onTap: () => openForm(item),
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }
}

class _AnnouncementSheet extends StatefulWidget {
  final AdminSession session;
  final AnnouncementItem? item;

  const _AnnouncementSheet({required this.session, this.item});

  @override
  State<_AnnouncementSheet> createState() => _AnnouncementSheetState();
}

class _AnnouncementSheetState extends State<_AnnouncementSheet> {
  late final TextEditingController title = TextEditingController(text: widget.item?.title ?? '');
  late final TextEditingController message = TextEditingController(text: widget.item?.message ?? '');
  late final TextEditingController targetIds = TextEditingController(text: widget.item?.targetIds.join(', ') ?? '');
  late String targetType = widget.item?.targetType ?? 'all';
  late String type = widget.item?.type ?? 'info';
  late bool published = widget.item?.published ?? false;
  late bool push = widget.item?.sendPush ?? true;
  bool saving = false;

  @override
  void dispose() {
    title.dispose();
    message.dispose();
    targetIds.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (title.text.trim().isEmpty || message.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Judul dan isi wajib diisi.')));
      return;
    }
    setState(() => saving = true);
    try {
      final col = FirebaseFirestore.instance.collection(FirestorePaths.announcements(widget.session.companyId));
      final id = widget.item?.id ?? col.doc().id;
      final now = DateTime.now().millisecondsSinceEpoch;
      final ids = _targetIdsFromText(targetIds.text);
      await col.doc(id).set({
        'id': id,
        'announcement_id': id,
        'company_id': widget.session.companyId,
        'title': title.text.trim(),
        'message': message.text.trim(),
        'body': message.text.trim(),
        'type': type,
        'target_type': targetType,
        'target_ids': ids,
        'send_push': push,
        'active': published,
        'status': published ? 'published' : 'draft',
        'published_at': published ? now : widget.item?.data['published_at'],
        'scheduled_at': null,
        'updated_at': now,
        'updated_by': widget.session.uid,
        if (widget.item == null) 'created_at': now,
        if (widget.item == null) 'created_by': widget.session.uid,
        if (widget.item == null) 'created_by_name': widget.session.displayName,
        if (widget.item == null) 'created_by_email': widget.session.email,
      }, SetOptions(merge: true));

      if (published && push) {
        final targetUids = await _resolveAnnouncementTargetUids(widget.session.companyId, targetType, ids);
        await NotificationBridge().createNotificationForUsers(
          companyId: widget.session.companyId,
          uids: targetUids,
          title: title.text.trim(),
          message: message.text.trim(),
          type: type,
          refType: 'announcement',
          refId: id,
          data: {'announcement_id': id, 'target_type': targetType},
        );
        await NotificationBridge().writeNotificationLog(widget.session.companyId, {
          'action': 'announcement_push_queue_created',
          'announcement_id': id,
          'target_count': targetUids.length,
          'queue_count': targetUids.length,
          'created_by': widget.session.uid,
          'created_by_name': widget.session.displayName,
        });
      }

      await NotificationBridge().writeNotificationLog(widget.session.companyId, {
        'action': widget.item == null ? 'announcement_create' : 'announcement_update',
        'announcement_id': id,
        'title': title.text.trim(),
        'status': published ? 'published' : 'draft',
        'target_type': targetType,
        'target_ids': ids,
        'created_by': widget.session.uid,
        'created_by_name': widget.session.displayName,
      });

      await FirebaseDatabase.instance.ref(FirebasePaths.auditLogs(widget.session.companyId)).push().set({
        'action': widget.item == null ? 'create_announcement' : 'update_announcement',
        'target_id': id,
        'target_path': FirestorePaths.announcement(widget.session.companyId, id),
        'actor_uid': widget.session.uid,
        'actor_email': widget.session.email,
        'created_at': now,
      });

      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(widget.item == null ? 'Buat Pengumuman' : 'Edit Pengumuman', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Judul')),
          const SizedBox(height: 10),
          TextField(controller: message, maxLines: 5, decoration: const InputDecoration(labelText: 'Isi pengumuman')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: type,
            decoration: const InputDecoration(labelText: 'Tipe'),
            items: const [
              DropdownMenuItem(value: 'info', child: Text('Info')),
              DropdownMenuItem(value: 'success', child: Text('Success')),
              DropdownMenuItem(value: 'warning', child: Text('Warning')),
              DropdownMenuItem(value: 'danger', child: Text('Danger')),
            ],
            onChanged: (value) => setState(() => type = value ?? 'info'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: targetType,
            decoration: const InputDecoration(labelText: 'Target'),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('Semua karyawan')),
              DropdownMenuItem(value: 'user', child: Text('User tertentu')),
              DropdownMenuItem(value: 'office', child: Text('Kantor')),
              DropdownMenuItem(value: 'area', child: Text('Area')),
              DropdownMenuItem(value: 'department', child: Text('Departemen')),
              DropdownMenuItem(value: 'sub_department', child: Text('Sub Departemen')),
              DropdownMenuItem(value: 'group', child: Text('Grup')),
            ],
            onChanged: (value) => setState(() => targetType = value ?? 'all'),
          ),
          if (targetType != 'all') ...[
            const SizedBox(height: 10),
            TextField(
              controller: targetIds,
              decoration: const InputDecoration(
                labelText: 'Target IDs',
                hintText: 'Pisahkan dengan koma, contoh: id1, id2',
              ),
            ),
          ],
          SwitchListTile(value: published, onChanged: (value) => setState(() => published = value), title: const Text('Publish sekarang')),
          SwitchListTile(value: push, onChanged: (value) => setState(() => push = value), title: const Text('Kirim push notification')),
          FilledButton.icon(onPressed: saving ? null : save, icon: const Icon(Icons.save_rounded), label: Text(saving ? 'Menyimpan...' : 'Simpan')),
        ]),
      ),
    );
  }
}

class AnnouncementItem {
  final String id;
  final Map<String, dynamic> data;
  final String source;

  const AnnouncementItem({required this.id, required this.data, required this.source});

  String get title => _read(data, const ['title', 'judul']).ifEmpty(id);
  String get message => _read(data, const ['message', 'body', 'isi', 'description']);
  String get type => _read(data, const ['type']).ifEmpty('info');
  String get targetType => _read(data, const ['target_type', 'target', 'target_audience']).ifEmpty('all');
  List<String> get targetIds {
    final raw = data['target_ids'];
    if (raw is List) return raw.map((item) => item.toString()).where((item) => item.trim().isNotEmpty).toList();
    if (raw is Map) return raw.values.map((item) => item.toString()).where((item) => item.trim().isNotEmpty).toList();
    return _targetIdsFromText(raw?.toString() ?? '');
  }

  String get targetLabel => targetType == 'all' ? 'Semua karyawan' : '$targetType: ${targetIds.join(', ')}';
  bool get sendPush => data['send_push'] != false;
  bool get published => data['published'] == true || status == 'published';
  bool get active => data['active'] != false && status != 'inactive';
  String get status => _read(data, const ['status']).ifEmpty(data['published'] == true ? 'published' : 'draft').toLowerCase();
  String get sortKey => '${data['published_at'] ?? data['created_at'] ?? data['updated_at'] ?? ''}$id';
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

List<String> _targetIdsFromText(String text) {
  return text
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();
}

Future<List<String>> _resolveAnnouncementTargetUids(String companyId, String targetType, List<String> targetIds) async {
  final snap = await FirebaseDatabase.instance.ref(FirebasePaths.companyUsers(companyId)).get();
  final data = _asMap(snap.value) ?? const <String, dynamic>{};
  final safeIds = targetIds.map((item) => item.toString()).toSet();
  final uids = <String>[];
  for (final entry in data.entries) {
    final employee = _asMap(entry.value) ?? const <String, dynamic>{};
    if (!_isActiveEmployee(employee)) continue;
    final uid = _read(employee, const ['uid']).ifEmpty(entry.key);
    if (targetType == 'all') {
      uids.add(uid);
    } else if (targetType == 'user' && safeIds.contains(uid)) {
      uids.add(uid);
    } else if (targetType == 'office' && safeIds.contains(_read(employee, const ['office_id', 'officeId']))) {
      uids.add(uid);
    } else if (targetType == 'area' && safeIds.contains(_read(employee, const ['area_id', 'areaId']))) {
      uids.add(uid);
    } else if (targetType == 'department' && safeIds.contains(_read(employee, const ['department_id', 'departmentId']))) {
      uids.add(uid);
    } else if (targetType == 'sub_department' && safeIds.contains(_read(employee, const ['sub_department_id', 'subDepartmentId']))) {
      uids.add(uid);
    } else if (targetType == 'group' && safeIds.contains(_read(employee, const ['group_id', 'groupId']))) {
      uids.add(uid);
    }
  }
  return uids.toSet().toList();
}

bool _isActiveEmployee(Map<String, dynamic> data) {
  final status = _read(data, const ['status_akun', 'status', 'account_status']).toLowerCase();
  return data['active'] == true ||
      data['is_active'] == true ||
      status == 'active' ||
      status == 'aktif' ||
      status == 'enabled' ||
      status == 'approved' ||
      status == '1';
}

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
