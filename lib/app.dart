import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'features/auth/auth_gate.dart';

class AdminMyPresenceApp extends StatelessWidget {
  const AdminMyPresenceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Admin MyPresence',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AuthGate(),
    );
  }
}
