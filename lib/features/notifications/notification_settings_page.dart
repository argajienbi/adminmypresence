import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/firebase_paths.dart';
import '../../core/models.dart';
import '../../services/notification_bridge.dart';
import '../shared/message_card.dart';

class NotificationSettingsPageFull extends StatefulWidget {
  final AdminSession session;

  const NotificationSettingsPageFull({super.key, required this.session});

  @override
  State<NotificationSettingsPageFull> createState() => _NotificationSettingsPageFullState();
}

class _NotificationSettingsPageFullState extends State<NotificationSettingsPageFull> {
  late Future<_NotificationBundle> future;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    future = load();
  }

  void refresh() {
    setState(() => future = load());
  }

  Future<_NotificationBundle> load() async {
    final companyId = widget.session.companyId;
    final results = await Future.wait([
      FirebaseFirestore.instance.doc(FirestorePaths.notificationSettings(companyId)).get(),
      FirebaseFirestore.instance.collection(FirestorePaths.notificationQueue(companyId)).get(),
      FirebaseFirestore.instance.collection(FirestorePaths.notificationLogs(companyId)).get(),
    ]);

    final settingsDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    final queueSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final logsSnap = results[2] as QuerySnapshot<Map<String, dynamic>>;
    final settings = settingsDoc.data() ?? const <String, dynamic>{};

    return _NotificationBundle(
      settings: _NotificationSettings.fromMap(settings),
      queueCount: queueSnap.docs.length,
      logCount: logsSnap.docs.length,
      logs: logsSnap.docs.map((doc) => _NotificationLog(id: doc.id, data: doc.data())).toList()
        ..sort((a, b) => b.sortKey.compareTo(a.sortKey)),
    );
  }

  Future<void> saveSettings(_NotificationSettings settings) async {
    setState(() => saving = true);
    try {
      await FirebaseFirestore.instance.doc(FirestorePaths.notificationSettings(widget.session.companyId)).set({
        ...settings.toMap(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'updated_by': widget.session.uid,
      }, SetOptions(merge: true));
      refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> addTestQueue() async {
    final title = TextEditingController(text: 'Test Notification');
    final body = TextEditingController(text: 'Pesan test dari Admin MyPresence');
    final uid = TextEditingController();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Tambah Queue Notifikasi', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Judul')),
              const SizedBox(height: 10),
              TextField(controller: body, decoration: const InputDecoration(labelText: 'Pesan')),
              const SizedBox(height: 10),
              TextField(controller: uid, decoration: const InputDecoration(labelText: 'UID target karyawan')),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Tambahkan')),
            ],
          ),
        ),
      ),
    );

    if (ok == true && uid.text.trim().isNotEmpty) {
      await NotificationBridge().createNotification(
        uid: uid.text.trim(),
        companyId: widget.session.companyId,
        title: title.text.trim(),
        message: body.text.trim(),
        type: 'info',
        refType: 'manual_test',
        refId: 'test_${DateTime.now().millisecondsSinceEpoch}',
      );
      refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan Notifikasi'), actions: [IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
      floatingActionButton: FloatingActionButton.extended(onPressed: addTestQueue, icon: const Icon(Icons.add_alert_rounded), label: const Text('Queue')),
      body: FutureBuilder<_NotificationBundle>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(18),
              children: [MessageCard(title: 'Gagal memuat notifikasi', message: snapshot.error.toString(), icon: Icons.error_outline_rounded)],
            );
          }

          final bundle = snapshot.data ?? const _NotificationBundle.empty();
          final settings = bundle.settings;

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              MessageCard(
                title: 'Notification Center',
                message: 'Queue: ${bundle.queueCount} • Logs: ${bundle.logCount}',
                icon: Icons.notifications_active_rounded,
              ),
              const SizedBox(height: 12),
              _SwitchTile(title: 'Absensi', subtitle: 'Notifikasi check-in/check-out.', value: settings.attendanceEnabled, onChanged: (value) => saveSettings(settings.copyWith(attendanceEnabled: value))),
              _SwitchTile(title: 'Approval', subtitle: 'Notifikasi cuti, QR, dan koreksi.', value: settings.approvalEnabled, onChanged: (value) => saveSettings(settings.copyWith(approvalEnabled: value))),
              _SwitchTile(title: 'Pengumuman', subtitle: 'Push notification saat pengumuman dipublish.', value: settings.announcementEnabled, onChanged: (value) => saveSettings(settings.copyWith(announcementEnabled: value))),
              _SwitchTile(title: 'Jadwal', subtitle: 'Notifikasi perubahan jadwal.', value: settings.scheduleEnabled, onChanged: (value) => saveSettings(settings.copyWith(scheduleEnabled: value))),
              _SwitchTile(title: 'Luar Radius', subtitle: 'Alert jika absensi berada di luar radius kantor.', value: settings.outsideRadiusEnabled, onChanged: (value) => saveSettings(settings.copyWith(outsideRadiusEnabled: value))),
              _SwitchTile(title: 'Terlambat', subtitle: 'Alert keterlambatan karyawan.', value: settings.lateEnabled, onChanged: (value) => saveSettings(settings.copyWith(lateEnabled: value))),
              _SwitchTile(title: 'Daily Summary', subtitle: 'Ringkasan harian admin.', value: settings.dailySummaryEnabled, onChanged: (value) => saveSettings(settings.copyWith(dailySummaryEnabled: value))),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.schedule_send_rounded)),
                  title: const Text('Jam Daily Summary', style: TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text(settings.dailySummaryTime),
                  trailing: saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.edit_rounded),
                  onTap: () async {
                    final controller = TextEditingController(text: settings.dailySummaryTime);
                    final ok = await showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => SafeArea(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('Jam Daily Summary', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                              const SizedBox(height: 12),
                              TextField(controller: controller, decoration: const InputDecoration(labelText: 'HH:mm', hintText: '08:00')),
                              const SizedBox(height: 12),
                              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Simpan')),
                            ],
                          ),
                        ),
                      ),
                    );
                    if (ok == true) saveSettings(settings.copyWith(dailySummaryTime: controller.text.trim()));
                  },
                ),
              ),
              const SizedBox(height: 18),
              Text('Log Terbaru', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              if (bundle.logs.isEmpty)
                const MessageCard(title: 'Belum ada log', message: 'Log notifikasi akan tampil di sini.', icon: Icons.list_alt_rounded)
              else
                ...bundle.logs.take(20).map((log) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.notifications_rounded)),
                        title: Text(log.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text(log.subtitle),
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({required this.title, required this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        secondary: const CircleAvatar(child: Icon(Icons.notifications_active_rounded)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class _NotificationBundle {
  final _NotificationSettings settings;
  final int queueCount;
  final int logCount;
  final List<_NotificationLog> logs;

  const _NotificationBundle({required this.settings, required this.queueCount, required this.logCount, required this.logs});
  const _NotificationBundle.empty() : settings = const _NotificationSettings.defaults(), queueCount = 0, logCount = 0, logs = const [];
}

class _NotificationSettings {
  final bool attendanceEnabled;
  final bool approvalEnabled;
  final bool announcementEnabled;
  final bool scheduleEnabled;
  final bool outsideRadiusEnabled;
  final bool lateEnabled;
  final bool dailySummaryEnabled;
  final String dailySummaryTime;

  const _NotificationSettings({required this.attendanceEnabled, required this.approvalEnabled, required this.announcementEnabled, required this.scheduleEnabled, required this.outsideRadiusEnabled, required this.lateEnabled, required this.dailySummaryEnabled, required this.dailySummaryTime});
  const _NotificationSettings.defaults() : attendanceEnabled = true, approvalEnabled = true, announcementEnabled = true, scheduleEnabled = true, outsideRadiusEnabled = true, lateEnabled = true, dailySummaryEnabled = false, dailySummaryTime = '08:00';

  factory _NotificationSettings.fromMap(Map<String, dynamic> data) {
    return _NotificationSettings(
      attendanceEnabled: _bool(data['attendance_reminder_enabled'] ?? data['attendance_enabled'], true),
      approvalEnabled: _bool(data['approval_push_enabled'] ?? data['approval_enabled'], true),
      announcementEnabled: _bool(data['announcement_push_enabled'] ?? data['announcement_enabled'], true),
      scheduleEnabled: _bool(data['schedule_change_push_enabled'] ?? data['schedule_enabled'], true),
      outsideRadiusEnabled: _bool(data['outside_radius_enabled'], true),
      lateEnabled: _bool(data['late_enabled'], true),
      dailySummaryEnabled: _bool(data['daily_summary_enabled'], false),
      dailySummaryTime: data['daily_summary_time']?.toString() ?? '08:00',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'push_enabled': true,
      'in_app_enabled': true,
      'attendance_reminder_enabled': attendanceEnabled,
      'pre_check_in_enabled': attendanceEnabled,
      'pre_check_in_minutes': 15,
      'missed_check_in_enabled': attendanceEnabled,
      'missed_check_in_minutes': 10,
      'pre_check_out_enabled': attendanceEnabled,
      'pre_check_out_minutes': 15,
      'missed_check_out_enabled': attendanceEnabled,
      'missed_check_out_minutes': 10,
      'announcement_push_enabled': announcementEnabled,
      'approval_push_enabled': approvalEnabled,
      'schedule_change_push_enabled': scheduleEnabled,
      'holiday_notice_push_enabled': scheduleEnabled,
      'outside_radius_enabled': outsideRadiusEnabled,
      'late_enabled': lateEnabled,
      'daily_summary_enabled': dailySummaryEnabled,
      'daily_summary_time': dailySummaryTime,
    };
  }

  _NotificationSettings copyWith({bool? attendanceEnabled, bool? approvalEnabled, bool? announcementEnabled, bool? scheduleEnabled, bool? outsideRadiusEnabled, bool? lateEnabled, bool? dailySummaryEnabled, String? dailySummaryTime}) {
    return _NotificationSettings(
      attendanceEnabled: attendanceEnabled ?? this.attendanceEnabled,
      approvalEnabled: approvalEnabled ?? this.approvalEnabled,
      announcementEnabled: announcementEnabled ?? this.announcementEnabled,
      scheduleEnabled: scheduleEnabled ?? this.scheduleEnabled,
      outsideRadiusEnabled: outsideRadiusEnabled ?? this.outsideRadiusEnabled,
      lateEnabled: lateEnabled ?? this.lateEnabled,
      dailySummaryEnabled: dailySummaryEnabled ?? this.dailySummaryEnabled,
      dailySummaryTime: dailySummaryTime ?? this.dailySummaryTime,
    );
  }
}

class _NotificationLog {
  final String id;
  final Map<String, dynamic> data;

  const _NotificationLog({required this.id, required this.data});

  String get title => _read(data, const ['title', 'type', 'event']).ifEmpty(id);
  String get subtitle => '${_read(data, const ['body', 'message', 'status']).ifEmpty('-')} • ${data['created_at'] ?? data['sent_at'] ?? ''}';
  String get sortKey => '${data['created_at'] ?? data['sent_at'] ?? ''}$id';
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
