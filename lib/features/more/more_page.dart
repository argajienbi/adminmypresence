import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../services/admin_service.dart';
import '../announcements/announcements_page.dart';
import '../notifications/notification_logs_page.dart';
import '../reports/reports_page.dart';

class MorePage extends StatelessWidget {
  final AdminSession session; final AdminService service;
  const MorePage({super.key, required this.session, required this.service});
  @override
  Widget build(BuildContext context) {
    final theme=Theme.of(context);
    return ListView(padding: const EdgeInsets.fromLTRB(18,18,18,24), children:[
      Text('Lainnya', style:theme.textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w900)), const SizedBox(height:12),
      _MoreTile('Pengumuman','Buat dan publish pengumuman.',Icons.campaign_rounded,()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>AnnouncementsPage(session:session, service:service)))),
      _MoreTile('Notifikasi','Pantau queue push notification.',Icons.notifications_active_rounded,()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>NotificationLogsPage(session:session, service:service)))),
      _MoreTile('Laporan','Lihat ringkasan laporan.',Icons.insert_chart_rounded,()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>ReportsPage(session:session, service:service)))),
      const SizedBox(height:12), Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.logout_rounded)), title:const Text('Keluar', style:TextStyle(fontWeight:FontWeight.w900)), subtitle:Text(session.email), onTap:service.signOut)),
    ]);
  }
}
class _MoreTile extends StatelessWidget { final String t,s; final IconData i; final VoidCallback tap; const _MoreTile(this.t,this.s,this.i,this.tap); @override Widget build(BuildContext context)=>Card(child:ListTile(onTap:tap, leading:CircleAvatar(child:Icon(i)), title:Text(t, style:const TextStyle(fontWeight:FontWeight.w900)), subtitle:Text(s), trailing:const Icon(Icons.chevron_right_rounded))); }
