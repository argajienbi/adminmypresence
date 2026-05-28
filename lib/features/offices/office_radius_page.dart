import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/models.dart';
import '../shared/message_card.dart';

class OfficeRadiusPage extends StatefulWidget {
  final AdminSession session;

  const OfficeRadiusPage({super.key, required this.session});

  @override
  State<OfficeRadiusPage> createState() => _OfficeRadiusPageState();
}

class _OfficeRadiusPageState extends State<OfficeRadiusPage> {
  late Future<List<OfficeRadiusRecord>> future;
  String query = '';
  String statusFilter = 'active';

  @override
  void initState() {
    super.initState();
    future = loadOffices();
  }

  void refresh() {
    setState(() {
      future = loadOffices();
    });
  }

  Future<List<OfficeRadiusRecord>> loadOffices() async {
    final snap = await FirebaseDatabase.instance.ref('offices/${widget.session.companyId}').get();
    final data = _asMap(snap.value) ?? const <String, dynamic>{};

    final rows = data.entries.map((entry) {
      final value = _asMap(entry.value) ?? const <String, dynamic>{};
      return OfficeRadiusRecord(
        id: entry.key,
        name: _read(value, const ['name', 'nama', 'office_name']).ifEmpty(entry.key),
        address: _read(value, const ['address', 'alamat', 'location_name']),
        areaName: _read(value, const ['area_name', 'area', 'wilayah']),
        latitude: _toDouble(value['latitude'] ?? value['lat']),
        longitude: _toDouble(value['longitude'] ?? value['lng'] ?? value['long']),
        radius: _toDouble(value['radius_meter'] ?? value['radius'] ?? value['geofence_radius']).ifZero(100),
        active: value['active'] != false && value['status']?.toString().toLowerCase() != 'inactive',
      );
    }).toList();

    rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return rows;
  }

  List<OfficeRadiusRecord> filtered(List<OfficeRadiusRecord> rows) {
    final q = query.trim().toLowerCase();
    return rows.where((office) {
      if (statusFilter == 'active' && !office.active) return false;
      if (statusFilter == 'inactive' && office.active) return false;
      if (q.isEmpty) return true;
      final text = '${office.name} ${office.address} ${office.areaName}'.toLowerCase();
      return text.contains(q);
    }).toList();
  }

  Future<void> toggleOfficeActive(OfficeRadiusRecord office, bool active) async {
    try {
      final db = FirebaseDatabase.instance;
      final targetPath = 'offices/${widget.session.companyId}/${office.id}';
      await db.ref(targetPath).update({
        'active': active,
        'status': active ? 'active' : 'inactive',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'updated_by': widget.session.uid,
      });
      await _writeAuditLog(
        session: widget.session,
        action: active ? 'activate office' : 'deactivate office',
        targetId: office.id,
        targetPath: targetPath,
      );
      refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> openForm([OfficeRadiusRecord? office]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OfficeRadiusFormPage(
          session: widget.session,
          office: office,
        ),
      ),
    );

    if (!mounted) return;
    if (saved == true) refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Radius Kantor'),
        actions: [
          IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Kantor'),
      ),
      body: FutureBuilder<List<OfficeRadiusRecord>>(
        future: future,
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <OfficeRadiusRecord>[];
          final offices = filtered(all);
          final active = all.where((office) => office.active).length;
          final inactive = all.length - active;
          final missingLocation = all.where((office) => office.latitude == 0 || office.longitude == 0).length;

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              MessageCard(
                title: 'Radius Kantor',
                message: 'Total: ${all.length} • Aktif: $active • Nonaktif: $inactive • Belum ada koordinat: $missingLocation',
                icon: Icons.map_rounded,
              ),
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
              TextField(
                onChanged: (value) => setState(() => query = value),
                decoration: const InputDecoration(labelText: 'Cari kantor, alamat, area', prefixIcon: Icon(Icons.search_rounded)),
              ),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot.hasError)
                MessageCard(
                  title: 'Gagal memuat kantor',
                  message: snapshot.error.toString(),
                  icon: Icons.error_outline_rounded,
                )
              else if (offices.isEmpty)
                const MessageCard(
                  title: 'Belum ada kantor',
                  message: 'Tambahkan kantor dulu, lalu pilih titik di peta dan isi radius.',
                  icon: Icons.business_outlined,
                )
              else
                ...offices.map(
                  (office) => Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Icon(office.active ? Icons.business_rounded : Icons.business_outlined)),
                      title: Text(
                        office.name,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        '${office.address.ifEmpty('-')}\n${office.areaName.ifEmpty('-')} • Lat ${office.latitude}, Lng ${office.longitude}, Radius ${office.radius.toStringAsFixed(0)} m',
                      ),
                      isThreeLine: true,
                      trailing: Switch(
                        value: office.active,
                        onChanged: (value) => toggleOfficeActive(office, value),
                      ),
                      onTap: () => openForm(office),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class OfficeRadiusFormPage extends StatefulWidget {
  final AdminSession session;
  final OfficeRadiusRecord? office;

  const OfficeRadiusFormPage({
    super.key,
    required this.session,
    this.office,
  });

  @override
  State<OfficeRadiusFormPage> createState() => _OfficeRadiusFormPageState();
}

class _OfficeRadiusFormPageState extends State<OfficeRadiusFormPage> {
  late LatLng selectedPoint = LatLng(
    widget.office == null || widget.office!.latitude == 0 ? -6.200000 : widget.office!.latitude,
    widget.office == null || widget.office!.longitude == 0 ? 106.816666 : widget.office!.longitude,
  );
  late final TextEditingController name = TextEditingController(text: widget.office?.name ?? '');
  late final TextEditingController address = TextEditingController(text: widget.office?.address ?? '');
  late final TextEditingController area = TextEditingController(text: widget.office?.areaName ?? '');
  late final TextEditingController radiusController = TextEditingController(text: (widget.office?.radius ?? 100).toStringAsFixed(0));
  late final TextEditingController latitudeController = TextEditingController(text: selectedPoint.latitude.toStringAsFixed(6));
  late final TextEditingController longitudeController = TextEditingController(text: selectedPoint.longitude.toStringAsFixed(6));
  late double radius = widget.office?.radius ?? 100;
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    address.dispose();
    area.dispose();
    radiusController.dispose();
    latitudeController.dispose();
    longitudeController.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final officeName = name.text.trim();
    final rad = double.tryParse(radiusController.text.trim());

    if (officeName.isEmpty) {
      showError('Nama kantor wajib diisi.');
      return;
    }
    if (rad == null || rad <= 0) {
      showError('Radius harus lebih dari 0 meter.');
      return;
    }
    final manualPoint = resolveManualCoordinate();
    if (manualPoint == null) return;

    setState(() {
      saving = true;
      radius = rad;
      selectedPoint = manualPoint;
    });

    try {
      final db = FirebaseDatabase.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      final officeId = widget.office?.id ?? db.ref('offices/${widget.session.companyId}').push().key!;
      final path = 'offices/${widget.session.companyId}/$officeId';
      final officeAddress = address.text.trim();
      final officeArea = area.text.trim();

      await db.ref(path).update({
        'office_id': officeId,
        'company_id': widget.session.companyId,
        'name': officeName,
        'office_name': officeName,
        'address': officeAddress,
        'alamat': officeAddress,
        'area_name': officeArea,
        'area': officeArea,
        'wilayah': officeArea,
        'latitude': manualPoint.latitude,
        'longitude': manualPoint.longitude,
        'lat': manualPoint.latitude,
        'lng': manualPoint.longitude,
        'radius_meter': rad,
        'radius': rad,
        'geofence_radius': rad,
        'active': true,
        'updated_at': now,
        'updated_by': widget.session.uid,
        if (widget.office == null) 'created_at': now,
        if (widget.office == null) 'created_by': widget.session.uid,
      });
      await _writeAuditLog(
        session: widget.session,
        action: widget.office == null ? 'create office radius' : 'update office radius',
        targetId: officeId,
        targetPath: path,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      showError(error.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void updateSelectedPoint(LatLng point) {
    setState(() {
      selectedPoint = point;
      latitudeController.text = point.latitude.toStringAsFixed(6);
      longitudeController.text = point.longitude.toStringAsFixed(6);
    });
  }

  LatLng? resolveManualCoordinate() {
    final lat = double.tryParse(latitudeController.text.trim());
    final lng = double.tryParse(longitudeController.text.trim());
    if (lat == null || lat < -90 || lat > 90 || lng == null || lng < -180 || lng > 180) {
      showError('Latitude atau longitude manual tidak valid.');
      return null;
    }
    return LatLng(lat, lng);
  }

  void applyManualCoordinate() {
    final point = resolveManualCoordinate();
    if (point == null) return;
    updateSelectedPoint(point);
  }

  void showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void updateRadius(String value) {
    final parsed = double.tryParse(value.trim());
    if (parsed == null || parsed <= 0) return;
    setState(() => radius = parsed);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.office != null;

    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit Radius Kantor' : 'Tambah Kantor')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const MessageCard(
            title: 'Peta Radius Kantor',
            message: 'Tap peta untuk memilih titik kantor. Lingkaran menunjukkan radius absen dalam meter.',
            icon: Icons.place_rounded,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 340,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: selectedPoint,
                  initialZoom: 16,
                  onTap: (_, point) => updateSelectedPoint(point),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.adminmypresence',
                  ),
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: selectedPoint,
                        radius: radius,
                        useRadiusInMeter: true,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: selectedPoint,
                        width: 48,
                        height: 48,
                        child: const Icon(Icons.location_pin, size: 44),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Lat ${selectedPoint.latitude.toStringAsFixed(6)}  |  Lng ${selectedPoint.longitude.toStringAsFixed(6)}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nama kantor')),
          const SizedBox(height: 10),
          TextField(controller: address, decoration: const InputDecoration(labelText: 'Alamat')),
          const SizedBox(height: 10),
          TextField(controller: area, decoration: const InputDecoration(labelText: 'Area / Wilayah')),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: latitudeController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Latitude'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: longitudeController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Longitude'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: applyManualCoordinate,
            icon: const Icon(Icons.my_location_rounded),
            label: const Text('Terapkan Koordinat Manual'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: radiusController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Radius meter', hintText: '100'),
            onChanged: updateRadius,
          ),
          const SizedBox(height: 12),
          Slider(
            value: radius.clamp(10, 1000),
            min: 10,
            max: 1000,
            divisions: 99,
            label: '${radius.toStringAsFixed(0)} m',
            onChanged: (value) {
              setState(() {
                radius = value;
                radiusController.text = value.toStringAsFixed(0);
              });
            },
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: saving ? null : save,
            icon: const Icon(Icons.save_rounded),
            label: Text(saving ? 'Menyimpan...' : 'Simpan Radius Kantor'),
          ),
        ],
      ),
    );
  }
}

class OfficeRadiusRecord {
  const OfficeRadiusRecord({
    required this.id,
    required this.name,
    required this.address,
    required this.areaName,
    required this.latitude,
    required this.longitude,
    required this.radius,
    required this.active,
  });

  final String id;
  final String name;
  final String address;
  final String areaName;
  final double latitude;
  final double longitude;
  final double radius;
  final bool active;
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

double _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

Future<void> _writeAuditLog({
  required AdminSession session,
  required String action,
  required String targetId,
  required String targetPath,
}) async {
  await FirebaseDatabase.instance.ref('audit_logs/${session.companyId}').push().set({
    'action': action,
    'target_id': targetId,
    'target_path': targetPath,
    'actor_uid': session.uid,
    'actor_email': session.email,
    'created_at': DateTime.now().millisecondsSinceEpoch,
  });
}

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}

extension _DoubleFallback on double {
  double ifZero(double fallback) => this == 0 ? fallback : this;
}
