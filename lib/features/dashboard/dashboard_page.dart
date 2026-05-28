import 'package:firebase_database/firebase_database.dart';
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
  late Future<_DashboardData> future;

  @override
  void initState() {
    super.initState();
    future = loadDashboard();
  }

  void refresh() {
    setState(() => future = loadDashboard());
  }

  Future<_DashboardData> loadDashboard() async {
    final companyId = widget.session.companyId;
    final db = FirebaseDatabase.instance;
    final today = _dateKey(DateTime.now());
    final results = await Future.wait([
      db.ref('company_users/$companyId').get(),
      db.ref('attendance/$companyId').get(),
      db.ref('leave_requests/$companyId').get(),
      db.ref('qr_attendance_requests/$companyId').get(),
      db.ref('attendance_corrections/$companyId').get(),
      db.ref('overtime_schedules/$companyId').get(),
      db.ref('announcements/$companyId').get(),
      db.ref('schedule_change_logs/$companyId').get(),
    ]);

    final users = _asMap(results[0].value) ?? const <String, dynamic>{};
    final attendance = _asMap(results[1].value) ?? const <String, dynamic>{};
    final leaveRequests = _asMap(results[2].value) ?? const <String, dynamic>{};
    final qrRequests = _asMap(results[3].value) ?? const <String, dynamic>{};
    final corrections = _asMap(results[4].value) ?? const <String, dynamic>{};
    final overtime = _asMap(results[5].value) ?? const <String, dynamic>{};
    final announcements = _asMap(results[6].value) ?? const <String, dynamic>{};
    final scheduleLogs = _asMap(results[7].value) ?? const <String, dynamic>{};

    var activeEmployees = 0;
    for (final entry in users.entries) {
      final data = _asMap(entry.value) ?? const <String, dynamic>{};
      final role = _read(data, const ['role', 'level']).toLowerCase();
      final active = data['active'] != false && data['status']?.toString().toLowerCase() != 'inactive';
      if (active && !role.contains('admin') && !role.contains('owner')) activeEmployees++;
    }

    var checkedIn = 0;
    var checkedOut = 0;
    var outsideRadius = 0;
    var late = 0;
    final activeTodayUsers = <String>{};

    for (final userEntry in attendance.entries) {
      final uid = userEntry.key;
      final days = _asMap(userEntry.value);
      if (days == null) continue;
      final actions = _asMap(days[today]);
      if (actions == null) continue;
      activeTodayUsers.add(uid);

      for (final actionEntry in actions.entries) {
        final action = actionEntry.key.toLowerCase();
        final data = _asMap(actionEntry.value) ?? const <String, dynamic>{};
        final status = _read(data, const ['attendance_status', 'status_absen', 'validation_status', 'status']).toLowerCase();
        if (action.contains('masuk') || action.contains('check_in') || action == 'in') checkedIn++;
        if (action.contains('pulang') || action.contains('check_out') || action == 'out') checkedOut++;
        if (status.contains('late') || status.contains('telat') || status.contains('terlambat')) late++;
        if (status.contains('outside') || status.contains('luar')) outsideRadius++;
      }
    }

    final pendingLeave = _countPending(leaveRequests);
    final pendingQr = _countPending(qrRequests);
    final pendingCorrection = _countPending(corrections);
    final overtimeToday = _countDateMatch(overtime, today);

    return _DashboardData(
      activeEmployees: activeEmployees,
      checkedIn: checkedIn,
      checkedOut: checkedOut,
      pendingApproval: pendingLeave + pendingQr + pendingCorrection,
      pendingLeave: pendingLeave,
      pendingQr: pendingQr,
      pendingCorrection: pendingCorrection,
      overtimeToday: overtimeToday,
      outsideRadius: outsideRadius,
      late: late,
      attendanceUsersToday: activeTodayUsers.length,
      announcements: announcements.length,
      scheduleLogs: scheduleLogs.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () async => refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dashboard Admin', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                    Text(AdminDateUtils.dayDate(DateTime.now()), style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              IconButton.filledTonal(onPressed: refresh, icon: const Icon(Icons.refresh_rounded)),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.business_rounded)),
              title: Text(widget.session.companyName, style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('${widget.session.displayName} • ${widget.session.role.toUpperCase()}'),
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<_DashboardData>(
            future: future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
              }
              if (snap.hasError) {
                return MessageCard(title: 'Dashboard gagal dimuat', message: snap.error.toString(), icon: Icons.error_outline_rounded);
              }
              final s = snap.data ?? const _DashboardData.empty();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.25,
                    children: [
                      _Stat('Karyawan Aktif', s.activeEmployees, Icons.people_rounded),
                      _Stat('Hadir Hari Ini', s.checkedIn, Icons.login_rounded),
                      _Stat('Sudah Pulang', s.checkedOut, Icons.logout_rounded),
                      _Stat('Pending Approval', s.pendingApproval, Icons.fact_check_rounded),
                      _Stat('Luar Radius', s.outsideRadius, Icons.wrong_location_rounded),
                      _Stat('Terlambat', s.late, Icons.timer_off_rounded),
                      _Stat('Lembur Hari Ini', s.overtimeToday, Icons.more_time_rounded),
                      _Stat('Pengumuman', s.announcements, Icons.campaign_rounded),
                    ],
                  ),
                  const SizedBox(height: 12),
                  MessageCard(
                    title: 'Ringkasan Approval',
                    message: 'Cuti: ${s.pendingLeave} • QR: ${s.pendingQr} • Koreksi: ${s.pendingCorrection}',
                    icon: Icons.pending_actions_rounded,
                  ),
                  const SizedBox(height: 12),
                  MessageCard(
                    title: 'Aktivitas Hari Ini',
                    message: 'User absensi hari ini: ${s.attendanceUsersToday} • Change log jadwal: ${s.scheduleLogs}',
                    icon: Icons.insights_rounded,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;

  const _Stat(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(child: Icon(icon)),
            const Spacer(),
            Text('$value', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _DashboardData {
  final int activeEmployees;
  final int checkedIn;
  final int checkedOut;
  final int pendingApproval;
  final int pendingLeave;
  final int pendingQr;
  final int pendingCorrection;
  final int overtimeToday;
  final int outsideRadius;
  final int late;
  final int attendanceUsersToday;
  final int announcements;
  final int scheduleLogs;

  const _DashboardData({
    required this.activeEmployees,
    required this.checkedIn,
    required this.checkedOut,
    required this.pendingApproval,
    required this.pendingLeave,
    required this.pendingQr,
    required this.pendingCorrection,
    required this.overtimeToday,
    required this.outsideRadius,
    required this.late,
    required this.attendanceUsersToday,
    required this.announcements,
    required this.scheduleLogs,
  });

  const _DashboardData.empty()
      : activeEmployees = 0,
        checkedIn = 0,
        checkedOut = 0,
        pendingApproval = 0,
        pendingLeave = 0,
        pendingQr = 0,
        pendingCorrection = 0,
        overtimeToday = 0,
        outsideRadius = 0,
        late = 0,
        attendanceUsersToday = 0,
        announcements = 0,
        scheduleLogs = 0;
}

int _countPending(Map<String, dynamic> source) {
  var count = 0;
  for (final entry in source.entries) {
    final data = _asMap(entry.value) ?? const <String, dynamic>{};
    final status = _read(data, const ['status', 'approval_status']).toLowerCase();
    if (status.isEmpty || status.contains('pending') || status.contains('menunggu')) count++;
  }
  return count;
}

int _countDateMatch(Map<String, dynamic> source, String date) {
  var count = 0;
  for (final entry in source.entries) {
    final data = _asMap(entry.value) ?? const <String, dynamic>{};
    final value = _read(data, const ['date', 'tanggal', 'start_date']);
    if (value == date) count++;
  }
  return count;
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

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
