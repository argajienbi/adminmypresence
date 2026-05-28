import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../core/firebase_paths.dart';

class FirestoreUserSyncResult {
  const FirestoreUserSyncResult({required this.total, required this.synced});

  final int total;
  final int synced;
}

class FirestoreUserSyncService {
  FirestoreUserSyncService({FirebaseDatabase? database, FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = database ?? FirebaseDatabase.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseDatabase _db;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Future<FirestoreUserSyncResult> sync({String? companyId}) async {
    final usersSnap = await _db.ref(FirebasePaths.users()).get();
    final users = _asMap(usersSnap.value) ?? const <String, dynamic>{};
    var synced = 0;
    final batch = _firestore.batch();

    for (final entry in users.entries) {
      final uid = entry.key;
      final data = _asMap(entry.value) ?? const <String, dynamic>{};
      final userCompanyId = _read(data, const ['company_id', 'companyId']);
      if (companyId != null && companyId.isNotEmpty && userCompanyId != companyId) continue;

      batch.set(_firestore.collection('users').doc(uid), _normalize(uid, data), SetOptions(merge: true));
      synced++;
    }

    if (synced > 0) await batch.commit();
    return FirestoreUserSyncResult(total: users.length, synced: synced);
  }

  Future<void> mirrorUser(String uid, Map<String, dynamic> data) {
    return _firestore.collection('users').doc(uid).set(_normalize(uid, data), SetOptions(merge: true));
  }

  Future<String?> currentIdToken() async => _auth.currentUser?.getIdToken();

  Map<String, dynamic> _normalize(String uid, Map<String, dynamic> data) {
    return {
      'uid': _read(data, const ['uid']).ifEmpty(uid),
      'company_id': _read(data, const ['company_id', 'companyId']),
      'role': _read(data, const ['role', 'level']).ifEmpty('user'),
      'status_akun': _read(data, const ['status_akun', 'status']).ifEmpty('active'),
      'nama_lengkap': _read(data, const ['nama_lengkap', 'display_name', 'name']),
      'email': _read(data, const ['email']),
      'nip': _read(data, const ['nip']),
      'no_hp': _read(data, const ['no_hp', 'phone', 'nomor_hp']),
      'position': _read(data, const ['position', 'job_title', 'jabatan']),
      'area_id': _read(data, const ['area_id']),
      'office_id': _read(data, const ['office_id']),
      'department_id': _read(data, const ['department_id']),
      'sub_department_id': _read(data, const ['sub_department_id']),
      'group_id': _read(data, const ['group_id', 'employee_group_id']),
      'photo_url': _read(data, const ['photo_url']),
      'photo_path': _read(data, const ['photo_path']),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
  }
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map) return value.map((key, item) => MapEntry(key.toString(), item));
  return null;
}

String _read(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value != null && value.toString().trim().isNotEmpty) return value.toString().trim();
  }
  return '';
}

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
