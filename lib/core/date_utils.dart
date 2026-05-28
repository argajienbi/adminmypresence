class AdminDateUtils {
  static const _days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
  static const _months = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];

  static String dateKey(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  static String monthKey(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}';
  }

  static String dayDate(DateTime value) {
    final local = value.toLocal();
    return '${_days[local.weekday - 1]}, ${local.day} ${_months[local.month - 1]} ${local.year}';
  }

  static String monthLabel(DateTime value) {
    final local = value.toLocal();
    return '${_months[local.month - 1]} ${local.year}';
  }
}
