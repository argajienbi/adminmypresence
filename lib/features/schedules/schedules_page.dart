import 'package:flutter/material.dart';

import '../../core/date_utils.dart';
import '../../core/models.dart';
import '../../services/admin_service.dart';
import '../shared/message_card.dart';

class SchedulesPage extends StatelessWidget {
  final AdminSession session;
  final AdminService service;

  const SchedulesPage({
    super.key,
    required this.session,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      children: [
        Text(
          'Jadwal Kerja',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Kelola jam kerja, shift, jadwal khusus, dan lembur.',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        _Tile(
          title: 'Jam Kerja',
          subtitle: 'Buat dan lihat jam kerja.',
          icon: Icons.schedule_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SimpleListPage(
                title: 'Jam Kerja',
                actionLabel: 'Tambah Jam Kerja',
                load: () => service.loadWorkTimes(session),
                create: () => _createWorkTime(context),
              ),
            ),
          ),
        ),
        _Tile(
          title: 'Shift',
          subtitle: 'Lihat pola shift.',
          icon: Icons.view_week_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SimpleListPage(
                title: 'Shift',
                load: () => service.loadShifts(session),
              ),
            ),
          ),
        ),
        _Tile(
          title: 'Terapkan Jadwal',
          subtitle: 'Daftar penerapan jadwal.',
          icon: Icons.assignment_ind_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SimpleListPage(
                title: 'Terapkan Jadwal',
                load: () => service.loadAssignments(session),
              ),
            ),
          ),
        ),
        _Tile(
          title: 'Jadwal Khusus',
          subtitle: 'Override jadwal tanggal tertentu.',
          icon: Icons.event_repeat_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SimpleListPage(
                title: 'Jadwal Khusus',
                load: () => service.loadSpecials(session),
              ),
            ),
          ),
        ),
        _Tile(
          title: 'Jadwal Lembur',
          subtitle: 'Buat grup lembur, pilih karyawan, tanggal, dan jam.',
          icon: Icons.more_time_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OvertimePage(session: session, service: service),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _createWorkTime(BuildContext context) async {
    final name = TextEditingController();
    final start = TextEditingController(text: '08:00');
    final end = TextEditingController(text: '16:00');

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              18,
              18,
              18 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nama jam kerja'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: start,
                  decoration: const InputDecoration(labelText: 'Mulai kerja'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: end,
                  decoration: const InputDecoration(labelText: 'Selesai kerja'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Simpan'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (ok == true) {
      await service.createWorkTime(session, name.text, start.text, end.text);
    }
  }
}

class _Tile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _Tile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class SimpleListPage extends StatefulWidget {
  final String title;
  final String? actionLabel;
  final Future<List<SimpleItem>> Function() load;
  final Future<void> Function()? create;

  const SimpleListPage({
    super.key,
    required this.title,
    required this.load,
    this.actionLabel,
    this.create,
  });

  @override
  State<SimpleListPage> createState() => _SimpleListPageState();
}

class _SimpleListPageState extends State<SimpleListPage> {
  late Future<List<SimpleItem>> future;

  @override
  void initState() {
    super.initState();
    future = widget.load();
  }

  void refresh() {
    setState(() {
      future = widget.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<SimpleItem>>(
        future: future,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <SimpleItem>[];

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              if (widget.create != null)
                FilledButton.icon(
                  onPressed: () async {
                    await widget.create!();
                    refresh();
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: Text(widget.actionLabel ?? 'Tambah'),
                ),
              if (widget.create != null) const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot.hasError)
                MessageCard(
                  title: 'Gagal memuat data',
                  message: snapshot.error.toString(),
                  icon: Icons.error_outline_rounded,
                )
              else if (items.isEmpty)
                const MessageCard(
                  title: 'Belum ada data',
                  message: 'Data akan tampil di sini.',
                  icon: Icons.inbox_outlined,
                )
              else
                ...items.map(
                  (item) => Card(
                    child: ListTile(
                      title: Text(
                        item.title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(item.subtitle.isEmpty ? '-' : item.subtitle),
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

class OvertimePage extends StatefulWidget {
  final AdminSession session;
  final AdminService service;

  const OvertimePage({
    super.key,
    required this.session,
    required this.service,
  });

  @override
  State<OvertimePage> createState() => _OvertimePageState();
}

class _OvertimePageState extends State<OvertimePage> {
  late Future<List<SimpleItem>> future;

  @override
  void initState() {
    super.initState();
    future = widget.service.loadOvertime(widget.session);
  }

  void refresh() {
    setState(() {
      future = widget.service.loadOvertime(widget.session);
    });
  }

  Future<void> create() async {
    final employees = await widget.service.loadEmployees(widget.session);
    if (!mounted) return;

    final selected = <EmployeeRecord>{};
    final name = TextEditingController();
    final start = TextEditingController(text: '08:00');
    final end = TextEditingController(text: '16:00');
    final dates = <String>{};

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  18,
                  18,
                  18,
                  18 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Buat Jadwal Lembur',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Nama grup lembur'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: start,
                      decoration: const InputDecoration(labelText: 'Mulai kerja'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: end,
                      decoration: const InputDecoration(labelText: 'Selesai kerja'),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                          initialDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setLocal(() => dates.add(AdminDateUtils.dateKey(picked)));
                        }
                      },
                      icon: const Icon(Icons.calendar_month_rounded),
                      label: const Text('Tambah tanggal'),
                    ),
                    Wrap(
                      spacing: 8,
                      children: dates.map((date) => Chip(label: Text(date))).toList(),
                    ),
                    const SizedBox(height: 10),
                    ...employees.map(
                      (employee) => CheckboxListTile(
                        value: selected.contains(employee),
                        onChanged: (value) {
                          setLocal(() {
                            if (value == true) {
                              selected.add(employee);
                            } else {
                              selected.remove(employee);
                            }
                          });
                        },
                        title: Text(employee.name),
                      ),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Simpan'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (ok == true) {
      await widget.service.createOvertime(
        widget.session,
        name.text,
        selected.toList(),
        dates.toList(),
        start.text,
        end.text,
      );
      refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SimpleListPage(
      title: 'Jadwal Lembur',
      actionLabel: 'Buat Jadwal Lembur',
      load: () => future,
      create: create,
    );
  }
}
