import 'package:flutter/cupertino.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/number_input.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/barcode_scanner.dart';
import '../domain/product_pricing.dart';

class _UnitRow {
  _UnitRow([ProductUnit? u])
    : id = u?.id,
      name = TextEditingController(text: u?.name),
      factor = TextEditingController(
        text: u == null ? '' : Fmt.number(u.factor),
      ),
      // Harga default (semua toko); harga khusus toko diisi di bagian toko.
      price = TextEditingController(
        text: u == null ? '' : Fmt.number(u.defaultPrice),
      ),
      barcode = TextEditingController(text: u?.barcode);

  final int? id;
  final TextEditingController name;
  final TextEditingController factor;
  final TextEditingController price;
  final TextEditingController barcode;

  List<TextEditingController> get all => [name, factor, price, barcode];
}

class _TierRow {
  _TierRow([PriceTier? t])
    : minQty = TextEditingController(
        text: t == null ? '' : Fmt.number(t.minQty),
      ),
      price = TextEditingController(text: t == null ? '' : Fmt.number(t.price));

  final TextEditingController minQty;
  final TextEditingController price;
}

/// Isian satuan lain (multi-satuan) dan harga grosir di form barang.
class PricingEditorController extends ChangeNotifier {
  PricingEditorController({
    List<ProductUnit> units = const [],
    List<PriceTier> tiers = const [],
  }) : _tiers = [for (final t in tiers) _TierRow(t)] {
    units.map(_UnitRow.new).forEach(_trackUnit);
  }

  final List<_UnitRow> _units = [];
  final List<_TierRow> _tiers;

  /// Keterangan harga per satuan dasar ikut berubah saat isi/harga diketik.
  void _trackUnit(_UnitRow r) {
    r.name.addListener(notifyListeners);
    r.factor.addListener(notifyListeners);
    r.price.addListener(notifyListeners);
    _units.add(r);
  }

  void addUnit() {
    _trackUnit(_UnitRow());
    notifyListeners();
  }

  void removeUnit(int i) {
    for (final c in _units.removeAt(i).all) {
      c.dispose();
    }
    notifyListeners();
  }

  void addTier() {
    _tiers.add(_TierRow());
    notifyListeners();
  }

  void removeTier(int i) {
    final t = _tiers.removeAt(i);
    t.minQty.dispose();
    t.price.dispose();
    notifyListeners();
  }

  static double? _num(TextEditingController c) =>
      c.text.trim().isEmpty ? null : parseIdNumber(c.text)?.toDouble();

  /// Isian yang tidak bisa dibaca (angka kosong/salah), atau `null`.
  String? get parseError {
    for (final u in _units) {
      final name = u.name.text.trim().isEmpty ? 'baru' : u.name.text.trim();
      if (_num(u.factor) == null) return 'Isi satuan $name wajib diisi.';
      if (_num(u.price) == null) return 'Harga satuan $name wajib diisi.';
    }
    for (final t in _tiers) {
      if (_num(t.minQty) == null || _num(t.price) == null) {
        return 'Lengkapi jumlah minimal dan harga grosir.';
      }
    }
    return null;
  }

  /// Nama satuan lain yang sudah diisi (huruf besar), untuk isian harga
  /// per toko.
  List<String> get unitNames => [
    for (final u in _units)
      if (PricingRules.unitName(u.name.text) case final n when n.isNotEmpty) n,
  ];

  /// Harga default satuan [name] yang sedang diketik (placeholder harga
  /// toko).
  int? defaultPriceOf(String name) {
    for (final u in _units) {
      if (PricingRules.unitName(u.name.text) == name) {
        return _num(u.price)?.round();
      }
    }
    return null;
  }

  /// Hanya dipanggil bila [parseError] `null`.
  List<ProductUnit> get units => [
    for (final u in _units)
      ProductUnit(
        id: u.id,
        name: PricingRules.unitName(u.name.text),
        factor: _num(u.factor)!,
        barcode: u.barcode.text.trim().isEmpty ? null : u.barcode.text.trim(),
        price: _num(u.price)!.round(),
      ),
  ];

  List<PriceTier> get tiers => [
    for (final t in _tiers)
      PriceTier(minQty: _num(t.minQty)!, price: _num(t.price)!.round()),
  ];

  @override
  void dispose() {
    for (final u in _units) {
      for (final c in u.all) {
        c.dispose();
      }
    }
    for (final t in _tiers) {
      t.minQty.dispose();
      t.price.dispose();
    }
    super.dispose();
  }
}

/// Bagian "Satuan lain" dan "Harga grosir" di form barang.
class PricingEditor extends StatelessWidget {
  const PricingEditor({
    super.key,
    required this.controller,
    required this.baseUnit,
    required this.purchasePrice,
  });

  final PricingEditorController controller;
  final String baseUnit;

  /// Harga beli satuan dasar (untuk keterangan untung per satuan lain).
  final int purchasePrice;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final c = context.colors;
    Widget heading(String text) => Text(
      text,
      style: AppTypography.footnote.copyWith(
        color: c.labelSecondary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );
    Widget note(String text) => Text(
      text,
      style: AppTypography.footnote.copyWith(color: c.labelSecondary),
    );
    Widget pair(Widget a, Widget b) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: b),
      ],
    );
    final box = BoxDecoration(
      color: c.fillSecondary,
      borderRadius: AppRadius.mdAll,
    );
    Widget removeButton(String tooltip, VoidCallback onPressed) =>
        AppIconButton(
          icon: CupertinoIcons.minus_circle_fill,
          tooltip: tooltip,
          color: c.danger,
          onPressed: onPressed,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('SATUAN LAIN (MULTI-SATUAN)'),
        const SizedBox(height: AppSpacing.xs),
        for (final (i, u) in controller._units.indexed) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: box,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: pair(
                        AppTextField(
                          controller: u.name,
                          label: 'Nama satuan',
                          placeholder: 'mis. DUS',
                        ),
                        AppTextField(
                          controller: u.factor,
                          label: 'Isi ($baseUnit)',
                          placeholder: 'mis. 24',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: removeButton(
                        'Hapus satuan',
                        () => controller.removeUnit(i),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                pair(
                  AppTextField(
                    controller: u.price,
                    label: 'Harga satuan ini (Rp)',
                    placeholder: '0',
                    keyboardType: TextInputType.number,
                    inputFormatters: [RupiahInputFormatter()],
                  ),
                  WithScanButton(
                    onScanned: (v) => u.barcode.text = v,
                    field: AppTextField(
                      controller: u.barcode,
                      label: 'Barcode kemasan (opsional)',
                      placeholder: 'Barcode di dus',
                      prefixIcon: CupertinoIcons.barcode,
                    ),
                  ),
                ),
                if (_unitNote(u) case final text?) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    text,
                    style: AppTypography.footnote.copyWith(
                      color: c.labelSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: 'Tambah Satuan',
            icon: CupertinoIcons.plus_circle,
            variant: AppButtonVariant.plain,
            size: AppButtonSize.small,
            onPressed: controller.addUnit,
          ),
        ),
        note(
          'Mis. DUS isi 24: scan barcode kemasan atau ganti satuan di kasir. '
          'Stok tetap dihitung dalam $baseUnit (jual 1 DUS = stok berkurang '
          '24). Harga satuan lain berlaku di semua toko.',
        ),
        const SizedBox(height: AppSpacing.lg),
        heading('HARGA GROSIR'),
        const SizedBox(height: AppSpacing.xs),
        for (final (i, t) in controller._tiers.indexed) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            decoration: box,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: pair(
                    AppTextField(
                      controller: t.minQty,
                      label: 'Beli minimal ($baseUnit)',
                      placeholder: 'mis. 12',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    AppTextField(
                      controller: t.price,
                      label: 'Harga per $baseUnit (Rp)',
                      placeholder: '0',
                      keyboardType: TextInputType.number,
                      inputFormatters: [RupiahInputFormatter()],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: removeButton(
                    'Hapus harga grosir',
                    () => controller.removeTier(i),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: 'Tambah Harga Grosir',
            icon: CupertinoIcons.plus_circle,
            variant: AppButtonVariant.plain,
            size: AppButtonSize.small,
            onPressed: controller.addTier,
          ),
        ),
        note(
          'Kasir otomatis memakai harga grosir bila jumlah $baseUnit di satu '
          'baris mencapai minimalnya. Berlaku di semua toko, dan hanya bila '
          'lebih murah dari harga toko.',
        ),
      ],
    );
  }

  /// "Harga per PCS Rp 2.917 · untung Rp 12.000".
  String? _unitNote(_UnitRow u) {
    final factor = PricingEditorController._num(u.factor);
    final price = PricingEditorController._num(u.price);
    if (factor == null || factor <= 0 || price == null) return null;
    final perBase = (price / factor).round();
    final cost = (purchasePrice * factor).round();
    return 'Setara ${Fmt.rupiah(perBase)} per $baseUnit'
        '${purchasePrice > 0 ? ' · untung ${Fmt.rupiah(price.round() - cost)}' : ''}';
  }
}

/// Baris harga grosir khusus satu toko (form barang, bagian per toko).
class TierRowsController extends ChangeNotifier {
  TierRowsController([List<PriceTier> tiers = const []])
    : _rows = [for (final t in tiers) _TierRow(t)];

  final List<_TierRow> _rows;

  bool get isEmpty => _rows.isEmpty;

  void add() {
    _rows.add(_TierRow());
    notifyListeners();
  }

  void removeAt(int i) {
    final t = _rows.removeAt(i);
    t.minQty.dispose();
    t.price.dispose();
    notifyListeners();
  }

  String? get parseError {
    for (final t in _rows) {
      if (PricingEditorController._num(t.minQty) == null ||
          PricingEditorController._num(t.price) == null) {
        return 'Lengkapi jumlah minimal dan harga grosir toko.';
      }
    }
    return null;
  }

  List<PriceTier> get tiers => [
    for (final t in _rows)
      PriceTier(
        minQty: PricingEditorController._num(t.minQty)!,
        price: PricingEditorController._num(t.price)!.round(),
      ),
  ];

  @override
  void dispose() {
    for (final t in _rows) {
      t.minQty.dispose();
      t.price.dispose();
    }
    super.dispose();
  }
}

/// Isian grosir khusus toko: kosong = ikut grosir semua toko.
class TierRowsEditor extends StatelessWidget {
  const TierRowsEditor({
    super.key,
    required this.controller,
    required this.baseUnit,
  });

  final TierRowsController controller;
  final String baseUnit;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = context.colors;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, t) in controller._rows.indexed)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: t.minQty,
                      label: 'Grosir toko: min. ($baseUnit)',
                      placeholder: 'mis. 12',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppTextField(
                      controller: t.price,
                      label: 'Harga grosir toko (Rp)',
                      placeholder: '0',
                      keyboardType: TextInputType.number,
                      inputFormatters: [RupiahInputFormatter()],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: AppIconButton(
                      icon: CupertinoIcons.minus_circle_fill,
                      tooltip: 'Hapus grosir toko',
                      color: c.danger,
                      onPressed: () => controller.removeAt(i),
                    ),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: controller.isEmpty
                  ? 'Grosir khusus toko ini'
                  : 'Tambah grosir toko',
              icon: CupertinoIcons.plus_circle,
              variant: AppButtonVariant.plain,
              size: AppButtonSize.small,
              onPressed: controller.add,
            ),
          ),
        ],
      );
    },
  );
}
