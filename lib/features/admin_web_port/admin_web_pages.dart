import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/date_utils.dart';
import '../../core/models.dart';
import '../shared/message_card.dart';

class CompaniesPage extends StatelessWidget {
  const CompaniesPage({super.key, required this.session});
  final AdminSession session;

  @override
  Widget build(BuildContext context) {
    return const AdminDataPage(
      title: 'Companies',
      subtitle: 'Daftar perusahaan dari admin web.',
      icon: Icons.business_rounded,
      path: 'companies',
      titleKeys: ['name', 'company_name', 'nama_perusahaan'],
      subtitleKeys: ['status', 'owner_email', 'email', 'created_at'],
    );
  }
}

class CompanyAdminsPage extends StatelessWidget {
  const CompanyAdminsPage({super.key, required this.session});
  final AdminSession session;

  @override
  Widget build(BuildContext context) {
    return AdminDataPage(
      title: 'Company Admins',
      subtitle: 'Daftar admin perusahaan.',
      icon: Icons.admin_panel_settings_rounded,
      path: 'company_admins/${session.companyId}',
      fallbackPath: 'users',
      titleKeys: const ['display_name', 'nama_lengkap', 'name', 'email'],
      subtitleKeys: const ['role', 'company_name', 'status', 'status_akun'],
      filterRole: 'admin',
    );
  }
}

class OrganizationPage extends StatelessWidget {
  const OrganizationPage({super.key, required this.session});
  final AdminSession session;

  @override
  Widget build(BuildContext context) {
    return AdminDataPage(
      title: 'Organization',
      subtitle: 'Kantor, grup, dan struktur organisasi.',
      icon: Icons.account_tree_rounded,
      path: 'organizations/${session.companyId}',
      fallbackPath: 'companies/${session.companyId}',
      titleKeys: const ['name', 'nama', 'office_name', 'group_name'],
      subtitleKeys: const ['type', 'alamat', 'address', 'status'],
    );
  }
}

class AttendancePage extends StatelessWidget {
  const AttendancePage({super.key, required this.session});
  final AdminSession session;

  @override
  Widget build(BuildContext context) {
    final today = AdminDateUtils.dateKey(DateTime.now());
    return AdminDataPage(
      title: 'Attendance',
      subtitle: 'Absensi hari ini.',
      icon: Icons.access_time_filled_rounded,
      path: 'attendance/${session.companyId}/$today',
      titleKeys: const ['nama_lengkap', 'name', 'display_name', 'uid'],
      subtitleKeys: const ['status', 'check_in', 'masuk', 'check_out', 'pulang'],
    );
  }
}

class AttendanceCorrectionsPage extends StatelessWidget {
  const AttendanceCorrectionsPage({super.key, required this.session});
  final AdminSession session;

  @override
  Widget build(BuildContext context) {
    return AdminDataPage(
      title: 'Attendance Corrections',
      subtitle: 'Koreksi absensi yang diajukan karyawan.',
      icon: Icons.edit_calendar_rounded,
      path: 'attendance_corrections/${session.companyId}',
      titleKeys: const ['employee_name', 'nama_lengkap', 'name', 'uid'],
      subtitleKeys: const ['status', 'date', 'reason', 'type'],
    );
  }
}

class NotificationSettingsPage extends StatelessWidget {
  const NotificationSettingsPage({super.key, required this.session});
  final AdminSession session;

  @override
  Widget build(BuildContext context) {
    return AdminDataPage(
      title: 'Notification Settings',
      subtitle: 'Pengaturan notifikasi perusahaan.',
      icon: Icons.notifications_active_rounded,
      path: 'companies/${session.companyId}/notification_settings',
      titleKeys: const ['title', 'name', 'type', 'key'],
      subtitleKeys: const ['enabled', 'status', 'description', 'value'],
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.session});
  final AdminSession session;

  @override
  Widget build(BuildContext context) {
    return AdminDataPage(
      title: 'Settings',
      subtitle: 'Pengaturan perusahaan dan aplikasi admin.',
      icon: Icons.settings_rounded,
      path: 'companies/${session.companyId}/settings',
      fallbackPath: 'companies/${session.companyId}',
      titleKeys: const ['name', 'company_name', 'nama_perusahaan', 'key'],
      subtitleKeys: const ['status', 'timezone', 'address', 'value'],
    );
  }
}

class AuditPage extends StatelessWidget {
  const AuditPage({super.key, required this.session});
  final AdminSession session;

  @override
  Widget build(BuildContext context) {
    return AdminDataPage(
      title: 'Audit',
      subtitle: 'Aktivitas dan perubahan data admin.',
      icon: Icons.history_edu_rounded,
      path: 'audit_logs/${session.companyId}',
      fallbackPath: 'companies/${session.companyId}/audit_logs',
      titleKeys: const ['action', 'title', 'event', 'type'],
      subtitleKeys: const ['actor_name', 'actor_email', 'created_at', 'timestamp'],
    );
  }
}

class DatabaseHealthPage extends StatelessWidget {
  const DatabaseHealthPage({super.key, required this.session});
  final AdminSession session;

  @override
  Widget build(BuildContext context) {
    final paths = [
      'companies/${session.companyId}',
      'company_users/${session.companyId}',
      'attendance/${session.companyId}',
      'leave_requests/${session.companyId}',
      'qr_attendance_requests/${session.companyId}',
      'timetables/${session.companyId}',
      'shifts/${session.companyId}',
      'schedule_assignments/${session.companyId}',
      'schedule_specials/${session.companyId}',
      'overtime_schedules/${session.companyId}',
      'announcements/${session.companyId}',
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Database Health')),
      body: FutureBuilder<List<_HealthItem>>(
        future: _load(paths),
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <_HealthItem>[];
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const MessageCard(
                title: 'Database Health',
                message: 'Cek cepat path penting yang dipakai admin web dan app.',
                icon: Icons.health_and_safety_rounded,
              ),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                ...items.map(
                  (item) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(item.exists ? Icons.check_rounded : Icons.close_rounded),
                      ),
                      title: Text(item.path, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(item.exists ? 'OK' : 'Belum ada data'),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<List<_HealthItem>> _load(List<String> paths) async {
    final db = FirebaseDatabase.instance;
    final items = <_HealthItem>[];
    for (final path in paths) {
      final snap = await db.ref(path).get();
      items.add(_HealthItem(path: path, exists: snap.exists));
    }
    return items;
  }
}

class AdminDataPage extends StatefulWidget {
  const AdminDataPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.path,
    required this.titleKeys,
    required this.subtitleKeys,
    this.fallbackPath,
    this.filterRole,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String path;
  final String? fallbackPath;
  final String? filterRole;
  final List<String> titleKeys;
  final List<String> subtitleKeys;

  @override
  State<AdminDataPage> createState() => _AdminDataPageState();
}

class _AdminDataPageState extends State<AdminDataPage> {
  late Future<List<_DataRow>> future;

  @override
  void initState() {
    super.initState();
    future = loadRows();
  }

  void refresh() {
    setState(() => future = loadRows());
  }

  Future<List<_DataRow>> loadRows() async {
    final db = FirebaseDatabase.instance;
    var snap = await db.ref(widget.path).get();
    if (!snap.exists && widget.fallbackPath != null) {
      snap = await db.ref(widget.fallbackPath!).get();
    }
    final value = snap.value;
    if (value is! Map) return const <_DataRow>[];

    final rows = <_DataRow>[];
    for (final entry in value.entries) {
      final data = _asMap(entry.value);
      if (data == null) continue;
      if (widget.filterRole != null) {
        final role = _read(data, const ['role', 'level']).toLowerCase();
        if (role != widget.filterRole) continue;
      }
      rows.add(
        _DataRow(
          id: entry.key.toString(),
          title: _read(data, widget.titleKeys).ifEmpty(entry.key.toString()),
          subtitle: _read(data, widget.subtitleKeys).ifEmpty('Tidak ada detail'),
        ),
      );
    }
    rows.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: FutureBuilder<List<_DataRow>>(
        future: future,
        builder: (context, snapshot) {
          final rows = snapshot.data ?? const <_DataRow>[];
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              MessageCard(title: widget.title, message: widget.subtitle, icon: widget.icon),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot.hasError)
                MessageCard(title: 'Gagal memuat data', message: snapshot.error.toString(), icon: Icons.error_outline_rounded)
              else if (rows.isEmpty)
                const MessageCard(title: 'Belum ada data', message: 'Data untuk modul ini belum tersedia.', icon: Icons.inbox_outlined)
              else
                ...rows.map(
                  (row) => Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.storage_rounded)),
                      title: Text(row.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: Text(row.subtitle),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DataRow {
  const _DataRow({required this.id, required this.title, required this.subtitle});
  final String id;
  final String title;
  final String subtitle;
}

class _HealthItem {
  const _HealthItem({required this.path, required this.exists});
  final String path;
  final bool exists;
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
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
