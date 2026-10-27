import 'sale.dart';

/// Jumlah uang dari daftar faktur (tab Hari Ini) untuk menutup kasir.
///
/// Nota retur bernilai negatif, jadi ikut memotong total dan metode bayarnya
/// (uang tunai yang dikembalikan mengurangi uang di laci). Faktur split
/// payment dibagi ke tiap metodenya.
class DayTotal {
  const DayTotal({
    required this.total,
    required this.transactions,
    required this.byMethod,
  });

  factory DayTotal.of(List<SaleSummary> sales) {
    var total = 0;
    var transactions = 0;
    final byMethod = <String, int>{};
    // Daftar terbaru dulu; dibalik supaya urutan metode = urutan dipakai.
    for (final s in sales.reversed) {
      total += s.total;
      if (!s.isReturn) transactions++;
      for (final (method, amount) in s.amountsByMethod) {
        byMethod.update(method, (v) => v + amount, ifAbsent: () => amount);
      }
    }
    return DayTotal(
      total: total,
      transactions: transactions,
      byMethod: byMethod,
    );
  }

  /// Total bersih (penjualan dikurangi retur).
  final int total;

  /// Jumlah faktur penjualan (nota retur tidak dihitung).
  final int transactions;

  /// Total bersih per metode bayar, urut pertama kali dipakai.
  final Map<String, int> byMethod;
}
