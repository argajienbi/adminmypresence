class FirebasePaths {
  static String user(String uid) => 'users/$uid';
  static String company(String companyId) => 'companies/$companyId';
  static String companyUsers(String companyId) => 'company_users/$companyId';
  static String companyUser(String companyId, String uid) => 'company_users/$companyId/$uid';
  static String attendanceRoot(String companyId) => 'attendance/$companyId';
  static String attendanceToday(String companyId, String dateKey) => 'attendance/$companyId/$dateKey';
  static String leaveRequests(String companyId) => 'leave_requests/$companyId';
  static String qrRequests(String companyId) => 'qr_attendance_requests/$companyId';
  static String timetables(String companyId) => 'timetables/$companyId';
  static String shifts(String companyId) => 'shifts/$companyId';
  static String assignments(String companyId) => 'schedule_assignments/$companyId';
  static String specials(String companyId) => 'schedule_specials/$companyId';
  static String overtime(String companyId) => 'overtime_schedules/$companyId';
  static String announcements(String companyId) => 'announcements/$companyId';
  static String notificationQueue(String companyId) => 'companies/$companyId/notification_queue';
}
