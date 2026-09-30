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
}
