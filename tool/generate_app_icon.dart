// Membuat ikon aplikasi Android (kantong belanja putih di atas biru aksen,
// sama dengan logo sidebar). Jalankan ulang setelah mengubah gambar:
//
//   fvm flutter test tool/generate_app_icon.dart
//
// Menulis android/app/src/main/res/mipmap-*/ic_launcher.png (ikon biasa) dan
// ic_launcher_foreground.png + mipmap-anydpi-v26/ic_launcher.xml (ikon
// adaptif Android 8+, latar = warna @color/ic_launcher_background).
import 'dart:io';
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

Future<void> _write(
  String path,
  int px,
  void Function(Canvas, double) paint,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paint(canvas, px.toDouble());
  final image = await recorder.endRecording().toImage(px, px);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  test('ikon aplikasi Android', () async {
    await TestWidgetsFlutterBinding.ensureInitialized().runAsync(() async {
      for (final MapEntry(key: name, value: k) in _densities.entries) {
        // Ikon biasa 48dp: kotak membulat penuh, gradasi biru.
        await _write('$_res/mipmap-$name/ic_launcher.png', (48 * k).round(), (
          canvas,
          size,
        ) {
          final rect = Rect.fromLTWH(0, 0, size, size);
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(size * 0.22)),
            Paint()
              ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_blueLight, _blue],
              ).createShader(rect),
          );
          _paintBag(canvas, size);
        });
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
