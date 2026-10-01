import 'package:intl/intl.dart';

/// Format angka dan tanggal untuk locale Indonesia.
class Fmt {
  const Fmt._();

  static final _rupiah = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  static final _number = NumberFormat.decimalPattern('id_ID');

  /// `10000` → `Rp 10.000`
  static String rupiah(num value) => _rupiah.format(value);

  /// `1250.5` → `1.250,5`
  static String number(num value) => _number.format(value);

  /// `Senin, 30 September 2026`. Butuh `initializeDateFormatting('id_ID')`
  /// yang dipanggil di `main()`.
  static String dateLong(DateTime d) =>
      DateFormat('EEEE, d MMMM y', 'id_ID').format(d);

  /// `30 Sep 2026`
  static String dateShort(DateTime d) =>
      DateFormat('d MMM y', 'id_ID').format(d);

  /// `30/09/2026 14:05`
  static String dateTime(DateTime d) =>
      DateFormat('dd/MM/y HH:mm', 'id_ID').format(d);

  /// Rupiah ringkas untuk sumbu grafik: `950` → `950`, `12500` → `12,5 rb`,
  /// `1250000` → `1,25 jt`, `2000000000` → `2 M`.
  static String compact(num value) {
    final v = value.abs();
    final sign = value < 0 ? '−' : '';
    String fmt(double x) => NumberFormat('#,##0.##', 'id_ID').format(x);
    if (v < 1000) return '$sign${fmt(v.toDouble())}';
    if (v < 1000000) return '$sign${fmt(v / 1000)} rb';
    if (v < 1000000000) return '$sign${fmt(v / 1000000)} jt';
    return '$sign${fmt(v / 1000000000)} M';
  }

  /// `0.1234` → `12,3%`.
  static String percent(double ratio, {int decimals = 1}) =>
      '${NumberFormat('#,##0.${'0' * decimals}', 'id_ID').format(ratio * 100)}%';

  /// `Kam 15` untuk label sumbu harian.
  static String dayShort(DateTime d) => DateFormat('EEE d', 'id_ID').format(d);
}
