/// Nomor faktur `INV-<kode terminal>-YYYYMMDD-0001`, misalnya
/// `INV-K01-20261001-0001`. Urut ulang dari 0001 setiap hari, terpisah per
/// terminal, sehingga beberapa komputer kasir tidak menghasilkan nomor sama.
/// Nota retur memakai pola yang sama dengan [type] `RET`.
class InvoiceNumber {
  const InvoiceNumber._();

  static const sale = 'INV';
  static const saleReturn = 'RET';

  static String prefixFor(
    DateTime date,
    String terminalCode, {
    String type = sale,
  }) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '$type-$terminalCode-${date.year}${two(date.month)}${two(date.day)}-';
  }

  /// Nomor berikutnya setelah [last] (nomor terakhir terminal ini pada hari
  /// itu, atau `null`).
  static String next(
    DateTime date,
    String terminalCode,
    String? last, {
    String type = sale,
  }) {
    final prefix = prefixFor(date, terminalCode, type: type);
    var seq = 1;
    if (last != null && last.startsWith(prefix)) {
      seq = (int.tryParse(last.substring(prefix.length)) ?? 0) + 1;
    }
    return '$prefix${seq.toString().padLeft(4, '0')}';
  }
}
