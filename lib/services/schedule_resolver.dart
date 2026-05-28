import 'package:firebase_database/firebase_database.dart';

import '../core/firebase_paths.dart';

class ScheduleResolveResult {
  const ScheduleResolveResult({
    required this.scheduleReady,
    required this.todayActive,
    required this.scheduleSource,
    this.attendanceStatus,
    this.assignmentId,
    this.shiftId,
    this.shiftName,
    this.timetableId,
    this.timetableName,
    this.workStart,
    this.workEnd,
    this.checkInStart,
    this.checkInEnd,
    this.checkOutStart,
    this.checkOutEnd,
    this.lateToleranceMinute,
  });

  final bool scheduleReady;
  final bool todayActive;
  final String scheduleSource;
  final String? attendanceStatus;
  final String? assignmentId;
  final String? shiftId;
  final String? shiftName;
  final String? timetableId;
  final String? timetableName;
  final String? workStart;
  final String? workEnd;
  final String? checkInStart;
  final String? checkInEnd;
  final String? checkOutStart;
  final String? checkOutEnd;
  final int? lateToleranceMinute;

  const ScheduleResolveResult.none()
      : scheduleReady = false,
        todayActive = false,
        scheduleSource = 'none',
        attendanceStatus = null,
        assignmentId = null,
        shiftId = null,
        shiftName = null,
        timetableId = null,
        timetableName = null,
        workStart = null,
        workEnd = null,
        checkInStart = null,
        checkInEnd = null,
        checkOutStart = null,
        checkOutEnd = null,
        lateToleranceMinute = null;
}

class ScheduleResolver {
  ScheduleResolver({FirebaseDatabase? database}) : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  Future<ScheduleResolveResult> resolveScheduleForUser({
    required String companyId,
    required String uid,
    required String date,
  }) async {
    final employeeSnap = await _db.ref(FirebasePaths.companyUser(companyId, uid)).get();
    final employee = _asMap(employeeSnap.value);
    if (employee == null) return const ScheduleResolveResult.none();

    final holidaySnap = await _db.ref(FirebasePaths.holiday(companyId, date)).get();
    final holiday = _asMap(holidaySnap.value);
    if (holiday != null && _bool(holiday['active'], false)) {
      return const ScheduleResolveResult(
        scheduleReady: true,
        todayActive: false,
        scheduleSource: 'holiday',
        attendanceStatus: 'libur',
      );
    }

    final special = await _findSpecial(companyId: companyId, uid: uid, employee: employee, date: date);
    if (special != null) {
      return _buildFromShift(
        companyId: companyId,
        date: date,
        shiftId: _read(special.data, const ['shift_id']),
        source: 'special_schedule',
        assignmentId: special.id,
      );
    }

    final assignment = await _findAssignment(companyId: companyId, uid: uid, employee: employee, date: date);
    if (assignment.user != null) {
      return _buildFromShift(
        companyId: companyId,
        date: date,
        shiftId: _read(assignment.user!.data, const ['shift_id']),
        source: 'user_assignment',
        assignmentId: assignment.user!.id,
      );
    }
    if (assignment.group != null) {
      return _buildFromShift(
        companyId: companyId,
        date: date,
        shiftId: _read(assignment.group!.data, const ['shift_id']),
        source: 'group_assignment',
        assignmentId: assignment.group!.id,
      );
    }

    return const ScheduleResolveResult.none();
  }

  Future<_ScheduleRecord?> _findSpecial({
    required String companyId,
    required String uid,
    required Map<String, dynamic> employee,
    required String date,
  }) async {
    final snap = await _db.ref(FirebasePaths.scheduleSpecials(companyId)).get();
    final data = _asMap(snap.value) ?? const <String, dynamic>{};
    final groupId = _read(employee, const ['group_id']);

    for (final entry in data.entries) {
      final item = _asMap(entry.value) ?? const <String, dynamic>{};
      if (!_bool(item['active'], false)) continue;
      if (_read(item, const ['date']) != date) continue;

      final type = _read(item, const ['type']);
      final targetId = _read(item, const ['target_id']);
      if ((type == 'user' && targetId == uid) || (type == 'group' && targetId == groupId)) {
        return _ScheduleRecord(id: entry.key, data: item);
      }
    }
    return null;
  }

  Future<_AssignmentMatch> _findAssignment({
    required String companyId,
    required String uid,
    required Map<String, dynamic> employee,
    required String date,
  }) async {
    final snap = await _db.ref(FirebasePaths.scheduleAssignments(companyId)).get();
    final data = _asMap(snap.value) ?? const <String, dynamic>{};
    final groupId = _read(employee, const ['group_id']);
    _ScheduleRecord? userAssignment;
    _ScheduleRecord? groupAssignment;

    for (final entry in data.entries) {
      final item = _asMap(entry.value) ?? const <String, dynamic>{};
      if (!_bool(item['active'], false)) continue;
      if (!_dateInRange(date, _read(item, const ['start_date']), _read(item, const ['end_date']))) continue;

      final type = _read(item, const ['type']);
      final targetId = _read(item, const ['target_id']);
      if (type == 'user' && targetId == uid) {
        userAssignment = _ScheduleRecord(id: entry.key, data: item);
      }
      if (type == 'group' && targetId == groupId) {
        groupAssignment = _ScheduleRecord(id: entry.key, data: item);
      }
    }

    return _AssignmentMatch(user: userAssignment, group: groupAssignment);
  }

  Future<ScheduleResolveResult> _buildFromShift({
    required String companyId,
    required String date,
    required String shiftId,
    required String source,
    required String assignmentId,
  }) async {
    if (shiftId.isEmpty) return const ScheduleResolveResult.none();

    final shiftSnap = await _db.ref(FirebasePaths.shift(companyId, shiftId)).get();
    final shift = _asMap(shiftSnap.value);
    if (shift == null) return const ScheduleResolveResult.none();

    final dayKey = _dayKey(date);
    final days = _asMap(shift['days']) ?? const <String, dynamic>{};
    final day = _asMap(days[dayKey]);
    final timetableId = day == null ? '' : _read(day, const ['timetable_id']);

    if (day == null || !_bool(day['active'], false) || timetableId.isEmpty) {
      return ScheduleResolveResult(
        scheduleReady: true,
        todayActive: false,
        scheduleSource: source,
        assignmentId: assignmentId,
        shiftId: shiftId,
        shiftName: _read(shift, const ['name']),
      );
    }

    final timetableSnap = await _db.ref(FirebasePaths.timetable(companyId, timetableId)).get();
    final timetable = _asMap(timetableSnap.value);
    if (timetable == null) {
      return ScheduleResolveResult(
        scheduleReady: false,
        todayActive: false,
        scheduleSource: source,
        assignmentId: assignmentId,
        shiftId: shiftId,
        shiftName: _read(shift, const ['name']),
      );
    }

    return ScheduleResolveResult(
      scheduleReady: true,
      todayActive: true,
      scheduleSource: source,
      assignmentId: assignmentId,
      shiftId: shiftId,
      shiftName: _read(shift, const ['name']),
      timetableId: timetableId,
      timetableName: _read(timetable, const ['name']),
      workStart: _read(timetable, const ['work_start']),
      workEnd: _read(timetable, const ['work_end']),
      checkInStart: _read(timetable, const ['check_in_start']),
      checkInEnd: _read(timetable, const ['check_in_end']),
      checkOutStart: _read(timetable, const ['check_out_start']),
      checkOutEnd: _read(timetable, const ['check_out_end']),
      lateToleranceMinute: _toInt(timetable['late_tolerance_minute'], 0),
    );
  }
}

class _ScheduleRecord {
  const _ScheduleRecord({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;
}

class _AssignmentMatch {
  const _AssignmentMatch({required this.user, required this.group});

  final _ScheduleRecord? user;
  final _ScheduleRecord? group;
}

bool _dateInRange(String date, String startDate, String endDate) {
  if (startDate.isEmpty) return false;
  if (date.compareTo(startDate) < 0) return false;
  if (endDate.isNotEmpty && date.compareTo(endDate) > 0) return false;
  return true;
}

String _dayKey(String date) {
  final parsed = DateTime.tryParse('${date}T00:00:00') ?? DateTime.now();
  switch (parsed.weekday) {
    case DateTime.monday:
      return 'monday';
    case DateTime.tuesday:
      return 'tuesday';
    case DateTime.wednesday:
      return 'wednesday';
    case DateTime.thursday:
      return 'thursday';
    case DateTime.friday:
      return 'friday';
    case DateTime.saturday:
      return 'saturday';
    default:
      return 'sunday';
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

int _toInt(Object? value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

bool _bool(Object? value, bool fallback) {
  if (value is bool) return value;
  if (value == null) return fallback;
  final text = value.toString().toLowerCase();
  if (text == 'true' || text == '1' || text == 'yes' || text == 'active') return true;
  if (text == 'false' || text == '0' || text == 'no' || text == 'inactive') return false;
  return fallback;
}
