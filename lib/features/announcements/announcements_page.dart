import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../services/admin_service.dart';
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
    final snap = await FirebaseDatabase.instance.ref('announcements/${widget.session.companyId}').get();
    final data = _asMap(snap.value) ?? const <String, dynamic>{};
    final rows = <AnnouncementItem>[];
    for (final entry in data.entries) {
      rows.add(AnnouncementItem(id: entry.key, data: _asMap(entry.value) ?? const <String, dynamic>{}));
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
      final text = '${item.title} ${item.message} ${item.target} ${item.status}'.toLowerCase();
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
    await FirebaseDatabase.instance.ref('announcements/${widget.session.companyId}/${item.id}').update({
      'published': published,
      'status': published ? 'published' : 'draft',
      'active': published,
      'published_at': published ? now : null,
      'updated_at': now,
      'updated_by': widget.session.uid,
    });
    if (published) await _queueNotification(item.title, item.message, item.target, item.id);
    await _audit(published ? 'publish_announcement' : 'unpublish_announcement', item.id);
    refresh();
  }

  Future<void> _queueNotification(String title, String body, String target, String announcementId) async {
    final ref = FirebaseDatabase.instance.ref('companies/${widget.session.companyId}/notification_queue').push();
    await ref.set({
      'id': ref.key,
      'type': 'announcement',
      'announcement_id': announcementId,
      'title': title,
      'body': body,
      'target': target,
      'status': 'pending',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'created_by': widget.session.uid,
      'created_by_email': widget.session.email,
    });
  }

  Future<void> _audit(String action, String id) async {
    await FirebaseDatabase.instance.ref('audit_logs/${widget.session.companyId}').push().set({
      'action': action,
      'target_id': id,
      'target_path': 'announcements/${widget.session.companyId}/$id',
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
                        subtitle: Text('${item.status} • target: ${item.target}\n${item.message}'),
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
  late String target = widget.item?.target ?? 'all';
  late bool published = widget.item?.published ?? false;
  late bool push = true;
  bool saving = false;

  @override
  void dispose() {
    title.dispose();
    message.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (title.text.trim().isEmpty || message.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Judul dan isi wajib diisi.')));
      return;
    }
    setState(() => saving = true);
    try {
      final db = FirebaseDatabase.instance;
      final id = widget.item?.id ?? db.ref('announcements/${widget.session.companyId}').push().key!;
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.ref('announcements/${widget.session.companyId}/$id').update({
        'id': id,
        'announcement_id': id,
        'company_id': widget.session.companyId,
        'title': title.text.trim(),
        'message': message.text.trim(),
        'body': message.text.trim(),
        'target': target,
        'target_audience': target,
        'published': published,
        'active': published,
        'status': published ? 'published' : 'draft',
        'published_at': published ? now : widget.item?.data['published_at'],
        'updated_at': now,
        'updated_by': widget.session.uid,
        if (widget.item == null) 'created_at': now,
        if (widget.item == null) 'created_by': widget.session.uid,
        if (widget.item == null) 'created_by_email': widget.session.email,
      });

      if (published && push) {
        final ref = db.ref('companies/${widget.session.companyId}/notification_queue').push();
        await ref.set({
          'id': ref.key,
          'type': 'announcement',
          'announcement_id': id,
          'title': title.text.trim(),
          'body': message.text.trim(),
          'target': target,
          'status': 'pending',
          'created_at': now,
          'created_by': widget.session.uid,
          'created_by_email': widget.session.email,
        });
      }

      await db.ref('audit_logs/${widget.session.companyId}').push().set({
        'action': widget.item == null ? 'create_announcement' : 'update_announcement',
        'target_id': id,
        'target_path': 'announcements/${widget.session.companyId}/$id',
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
            value: target,
            decoration: const InputDecoration(labelText: 'Target audience'),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('Semua karyawan')),
              DropdownMenuItem(value: 'employee', child: Text('Employee')),
              DropdownMenuItem(value: 'admin', child: Text('Admin')),
              DropdownMenuItem(value: 'owner', child: Text('Owner')),
            ],
            onChanged: (value) => setState(() => target = value ?? 'all'),
          ),
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

  const AnnouncementItem({required this.id, required this.data});

  String get title => _read(data, const ['title', 'judul']).ifEmpty(id);
  String get message => _read(data, const ['message', 'body', 'isi', 'description']);
  String get target => _read(data, const ['target', 'target_audience']).ifEmpty('all');
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

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
