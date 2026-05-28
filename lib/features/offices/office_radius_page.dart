import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

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
                message: 'Atur latitude, longitude, dan radius absen kantor. Data disimpan ke offices/{companyId}/{officeId}.',
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
                  message: 'Tambahkan kantor dulu, lalu isi titik koordinat dan radius.',
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
  late final TextEditingController latitude = TextEditingController(text: widget.office == null || widget.office!.latitude == 0 ? '' : widget.office!.latitude.toString());
  late final TextEditingController longitude = TextEditingController(text: widget.office == null || widget.office!.longitude == 0 ? '' : widget.office!.longitude.toString());
  late final TextEditingController radius = TextEditingController(text: (widget.office?.radius ?? 100).toStringAsFixed(0));
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    address.dispose();
    latitude.dispose();
    longitude.dispose();
    radius.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final officeName = name.text.trim();
    final lat = double.tryParse(latitude.text.trim());
    final lng = double.tryParse(longitude.text.trim());
    final rad = double.tryParse(radius.text.trim());

    if (officeName.isEmpty) {
      showError('Nama kantor wajib diisi.');
      return;
    }
    if (lat == null || lat < -90 || lat > 90) {
      showError('Latitude tidak valid.');
      return;
    }
    if (lng == null || lng < -180 || lng > 180) {
      showError('Longitude tidak valid.');
      return;
    }
    if (rad == null || rad <= 0) {
      showError('Radius harus lebih dari 0 meter.');
      return;
    }

    setState(() => saving = true);

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
        'latitude': lat,
        'longitude': lng,
        'lat': lat,
        'lng': lng,
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

  @override
  Widget build(BuildContext context) {
    final editing = widget.office != null;

    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit Radius Kantor' : 'Tambah Kantor')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const MessageCard(
            title: 'Koordinat Kantor',
            message: 'Isi latitude dan longitude dari Google Maps/OpenStreetMap, lalu tentukan radius meter untuk validasi absen.',
            icon: Icons.place_rounded,
          ),
          const SizedBox(height: 12),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nama kantor')),
          const SizedBox(height: 10),
          TextField(controller: address, decoration: const InputDecoration(labelText: 'Alamat')),
          const SizedBox(height: 10),
          TextField(controller: latitude, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Latitude', hintText: '-6.200000')),
          const SizedBox(height: 10),
          TextField(controller: longitude, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Longitude', hintText: '106.816666')),
          const SizedBox(height: 10),
          TextField(controller: radius, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Radius meter', hintText: '100')),
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
