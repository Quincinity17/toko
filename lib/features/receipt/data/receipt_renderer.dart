import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../domain/escpos.dart';
import '../domain/printer_config.dart';

/// Struk sebagai widget: kertas putih selebar titik printer, isi HTML hasil
/// [ReceiptHtml.render]. Dipakai pratinjau di layar dan oleh
/// [WidgetReceiptRasterizer] untuk dicetak, jadi keduanya sama persis.
class ReceiptView extends StatelessWidget {
  const ReceiptView({super.key, required this.html, required this.paperWidth});

  final String html;
  final PaperWidth paperWidth;

  /// Gaya dasar; bisa ditimpa CSS template (`body { … }`).
  static const baseStyle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 20,
    height: 1.3,
    color: Color(0xFF000000),
  );

  /// Jarak kiri/kanan di dalam area cetak.
  static const sidePadding = 4.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: paperWidth.dots.toDouble(),
      color: const Color(0xFFFFFFFF),
      padding: const EdgeInsets.symmetric(horizontal: sidePadding, vertical: 8),
      child: DefaultTextStyle(
        style: baseStyle,
        child: HtmlWidget(
          html,
          textStyle: baseStyle,
          buildAsync: false,
          factoryBuilder: ReceiptWidgetFactory.new,
          onErrorBuilder: (context, element, error) => const SizedBox.shrink(),
          onLoadingBuilder: (context, element, progress) =>
              const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Gambar `data:` dipakai ulang dari cache supaya bisa disiapkan (decode)
/// sebelum dirender; gambar dari internet tidak dimuat (aplikasi offline).
class ReceiptWidgetFactory extends WidgetFactory {
  static final _cache = <String, ImageProvider>{};

  static ImageProvider? providerFor(String dataUri) {
    final cached = _cache[dataUri];
    if (cached != null) return cached;
    final bytes = bytesFromDataUri(dataUri);
    if (bytes == null) return null;
    if (_cache.length >= 8) _cache.remove(_cache.keys.first);
    return _cache[dataUri] = MemoryImage(bytes);
  }

  @override
  ImageProvider? imageProviderFromDataUri(String dataUri) =>
      providerFor(dataUri);

  @override
  ImageProvider? imageProviderFromNetwork(String url) => null;

  /// Baris flex dibuat sendiri ([ShrinkRow]) supaya meniru `flex-shrink`
  /// browser: item kepanjangan menyusut sebanding ukurannya dan teksnya
  /// turun baris, bukan meluap.
  @override
  Widget? buildFlex(
    BuildTree tree,
    List<Widget> children, {
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
    required Axis direction,
    MainAxisAlignment mainAxisAlignment = MainAxisAlignment.start,
    double spacing = 0.0,
    TextBaseline textBaseline = TextBaseline.alphabetic,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    if (direction == Axis.vertical) {
      return super.buildFlex(
        tree,
        children,
        crossAxisAlignment: crossAxisAlignment,
        direction: direction,
        mainAxisAlignment: mainAxisAlignment,
        spacing: spacing,
        textBaseline: textBaseline,
        textDirection: textDirection,
      );
    }
    return ShrinkRow(
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      spacing: spacing,
      children: children,
    );
  }
}

/// Baris seperti CSS `display: flex` (arah baris): item memakai lebar
/// alaminya; jika total melebihi lebar tersedia, setiap item menyusut
/// sebanding lebar alaminya (`flex-shrink: 1`). Tinggi = item tertinggi.
class ShrinkRow extends MultiChildRenderObjectWidget {
  const ShrinkRow({
    super.key,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.spacing = 0,
    super.children,
  });

  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final double spacing;

  @override
  RenderShrinkRow createRenderObject(BuildContext context) => RenderShrinkRow(
    mainAxisAlignment: mainAxisAlignment,
    crossAxisAlignment: crossAxisAlignment,
    spacing: spacing,
  );

  @override
  void updateRenderObject(BuildContext context, RenderShrinkRow renderObject) {
    renderObject
      ..mainAxisAlignment = mainAxisAlignment
      ..crossAxisAlignment = crossAxisAlignment
      ..spacing = spacing;
  }
}

class _ShrinkRowParentData extends ContainerBoxParentData<RenderBox> {}

class RenderShrinkRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ShrinkRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ShrinkRowParentData> {
  RenderShrinkRow({
    required this._mainAxisAlignment,
    required this._crossAxisAlignment,
    required this._spacing,
  });

  MainAxisAlignment _mainAxisAlignment;
  set mainAxisAlignment(MainAxisAlignment v) {
    if (v == _mainAxisAlignment) return;
    _mainAxisAlignment = v;
    markNeedsLayout();
  }

  CrossAxisAlignment _crossAxisAlignment;
  set crossAxisAlignment(CrossAxisAlignment v) {
    if (v == _crossAxisAlignment) return;
    _crossAxisAlignment = v;
    markNeedsLayout();
  }

  double _spacing;
  set spacing(double v) {
    if (v == _spacing) return;
    _spacing = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ShrinkRowParentData) {
      child.parentData = _ShrinkRowParentData();
    }
  }

  List<RenderBox> get _children {
    final out = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      out.add(child);
      child = childAfter(child);
    }
    return out;
  }

  @override
  void performLayout() {
    final children = _children;
    final maxWidth = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : double.infinity;
    final gaps = _spacing * (children.length - 1).clamp(0, children.length);
    final avail = maxWidth - gaps;

    // 1. Lebar alami = lebar isi tanpa dibungkus (intrinsik), maksimal
    //    selebar baris. Item block tidak melebar penuh seperti di Column.
    final natural = [
      for (final c in children)
        c.getMaxIntrinsicWidth(double.infinity).clamp(0.0, avail),
    ];
    final total = natural.fold<double>(0, (a, b) => a + b);

    // 2. Kepanjangan: susutkan sebanding lebar alami.
    final ratio = avail.isFinite && total > avail && total > 0
        ? avail / total
        : 1.0;
    for (final (i, c) in children.indexed) {
      final w = (natural[i] * ratio).ceilToDouble();
      c.layout(BoxConstraints(maxWidth: w), parentUsesSize: true);
    }

    final used = children.fold<double>(0, (a, c) => a + c.size.width) + gaps;
    final height = children.fold<double>(
      0,
      (a, c) => c.size.height > a ? c.size.height : a,
    );
    final width = maxWidth.isFinite ? maxWidth : used;
    size = constraints.constrain(Size(width, height));

    // 3. Posisi sesuai justify-content dan align-items.
    final free = (size.width - used).clamp(0.0, double.infinity);
    final n = children.length;
    var x = 0.0;
    var between = _spacing;
    switch (_mainAxisAlignment) {
      case MainAxisAlignment.start:
        break;
      case MainAxisAlignment.end:
        x = free;
      case MainAxisAlignment.center:
        x = free / 2;
      case MainAxisAlignment.spaceBetween:
        if (n > 1) between += free / (n - 1);
      case MainAxisAlignment.spaceAround:
        x = free / n / 2;
        between += free / n;
      case MainAxisAlignment.spaceEvenly:
        x = free / (n + 1);
        between += free / (n + 1);
    }
    for (final c in children) {
      final y = switch (_crossAxisAlignment) {
        CrossAxisAlignment.center => (size.height - c.size.height) / 2,
        CrossAxisAlignment.end => size.height - c.size.height,
        _ => 0.0,
      };
      (c.parentData! as _ShrinkRowParentData).offset = Offset(x, y);
      x += c.size.width + between;
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _children.fold(0.0, (a, c) => a + c.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _children.fold(0.0, (a, c) => a + c.getMaxIntrinsicWidth(height)) +
      _spacing * (_children.length - 1).clamp(0, 1 << 20);

  @override
  double computeMinIntrinsicHeight(double width) => _children.fold(0.0, (a, c) {
    final h = c.getMinIntrinsicHeight(width);
    return h > a ? h : a;
  });

  @override
  double computeMaxIntrinsicHeight(double width) => _children.fold(0.0, (a, c) {
    final h = c.getMaxIntrinsicHeight(width);
    return h > a ? h : a;
  });

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// Mengubah HTML struk menjadi gambar hitam-putih untuk printer.
abstract interface class ReceiptRasterizer {
  Future<MonoBitmap> rasterize(String html, PaperWidth paperWidth);
}

/// Merender [ReceiptView] di luar layar (tanpa ditampilkan) lalu mengubahnya
/// menjadi [MonoBitmap].
class WidgetReceiptRasterizer implements ReceiptRasterizer {
  const WidgetReceiptRasterizer();

  @override
  Future<MonoBitmap> rasterize(String html, PaperWidth paperWidth) async {
    await _precacheImages(html);
    final image = await renderWidgetToImage(
      ReceiptView(html: html, paperWidth: paperWidth),
      width: paperWidth.dots.toDouble(),
    );
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return MonoBitmap.fromRgba(
        data!.buffer.asUint8List(),
        image.width,
        image.height,
      ).trimBottom();
    } finally {
      image.dispose();
    }
  }

  /// Decode semua gambar `data:` lebih dulu, supaya saat dirender gambarnya
  /// sudah ada di cache dan langsung tergambar.
  static Future<void> _precacheImages(String html) async {
    final uris = RegExp(r'''src\s*=\s*["']?(data:image/[^"'\s>]+)''')
        .allMatches(html)
        .map((m) => m.group(1)!.replaceAll('&amp;', '&'));
    for (final uri in uris) {
      final provider = ReceiptWidgetFactory.providerFor(uri);
      if (provider == null) continue;
      final done = Completer<void>();
      final stream = provider.resolve(ImageConfiguration.empty);
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (_, _) {
          if (!done.isCompleted) done.complete();
        },
        onError: (_, _) {
          if (!done.isCompleted) done.complete();
        },
      );
      stream.addListener(listener);
      await done.future.timeout(const Duration(seconds: 3), onTimeout: () {});
      stream.removeListener(listener);
    }
  }
}

/// Merender [widget] selebar [width] piksel logis (rasio 1) tanpa
/// menampilkannya, lalu mengembalikan gambarnya. Tinggi mengikuti isi.
Future<ui.Image> renderWidgetToImage(
  Widget widget, {
  required double width,
  int passes = 3,
}) async {
  final view =
      WidgetsBinding.instance.platformDispatcher.implicitView ??
      WidgetsBinding.instance.platformDispatcher.views.first;
  final boundary = RenderRepaintBoundary();
  final constraints = BoxConstraints(minWidth: width, maxWidth: width);
  final renderView = RenderView(
    view: view,
    configuration: ViewConfiguration(
      logicalConstraints: constraints,
      physicalConstraints: constraints,
    ),
    child: RenderPositionedBox(alignment: Alignment.topLeft, child: boundary),
  );
  final pipeline = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();

  final focus = FocusManager();
  final buildOwner = BuildOwner(focusManager: focus);
  final root = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(textDirection: TextDirection.ltr, child: widget),
    ),
  ).attachToRenderTree(buildOwner);

  try {
    // Beberapa putaran: widget yang baru siap setelah frame pertama (mis.
    // gambar) sempat digambar ulang.
    for (var i = 0; i < passes; i++) {
      buildOwner
        ..buildScope(root)
        ..finalizeTree();
      pipeline
        ..flushLayout()
        ..flushCompositingBits()
        ..flushPaint();
      if (i < passes - 1) await Future<void>.delayed(Duration.zero);
    }
    return await boundary.toImage();
  } finally {
    // Bongkar pohon widget supaya state (dan stream gambar) dibuang.
    RenderObjectToWidgetAdapter<RenderBox>(container: boundary)
        .attachToRenderTree(buildOwner, root);
    buildOwner
      ..buildScope(root)
      ..finalizeTree();
    focus.dispose();
  }
}

final receiptRasterizerProvider = Provider<ReceiptRasterizer>(
  (ref) => const WidgetReceiptRasterizer(),
);
