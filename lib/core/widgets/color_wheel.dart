import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'app_button.dart';
import 'app_dialogs.dart';

/// Popup memilih warna bebas: roda warna (sudut = warna, jarak dari tengah =
/// kepekatan), slider kecerahan, dan kode hex. Mengembalikan warna terpilih,
/// atau `null` bila dibatalkan.
Future<Color?> showColorWheelPicker(
  BuildContext context, {
  required Color initial,
  String title = 'Warna Kustom',
  Widget Function(Color color)? previewBuilder,
}) {
  return AppDialogs.popup<Color>(
    context,
    title: title,
    maxWidth: 400,
    autofocusRoot: false,
    builder: (_) =>
        _ColorWheelDialog(initial: initial, previewBuilder: previewBuilder),
  );
}

class _ColorWheelDialog extends StatefulWidget {
  const _ColorWheelDialog({required this.initial, this.previewBuilder});

  final Color initial;
  final Widget Function(Color color)? previewBuilder;

  @override
  State<_ColorWheelDialog> createState() => _ColorWheelDialogState();
}

class _ColorWheelDialogState extends State<_ColorWheelDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final _hex = TextEditingController(text: _hexOf(widget.initial));
  String? _hexError;

  static String _hexOf(Color c) =>
      (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  Color get _color => _hsv.toColor();

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _setHsv(HSVColor hsv) {
    setState(() {
      _hsv = hsv;
      _hexError = null;
    });
    final text = _hexOf(hsv.toColor());
    if (_hex.text.toUpperCase() != text) {
      _hex.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  void _onHex(String text) {
    var h = text.trim().replaceFirst('#', '');
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
    if (h.length == 6 && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(h)) {
      setState(() {
        _hsv = HSVColor.fromColor(Color(0xFF000000 | int.parse(h, radix: 16)));
        _hexError = null;
      });
    } else {
      setState(() => _hexError = h.length >= 6 ? 'Kode hex tidak valid' : null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ColorWheel(
              key: const ValueKey('color-wheel'),
              hsv: _hsv,
              size: 240,
              onChanged: _setHsv,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(CupertinoIcons.sun_min, size: 18, color: c.labelSecondary),
              Expanded(
                child: CupertinoSlider(
                  key: const ValueKey('color-brightness'),
                  value: _hsv.value,
                  min: 0.15,
                  activeColor: _color,
                  onChanged: (v) => _setHsv(_hsv.withValue(v)),
                ),
              ),
              Icon(
                CupertinoIcons.sun_max_fill,
                size: 18,
                color: c.labelSecondary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _color,
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(color: c.separator),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: CupertinoTextField(
                  key: const ValueKey('color-hex'),
                  controller: _hex,
                  maxLength: 7,
                  prefix: Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.sm),
                    child: Text(
                      '#',
                      style: AppTypography.body.copyWith(
                        color: c.labelSecondary,
                      ),
                    ),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F#]')),
                  ],
                  onChanged: _onHex,
                  style: AppTypography.body.copyWith(
                    color: c.label,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: c.fill,
                    borderRadius: AppRadius.mdAll,
                  ),
                ),
              ),
              if (widget.previewBuilder != null) ...[
                const SizedBox(width: AppSpacing.sm),
                widget.previewBuilder!(_color),
              ],
            ],
          ),
          if (_hexError != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                _hexError!,
                style: AppTypography.footnote.copyWith(color: c.danger),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Batal',
                  variant: AppButtonVariant.gray,
                  expand: true,
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  label: 'Pakai Warna',
                  expand: true,
                  onPressed: () => Navigator.pop(context, _color),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Roda warna HSV: sudut = hue, jarak dari tengah = saturasi; kecerahan
/// ([HSVColor.value]) diatur dari luar. Ketuk atau geser untuk memilih.
class ColorWheel extends StatelessWidget {
  const ColorWheel({
    super.key,
    required this.hsv,
    required this.onChanged,
    this.size = 240,
  });

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  final double size;

  void _pick(Offset local) {
    final r = size / 2;
    final d = local - Offset(r, r);
    final hue = (math.atan2(d.dy, d.dx) * 180 / math.pi + 360) % 360;
    final sat = (d.distance / r).clamp(0.0, 1.0);
    onChanged(hsv.withHue(hue).withSaturation(sat));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: (e) => _pick(e.localPosition),
      onPanUpdate: (e) => _pick(e.localPosition),
      child: CustomPaint(size: Size.square(size), painter: _WheelPainter(hsv)),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    final rect = Rect.fromCircle(center: center, radius: r);
    final v = hsv.value;

    // Hue melingkar (searah jarum jam, 0° di kanan).
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = SweepGradient(
          colors: [
            for (var h = 0; h <= 360; h += 30)
              HSVColor.fromAHSV(1, h % 360.0, 1, v).toColor(),
          ],
        ).createShader(rect),
    );
    // Tengah = abu (saturasi 0) memudar ke tepi.
    final gray = HSVColor.fromAHSV(1, 0, 0, v).toColor();
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(colors: [gray, gray.withAlpha(0)])
            .createShader(rect),
    );

    // Penanda warna terpilih.
    final angle = hsv.hue * math.pi / 180;
    final p =
        center + Offset(math.cos(angle), math.sin(angle)) * hsv.saturation * r;
    canvas
      ..drawCircle(p, 11, Paint()..color = const Color(0x40000000))
      ..drawCircle(p, 10, Paint()..color = const Color(0xFFFFFFFF))
      ..drawCircle(p, 7, Paint()..color = hsv.toColor());
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.hsv != hsv;
}
