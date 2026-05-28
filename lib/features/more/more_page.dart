import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../services/admin_service.dart';
import '../admin_web_port/admin_web_pages.dart';
import '../announcements/announcements_page.dart';
import '../approvals/approvals_page.dart';
import '../notifications/notification_logs_page.dart';
import '../reports/advanced_reports_page.dart';
import '../reports/reports_page.dart';

class MorePage extends StatelessWidget {
  final AdminSession session;
  final AdminService service;

  const MorePage({super.key, required this.session, required this.service});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOwner = session.role == 'owner';

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      children: [
        Text('Lainnya', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        _MoreTile('Approval', 'Approve cuti, QR, dan pengajuan.', Icons.fact_check_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ApprovalsPage(session: session, service: service)))),
        _MoreTile('Pengumuman', 'Buat dan publish pengumuman.', Icons.campaign_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AnnouncementsPage(session: session, service: service)))),
        _MoreTile('Notifikasi', 'Pantau queue push notification.', Icons.notifications_active_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotificationLogsPage(session: session, service: service)))),
        _MoreTile('Pengaturan Notifikasi', 'Port dari Notification Settings admin web.', Icons.notification_important_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotificationSettingsPage(session: session)))),
        _MoreTile('Laporan Ringkas', 'Lihat ringkasan laporan.', Icons.insert_chart_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReportsPage(session: session, service: service)))),
        _MoreTile('Advanced Reports', 'Port laporan absensi admin web dengan filter.', Icons.table_chart_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdvancedReportsPage(session: session)))),
        _MoreTile('Koreksi Absensi', 'Port dari Attendance Corrections admin web.', Icons.edit_calendar_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AttendanceCorrectionsPage(session: session)))),
        _MoreTile('Organisasi', 'Kantor, grup, dan struktur perusahaan.', Icons.account_tree_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrganizationPage(session: session)))),
        _MoreTile('Settings', 'Pengaturan perusahaan dan aplikasi.', Icons.settings_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsPage(session: session)))),
        if (isOwner) ...[
          _MoreTile('Companies', 'Daftar semua perusahaan.', Icons.business_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompaniesPage(session: session)))),
          _MoreTile('Company Admins', 'Kelola admin perusahaan.', Icons.admin_panel_settings_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompanyAdminsPage(session: session)))),
          _MoreTile('Audit', 'Log aktivitas admin.', Icons.history_edu_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AuditPage(session: session)))),
          _MoreTile('Database Health', 'Cek path database penting.', Icons.health_and_safety_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DatabaseHealthPage(session: session)))),
        ],
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.logout_rounded)),
            title: const Text('Keluar', style: TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text(session.email),
            onTap: service.signOut,
          ),
        ),
      ],
    );
  }
}

class _MoreTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _MoreTile(this.title, this.subtitle, this.icon, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
