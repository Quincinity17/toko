import 'dart:typed_data';

/// Gambar hitam-putih 1 bit per titik, baris demi baris, 8 titik per byte
/// (bit tertinggi = titik paling kiri), seperti yang diminta printer.
class MonoBitmap {
  MonoBitmap(this.width, this.height)
    : bytes = Uint8List(((width + 7) >> 3) * height);

  final int width;
  final int height;
  final Uint8List bytes;

  int get widthBytes => (width + 7) >> 3;

  void setBlack(int x, int y) =>
      bytes[y * widthBytes + (x >> 3)] |= 0x80 >> (x & 7);

  bool isBlack(int x, int y) =>
      bytes[y * widthBytes + (x >> 3)] & (0x80 >> (x & 7)) != 0;

  /// Dari piksel RGBA (mis. `ui.Image.toByteData(rawRgba)`). Titik dianggap
  /// hitam bila kecerahannya di bawah [threshold] (0–255). Transparan =
  /// putih (kertas).
  factory MonoBitmap.fromRgba(
    Uint8List rgba,
    int width,
    int height, {
    int threshold = 160,
  }) {
    final bmp = MonoBitmap(width, height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        final a = rgba[i + 3];
        if (a < 128) continue;
        // Kecerahan (Rec. 601), dibulatkan ke bilangan bulat.
        final luma =
            (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) ~/ 1000;
        if (luma < threshold) bmp.setBlack(x, y);
      }
    }
    return bmp;
  }

  /// Baris kosong (putih) di bawah dibuang supaya kertas tidak terbuang.
  MonoBitmap trimBottom() {
    var last = height - 1;
    final wb = widthBytes;
    while (last >= 0) {
      final start = last * wb;
      if (bytes.sublist(start, start + wb).any((b) => b != 0)) break;
      last--;
    }
    final h = last + 1;
    if (h == height) return this;
    final out = MonoBitmap(width, h);
    out.bytes.setAll(0, bytes.sublist(0, h * wb));
    return out;
  }
}

/// Penyusun perintah ESC/POS, bahasa printer thermal yang dipakai hampir
/// semua merek (Epson, Xprinter, Zjiang, Panda, dll.).
///
/// Struk dicetak sebagai gambar raster (`GS v 0`) supaya bentuk HTML/CSS,
/// font, dan logo tercetak persis seperti pratinjau.
class EscPos {
  EscPos();

  static const _esc = 0x1B;
  static const _gs = 0x1D;

  /// Tinggi maksimal satu perintah raster. Printer murah punya buffer kecil,
  /// jadi gambar panjang dikirim per potongan.
  static const rasterChunk = 128;

  final _bytes = BytesBuilder(copy: false);

  Uint8List get bytes => _bytes.toBytes();

  /// `ESC @`: kembalikan printer ke pengaturan awal.
  void init() => _bytes.add(const [_esc, 0x40]);

  /// `GS v 0`: cetak gambar raster, per potongan [rasterChunk] baris.
  void raster(MonoBitmap bmp) {
    final wb = bmp.widthBytes;
    for (var y = 0; y < bmp.height; y += rasterChunk) {
      final h = (bmp.height - y).clamp(0, rasterChunk);
      _bytes
        ..add([_gs, 0x76, 0x30, 0, wb & 0xFF, wb >> 8, h & 0xFF, h >> 8])
        ..add(bmp.bytes.sublist(y * wb, (y + h) * wb));
    }
  }

  /// `ESC d n`: maju [n] baris kosong.
  void feed(int n) {
    if (n > 0) _bytes.add([_esc, 0x64, n.clamp(0, 255)]);
  }

  /// `GS V 66 0`: maju sampai pisau lalu potong (sebagian). Printer tanpa
  /// pemotong mengabaikannya.
  void cut() => _bytes.add(const [_gs, 0x56, 66, 0]);

  /// `ESC p m t1 t2`: kirim pulsa ke laci uang lewat [pin] 2 atau 5.
  void openDrawer({int pin = 2}) =>
      _bytes.add([_esc, 0x70, pin == 5 ? 1 : 0, 25, 250]);
}

/// Byte lengkap satu pekerjaan cetak struk.
///
/// [openDrawer] ditaruh di awal supaya laci terbuka sementara struk keluar.
Uint8List buildReceiptJob(
  MonoBitmap image, {
  int feedLines = 3,
  bool cut = true,
  bool openDrawer = false,
  int drawerPin = 2,
}) {
  final p = EscPos()..init();
  if (openDrawer) p.openDrawer(pin: drawerPin);
  p
    ..raster(image)
    ..feed(feedLines);
  if (cut) p.cut();
  return p.bytes;
}

/// Byte untuk membuka laci saja (tanpa mencetak).
Uint8List buildDrawerKick({int pin = 2}) =>
    (EscPos()
          ..init()
          ..openDrawer(pin: pin))
        .bytes;
