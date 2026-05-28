class AdminSession {
  final String uid;
  final String email;
  final String name;
  final String role;
  final String companyId;
  final String companyName;
  const AdminSession({required this.uid, required this.email, required this.name, required this.role, required this.companyId, required this.companyName});
  bool get isOwner => role.toLowerCase() == 'owner';
  bool get isAdmin => role.toLowerCase() == 'owner' || role.toLowerCase() == 'admin';
  String get displayName => name.trim().isEmpty ? email : name;
}

class EmployeeRecord {
  final String uid;
  final String name;
  final String email;
  final String nip;
  final String phone;
  final String jobTitle;
  final String groupId;
  final String groupName;
  final String officeName;
  final bool active;
  const EmployeeRecord({required this.uid, required this.name, required this.email, required this.nip, required this.phone, required this.jobTitle, required this.groupId, required this.groupName, required this.officeName, required this.active});
}

class DashboardSummary {
  final int activeEmployees;
  final int checkedIn;
  final int checkedOut;
  final int pendingApproval;
  final int overtimeToday;
  const DashboardSummary({required this.activeEmployees, required this.checkedIn, required this.checkedOut, required this.pendingApproval, required this.overtimeToday});
  const DashboardSummary.empty() : activeEmployees = 0, checkedIn = 0, checkedOut = 0, pendingApproval = 0, overtimeToday = 0;
}

class ApprovalItem {
  final String id;
  final String source;
  final String uid;
  final String userName;
  final String type;
  final String date;
  final String reason;
  const ApprovalItem({required this.id, required this.source, required this.uid, required this.userName, required this.type, required this.date, required this.reason});
  String get typeLabel => source == 'qr' ? 'QR' : (type.trim().isEmpty ? 'Izin' : '${type[0].toUpperCase()}${type.substring(1)}');
}

class SimpleItem {
  final String id;
  final String title;
  final String subtitle;
  final String status;
  const SimpleItem({required this.id, required this.title, required this.subtitle, this.status = ''});
}
