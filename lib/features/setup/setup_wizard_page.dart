import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../services/admin_service.dart';
import '../../services/firestore_user_sync_service.dart';
import '../employees/employees_page.dart';
import '../organization/organization_management_page.dart';
import '../owner/owner_tools_page.dart';
import '../schedules/schedules_management_page.dart';
import '../settings/settings_management_page.dart';
import '../shared/message_card.dart';

class SetupWizardPage extends StatefulWidget {
  const SetupWizardPage({super.key, required this.session, required this.service});

  final AdminSession session;
  final AdminService service;

  @override
  State<SetupWizardPage> createState() => _SetupWizardPageState();
}

class _SetupWizardPageState extends State<SetupWizardPage> {
  late Future<SetupStats> future;
  bool syncing = false;

  @override
  void initState() {
    super.initState();
    future = loadStats();
  }

  void refresh() => setState(() => future = loadStats());

  Future<SetupStats> loadStats() async {
    final companyId = widget.session.companyId;
    final db = FirebaseDatabase.instance;
    final results = await Future.wait([
      db.ref('companies/$companyId').get(),
      db.ref('offices/$companyId').get(),
      db.ref('areas/$companyId').get(),
      db.ref('departments/$companyId').get(),
      db.ref('sub_departments/$companyId').get(),
      db.ref('employee_groups/$companyId').get(),
      db.ref('timetables/$companyId').get(),
      db.ref('shifts/$companyId').get(),
      db.ref('schedule_assignments/$companyId').get(),
      db.ref('company_users/$companyId').get(),
    ]);

    return SetupStats(
      hasCompany: results[0].exists,
      officeCount: _activeCount(results[1].value),
      areaCount: _activeCount(results[2].value),
      departmentCount: _activeCount(results[3].value),
      subDepartmentCount: _activeCount(results[4].value),
      groupCount: _activeCount(results[5].value),
      timetableCount: _activeCount(results[6].value),
      shiftCount: _activeCount(results[7].value),
      assignmentCount: _activeCount(results[8].value),
      employeeCount: _activeCount(results[9].value),
    );
  }

  Future<void> syncUsers() async {
    setState(() => syncing = true);
    try {
      final result = await FirestoreUserSyncService().sync(companyId: widget.session.companyId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync Firestore selesai: ${result.synced}/${result.total} user.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  void open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)).then((_) => refresh());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setup Awal'), actions: [IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
      body: FutureBuilder<SetupStats>(
        future: future,
        builder: (context, snapshot) {
          final stats = snapshot.data ?? const SetupStats.empty();
          final progress = stats.progress;
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              MessageCard(
                title: 'Progress Setup ${progress.toStringAsFixed(0)}%',
                message: stats.complete ? 'Setup utama sudah selesai.' : 'Selesaikan langkah setup agar karyawan siap menggunakan presensi.',
                icon: Icons.checklist_rounded,
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress / 100),
              if (syncing) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                MessageCard(title: 'Gagal memuat setup', message: snapshot.error.toString(), icon: Icons.error_outline_rounded)
              else ...[
                _StepTile(done: stats.hasCompany, title: 'Lengkapi Data Perusahaan', subtitle: widget.session.companyName, icon: Icons.business_rounded, onTap: () => open(widget.session.isOwner ? OwnerToolsPage(session: widget.session) : SettingsManagementPage(session: widget.session))),
                _StepTile(done: stats.hasOffice, title: 'Kantor / Lokasi Kerja', subtitle: '${stats.officeCount} lokasi aktif', icon: Icons.location_city_rounded, onTap: () => open(OrganizationManagementPage(session: widget.session))),
                _StepTile(done: stats.hasArea, title: 'Area Wilayah', subtitle: '${stats.areaCount} area aktif', icon: Icons.map_rounded, onTap: () => open(OrganizationManagementPage(session: widget.session))),
                _StepTile(done: stats.hasDepartment, title: 'Departemen', subtitle: '${stats.departmentCount} departemen aktif', icon: Icons.apartment_rounded, onTap: () => open(OrganizationManagementPage(session: widget.session))),
                _StepTile(done: stats.hasSubDepartment, title: 'Sub Departemen', subtitle: '${stats.subDepartmentCount} sub departemen aktif', icon: Icons.account_tree_rounded, onTap: () => open(OrganizationManagementPage(session: widget.session))),
                _StepTile(done: stats.hasGroup, title: 'Grup Karyawan', subtitle: '${stats.groupCount} grup aktif', icon: Icons.groups_rounded, onTap: () => open(OrganizationManagementPage(session: widget.session))),
                _StepTile(done: stats.hasTimetable, title: 'Jam Kerja', subtitle: '${stats.timetableCount} jam kerja aktif', icon: Icons.access_time_rounded, onTap: () => open(SchedulesManagementPage(session: widget.session))),
                _StepTile(done: stats.hasShift, title: 'Pola Shift', subtitle: '${stats.shiftCount} shift aktif', icon: Icons.work_history_rounded, onTap: () => open(SchedulesManagementPage(session: widget.session))),
                _StepTile(done: stats.hasAssignment, title: 'Terapkan Jadwal', subtitle: '${stats.assignmentCount} assignment aktif', icon: Icons.assignment_ind_rounded, onTap: () => open(SchedulesManagementPage(session: widget.session))),
                _StepTile(done: stats.hasEmployee, title: 'Karyawan', subtitle: '${stats.employeeCount} karyawan aktif', icon: Icons.people_rounded, onTap: () => open(EmployeesPage(session: widget.session, service: widget.service))),
                _StepTile(done: stats.hasAssignment && stats.hasEmployee, title: 'Cek Jadwal Karyawan', subtitle: 'Validasi assignment, shift, timetable, dan hari aktif', icon: Icons.rule_rounded, onTap: () => open(SchedulesManagementPage(session: widget.session))),
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: syncing ? null : syncUsers, icon: const Icon(Icons.cloud_sync_rounded), label: Text(syncing ? 'Sync...' : 'Sync Users RTDB ke Firestore')),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.done, required this.title, required this.subtitle, required this.icon, required this.onTap});

  final bool done;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(done ? Icons.check_rounded : icon)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class SetupStats {
  const SetupStats({
    required this.hasCompany,
    required this.officeCount,
    required this.areaCount,
    required this.departmentCount,
    required this.subDepartmentCount,
    required this.groupCount,
    required this.timetableCount,
    required this.shiftCount,
    required this.assignmentCount,
    required this.employeeCount,
  });

  const SetupStats.empty()
      : hasCompany = false,
        officeCount = 0,
        areaCount = 0,
        departmentCount = 0,
        subDepartmentCount = 0,
        groupCount = 0,
        timetableCount = 0,
        shiftCount = 0,
        assignmentCount = 0,
        employeeCount = 0;

  final bool hasCompany;
  final int officeCount;
  final int areaCount;
  final int departmentCount;
  final int subDepartmentCount;
  final int groupCount;
  final int timetableCount;
  final int shiftCount;
  final int assignmentCount;
  final int employeeCount;

  bool get hasOffice => officeCount > 0;
  bool get hasArea => areaCount > 0;
  bool get hasDepartment => departmentCount > 0;
  bool get hasSubDepartment => subDepartmentCount > 0;
  bool get hasGroup => groupCount > 0;
  bool get hasTimetable => timetableCount > 0;
  bool get hasShift => shiftCount > 0;
  bool get hasAssignment => assignmentCount > 0;
  bool get hasEmployee => employeeCount > 0;

  int get doneCount => [hasCompany, hasOffice, hasArea, hasDepartment, hasSubDepartment, hasGroup, hasTimetable, hasShift, hasAssignment, hasEmployee].where((done) => done).length;
  double get progress => doneCount * 10;
  bool get complete => doneCount == 10;
}

int _activeCount(Object? value) {
  final data = _asMap(value) ?? const <String, dynamic>{};
  var count = 0;
  for (final entry in data.values) {
    final item = _asMap(entry) ?? const <String, dynamic>{};
    if (item['active'] != false && item['status']?.toString().toLowerCase() != 'inactive' && item['status_akun']?.toString().toLowerCase() != 'inactive') count++;
  }
  return count;
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map) return value.map((key, item) => MapEntry(key.toString(), item));
  return null;
}
