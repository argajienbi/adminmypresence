import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/models.dart';
import '../shared/message_card.dart';

class OfficeRadiusFullPage extends StatefulWidget {
  final AdminSession session;

  const OfficeRadiusFullPage({super.key, required this.session});

  @override
  State<OfficeRadiusFullPage> createState() => _OfficeRadiusFullPageState();
}

class _OfficeRadiusFullPageState extends State<OfficeRadiusFullPage> {
  late Future<List<OfficeRadiusFullRecord>> future;
  String query = '';
  String statusFilter = 'active';

  @override
  void initState() {
    super.initState();
    future = loadOffices();
  }

  void refresh() => setState(() => future = loadOffices());

  Future<List<OfficeRadiusFullRecord>> loadOffices() async {
    final snap = await FirebaseDatabase.instance.ref('offices/${widget.session.companyId}').get();
    final data = _asMap(snap.value) ?? const <String, dynamic>{};
    final rows = data.entries.map((entry) => OfficeRadiusFullRecord(entry.key, _asMap(entry.value) ?? const <String, dynamic>{})).toList();
    rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return rows;
  }

  List<OfficeRadiusFullRecord> filtered(List<OfficeRadiusFullRecord> rows) {
    final q = query.trim().toLowerCase();
    return rows.where((office) {
      if (statusFilter == 'active' && !office.active) return false;
      if (statusFilter == 'inactive' && office.active) return false;
      if (q.isEmpty) return true;
      return '${office.name} ${office.address} ${office.areaName}'.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> openForm([OfficeRadiusFullRecord? office]) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => OfficeRadiusFullFormPage(session: widget.session, office: office)));
    if (ok == true && mounted) refresh();
  }

  Future<void> setActive(OfficeRadiusFullRecord office, bool active) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final path = 'offices/${widget.session.companyId}/${office.id}';
    await FirebaseDatabase.instance.ref(path).update({
      'active': active,
      'status': active ? 'active' : 'inactive',
      'updated_at': now,
      'updated_by': widget.session.uid,
    });
    await writeOfficeAudit(widget.session, active ? 'activate_office_radius' : 'deactivate_office_radius', office.id, path, now);
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Radius Kantor'), actions: [IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded))]),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => openForm(), icon: const Icon(Icons.add_rounded), label: const Text('Kantor')),
      body: FutureBuilder<List<OfficeRadiusFullRecord>>(
        future: future,
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <OfficeRadiusFullRecord>[];
          final offices = filtered(all);
          final active = all.where((office) => office.active).length;
          final inactive = all.length - active;
          final missingLocation = all.where((office) => office.latitude == 0 || office.longitude == 0).length;
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              MessageCard(title: 'Radius Kantor', message: 'Total: ${all.length} • Aktif: $active • Nonaktif: $inactive • Belum ada koordinat: $missingLocation', icon: Icons.map_rounded),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: statusFilter,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Aktif')),
                  DropdownMenuItem(value: 'inactive', child: Text('Nonaktif')),
                  DropdownMenuItem(value: 'all', child: Text('Semua')),
                ],
                onChanged: (value) => setState(() => statusFilter = value ?? 'active'),
              ),
              const SizedBox(height: 12),
              TextField(onChanged: (value) => setState(() => query = value), decoration: const InputDecoration(labelText: 'Cari kantor, alamat, area', prefixIcon: Icon(Icons.search_rounded))),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                MessageCard(title: 'Gagal memuat kantor', message: snapshot.error.toString(), icon: Icons.error_outline_rounded)
              else if (offices.isEmpty)
                const MessageCard(title: 'Belum ada kantor', message: 'Tambahkan kantor dulu, lalu pilih titik di peta dan isi radius.', icon: Icons.business_outlined)
              else
                ...offices.map((office) => Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Icon(office.active ? Icons.business_rounded : Icons.business_outlined)),
                        title: Text(office.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text('${office.address.ifEmpty('-')}\n${office.areaName.ifEmpty('-')} • Lat ${office.latitude.toStringAsFixed(6)}, Lng ${office.longitude.toStringAsFixed(6)}, Radius ${office.radius.toStringAsFixed(0)} m'),
                        isThreeLine: true,
                        trailing: Switch(value: office.active, onChanged: (value) => setActive(office, value)),
                        onTap: () => openForm(office),
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }
}

class OfficeRadiusFullFormPage extends StatefulWidget {
  final AdminSession session;
  final OfficeRadiusFullRecord? office;

  const OfficeRadiusFullFormPage({super.key, required this.session, this.office});

  @override
  State<OfficeRadiusFullFormPage> createState() => _OfficeRadiusFullFormPageState();
}

class _OfficeRadiusFullFormPageState extends State<OfficeRadiusFullFormPage> {
  late final name = TextEditingController(text: widget.office?.name ?? '');
  late final address = TextEditingController(text: widget.office?.address ?? '');
  late final areaName = TextEditingController(text: widget.office?.areaName ?? '');
  late final radiusController = TextEditingController(text: (widget.office?.radius ?? 100).toStringAsFixed(0));
  late final latitudeController = TextEditingController(text: (widget.office == null || widget.office!.latitude == 0 ? -6.200000 : widget.office!.latitude).toStringAsFixed(6));
  late final longitudeController = TextEditingController(text: (widget.office == null || widget.office!.longitude == 0 ? 106.816666 : widget.office!.longitude).toStringAsFixed(6));
  late LatLng selectedPoint = LatLng(double.parse(latitudeController.text), double.parse(longitudeController.text));
  late double radius = widget.office?.radius ?? 100;
  late bool active = widget.office?.active ?? true;
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    address.dispose();
    areaName.dispose();
    radiusController.dispose();
    latitudeController.dispose();
    longitudeController.dispose();
    super.dispose();
  }

  void showError(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  void updatePoint(LatLng point) {
    setState(() {
      selectedPoint = point;
      latitudeController.text = point.latitude.toStringAsFixed(6);
      longitudeController.text = point.longitude.toStringAsFixed(6);
    });
  }

  void applyManualCoordinate() {
    final lat = double.tryParse(latitudeController.text.trim());
    final lng = double.tryParse(longitudeController.text.trim());
    if (lat == null || lat < -90 || lat > 90) {
      showError('Latitude harus valid antara -90 sampai 90.');
      return;
    }
    if (lng == null || lng < -180 || lng > 180) {
      showError('Longitude harus valid antara -180 sampai 180.');
      return;
    }
    updatePoint(LatLng(lat, lng));
  }

  Future<void> save() async {
    final officeName = name.text.trim();
    final lat = double.tryParse(latitudeController.text.trim());
    final lng = double.tryParse(longitudeController.text.trim());
    final rad = double.tryParse(radiusController.text.trim());
    if (officeName.isEmpty) return showError('Nama kantor wajib diisi.');
    if (lat == null || lat < -90 || lat > 90) return showError('Latitude harus valid antara -90 sampai 90.');
    if (lng == null || lng < -180 || lng > 180) return showError('Longitude harus valid antara -180 sampai 180.');
    if (rad == null || rad <= 0) return showError('Radius harus lebih dari 0 meter.');
    setState(() => saving = true);
    try {
      final db = FirebaseDatabase.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = widget.office?.id ?? db.ref('offices/${widget.session.companyId}').push().key!;
      final path = 'offices/${widget.session.companyId}/$id';
      final area = areaName.text.trim();
      final officeAddress = address.text.trim();
      await db.ref(path).update({
        'office_id': id,
        'company_id': widget.session.companyId,
        'name': officeName,
        'office_name': officeName,
        'address': officeAddress,
        'alamat': officeAddress,
        'area_name': area,
        'area': area,
        'wilayah': area,
        'latitude': lat,
        'longitude': lng,
        'lat': lat,
        'lng': lng,
        'radius_meter': rad,
        'radius': rad,
        'geofence_radius': rad,
        'active': active,
        'status': active ? 'active' : 'inactive',
        'updated_at': now,
        'updated_by': widget.session.uid,
        if (widget.office == null) 'created_at': now,
        if (widget.office == null) 'created_by': widget.session.uid,
      });
      await writeOfficeAudit(widget.session, widget.office == null ? 'create_office_radius' : 'update_office_radius', id, path, now);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showError(error.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.office != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit Radius Kantor' : 'Tambah Kantor')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const MessageCard(title: 'Peta Radius Kantor', message: 'Tap peta untuk memilih titik kantor atau isi koordinat manual.', icon: Icons.place_rounded),
          const SizedBox(height: 12),
          SizedBox(
            height: 340,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: FlutterMap(
                options: MapOptions(initialCenter: selectedPoint, initialZoom: 16, onTap: (_, point) => updatePoint(point)),
                children: [
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.adminmypresence'),
                  CircleLayer(circles: [CircleMarker(point: selectedPoint, radius: radius, useRadiusInMeter: true)]),
                  MarkerLayer(markers: [Marker(point: selectedPoint, width: 48, height: 48, child: const Icon(Icons.location_pin, size: 44))]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Lat ${selectedPoint.latitude.toStringAsFixed(6)}  |  Lng ${selectedPoint.longitude.toStringAsFixed(6)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nama kantor')),
          const SizedBox(height: 10),
          TextField(controller: address, decoration: const InputDecoration(labelText: 'Alamat')),
          const SizedBox(height: 10),
          TextField(controller: areaName, decoration: const InputDecoration(labelText: 'Area / wilayah')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: latitudeController, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Latitude'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: longitudeController, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Longitude'))),
          ]),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: applyManualCoordinate, icon: const Icon(Icons.my_location_rounded), label: const Text('Terapkan Koordinat Manual')),
          const SizedBox(height: 10),
          TextField(controller: radiusController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Radius meter'), onChanged: (value) => setState(() => radius = double.tryParse(value) ?? radius)),
          const SizedBox(height: 12),
          Slider(value: radius.clamp(10, 1000), min: 10, max: 1000, divisions: 99, label: '${radius.toStringAsFixed(0)} m', onChanged: (value) => setState(() { radius = value; radiusController.text = value.toStringAsFixed(0); })),
          SwitchListTile(value: active, onChanged: (value) => setState(() => active = value), title: const Text('Kantor aktif')),
          const SizedBox(height: 18),
          FilledButton.icon(onPressed: saving ? null : save, icon: const Icon(Icons.save_rounded), label: Text(saving ? 'Menyimpan...' : 'Simpan Radius Kantor')),
        ],
      ),
    );
  }
}

class OfficeRadiusFullRecord {
  final String id;
  final Map<String, dynamic> data;

  const OfficeRadiusFullRecord(this.id, this.data);

  String get name => _read(data, const ['name', 'nama', 'office_name']).ifEmpty(id);
  String get address => _read(data, const ['address', 'alamat', 'location_name']);
  String get areaName => _read(data, const ['area_name', 'area', 'wilayah']);
  double get latitude => _toDouble(data['latitude'] ?? data['lat']);
  double get longitude => _toDouble(data['longitude'] ?? data['lng'] ?? data['long']);
  double get radius => _toDouble(data['radius_meter'] ?? data['radius'] ?? data['geofence_radius']).ifZero(100);
  bool get active => data['active'] != false && data['status']?.toString().toLowerCase() != 'inactive';
}

Future<void> writeOfficeAudit(AdminSession session, String action, String targetId, String targetPath, int createdAt) {
  return FirebaseDatabase.instance.ref('audit_logs/${session.companyId}').push().set({
    'action': action,
    'target_id': targetId,
    'target_path': targetPath,
    'actor_uid': session.uid,
    'actor_email': session.email,
    'created_at': createdAt,
  });
}

Map<String, dynamic>? _asMap(Object? value) => value is Map ? value.map((key, item) => MapEntry(key.toString(), item)) : null;

String _read(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value != null && value.toString().trim().isNotEmpty) return value.toString();
  }
  return '';
}

double _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}

extension _DoubleFallback on double {
  double ifZero(double fallback) => this == 0 ? fallback : this;
}
