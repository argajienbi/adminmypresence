import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../shared/message_card.dart';

class PayrollSettingsPage extends StatefulWidget {
  final AdminSession session;

  const PayrollSettingsPage({super.key, required this.session});

  @override
  State<PayrollSettingsPage> createState() => _PayrollSettingsPageState();
}

class _PayrollSettingsPageState extends State<PayrollSettingsPage> {
  final lateDeduction = TextEditingController();
  final outsideRadiusDeduction = TextEditingController();
  final rejectedDeduction = TextEditingController();
  final overtimeRate = TextEditingController();
  bool saving = false;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  @override
  void dispose() {
    lateDeduction.dispose();
    outsideRadiusDeduction.dispose();
    rejectedDeduction.dispose();
    overtimeRate.dispose();
    super.dispose();
  }

  DatabaseReference get ref => FirebaseDatabase.instance.ref('payroll_settings/${widget.session.companyId}');

  Future<void> loadSettings() async {
    final snap = await ref.get();
    final data = _asMap(snap.value) ?? const <String, dynamic>{};
    lateDeduction.text = _read(data, const ['late_deduction_amount']).ifEmpty('0');
    outsideRadiusDeduction.text = _read(data, const ['outside_radius_deduction_amount']).ifEmpty('0');
    rejectedDeduction.text = _read(data, const ['rejected_deduction_amount']).ifEmpty('0');
    overtimeRate.text = _read(data, const ['overtime_rate_per_hour']).ifEmpty('0');
    if (mounted) setState(() => loaded = true);
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await ref.update({
        'company_id': widget.session.companyId,
        'late_deduction_amount': _toInt(lateDeduction.text),
        'outside_radius_deduction_amount': _toInt(outsideRadiusDeduction.text),
        'rejected_deduction_amount': _toInt(rejectedDeduction.text),
        'overtime_rate_per_hour': _toInt(overtimeRate.text),
        'currency': 'IDR',
        'updated_at': now,
        'updated_by': widget.session.uid,
      });
      await FirebaseDatabase.instance.ref('audit_logs/${widget.session.companyId}').push().set({
        'action': 'update_payroll_settings',
        'target_path': 'payroll_settings/${widget.session.companyId}',
        'actor_uid': widget.session.uid,
        'actor_email': widget.session.email,
        'created_at': now,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payroll settings disimpan.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payroll Settings'), actions: [IconButton(onPressed: loadSettings, icon: const Icon(Icons.refresh_rounded))]),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const MessageCard(
            title: 'Payroll Settings',
            message: 'Konfigurasi nominal potongan dan rate lembur. Nilai disimpan dalam IDR.',
            icon: Icons.tune_rounded,
          ),
          const SizedBox(height: 12),
          if (!loaded)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else ...[
            TextField(controller: lateDeduction, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Potongan per terlambat')),
            const SizedBox(height: 10),
            TextField(controller: outsideRadiusDeduction, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Potongan per luar radius')),
            const SizedBox(height: 10),
            TextField(controller: rejectedDeduction, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Potongan per absensi ditolak')),
            const SizedBox(height: 10),
            TextField(controller: overtimeRate, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rate lembur per jam')),
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: saving ? null : save, icon: const Icon(Icons.save_rounded), label: Text(saving ? 'Menyimpan...' : 'Simpan Payroll Settings')),
          ],
        ],
      ),
    );
  }
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map) return value.map((key, item) => MapEntry(key.toString(), item));
  return null;
}

String _read(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value != null && value.toString().trim().isNotEmpty) return value.toString();
  }
  return '';
}

int _toInt(String value) => int.tryParse(value.trim().replaceAll('.', '').replaceAll(',', '')) ?? 0;

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
