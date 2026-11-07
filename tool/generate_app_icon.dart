// Membuat ikon aplikasi (kantong belanja putih di atas biru aksen, sama
// dengan logo sidebar) untuk Android, Windows, dan macOS. Jalankan ulang
// setelah mengubah gambar:
//
//   fvm flutter test tool/generate_app_icon.dart
//
// Menulis:
// - android/app/src/main/res/mipmap-*/ic_launcher.png (ikon biasa) dan
//   ic_launcher_foreground.png + mipmap-anydpi-v26/ic_launcher.xml (ikon
//   adaptif Android 8+, latar = warna @color/ic_launcher_background).
// - windows/runner/resources/app_icon.ico (16–256 px; 256 = PNG, lainnya
//   bitmap 32-bit supaya terbaca semua versi Windows).
// - macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png (kotak
//   membulat dengan tepi kosong sesuai grid ikon macOS).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _blue = Color(0xFF007AFF);
const _blueLight = Color(0xFF3D9BFF);
const _res = 'android/app/src/main/res';

/// Kepadatan Android → skala (mdpi = 1).
const _densities = {
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};

/// Kantong belanja di kotak [size] (koordinat 0–1 dari kotak itu).
void _paintBag(Canvas canvas, double size, {double scale = 1}) {
  canvas.save();
  canvas.translate(size * (1 - scale) / 2, size * (1 - scale) / 2);
  final s = size * scale;
  final white = Paint()..color = const Color(0xFFFFFFFF);
  // Badan kantong: trapesium (melebar ke bawah) bersudut bulat.
  final r = s * 0.05;
  final body = Path()
    ..moveTo(s * 0.30 + r, s * 0.38)
    ..lineTo(s * 0.70 - r, s * 0.38)
    ..quadraticBezierTo(s * 0.70, s * 0.38, s * 0.705, s * 0.38 + r)
    ..lineTo(s * 0.77, s * 0.80 - r)
    ..quadraticBezierTo(s * 0.78, s * 0.80, s * 0.77 - r, s * 0.80)
    ..lineTo(s * 0.23 + r, s * 0.80)
    ..quadraticBezierTo(s * 0.22, s * 0.80, s * 0.23, s * 0.80 - r)
    ..lineTo(s * 0.295, s * 0.38 + r)
    ..quadraticBezierTo(s * 0.30, s * 0.38, s * 0.30 + r, s * 0.38)
    ..close();
  canvas.drawPath(body, white);
  // Tali ramping dari lubang ke lubang.
  canvas.drawArc(
    Rect.fromLTRB(s * 0.39, s * 0.22, s * 0.61, s * 0.56),
    3.1416,
    3.1416,
    false,
    Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.045
      ..strokeCap = StrokeCap.round,
  );
  // Lubang tali di badan (aksen biru kecil).
  final hole = Paint()..color = _blue;
  canvas.drawCircle(Offset(s * 0.39, s * 0.47), s * 0.024, hole);
  canvas.drawCircle(Offset(s * 0.61, s * 0.47), s * 0.024, hole);
  canvas.restore();
}

/// Kotak membulat bergradasi biru + kantong, di kotak [size] dengan tepi
/// kosong [inset] (0–1 dari ukuran).
void _paintTile(Canvas canvas, double size, {double inset = 0}) {
  final pad = size * inset;
  final s = size - pad * 2;
  final rect = Rect.fromLTWH(pad, pad, s, s);
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(s * 0.22)),
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_blueLight, _blue],
      ).createShader(rect),
  );
  canvas.save();
  canvas.translate(pad, pad);
  _paintBag(canvas, s);
  canvas.restore();
}

Future<ui.Image> _render(int px, void Function(Canvas, double) paint) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paint(canvas, px.toDouble());
  return recorder.endRecording().toImage(px, px);
}

Future<Uint8List> _png(int px, void Function(Canvas, double) paint) async {
  final image = await _render(px, paint);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}

Future<void> _write(
  String path,
  int px,
  void Function(Canvas, double) paint,
) async {
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(await _png(px, paint));
}

/// Gambar ikon .ico bentuk bitmap 32-bit (BITMAPINFOHEADER + BGRA dari bawah
/// ke atas + mask AND kosong).
Future<Uint8List> _icoBitmap(
  int px,
  void Function(Canvas, double) paint,
) async {
  final image = await _render(px, paint);
  final rgba = (await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  ))!;
  final maskRow = ((px + 31) ~/ 32) * 4;
  final out = BytesBuilder();
  final header = ByteData(40)
    ..setUint32(0, 40, Endian.little)
    ..setInt32(4, px, Endian.little)
    ..setInt32(8, px * 2, Endian.little) // tinggi gambar + mask
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, 32, Endian.little)
    ..setUint32(20, px * px * 4 + maskRow * px, Endian.little);
  out.add(header.buffer.asUint8List());
  for (var y = px - 1; y >= 0; y--) {
    for (var x = 0; x < px; x++) {
      final i = (y * px + x) * 4;
      out.add([
        rgba.getUint8(i + 2),
        rgba.getUint8(i + 1),
        rgba.getUint8(i),
        rgba.getUint8(i + 3),
      ]);
    }
  }
  out.add(Uint8List(maskRow * px));
  return out.toBytes();
}

Future<void> _writeIco(String path, List<int> sizes) async {
  final images = <(int, Uint8List)>[];
  for (final px in sizes) {
    images.add((
      px,
      px >= 256 ? await _png(px, _paintTile) : await _icoBitmap(px, _paintTile),
    ));
  }
  final out = BytesBuilder();
  out.add(
    (ByteData(6)
          ..setUint16(2, 1, Endian.little)
          ..setUint16(4, images.length, Endian.little))
        .buffer
        .asUint8List(),
  );
  var offset = 6 + 16 * images.length;
  for (final (px, data) in images) {
    out.add(
      (ByteData(16)
            ..setUint8(0, px >= 256 ? 0 : px)
            ..setUint8(1, px >= 256 ? 0 : px)
            ..setUint16(4, 1, Endian.little)
            ..setUint16(6, 32, Endian.little)
            ..setUint32(8, data.length, Endian.little)
            ..setUint32(12, offset, Endian.little))
          .buffer
          .asUint8List(),
    );
    offset += data.length;
  }
  for (final (_, data) in images) {
    out.add(data);
  }
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(out.toBytes());
}

void main() {
  test('ikon Windows & macOS', () async {
    await TestWidgetsFlutterBinding.ensureInitialized().runAsync(() async {
      await _writeIco('windows/runner/resources/app_icon.ico', [
        16, 20, 24, 32, 40, 48, 64, 128, 256, //
      ]);
      for (final px in [16, 32, 64, 128, 256, 512, 1024]) {
        // Grid ikon macOS: isi 824 dari 1024 (tepi ±10%).
        await _write(
          'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$px.png',
          px,
          (canvas, size) => _paintTile(canvas, size, inset: 100 / 1024),
        );
      }
    });
  });

  test('ikon aplikasi Android', () async {
    await TestWidgetsFlutterBinding.ensureInitialized().runAsync(() async {
      for (final MapEntry(key: name, value: k) in _densities.entries) {
        // Ikon biasa 48dp: kotak membulat penuh, gradasi biru.
        await _write(
          '$_res/mipmap-$name/ic_launcher.png',
          (48 * k).round(),
          _paintTile,
        );
        // Latar depan ikon adaptif 108dp: isi di zona aman tengah (66dp).
        await _write(
          '$_res/mipmap-$name/ic_launcher_foreground.png',
          (108 * k).round(),
          (canvas, size) => _paintBag(canvas, size, scale: 0.62),
        );
      }
    });

    File('$_res/mipmap-anydpi-v26/ic_launcher.xml')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '</adaptive-icon>\n',
      );
    File('$_res/values/ic_launcher_background.xml').writeAsStringSync(
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<resources>\n'
      '    <color name="ic_launcher_background">#007AFF</color>\n'
      '</resources>\n',
    );
  });
}
