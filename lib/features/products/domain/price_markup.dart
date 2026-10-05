/// Harga jual dari persen untung (markup) terhadap harga beli, dan
/// sebaliknya. Dipakai form barang dan Input Tabel.
abstract final class PriceMarkup {
  /// Harga jual dibulatkan ke atas ke kelipatan ini, supaya untung tidak
  /// kurang dari persen yang diminta dan harga enak dibayar.
  static const roundTo = 100;

  /// `buy` 2.800 + 25% = 3.500. `null` bila harga beli belum diisi (0) atau
  /// persen negatif.
  static int? sellingPrice(int buy, double percent) {
    if (buy <= 0 || percent < 0) return null;
    final raw = buy * (1 + percent / 100);
    // Toleransi kecil: 2.800 × 1,25 bisa jadi 3.500,0000001.
    return ((raw - 1e-6) / roundTo).ceil() * roundTo;
  }

  /// Persen untung harga jual terhadap harga beli, dibulatkan 1 desimal.
  /// `null` bila harga beli belum diisi.
  static double? percent(int buy, int sell) {
    if (buy <= 0) return null;
    return ((sell - buy) / buy * 1000).round() / 10;
  }
}
