import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../services/admin_service.dart';
import '../approvals/approvals_page.dart';
import '../dashboard/dashboard_page.dart';
import '../employees/employees_page.dart';
import '../more/more_page.dart';
import '../schedules/schedules_page.dart';

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
      SchedulesPage(session: widget.session, service: widget.service),
      EmployeesPage(session: widget.session, service: widget.service),
      ApprovalsPage(session: widget.session, service: widget.service),
      MorePage(session: widget.session, service: widget.service),
    ];
    return Scaffold(
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note_rounded), label: 'Jadwal'),
          NavigationDestination(icon: Icon(Icons.people_outline_rounded), selectedIcon: Icon(Icons.people_rounded), label: 'Karyawan'),
          NavigationDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check_rounded), label: 'Approval'),
          NavigationDestination(icon: Icon(Icons.more_horiz_rounded), selectedIcon: Icon(Icons.more_rounded), label: 'Lainnya'),
        ],
      ),
    );
  }
}
