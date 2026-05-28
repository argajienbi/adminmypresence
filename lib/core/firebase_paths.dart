class FirebasePaths {
  static String appConfig() => 'app_config';

  static String user(String uid) => 'users/$uid';
  static String users() => 'users';

  static String companies() => 'companies';
  static String company(String companyId) => 'companies/$companyId';

  static String companyInvites() => 'company_invites';
  static String companyInvite(String code) => 'company_invites/$code';

  static String companyUsers(String companyId) => 'company_users/$companyId';
  static String companyUser(String companyId, String uid) => 'company_users/$companyId/$uid';

  static String areas(String companyId) => 'areas/$companyId';
  static String area(String companyId, String areaId) => 'areas/$companyId/$areaId';

  static String offices(String companyId) => 'offices/$companyId';
  static String office(String companyId, String officeId) => 'offices/$companyId/$officeId';

  static String departments(String companyId) => 'departments/$companyId';
  static String department(String companyId, String departmentId) => 'departments/$companyId/$departmentId';

  static String subDepartments(String companyId) => 'sub_departments/$companyId';
  static String subDepartment(String companyId, String subDepartmentId) => 'sub_departments/$companyId/$subDepartmentId';

  static String employeeGroups(String companyId) => 'employee_groups/$companyId';
  static String employeeGroup(String companyId, String groupId) => 'employee_groups/$companyId/$groupId';

  static String attendanceRoot(String companyId) => 'attendance/$companyId';
  static String attendanceToday(String companyId, String dateKey) => 'attendance/$companyId/$dateKey';
  static String attendanceUser(String companyId, String uid) => 'attendance/$companyId/$uid';
  static String attendanceRecord(String companyId, String uid, String date, String actionType) => 'attendance/$companyId/$uid/$date/$actionType';

  static String leaveRequests(String companyId) => 'leave_requests/$companyId';
  static String leaveRequest(String companyId, String requestId) => 'leave_requests/$companyId/$requestId';

  static String qrRequests(String companyId) => 'qr_attendance_requests/$companyId';
  static String qrRequest(String companyId, String requestId) => 'qr_attendance_requests/$companyId/$requestId';

  static String attendanceCorrections(String companyId) => 'attendance_corrections/$companyId';
  static String attendanceCorrection(String companyId, String correctionId) => 'attendance_corrections/$companyId/$correctionId';

  static String overtimeRequests(String companyId) => 'overtime_requests/$companyId';
  static String overtimeRequest(String companyId, String requestId) => 'overtime_requests/$companyId/$requestId';

  static String timetables(String companyId) => 'timetables/$companyId';
  static String timetable(String companyId, String timetableId) => 'timetables/$companyId/$timetableId';

  static String shifts(String companyId) => 'shifts/$companyId';
  static String shift(String companyId, String shiftId) => 'shifts/$companyId/$shiftId';

  static String assignments(String companyId) => 'schedule_assignments/$companyId';
  static String scheduleAssignments(String companyId) => 'schedule_assignments/$companyId';
  static String scheduleAssignment(String companyId, String assignmentId) => 'schedule_assignments/$companyId/$assignmentId';

  static String holidays(String companyId) => 'holidays/$companyId';
  static String holiday(String companyId, String date) => 'holidays/$companyId/$date';

  static String specials(String companyId) => 'schedule_specials/$companyId';
  static String scheduleSpecials(String companyId) => 'schedule_specials/$companyId';
  static String scheduleSpecial(String companyId, String specialId) => 'schedule_specials/$companyId/$specialId';

  static String scheduleChangeLogs(String companyId) => 'schedule_change_logs/$companyId';
  static String scheduleChangeLog(String companyId, String logId) => 'schedule_change_logs/$companyId/$logId';

  static String overtime(String companyId) => 'overtime_schedules/$companyId';
  static String overtimeSchedules(String companyId) => 'overtime_schedules/$companyId';
  static String overtimeSchedule(String companyId, String scheduleId) => 'overtime_schedules/$companyId/$scheduleId';

  static String announcements(String companyId) => 'announcements/$companyId';
  static String announcement(String companyId, String announcementId) => 'announcements/$companyId/$announcementId';

  static String auditLogs(String companyId) => 'audit_logs/$companyId';
  static String auditLog(String companyId, String logId) => 'audit_logs/$companyId/$logId';

  static String notifications(String uid) => 'notifications/$uid';
  static String notification(String uid, String notificationId) => 'notifications/$uid/$notificationId';

  static String reportCache(String companyId) => 'report_cache/$companyId';
  static String storageIndex(String companyId) => 'storage_index/$companyId';

  static String notificationQueue(String companyId) => 'companies/$companyId/notification_queue';
}

class FirestorePaths {
  static String company(String companyId) => 'companies/$companyId';

  static String announcements(String companyId) => 'companies/$companyId/announcements';
  static String announcement(String companyId, String announcementId) => 'companies/$companyId/announcements/$announcementId';

  static String notificationSettings(String companyId) => 'companies/$companyId/notification_settings/main';

  static String notificationQueue(String companyId) => 'companies/$companyId/notification_queue';
  static String notificationQueueItem(String companyId, String queueId) => 'companies/$companyId/notification_queue/$queueId';

  static String notificationLogs(String companyId) => 'companies/$companyId/notification_logs';
  static String notificationLog(String companyId, String logId) => 'companies/$companyId/notification_logs/$logId';

  static String notificationDedup(String companyId) => 'companies/$companyId/notification_dedup';
  static String notificationDedupItem(String companyId, String dedupId) => 'companies/$companyId/notification_dedup/$dedupId';

  static String announcementDeliveryLogs(String companyId) => 'companies/$companyId/announcement_delivery_logs';
  static String announcementDeliveryLog(String companyId, String logId) => 'companies/$companyId/announcement_delivery_logs/$logId';

  static String userNotificationInbox(String companyId, String uid) => 'companies/$companyId/users/$uid/notification_inbox';
  static String userNotificationItem(String companyId, String uid, String notificationId) => 'companies/$companyId/users/$uid/notification_inbox/$notificationId';

  static String userFcmTokens(String companyId, String uid) => 'companies/$companyId/users/$uid/fcm_tokens';
  static String userFcmToken(String companyId, String uid, String tokenId) => 'companies/$companyId/users/$uid/fcm_tokens/$tokenId';

  static String dashboardDailySummary(String companyId, String date) => 'companies/$companyId/dashboard_daily_summary/$date';
  static String reportCache(String companyId, String month) => 'companies/$companyId/report_cache/$month';
}
