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
        latitude: _toDouble(value['latitude'] ?? value['lat']),
        longitude: _toDouble(value['longitude'] ?? value['lng'] ?? value['long']),
        radius: _toDouble(value['radius_meter'] ?? value['radius'] ?? value['geofence_radius']).ifZero(100),
      );
    }).toList();

    rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return rows;
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
          final offices = snapshot.data ?? const <OfficeRadiusRecord>[];

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const MessageCard(
                title: 'Radius Kantor',
                message: 'Atur titik kantor lewat peta native Flutter dan radius absen kantor. Data disimpan ke offices/{companyId}/{officeId}.',
                icon: Icons.map_rounded,
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
                      leading: const CircleAvatar(child: Icon(Icons.business_rounded)),
                      title: Text(
                        office.name,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        '${office.address.ifEmpty('-')}\nLat ${office.latitude}, Lng ${office.longitude}, Radius ${office.radius.toStringAsFixed(0)} m',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right_rounded),
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
  late final TextEditingController name = TextEditingController(text: widget.office?.name ?? '');
  late final TextEditingController address = TextEditingController(text: widget.office?.address ?? '');
  late final TextEditingController radiusController = TextEditingController(text: (widget.office?.radius ?? 100).toStringAsFixed(0));
  late LatLng selectedPoint = LatLng(
    widget.office == null || widget.office!.latitude == 0 ? -6.200000 : widget.office!.latitude,
    widget.office == null || widget.office!.longitude == 0 ? 106.816666 : widget.office!.longitude,
  );
  late double radius = widget.office?.radius ?? 100;
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    address.dispose();
    radiusController.dispose();
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

    setState(() {
      saving = true;
      radius = rad;
    });

    try {
      final db = FirebaseDatabase.instance;
      final now = DateTime.now().millisecondsSinceEpoch;
      final officeId = widget.office?.id ?? db.ref('offices/${widget.session.companyId}').push().key!;
      final path = 'offices/${widget.session.companyId}/$officeId';

      await db.ref(path).update({
        'office_id': officeId,
        'company_id': widget.session.companyId,
        'name': officeName,
        'office_name': officeName,
        'address': address.text.trim(),
        'alamat': address.text.trim(),
        'latitude': selectedPoint.latitude,
        'longitude': selectedPoint.longitude,
        'lat': selectedPoint.latitude,
        'lng': selectedPoint.longitude,
        'radius_meter': rad,
        'radius': rad,
        'geofence_radius': rad,
        'active': true,
        'updated_at': now,
        'updated_by': widget.session.uid,
        if (widget.office == null) 'created_at': now,
        if (widget.office == null) 'created_by': widget.session.uid,
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      showError(error.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
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
                  onTap: (_, point) => setState(() => selectedPoint = point),
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
    required this.latitude,
    required this.longitude,
    required this.radius,
  });

  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final double radius;
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

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}

extension _DoubleFallback on double {
  double ifZero(double fallback) => this == 0 ? fallback : this;
}
