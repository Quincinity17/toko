/// Kamera membaca barcode yang sama berkali-kali per detik selama masih di
/// depan lensa. Kode yang sama baru diterima lagi setelah [repeatAfter]
/// (scan barang yang sama untuk menambah jumlah = jauhkan lalu dekatkan lagi,
/// atau tunggu sebentar); kode berbeda langsung diterima.
class ScanDebouncer {
  ScanDebouncer({
    this.repeatAfter = const Duration(milliseconds: 1500),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration repeatAfter;
  final DateTime Function() _clock;

  String? _last;
  DateTime? _lastAt;

  /// `true` bila [code] sebaiknya diproses sekarang.
  bool accept(String code) {
    final now = _clock();
    if (code == _last &&
        _lastAt != null &&
        now.difference(_lastAt!) < repeatAfter) {
      _lastAt = now; // masih di depan kamera: tunggu dijauhkan
      return false;
    }
    _last = code;
    _lastAt = now;
    return true;
  }
}
