/// Nomor faktur `INV-YYYYMMDD-0001`, urut ulang dari 0001 setiap hari.
class InvoiceNumber {
  const InvoiceNumber._();

  static String prefixFor(DateTime date) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'INV-${date.year}${two(date.month)}${two(date.day)}-';
  }

  /// Nomor berikutnya setelah [last] (nomor terakhir hari itu, atau `null`).
  static String next(DateTime date, String? last) {
    final prefix = prefixFor(date);
    var seq = 1;
    if (last != null && last.startsWith(prefix)) {
      seq = (int.tryParse(last.substring(prefix.length)) ?? 0) + 1;
    }
    return '$prefix${seq.toString().padLeft(4, '0')}';
  }
}
