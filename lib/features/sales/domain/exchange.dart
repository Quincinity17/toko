/// Hitungan tukar barang: barang dikembalikan menjadi [credit], barang
/// pengganti senilai [newTotal]. Selisih positif dibayar pelanggan, negatif
/// dikembalikan ke pelanggan.
class ExchangeTotals {
  const ExchangeTotals({required this.credit, required this.newTotal});

  final int credit;
  final int newTotal;

  int get difference => newTotal - credit;

  /// Yang masih harus dibayar pelanggan (0 bila kredit cukup).
  int get customerPays => difference > 0 ? difference : 0;

  /// Yang dikembalikan ke pelanggan (0 bila barang baru lebih mahal).
  int get refund => difference < 0 ? -difference : 0;
}
