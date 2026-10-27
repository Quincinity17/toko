import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_theme.dart';
import '../utils/device.dart';
import '../utils/scan_debouncer.dart';
import 'app_button.dart';
import 'pressable_scale.dart';

/// Hasil memproses satu barcode di mode beruntun, ditampilkan di bawah
/// layar kamera.
class ScanFeedback {
  const ScanFeedback.ok(this.message) : ok = true;
  const ScanFeedback.fail(this.message) : ok = false;

  final String message;
  final bool ok;
}

/// Jenis barcode toko & pabrik yang dibaca (lebih sedikit = lebih cepat).
const _formats = [
  BarcodeFormat.ean13,
  BarcodeFormat.ean8,
  BarcodeFormat.upcA,
  BarcodeFormat.upcE,
  BarcodeFormat.code128,
  BarcodeFormat.code39,
  BarcodeFormat.code93,
  BarcodeFormat.codabar,
  BarcodeFormat.itf14,
  BarcodeFormat.qrCode,
  BarcodeFormat.dataMatrix,
];

// Dibuka di navigator paling atas (layar penuh, di atas bilah ☰ AppShell).

/// Kamera HP: baca satu barcode lalu kembali dengan isinya (mis. mengisi
/// kolom barcode di form barang). `null` = ditutup tanpa hasil.
Future<String?> scanBarcodeOnce(
  BuildContext context, {
  String title = 'Scan Barcode',
}) => Navigator.of(context, rootNavigator: true).push<String>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _ScannerPage(title: title),
  ),
);

/// Kamera HP mode beruntun (kasir): setiap barcode diproses [onCode]
/// (mis. masuk keranjang) dan hasilnya tampil di bawah; kamera tetap terbuka
/// sampai "Selesai".
Future<void> scanBarcodesContinuous(
  BuildContext context, {
  required Future<ScanFeedback> Function(String code) onCode,
  String title = 'Scan Barang',
}) => Navigator.of(context, rootNavigator: true).push<void>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _ScannerPage(title: title, onCode: onCode),
  ),
);

class _ScannerPage extends StatefulWidget {
  const _ScannerPage({required this.title, this.onCode});

  final String title;

  /// `null` = mode sekali scan.
  final Future<ScanFeedback> Function(String code)? onCode;

  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  final _controller = MobileScannerController(
    formats: _formats,
    detectionSpeed: DetectionSpeed.normal,
  );
  final _debouncer = ScanDebouncer();
  ScanFeedback? _feedback;
  int _count = 0;
  bool _busy = false;
  bool _done = false;

  bool get _continuous => widget.onCode != null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || _done) return;
    final code = capture.barcodes
        .map((b) => b.rawValue?.trim() ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (code.isEmpty || !_debouncer.accept(code)) return;

    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
    if (!_continuous) {
      _done = true;
      Navigator.of(context).pop(code);
      return;
    }
    _busy = true;
    try {
      final feedback = await widget.onCode!(code);
      if (!mounted) return;
      setState(() {
        _feedback = feedback;
        if (feedback.ok) _count++;
      });
      if (!feedback.ok) HapticFeedback.heavyImpact();
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          // Bingkai baca: lebar (barcode batang), sedikit di atas tengah.
          final window = Rect.fromCenter(
            center: Offset(size.width / 2, size.height * 0.42),
            width: size.width * 0.82,
            height: (size.height * 0.24).clamp(140, 240),
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _controller,
                scanWindow: window,
                onDetect: _onDetect,
                errorBuilder: (context, error) => _ErrorView(error: error),
              ),
              IgnorePointer(
                child: CustomPaint(painter: _WindowPainter(window)),
              ),
              _topBar(context),
              Positioned(
                left: 0,
                right: 0,
                top: window.bottom + AppSpacing.lg,
                child: Text(
                  'Arahkan barcode ke dalam kotak',
                  textAlign: TextAlign.center,
                  style: AppTypography.subheadline.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
              if (_continuous) _bottomPanel(context),
            ],
          );
        },
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    Widget roundButton(IconData icon, String tooltip, VoidCallback onTap) =>
        Tooltip(
          message: tooltip,
          child: PressableScale(
            onPressed: onTap,
            pressedScale: 0.9,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        );

    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              roundButton(
                CupertinoIcons.xmark,
                'Tutup',
                () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: AppTypography.headline.copyWith(color: Colors.white),
                ),
              ),
              ValueListenableBuilder<MobileScannerState>(
                valueListenable: _controller,
                builder: (context, state, _) =>
                    state.torchState == TorchState.unavailable
                    ? const SizedBox(width: 44)
                    : roundButton(
                        state.torchState == TorchState.on
                            ? CupertinoIcons.bolt_fill
                            : CupertinoIcons.bolt_slash,
                        'Senter',
                        _controller.toggleTorch,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomPanel(BuildContext context) {
    final c = context.colors;
    final f = _feedback;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md + MediaQuery.paddingOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  f == null
                      ? CupertinoIcons.barcode_viewfinder
                      : f.ok
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.xmark_circle_fill,
                  color: f == null
                      ? c.labelSecondary
                      : f.ok
                      ? c.success
                      : c.danger,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    f?.message ??
                        'Scan barang satu per satu. Untuk menambah jumlah '
                            'barang yang sama, jauhkan lalu scan lagi.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.subheadline.copyWith(
                      color: f == null ? c.labelSecondary : c.label,
                      fontWeight: f == null ? null : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: _count == 0 ? 'Selesai' : 'Selesai ($_count di-scan)',
              icon: CupertinoIcons.checkmark_alt,
              size: AppButtonSize.large,
              expand: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Menggelapkan area di luar bingkai baca dan menggambar sudut bingkai.
class _WindowPainter extends CustomPainter {
  _WindowPainter(this.window);

  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = RRect.fromRectAndRadius(window, const Radius.circular(16));
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(frame),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );
    canvas.drawRRect(
      frame,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_WindowPainter old) => old.window != window;
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final message = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'Akses kamera belum diizinkan. Buka Pengaturan HP › Aplikasi › '
            'Toko › Izin › Kamera, lalu coba lagi.',
      MobileScannerErrorCode.unsupported =>
        'Perangkat ini tidak punya kamera yang bisa dipakai.',
      _ => 'Kamera tidak bisa dibuka (${error.errorCode.name}).',
    };
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.camera_fill,
                color: Colors.white70,
                size: 44,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTypography.subheadline.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [field] + tombol kamera di kanannya (hanya di HP/tablet): hasil scan
/// diberikan ke [onScanned]. Di komputer cukup [field] (pakai scanner USB).
class WithScanButton extends StatelessWidget {
  const WithScanButton({
    super.key,
    required this.field,
    required this.onScanned,
    this.enabled = true,
    this.topOffset = 22,
    this.size = 44,
  });

  final Widget field;
  final ValueChanged<String> onScanned;
  final bool enabled;

  /// Jarak atas tombol supaya sejajar kotak isian (melewati label).
  final double topOffset;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!Device.isTouch) return field;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: field),
        const SizedBox(width: AppSpacing.xs),
        Padding(
          padding: EdgeInsets.only(top: topOffset),
          child: AppIconButton(
            icon: CupertinoIcons.camera_viewfinder,
            tooltip: 'Scan dengan kamera',
            size: size,
            filled: true,
            onPressed: enabled
                ? () async {
                    final code = await scanBarcodeOnce(context);
                    if (code != null) onScanned(code);
                  }
                : null,
          ),
        ),
      ],
    );
  }
}
