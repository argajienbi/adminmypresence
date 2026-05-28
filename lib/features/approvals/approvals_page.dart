import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../services/admin_service.dart';
import '../shared/message_card.dart';

class ApprovalsPage extends StatefulWidget {
  final AdminSession session; final AdminService service;
  const ApprovalsPage({super.key, required this.session, required this.service});
  @override
  State<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends State<ApprovalsPage> {
  late Future<List<ApprovalItem>> future;
  String filter = 'Semua';
  @override
  void initState() { super.initState(); future = widget.service.loadApprovals(widget.session); }
  void refresh() => setState(() => future = widget.service.loadApprovals(widget.session));
  Future<void> decide(ApprovalItem item, bool approve) async {
    final note = await showModalBottomSheet<String>(context: context, builder: (_) => _NoteSheet(title: '${approve ? 'Setujui' : 'Tolak'} ${item.typeLabel}'));
    if (note == null) return;
    await widget.service.decideApproval(widget.session, item, approve, note);
    refresh();
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<ApprovalItem>>(future: future, builder: (context, snap) {
      var items = snap.data ?? const <ApprovalItem>[];
      if (filter != 'Semua') items = items.where((e) => e.typeLabel.toLowerCase() == filter.toLowerCase()).toList();
      return ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 24), children: [
        Row(children: [Expanded(child: Text('Approval', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900))), IconButton.filledTonal(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: ['Semua','Izin','Sakit','Cuti','Lembur','QR'].map((e) => ChoiceChip(label: Text(e), selected: filter == e, onSelected: (_) => setState(() => filter = e))).toList()),
        const SizedBox(height: 12),
        if (snap.connectionState == ConnectionState.waiting) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else if (snap.hasError) MessageCard(title: 'Gagal memuat approval', message: snap.error.toString(), icon: Icons.error_outline_rounded)
        else if (items.isEmpty) const MessageCard(title: 'Tidak ada approval pending', message: 'Pengajuan akan tampil di sini.', icon: Icons.fact_check_outlined)
        else ...items.map((e) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(e.userName, style: const TextStyle(fontWeight: FontWeight.w900)), Text('${e.typeLabel} • ${e.date}'), if (e.reason.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(e.reason)), const SizedBox(height: 12), Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () => decide(e, false), icon: const Icon(Icons.close_rounded), label: const Text('Tolak'))), const SizedBox(width: 10), Expanded(child: FilledButton.icon(onPressed: () => decide(e, true), icon: const Icon(Icons.check_rounded), label: const Text('Setujui')))]) ]))))
      ]);
    });
  }
}

class _NoteSheet extends StatefulWidget { final String title; const _NoteSheet({required this.title}); @override State<_NoteSheet> createState() => _NoteSheetState(); }
class _NoteSheetState extends State<_NoteSheet> { final note = TextEditingController(); @override Widget build(BuildContext context) => SafeArea(child: Padding(padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [Text(widget.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)), const SizedBox(height: 12), TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Catatan admin')), const SizedBox(height: 12), FilledButton(onPressed: () => Navigator.of(context).pop(note.text), child: const Text('Simpan'))]))); }
