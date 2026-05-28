import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../core/date_utils.dart';
import '../core/firebase_paths.dart';
import '../core/models.dart';
import '../firebase_options.dart';

class AdminService {
  AdminService({FirebaseAuth? auth, FirebaseDatabase? database, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = database ?? FirebaseDatabase.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseDatabase _db;
  final FirebaseFirestore _firestore;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<void> signIn(String email, String password) => _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  Future<void> signOut() => _auth.signOut();

  Future<AdminSession> loadSession(User user) async {
    final snap = await _db.ref(FirebasePaths.user(user.uid)).get();
    final data = _map(snap.value);
    if (data == null) throw Exception('Data akun admin tidak ditemukan.');
    final role = _read(data, ['role', 'level']).toLowerCase();
    if (role != 'admin' && role != 'owner') throw Exception('Akun ini bukan admin/owner.');
    final status = _read(data, ['status_akun', 'status']).toLowerCase();
    if (status.isNotEmpty && status != 'active' && status != 'aktif' && status != 'approved') throw Exception('Akun admin tidak aktif.');
    final companyId = _read(data, ['company_id', 'companyId']);
    var companyName = _read(data, ['company_name', 'companyName', 'nama_perusahaan']);
    if (companyName.isEmpty && companyId.isNotEmpty) {
      final companySnap = await _db.ref(FirebasePaths.company(companyId)).get();
      final company = _map(companySnap.value);
      if (company != null) companyName = _read(company, ['name', 'company_name', 'nama_perusahaan']);
    }
    return AdminSession(
      uid: user.uid,
      email: user.email ?? _read(data, ['email']),
      name: _read(data, ['nama_lengkap', 'display_name', 'name', 'nama']),
      role: role,
      companyId: companyId,
      companyName: companyName.isEmpty ? 'Perusahaan' : companyName,
    );
  }

  Future<DashboardSummary> loadDashboard(AdminSession session) async {
    if (session.companyId.isEmpty) return const DashboardSummary.empty();
    final today = AdminDateUtils.dateKey(DateTime.now());
    final results = await Future.wait([
      _db.ref(FirebasePaths.companyUsers(session.companyId)).get(),
      _db.ref(FirebasePaths.attendanceToday(session.companyId, today)).get(),
      _db.ref(FirebasePaths.leaveRequests(session.companyId)).get(),
      _db.ref(FirebasePaths.qrRequests(session.companyId)).get(),
      _db.ref(FirebasePaths.overtime(session.companyId)).get(),
    ]);
    final employees = _map(results[0].value) ?? const <String, dynamic>{};
    final attendance = _map(results[1].value) ?? const <String, dynamic>{};
    final leaves = _map(results[2].value) ?? const <String, dynamic>{};
    final qr = _map(results[3].value) ?? const <String, dynamic>{};
    final overtime = _map(results[4].value) ?? const <String, dynamic>{};
    final active = employees.values.where((e) => _isActive(_map(e) ?? const <String, dynamic>{})).length;
    var checkedIn = 0;
    var checkedOut = 0;
    for (final value in attendance.values) {
      final day = _map(value) ?? const <String, dynamic>{};
      if (_map(day['masuk']) != null || _map(day['check_in']) != null || _map(day['in']) != null) checkedIn++;
      if (_map(day['pulang']) != null || _map(day['check_out']) != null || _map(day['out']) != null) checkedOut++;
    }
    final pendingLeave = leaves.values.where((e) => _isPending(_map(e) ?? const <String, dynamic>{})).length;
    final pendingQr = qr.values.where((e) => _isPending(_map(e) ?? const <String, dynamic>{})).length;
    final overtimeToday = overtime.values.where((e) {
      final data = _map(e) ?? const <String, dynamic>{};
      final dates = _map(data['dates']) ?? const <String, dynamic>{};
      return data['active'] != false && (dates[today] == true || dates[today] == 'true');
    }).length;
    return DashboardSummary(activeEmployees: active, checkedIn: checkedIn, checkedOut: checkedOut, pendingApproval: pendingLeave + pendingQr, overtimeToday: overtimeToday);
  }

  Future<List<EmployeeRecord>> loadEmployees(AdminSession session) async {
    final snap = await _db.ref(FirebasePaths.companyUsers(session.companyId)).get();
    final raw = _map(snap.value) ?? const <String, dynamic>{};
    final items = raw.entries.map((e) => _employee(e.key, _map(e.value) ?? const <String, dynamic>{})).toList();
    items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return items;
  }

  Future<String> saveEmployee(
    AdminSession session, {
    EmployeeRecord? old,
    required String name,
    required String email,
    required String password,
    required String nip,
    required String phone,
    required String jobTitle,
    required String officeName,
    required String groupName,
    required bool active,
    String role = 'user',
    String areaId = '',
    String officeId = '',
    String departmentId = '',
    String subDepartmentId = '',
    String groupId = '',
    String timetableId = '',
    String timetableName = '',
    String shiftId = '',
    String shiftName = '',
    String photoUrl = '',
    String photoPath = '',
  }) async {
    if (name.trim().isEmpty) throw Exception('Nama wajib diisi.');
    if (!email.contains('@')) throw Exception('Email tidak valid.');
    final now = DateTime.now().millisecondsSinceEpoch;
    var uid = old?.uid ?? '';
    if (old == null) {
      if (password.length < 6) throw Exception('Password minimal 6 karakter.');
      final secondary = await _secondaryAuth();
      try {
        final cred = await secondary.createUserWithEmailAndPassword(email: email.trim(), password: password);
        uid = cred.user?.uid ?? '';
        await cred.user?.updateDisplayName(name.trim());
      } finally {
        await secondary.signOut();
      }
    }
    if (uid.isEmpty) throw Exception('UID karyawan tidak valid.');
    final status = active ? 'active' : 'inactive';
    final normalizedRole = role.trim().isEmpty ? 'user' : role.trim();
    final payload = <String, dynamic>{
      'uid': uid,
      'nama_lengkap': name.trim(),
      'display_name': name.trim(),
      'name': name.trim(),
      'email': email.trim(),
      'nip': nip.trim(),
      'phone': phone.trim(),
      'no_hp': phone.trim(),
      'nomor_hp': phone.trim(),
      'job_title': jobTitle.trim(),
      'jabatan': jobTitle.trim(),
      'position': jobTitle.trim().isEmpty ? 'USER' : jobTitle.trim(),
      'area_id': areaId,
      'office_id': officeId,
      'department_id': departmentId,
      'sub_department_id': subDepartmentId,
      'employee_group_id': groupId,
      'group_id': groupId,
      'office_name': officeName.trim(),
      'group_name': groupName.trim(),
      'timetable_id': timetableId,
      'timetable_name': timetableName,
      'shift_id': shiftId,
      'shift_name': shiftName,
      'company_id': session.companyId,
      'company_name': session.companyName,
      'role': normalizedRole,
      'level': normalizedRole,
      'active': active,
      'status': status,
      'status_akun': status,
      'profile_completed': true,
      'photo_url': photoUrl,
      'photo_path': photoPath,
      'updated_at': now,
      'updated_by': session.uid,
      if (old == null) 'created_at': now,
      if (old == null) 'created_by': session.uid,
      if (old == null) 'qr_token': '',
      if (old == null) 'qr_active': false,
      if (old == null) 'qr_updated_at': 0,
      if (old == null) 'face_registered': false,
      if (old == null) 'face_registered_at': null,
      if (old == null) 'device_id': null,
      if (old == null) 'device_name': null,
    };
    await _db.ref().update({FirebasePaths.user(uid): payload, FirebasePaths.companyUser(session.companyId, uid): payload});
    await _firestore.collection('users').doc(uid).set({
      'uid': uid,
      'company_id': session.companyId,
      'role': normalizedRole,
      'status_akun': status,
      'nama_lengkap': name.trim(),
      'email': email.trim(),
      'nip': nip.trim(),
      'no_hp': phone.trim(),
      'position': jobTitle.trim().isEmpty ? 'USER' : jobTitle.trim(),
      'area_id': areaId,
      'office_id': officeId,
      'department_id': departmentId,
      'sub_department_id': subDepartmentId,
      'group_id': groupId,
      'photo_url': photoUrl,
      'photo_path': photoPath,
      'updated_at': now,
    }, SetOptions(merge: true));
    return uid;
  }

  Future<void> setEmployeeActive(AdminSession session, EmployeeRecord employee, bool active) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final patch = {'active': active, 'status': active ? 'active' : 'inactive', 'status_akun': active ? 'active' : 'inactive', 'updated_at': now, 'updated_by': session.uid};
    await _db.ref().update({FirebasePaths.user(employee.uid): patch, FirebasePaths.companyUser(session.companyId, employee.uid): patch});
    await _firestore.collection('users').doc(employee.uid).set({
      'status_akun': active ? 'active' : 'inactive',
      'updated_at': now,
    }, SetOptions(merge: true));
  }

  Future<List<ApprovalItem>> loadApprovals(AdminSession session) async {
    final results = await Future.wait([_db.ref(FirebasePaths.leaveRequests(session.companyId)).get(), _db.ref(FirebasePaths.qrRequests(session.companyId)).get()]);
    final items = <ApprovalItem>[];
    final leave = _map(results[0].value) ?? const <String, dynamic>{};
    for (final e in leave.entries) {
      final data = _map(e.value) ?? const <String, dynamic>{};
      if (_isPending(data)) items.add(_approval(e.key, 'leave', data));
    }
    final qr = _map(results[1].value) ?? const <String, dynamic>{};
    for (final e in qr.entries) {
      final data = _map(e.value) ?? const <String, dynamic>{};
      if (_isPending(data)) items.add(_approval(e.key, 'qr', data));
    }
    return items;
  }

  Future<void> decideApproval(AdminSession session, ApprovalItem item, bool approve, String note) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final path = item.source == 'qr' ? '${FirebasePaths.qrRequests(session.companyId)}/${item.id}' : '${FirebasePaths.leaveRequests(session.companyId)}/${item.id}';
    final status = approve ? 'approved' : 'rejected';
    await _db.ref(path).update({'status': status, 'approval_status': status, 'admin_note': note.trim(), 'approved_by': session.uid, 'approved_by_name': session.displayName, 'approved_at': now, 'updated_at': now});
    if (item.uid.isNotEmpty) await queueNotification(session, uid: item.uid, title: '${item.typeLabel} ${approve ? 'Disetujui' : 'Ditolak'}', body: note.trim().isEmpty ? 'Pengajuan Anda $status.' : note.trim(), type: approve ? 'success' : 'error', refType: item.source == 'qr' ? 'attendance' : 'leave_request', refId: item.id);
  }

  Future<List<SimpleItem>> loadAnnouncements(AdminSession session) async {
    final snap = await _db.ref(FirebasePaths.announcements(session.companyId)).get();
    return _simpleList(snap.value, titleKeys: ['title', 'judul'], subKeys: ['message', 'body', 'isi']);
  }

  Future<void> publishAnnouncement(AdminSession session, String title, String message, bool pushToAll) async {
    if (title.trim().isEmpty || message.trim().isEmpty) throw Exception('Judul dan isi wajib diisi.');
    final ref = _db.ref(FirebasePaths.announcements(session.companyId)).push();
    final id = ref.key ?? 'ann_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now().millisecondsSinceEpoch;
    await ref.set({'announcement_id': id, 'company_id': session.companyId, 'title': title.trim(), 'message': message.trim(), 'body': message.trim(), 'status': 'published', 'target_type': 'all', 'send_push': pushToAll, 'created_by': session.uid, 'created_by_name': session.displayName, 'created_at': now, 'updated_at': now});
    if (pushToAll) {
      final employees = await loadEmployees(session);
      final batch = _firestore.batch();
      final col = _firestore.collection(FirebasePaths.notificationQueue(session.companyId));
      for (final employee in employees.where((e) => e.active)) {
        batch.set(col.doc('${id}_${employee.uid}'), _notifMap(uid: employee.uid, companyId: session.companyId, title: title.trim(), body: message.trim(), type: 'info', refType: 'announcement', refId: id));
      }
      await batch.commit();
    }
  }

  Future<List<SimpleItem>> loadNotificationQueue(AdminSession session) async {
    final snap = await _firestore.collection(FirebasePaths.notificationQueue(session.companyId)).orderBy('created_at', descending: true).limit(100).get();
    return snap.docs.map((d) {
      final data = d.data();
      return SimpleItem(id: d.id, title: _read(data, ['title']), subtitle: '${_read(data, ['status'])} • ${_read(data, ['body', 'message'])}', status: _read(data, ['status']));
    }).toList();
  }

  Future<List<SimpleItem>> loadWorkTimes(AdminSession session) async => _loadSimple(FirebasePaths.timetables(session.companyId), ['name'], ['work_start', 'work_end']);
  Future<List<SimpleItem>> loadShifts(AdminSession session) async => _loadSimple(FirebasePaths.shifts(session.companyId), ['name'], ['status']);
  Future<List<SimpleItem>> loadAssignments(AdminSession session) async => _loadSimple(FirebasePaths.assignments(session.companyId), ['target_name', 'target_id'], ['shift_name', 'start_date']);
  Future<List<SimpleItem>> loadSpecials(AdminSession session) async => _loadSimple(FirebasePaths.specials(session.companyId), ['target_name', 'target_id'], ['date', 'timetable_name']);
  Future<List<SimpleItem>> loadOvertime(AdminSession session) async => _loadSimple(FirebasePaths.overtime(session.companyId), ['name'], ['work_start', 'work_end']);

  Future<void> createWorkTime(AdminSession session, String name, String start, String end) async {
    final ref = _db.ref(FirebasePaths.timetables(session.companyId)).push();
    final id = ref.key ?? 'tt_${DateTime.now().millisecondsSinceEpoch}';
    await ref.set({'timetable_id': id, 'name': name.trim(), 'work_start': start.trim(), 'work_end': end.trim(), 'check_in_start': start.trim(), 'check_in_end': start.trim(), 'check_out_start': end.trim(), 'check_out_end': end.trim(), 'status': 'active', 'active': true, 'created_at': DateTime.now().millisecondsSinceEpoch});
  }

  Future<void> createOvertime(AdminSession session, String name, List<EmployeeRecord> employees, List<String> dates, String start, String end) async {
    if (employees.isEmpty) throw Exception('Pilih minimal satu karyawan.');
    if (dates.isEmpty) throw Exception('Pilih minimal satu tanggal.');
    final ref = _db.ref(FirebasePaths.overtime(session.companyId)).push();
    final id = ref.key ?? 'ot_${DateTime.now().millisecondsSinceEpoch}';
    await ref.set({'schedule_id': id, 'name': name.trim(), 'target_uids': {for (final e in employees) e.uid: true}, 'dates': {for (final d in dates) d: true}, 'work_start': start, 'work_end': end, 'check_in_start': start, 'check_in_end': start, 'check_out_start': end, 'check_out_end': end, 'active': true, 'status': 'active', 'created_by': session.uid, 'created_at': DateTime.now().millisecondsSinceEpoch});
    for (final e in employees) {
      await queueNotification(session, uid: e.uid, title: 'Jadwal Lembur Ditambahkan', body: '$name: ${dates.join(', ')}, $start-$end.', type: 'info', refType: 'schedule', refId: id);
    }
  }

  Future<void> queueNotification(AdminSession session, {required String uid, required String title, required String body, required String type, required String refType, required String refId}) async {
    final doc = _firestore.collection(FirebasePaths.notificationQueue(session.companyId)).doc('${refId}_$uid');
    await doc.set(_notifMap(uid: uid, companyId: session.companyId, title: title, body: body, type: type, refType: refType, refId: refId));
  }

  Future<SimpleItem> loadMonthlyReport(AdminSession session, DateTime month) async {
    final monthKey = AdminDateUtils.monthKey(month);
    final leaves = _map((await _db.ref(FirebasePaths.leaveRequests(session.companyId)).get()).value) ?? const <String, dynamic>{};
    var approved = 0;
    for (final e in leaves.values) {
      final data = _map(e) ?? const <String, dynamic>{};
      final date = _read(data, ['date_start', 'tanggal_mulai', 'date', 'tanggal']);
      final status = _read(data, ['status', 'approval_status']).toLowerCase();
      if (date.startsWith(monthKey) && (status == 'approved' || status == 'disetujui')) approved++;
    }
    return SimpleItem(id: monthKey, title: AdminDateUtils.monthLabel(month), subtitle: 'Pengajuan disetujui: $approved');
  }

  Future<FirebaseAuth> _secondaryAuth() async {
    const name = 'adminEmployeeCreation';
    try {
      return FirebaseAuth.instanceFor(app: Firebase.app(name));
    } catch (_) {
      final app = await Firebase.initializeApp(name: name, options: DefaultFirebaseOptions.currentPlatform);
      return FirebaseAuth.instanceFor(app: app);
    }
  }

  Future<List<SimpleItem>> _loadSimple(String path, List<String> titleKeys, List<String> subKeys) async {
    final snap = await _db.ref(path).get();
    return _simpleList(snap.value, titleKeys: titleKeys, subKeys: subKeys);
  }

  List<SimpleItem> _simpleList(Object? value, {required List<String> titleKeys, required List<String> subKeys}) {
    final raw = _map(value) ?? const <String, dynamic>{};
    final items = raw.entries.map((e) {
      final data = _map(e.value) ?? const <String, dynamic>{};
      return SimpleItem(id: e.key, title: _read(data, titleKeys).isEmpty ? e.key : _read(data, titleKeys), subtitle: subKeys.map((k) => data[k]?.toString().trim() ?? '').where((v) => v.isNotEmpty).join(' • '), status: _read(data, ['status']));
    }).toList();
    items.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return items;
  }

  Map<String, dynamic> _notifMap({required String uid, required String companyId, required String title, required String body, required String type, required String refType, required String refId}) {
    return {'uid': uid, 'company_id': companyId, 'title': title, 'body': body, 'message': body, 'type': type, 'ref_type': refType, 'ref_id': refId, 'related_id': refId, 'status': 'pending', 'created_at': DateTime.now().millisecondsSinceEpoch, 'sent_at': null, 'failed_at': null, 'failed_count': 0, 'success_count': 0, 'token_count': 0};
  }

  EmployeeRecord _employee(String key, Map<String, dynamic> data) {
    final name = _read(data, ['nama_lengkap', 'display_name', 'name', 'nama', 'user_name']);
    return EmployeeRecord(uid: _read(data, ['uid', 'user_id']).isEmpty ? key : _read(data, ['uid', 'user_id']), name: name.isEmpty ? key : name, email: _read(data, ['email']), nip: _read(data, ['nip', 'employee_id']), phone: _read(data, ['phone', 'nomor_hp']), jobTitle: _read(data, ['job_title', 'jabatan']), groupId: _read(data, ['group_id']), groupName: _read(data, ['group_name', 'nama_grup']), officeName: _read(data, ['office_name', 'nama_kantor']), active: _isActive(data));
  }

  ApprovalItem _approval(String key, String source, Map<String, dynamic> data) {
    return ApprovalItem(id: _read(data, ['request_id', 'id']).isEmpty ? key : _read(data, ['request_id', 'id']), source: source, uid: _read(data, ['uid', 'user_id', 'target_uid']), userName: _read(data, ['user_name', 'nama_lengkap', 'employee_name', 'name']).isEmpty ? 'Karyawan' : _read(data, ['user_name', 'nama_lengkap', 'employee_name', 'name']), type: source == 'qr' ? 'QR' : _read(data, ['type', 'leave_type', 'request_type']), date: _read(data, ['date_start', 'tanggal_mulai', 'date', 'tanggal']), reason: _read(data, ['reason', 'alasan', 'note', 'description']));
  }

  bool _isPending(Map<String, dynamic> data) {
    final status = _read(data, ['status', 'approval_status']).toLowerCase();
    return status.isEmpty || status == 'pending' || status == 'menunggu';
  }

  bool _isActive(Map<String, dynamic> data) {
    final status = _read(data, ['status_akun', 'status']).toLowerCase();
    return data['active'] != false && (status.isEmpty || status == 'active' || status == 'aktif' || status == 'approved');
  }

  Map<String, dynamic>? _map(Object? value) => value is Map ? value.map((key, entry) => MapEntry(key.toString(), entry)) : null;

  String _read(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }
}
