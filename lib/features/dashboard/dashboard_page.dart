import 'package:flutter/material.dart';

import '../../core/date_utils.dart';
import '../../core/models.dart';
import '../../services/admin_service.dart';
import '../shared/message_card.dart';

class DashboardPage extends StatefulWidget {
  final AdminSession session;
  final AdminService service;
  const DashboardPage({super.key, required this.session, required this.service});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<DashboardSummary> future;
  @override
  void initState() { super.initState(); future = widget.service.loadDashboard(widget.session); }
  void refresh() => setState(() => future = widget.service.loadDashboard(widget.session));
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () async => refresh(),
      child: ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 24), children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Dashboard Admin', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)), Text(AdminDateUtils.dayDate(DateTime.now()), style: TextStyle(color: theme.colorScheme.onSurfaceVariant))])),
          IconButton.filledTonal(onPressed: refresh, icon: const Icon(Icons.refresh_rounded)),
        ]),
        const SizedBox(height: 12),
        Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.business_rounded)), title: Text(widget.session.companyName, style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Text('${widget.session.displayName} • ${widget.session.role.toUpperCase()}'))),
        const SizedBox(height: 12),
        FutureBuilder<DashboardSummary>(future: future, builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
          if (snap.hasError) return MessageCard(title: 'Dashboard gagal dimuat', message: snap.error.toString(), icon: Icons.error_outline_rounded);
          final s = snap.data ?? const DashboardSummary.empty();
          return GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.35, children: [
            _Stat('Karyawan Aktif', s.activeEmployees, Icons.people_rounded),
            _Stat('Hadir Hari Ini', s.checkedIn, Icons.login_rounded),
            _Stat('Sudah Pulang', s.checkedOut, Icons.logout_rounded),
            _Stat('Pending Approval', s.pendingApproval, Icons.fact_check_rounded),
            _Stat('Lembur Hari Ini', s.overtimeToday, Icons.more_time_rounded),
          ]);
        }),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label; final int value; final IconData icon;
  const _Stat(this.label, this.value, this.icon);
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [CircleAvatar(child: Icon(icon)), const Spacer(), Text('$value', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)), Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)])));
  }
}
