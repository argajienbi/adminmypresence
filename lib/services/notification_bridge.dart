import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';

import '../core/firebase_paths.dart';

class CreateNotificationResult {
  const CreateNotificationResult({
    required this.rtdbNotificationId,
    required this.firestoreInboxId,
    required this.queueId,
  });

  final String? rtdbNotificationId;
  final String? firestoreInboxId;
  final String? queueId;
}

class NotificationBridge {
  NotificationBridge({FirebaseDatabase? database, FirebaseFirestore? firestore})
      : _db = database ?? FirebaseDatabase.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseDatabase _db;
  final FirebaseFirestore _firestore;

  Future<CreateNotificationResult> createNotification({
    required String uid,
    required String companyId,
    required String title,
    required String message,
    required String type,
    required String refType,
    required String refId,
    String? relatedId,
    Map<String, dynamic>? data,
  }) async {
    if (uid.trim().isEmpty) throw Exception('uid kosong, notifikasi tidak bisa dibuat.');
    if (companyId.trim().isEmpty) throw Exception('company_id kosong, notifikasi tidak bisa dibuat.');
    if (title.trim().isEmpty && message.trim().isEmpty) throw Exception('title/message kosong, notifikasi tidak bisa dibuat.');

    final parts = _nowDateParts();
    final normalized = <String, dynamic>{
      'company_id': companyId,
      'uid': uid,
      'title': title.trim(),
      'message': message.trim(),
      'body': message.trim(),
      'type': type.trim().isEmpty ? 'info' : type.trim(),
      'ref_type': refType,
      'ref_id': refId,
      'related_id': relatedId ?? refId,
      if (data != null) 'data': data,
      'read': false,
      'is_read': false,
      'created_date': parts.createdDate,
      'created_time': parts.createdTime,
      'created_at': parts.nowMs,
      'updated_at': parts.nowMs,
    };

    final rtdbRef = _db.ref(FirebasePaths.notifications(uid)).push();
    await rtdbRef.set({
      ...normalized,
      'notification_id': rtdbRef.key,
    });

    final inboxDoc = await _firestore.collection(FirestorePaths.userNotificationInbox(companyId, uid)).add(normalized);
    final queueId = await createNotificationQueue(
      companyId: companyId,
      uid: uid,
      title: title,
      message: message,
      type: type,
      refType: refType,
      refId: refId,
      relatedId: relatedId ?? refId,
      data: data,
    );

    return CreateNotificationResult(
      rtdbNotificationId: rtdbRef.key,
      firestoreInboxId: inboxDoc.id,
      queueId: queueId,
    );
  }

  Future<String> createNotificationQueue({
    required String companyId,
    required String uid,
    required String title,
    required String message,
    required String type,
    required String refType,
    required String refId,
    String? relatedId,
    Map<String, dynamic>? data,
  }) async {
    if (companyId.trim().isEmpty) throw Exception('company_id kosong, notification queue tidak bisa dibuat.');
    if (uid.trim().isEmpty) throw Exception('uid kosong, notification queue tidak bisa dibuat.');

    final now = DateTime.now().millisecondsSinceEpoch;
    final doc = await _firestore.collection(FirestorePaths.notificationQueue(companyId)).add({
      'company_id': companyId,
      'uid': uid,
      'title': title.trim(),
      'message': message.trim(),
      'body': message.trim(),
      'type': type.trim().isEmpty ? 'info' : type.trim(),
      'ref_type': refType,
      'ref_id': refId,
      'related_id': relatedId ?? refId,
      if (data != null) 'data': data,
      'status': 'pending',
      'retry_count': 0,
      'token_count': 0,
      'success_count': 0,
      'failed_count': 0,
      'error': null,
      'created_at': now,
      'sent_at': null,
      'failed_at': null,
    });
    return doc.id;
  }

  Future<void> createNotificationForUsers({
    required String companyId,
    required Iterable<String> uids,
    required String title,
    required String message,
    required String type,
    required String refType,
    required String refId,
    String? relatedId,
    Map<String, dynamic>? data,
  }) async {
    for (final uid in uids.where((item) => item.trim().isNotEmpty)) {
      await createNotification(
        uid: uid,
        companyId: companyId,
        title: title,
        message: message,
        type: type,
        refType: refType,
        refId: refId,
        relatedId: relatedId,
        data: data,
      );
    }
  }

  Future<DocumentReference<Map<String, dynamic>>> writeNotificationLog(String companyId, Map<String, dynamic> payload) {
    return _firestore.collection(FirestorePaths.notificationLogs(companyId)).add({
      ...payload,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> writeAuditLog(
    String companyId, {
    required String action,
    required String details,
    required String userUid,
    required String userName,
    String? targetPath,
    Object? oldValue,
    Object? newValue,
  }) async {
    await _db.ref(FirebasePaths.auditLogs(companyId)).push().set({
      'action': action,
      'details': details,
      'user_uid': userUid,
      'user_name': userName,
      if (targetPath != null) 'target_path': targetPath,
      'old_value': oldValue is String ? oldValue : jsonEncode(oldValue ?? ''),
      'new_value': newValue is String ? newValue : jsonEncode(newValue ?? ''),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }
}

class _DateParts {
  const _DateParts({required this.nowMs, required this.createdDate, required this.createdTime});

  final int nowMs;
  final String createdDate;
  final String createdTime;
}

_DateParts _nowDateParts() {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  return _DateParts(
    nowMs: now.millisecondsSinceEpoch,
    createdDate: '${now.year.toString().padLeft(4, '0')}-${two(now.month)}-${two(now.day)}',
    createdTime: '${two(now.hour)}:${two(now.minute)}:${two(now.second)}',
  );
}
