/// Lama riwayat penjualan disimpan sebelum dihapus otomatis (Pengaturan ›
/// Riwayat Penjualan). `0` bulan = tidak pernah dihapus (bawaan).
class HistoryRetention {
  const HistoryRetention._();

  static const never = 0;

  /// Pilihan di layar, dalam bulan.
  static const options = [never, 6, 12, 24, 36, 60];

  static int clamp(int months) => options.contains(months) ? months : never;

  static String label(int months) => switch (months) {
    never => 'Tidak pernah',
    6 => 'Lebih lama dari 6 bulan',
    _ => 'Lebih lama dari ${months ~/ 12} tahun',
  };

  /// Faktur sebelum tanggal ini (awal hari) dihapus: hari ini dikurangi
  /// [months] bulan, mis. 13 Okt 2026 − 12 bulan = 13 Okt 2025 00:00.
  /// Tanggal yang tidak ada (31 Feb) dibulatkan ke akhir bulan itu.
  static DateTime cutoff(DateTime now, int months) {
    final monthIndex = now.month - 1 - months;
    final year = now.year + (monthIndex / 12).floor();
    final month = monthIndex % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, now.day > lastDay ? lastDay : now.day);
  }

  /// Penghapusan otomatis berjalan sekali sehari.
  static bool isDue(DateTime? lastRun, DateTime now) =>
      lastRun == null ||
      DateTime(lastRun.year, lastRun.month, lastRun.day) !=
          DateTime(now.year, now.month, now.day);
}
