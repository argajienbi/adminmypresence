import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../services/admin_service.dart';
import '../shell/admin_shell.dart';
import 'login_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AdminService service = AdminService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: service.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (user == null) return LoginPage(service: service);
        return FutureBuilder<AdminSession>(
          future: service.loadSession(user),
          builder: (context, sessionSnap) {
            if (sessionSnap.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
            if (sessionSnap.hasError || !sessionSnap.hasData) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.admin_panel_settings_outlined, size: 48),
                          const SizedBox(height: 12),
                          const Text('Sesi admin bermasalah', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                          const SizedBox(height: 8),
                          Text(sessionSnap.error.toString(), textAlign: TextAlign.center),
                          const SizedBox(height: 14),
                          FilledButton(onPressed: () => setState(() {}), child: const Text('Coba Lagi')),
                          TextButton(onPressed: service.signOut, child: const Text('Keluar')),
                        ]),
                      ),
                    ),
                  ),
                ),
              );
            }
            return AdminShell(session: sessionSnap.data!, service: service);
          },
        );
      },
    );
  }
}
