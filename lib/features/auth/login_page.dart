import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/admin_service.dart';

class LoginPage extends StatefulWidget {
  final AdminService service;
  const LoginPage({super.key, required this.service});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  bool obscure = true;
  bool loading = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => loading = true);
    try {
      await widget.service.signIn(email.text, password.text);
    } on FirebaseAuthException catch (e) {
      showSnack(e.code == 'invalid-credential' ? 'Email atau password salah.' : (e.message ?? 'Login gagal.'));
    } catch (e) {
      showSnack(e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void showSnack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: formKey,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Icon(Icons.admin_panel_settings_rounded, color: theme.colorScheme.primary, size: 64),
                  const SizedBox(height: 16),
                  Text('Admin MyPresence', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text('Masuk sebagai owner/admin perusahaan.', textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 24),
                  TextFormField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email admin', prefixIcon: Icon(Icons.email_outlined)), validator: (v) => (v ?? '').contains('@') ? null : 'Email tidak valid.'),
                  const SizedBox(height: 12),
                  TextFormField(controller: password, obscureText: obscure, decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined))), validator: (v) => (v ?? '').isEmpty ? 'Password wajib diisi.' : null),
                  const SizedBox(height: 18),
                  FilledButton.icon(onPressed: loading ? null : submit, icon: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login_rounded), label: Text(loading ? 'Masuk...' : 'Masuk')),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
