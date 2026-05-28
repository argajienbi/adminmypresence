import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../shared/message_card.dart';

class SettingsManagementPage extends StatefulWidget {
  final AdminSession session;

  const SettingsManagementPage({super.key, required this.session});

  @override
  State<SettingsManagementPage> createState() => _SettingsManagementPageState();
}

class _SettingsManagementPageState extends State<SettingsManagementPage> {
  late Future<AppSettingsData> future;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    future = loadSettings();
  }

  void refresh() {
    setState(() => future = loadSettings());
  }

  Future<AppSettingsData> loadSettings() async {
    final companyId = widget.session.companyId;
    final db = FirebaseDatabase.instance;
    final results = await Future.wait([
      db.ref('companies/$companyId').get(),
      db.ref('companies/$companyId/settings').get(),
      db.ref('app_config').get(),
    ]);

    return AppSettingsData(
      company: _asMap(results[0].value) ?? const <String, dynamic>{},
      companySettings: _asMap(results[1].value) ?? const <String, dynamic>{},
      appConfig: _asMap(results[2].value) ?? const <String, dynamic>{},
    );
  }

  Future<void> saveCompany(AppSettingsData data) async {
    final name = TextEditingController(text: data.companyName);
    final email = TextEditingController(text: data.ownerEmail);
    final address = TextEditingController(text: data.address);
    final timezone = TextEditingController(text: data.timezone);

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
              Text('Profil Company', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nama company')),
              const SizedBox(height: 10),
              TextField(controller: email, decoration: const InputDecoration(labelText: 'Email owner/admin')),
              const SizedBox(height: 10),
              TextField(controller: address, decoration: const InputDecoration(labelText: 'Alamat')),
              const SizedBox(height: 10),
              TextField(controller: timezone, decoration: const InputDecoration(labelText: 'Timezone')),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Simpan')),
            ],
          ),
        ),
      ),
    );

    if (ok == true) {
      await _update('companies/${widget.session.companyId}', {
        'name': name.text.trim(),
        'company_name': name.text.trim(),
        'owner_email': email.text.trim(),
        'email': email.text.trim(),
        'address': address.text.trim(),
        'alamat': address.text.trim(),
        'timezone': timezone.text.trim().isEmpty ? 'Asia/Jakarta' : timezone.text.trim(),
      });
    }
  }

  Future<void> saveAttendance(AppSettingsData data) async {
    final defaultRadius = TextEditingController(text: data.defaultRadius.toStringAsFixed(0));
    final lateTolerance = TextEditingController(text: data.lateTolerance.toString());
    final minAccuracy = TextEditingController(text: data.minGpsAccuracy.toStringAsFixed(0));
    var requirePhoto = data.requirePhoto;
    var requireLocation = data.requireLocation;
    var allowOutsideRadius = data.allowOutsideRadius;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Aturan Absensi', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  TextField(controller: defaultRadius, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Default radius meter')),
                  const SizedBox(height: 10),
                  TextField(controller: lateTolerance, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Toleransi terlambat menit')),
                  const SizedBox(height: 10),
                  TextField(controller: minAccuracy, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minimal GPS accuracy meter')),
                  const SizedBox(height: 10),
                  SwitchListTile(value: requirePhoto, onChanged: (v) => setSheetState(() => requirePhoto = v), title: const Text('Wajib foto')),
                  SwitchListTile(value: requireLocation, onChanged: (v) => setSheetState(() => requireLocation = v), title: const Text('Wajib lokasi')),
                  SwitchListTile(value: allowOutsideRadius, onChanged: (v) => setSheetState(() => allowOutsideRadius = v), title: const Text('Izinkan luar radius')),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Simpan')),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (ok == true) {
      await _update('companies/${widget.session.companyId}/settings/attendance', {
        'default_radius_meter': _toDouble(defaultRadius.text, 100),
        'late_tolerance_minutes': _toInt(lateTolerance.text, 15),
        'min_gps_accuracy_meter': _toDouble(minAccuracy.text, 50),
        'require_photo': requirePhoto,
        'require_location': requireLocation,
        'allow_outside_radius': allowOutsideRadius,
      });
    }
  }

  Future<void> saveApproval(AppSettingsData data) async {
    var leaveApproval = data.leaveApprovalEnabled;
    var qrApproval = data.qrApprovalEnabled;
    var correctionApproval = data.correctionApprovalEnabled;
    var multiLevel = data.multiLevelApproval;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Policy Approval', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                SwitchListTile(value: leaveApproval, onChanged: (v) => setSheetState(() => leaveApproval = v), title: const Text('Approval Cuti')),
                SwitchListTile(value: qrApproval, onChanged: (v) => setSheetState(() => qrApproval = v), title: const Text('Approval QR')),
                SwitchListTile(value: correctionApproval, onChanged: (v) => setSheetState(() => correctionApproval = v), title: const Text('Approval Koreksi Absensi')),
                SwitchListTile(value: multiLevel, onChanged: (v) => setSheetState(() => multiLevel = v), title: const Text('Multi-level approval')),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Simpan')),
              ],
            ),
          ),
        ),
      ),
    );

    if (ok == true) {
      await _update('companies/${widget.session.companyId}/settings/approval', {
        'leave_approval_enabled': leaveApproval,
        'qr_approval_enabled': qrApproval,
        'correction_approval_enabled': correctionApproval,
        'multi_level_approval': multiLevel,
      });
    }
  }

  Future<void> saveAppConfig(AppSettingsData data) async {
    final appName = TextEditingController(text: data.appName);
    final minVersion = TextEditingController(text: data.minAppVersion);
    final supportEmail = TextEditingController(text: data.supportEmail);
    var maintenanceMode = data.maintenanceMode;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('App Config', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                TextField(controller: appName, decoration: const InputDecoration(labelText: 'App name')),
                const SizedBox(height: 10),
                TextField(controller: minVersion, decoration: const InputDecoration(labelText: 'Minimal app version')),
                const SizedBox(height: 10),
                TextField(controller: supportEmail, decoration: const InputDecoration(labelText: 'Support email')),
                SwitchListTile(value: maintenanceMode, onChanged: (v) => setSheetState(() => maintenanceMode = v), title: const Text('Maintenance mode')),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Simpan')),
              ],
            ),
          ),
        ),
      ),
    );

    if (ok == true) {
      await _update('app_config', {
        'app_name': appName.text.trim().isEmpty ? 'MyPresence' : appName.text.trim(),
        'min_app_version': minVersion.text.trim(),
        'support_email': supportEmail.text.trim(),
        'maintenance_mode': maintenanceMode,
      });
    }
  }

  Future<void> _update(String path, Map<String, dynamic> values) async {
    setState(() => saving = true);
    try {
      await FirebaseDatabase.instance.ref(path).update({
        ...values,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'updated_by': widget.session.uid,
        'updated_by_email': widget.session.email,
      });
      await FirebaseDatabase.instance.ref('audit_logs/${widget.session.companyId}').push().set({
        'action': 'update_settings',
        'target_path': path,
        'actor_uid': widget.session.uid,
        'actor_email': widget.session.email,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      refresh();
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
      appBar: AppBar(title: const Text('Settings'), actions: [IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
      body: FutureBuilder<AppSettingsData>(
        future: future,
        builder: (context, snapshot) {
          final data = snapshot.data ?? const AppSettingsData.empty();
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              MessageCard(title: 'Settings Center', message: '${data.companyName} • ${data.timezone}', icon: Icons.settings_rounded),
              if (saving) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                MessageCard(title: 'Gagal memuat settings', message: snapshot.error.toString(), icon: Icons.error_outline_rounded)
              else ...[
                _SettingsTile(title: 'Profil Company', subtitle: '${data.companyName}\n${data.ownerEmail.ifEmpty('-')} • ${data.address.ifEmpty('-')}', icon: Icons.business_rounded, onTap: () => saveCompany(data)),
                _SettingsTile(title: 'Aturan Absensi', subtitle: 'Radius ${data.defaultRadius.toStringAsFixed(0)} m • Toleransi ${data.lateTolerance} menit • GPS ${data.minGpsAccuracy.toStringAsFixed(0)} m', icon: Icons.access_time_filled_rounded, onTap: () => saveAttendance(data)),
                _SettingsTile(title: 'Policy Approval', subtitle: 'Cuti ${_onOff(data.leaveApprovalEnabled)} • QR ${_onOff(data.qrApprovalEnabled)} • Koreksi ${_onOff(data.correctionApprovalEnabled)}', icon: Icons.fact_check_rounded, onTap: () => saveApproval(data)),
                _SettingsTile(title: 'App Config', subtitle: '${data.appName} • min ${data.minAppVersion.ifEmpty('-')} • maintenance ${_onOff(data.maintenanceMode)}', icon: Icons.app_settings_alt_rounded, onTap: () => saveAppConfig(data)),
                _SettingsTile(title: 'Raw Company Settings', subtitle: '${data.companySettings.length} root settings item(s)', icon: Icons.data_object_rounded, onTap: () => _showRaw('Company Settings', data.companySettings)),
                _SettingsTile(title: 'Raw App Config', subtitle: '${data.appConfig.length} app config item(s)', icon: Icons.storage_rounded, onTap: () => _showRaw('App Config', data.appConfig)),
              ],
            ],
          );
        },
      ),
    );
  }

  void _showRaw(String title, Map<String, dynamic> data) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                if (data.isEmpty)
                  const Text('Tidak ada data.')
                else
                  ...data.entries.map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SelectableText('${entry.key}: ${entry.value}'),
                      )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _SettingsTile({required this.title, required this.subtitle, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle),
        isThreeLine: subtitle.contains('\n'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class AppSettingsData {
  final Map<String, dynamic> company;
  final Map<String, dynamic> companySettings;
  final Map<String, dynamic> appConfig;

  const AppSettingsData({required this.company, required this.companySettings, required this.appConfig});
  const AppSettingsData.empty() : company = const {}, companySettings = const {}, appConfig = const {};

  Map<String, dynamic> get attendance => _asMap(companySettings['attendance']) ?? const <String, dynamic>{};
  Map<String, dynamic> get approval => _asMap(companySettings['approval']) ?? const <String, dynamic>{};

  String get companyName => _read(company, const ['name', 'company_name', 'nama_perusahaan']).ifEmpty('Company');
  String get ownerEmail => _read(company, const ['owner_email', 'email']);
  String get address => _read(company, const ['address', 'alamat']);
  String get timezone => _read(company, const ['timezone']).ifEmpty('Asia/Jakarta');

  double get defaultRadius => _toDouble(attendance['default_radius_meter'], 100);
  int get lateTolerance => _toInt(attendance['late_tolerance_minutes'], 15);
  double get minGpsAccuracy => _toDouble(attendance['min_gps_accuracy_meter'], 50);
  bool get requirePhoto => _bool(attendance['require_photo'], true);
  bool get requireLocation => _bool(attendance['require_location'], true);
  bool get allowOutsideRadius => _bool(attendance['allow_outside_radius'], false);

  bool get leaveApprovalEnabled => _bool(approval['leave_approval_enabled'], true);
  bool get qrApprovalEnabled => _bool(approval['qr_approval_enabled'], true);
  bool get correctionApprovalEnabled => _bool(approval['correction_approval_enabled'], true);
  bool get multiLevelApproval => _bool(approval['multi_level_approval'], false);

  String get appName => _read(appConfig, const ['app_name', 'name']).ifEmpty('MyPresence');
  String get minAppVersion => _read(appConfig, const ['min_app_version']);
  String get supportEmail => _read(appConfig, const ['support_email']);
  bool get maintenanceMode => _bool(appConfig['maintenance_mode'], false);
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

double _toDouble(Object? value, double fallback) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

int _toInt(Object? value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

bool _bool(Object? value, bool fallback) {
  if (value is bool) return value;
  if (value == null) return fallback;
  final text = value.toString().toLowerCase();
  if (text == 'true' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == '0' || text == 'no') return false;
  return fallback;
}

String _onOff(bool value) => value ? 'ON' : 'OFF';

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
