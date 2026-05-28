import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../services/admin_service.dart';
import '../admin_web_port/admin_web_pages.dart';
import '../approvals/approvals_page.dart';
import '../dashboard/dashboard_page.dart';
import '../employees/employees_page.dart';
import '../more/more_page.dart';
import '../schedules/schedule_management_page.dart';

class AdminShell extends StatefulWidget {
  final AdminSession session;
  final AdminService service;
  const AdminShell({super.key, required this.session, required this.service});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(session: widget.session, service: widget.service),
      AttendancePage(session: widget.session),
      ScheduleManagementPage(session: widget.session),
      EmployeesPage(session: widget.session, service: widget.service),
      MorePage(session: widget.session, service: widget.service),
    ];

    return Scaffold(
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.access_time_outlined), selectedIcon: Icon(Icons.access_time_filled_rounded), label: 'Absensi'),
          NavigationDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note_rounded), label: 'Jadwal'),
          NavigationDestination(icon: Icon(Icons.people_outline_rounded), selectedIcon: Icon(Icons.people_rounded), label: 'Karyawan'),
          NavigationDestination(icon: Icon(Icons.more_horiz_rounded), selectedIcon: Icon(Icons.more_rounded), label: 'Lainnya'),
        ],
      ),
      floatingActionButton: index == 4
          ? null
          : FloatingActionButton.small(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ApprovalsPage(session: widget.session, service: widget.service),
                ),
              ),
              child: const Icon(Icons.fact_check_rounded),
            ),
    );
  }
}
