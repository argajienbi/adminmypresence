import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../services/admin_service.dart';
import '../admin_web_port/admin_web_pages.dart';
import '../announcements/announcements_page.dart';
import '../approvals/approvals_page.dart';
import '../attendance/attendance_corrections_page.dart';
import '../attendance/attendance_live_page.dart';
import '../audit/audit_logs_page.dart';
import '../health/database_health_full_page.dart';
import '../notifications/notification_logs_page.dart';
import '../notifications/notification_settings_page.dart';
import '../offices/office_radius_page.dart';
import '../organization/organization_management_page.dart';
import '../owner/owner_tools_page.dart';
import '../reports/advanced_reports_page.dart';
import '../reports/reports_page.dart';
import '../reports/reports_summary_page.dart';
import '../schedules/schedules_management_page.dart';
import '../settings/settings_management_page.dart';

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
        _MoreTile('Live Absensi', 'Pantau absensi harian, status, lokasi, dan radius.', Icons.monitor_heart_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AttendanceLivePage(session: session)))),
        _MoreTile('Approval', 'Approve cuti, QR, dan pengajuan.', Icons.fact_check_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ApprovalsPage(session: session, service: service)))),
        _MoreTile('Pengumuman', 'Buat dan publish pengumuman.', Icons.campaign_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AnnouncementsPage(session: session, service: service)))),
        _MoreTile('Notifikasi', 'Pantau queue push notification.', Icons.notifications_active_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotificationLogsPage(session: session, service: service)))),
        _MoreTile('Pengaturan Notifikasi', 'Atur notifikasi absensi, approval, jadwal, dan summary.', Icons.notification_important_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotificationSettingsPageFull(session: session)))),
        _MoreTile('Jadwal', 'Jam kerja, shift, assignment, libur, dan lembur.', Icons.calendar_month_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SchedulesManagementPage(session: session)))),
        _MoreTile('Radius Kantor', 'Atur titik kantor dan radius absen.', Icons.map_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OfficeRadiusPage(session: session)))),
        _MoreTile('Laporan Ringkas', 'Lihat ringkasan laporan lama.', Icons.insert_chart_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReportsPage(session: session, service: service)))),
        _MoreTile('Reports Summary', 'Ringkasan absensi per karyawan dan export Excel.', Icons.summarize_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReportsSummaryPage(session: session)))),
        _MoreTile('Advanced Reports', 'Detail absensi lengkap dengan export Excel.', Icons.table_chart_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdvancedReportsPage(session: session)))),
        _MoreTile('Koreksi Absensi', 'Review, approve, dan reject koreksi absensi.', Icons.edit_calendar_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AttendanceCorrectionsListPage(session: session)))),
        _MoreTile('Organisasi', 'Area, kantor, departemen, sub departemen, dan grup.', Icons.account_tree_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrganizationManagementPage(session: session)))),
        _MoreTile('Settings', 'Profil company, aturan absensi, approval, dan app config.', Icons.settings_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsManagementPage(session: session)))),
        if (isOwner) ...[
          _MoreTile('Owner Tools', 'Kelola company, admin, invite, dan status aktif.', Icons.admin_panel_settings_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OwnerToolsPage(session: session)))),
          _MoreTile('Audit', 'Filter dan detail log aktivitas admin.', Icons.history_edu_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AuditLogsPage(session: session)))),
          _MoreTile('Database Health', 'Cek path, count, status, dan raw data.', Icons.health_and_safety_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DatabaseHealthFullPage(session: session)))),
        ],
        const SizedBox(height: 12),
        Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.logout_rounded)), title: const Text('Keluar', style: TextStyle(fontWeight: FontWeight.w900)), subtitle: Text(session.email), onTap: service.signOut)),
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
    return Card(child: ListTile(onTap: onTap, leading: CircleAvatar(child: Icon(icon)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_right_rounded)));
  }
}
