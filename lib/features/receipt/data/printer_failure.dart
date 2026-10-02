/// Gagal mencetak atau membuka laci. [message] siap ditampilkan ke user.
class PrinterFailure implements Exception {
  const PrinterFailure(this.message);

  final String message;

  @override
  String toString() => 'PrinterFailure: $message';
}
