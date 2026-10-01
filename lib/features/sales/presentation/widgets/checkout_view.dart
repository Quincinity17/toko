import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/number_input.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../products/data/product_repository.dart';
import '../../../products/domain/product.dart';
import '../cart_controller.dart';
import 'cart_summary_panel.dart';
import 'cart_table.dart';
import 'payment_sheet.dart';
import 'product_search_sheet.dart';

/// Tab "Transaksi Baru": input barang, tabel keranjang, dan panel total.
///
/// Kolom kode selalu kembali fokus supaya scanner barcode USB (yang mengetik
/// seperti keyboard lalu menekan Enter) bisa langsung dipakai.
/// Shortcut: F2 / End = bayar, F3 = cari barang.
class CheckoutView extends ConsumerStatefulWidget {
  const CheckoutView({super.key});

  @override
  ConsumerState<CheckoutView> createState() => CheckoutViewState();
}

class CheckoutViewState extends ConsumerState<CheckoutView> {
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  final _qty = TextEditingController(text: '1');
  final _scroll = ScrollController();

  int? _selected;
  String? _codeError;

  /// Naik setiap transaksi selesai/batal, untuk me-reset panel ringkasan.
  int _session = 0;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _codeFocus.dispose();
    _qty.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void focusEntry() {
    if (mounted) _codeFocus.requestFocus();
  }

  CartController get _cart => ref.read(cartControllerProvider.notifier);

  void _addProduct(Product product) {
    final qty = parseIdNumber(_qty.text);
    _cart.add(product, qty: qty == null || qty <= 0 ? 1 : qty);
    final cart = ref.read(cartControllerProvider);
    setState(() {
      _selected = cart.lines.indexWhere((l) => l.product.id == product.id);
      _codeError = null;
    });
    _qty.text = '1';
    _code.clear();
    // Gulir ke baris yang baru ditambah/diubah.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients && _selected == cart.lines.length - 1) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: AppDurations.medium,
          curve: SpringCurve.smooth,
        );
      }
    });
  }

  Future<void> _submitCode() async {
    final text = _code.text.trim();
    if (text.isEmpty || _busy) return;
    final product = await ref
        .read(productRepositoryProvider)
        .findByCodeOrBarcode(text);
    if (!mounted) return;
    if (product != null) {
      _addProduct(product);
      focusEntry();
      return;
    }
    // Bukan kode/barcode persis: buka pencarian dengan teks yang sama.
    await _openSearch(initial: text);
  }

  Future<void> _openSearch({String initial = ''}) async {
    if (_busy) return;
    _busy = true;
    final product = await showProductSearchSheet(
      context,
      initialQuery: initial,
    );
    _busy = false;
    if (!mounted) return;
    if (product != null) {
      _addProduct(product);
    } else if (initial.isNotEmpty) {
      setState(() => _codeError = 'Barang "$initial" tidak ditemukan.');
      _code.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _code.text.length,
      );
    }
    focusEntry();
  }

  Future<void> _pay() async {
    final cart = ref.read(cartControllerProvider);
    if (cart.isEmpty || _busy) return;
    _busy = true;
    final result = await showPaymentSheet(context, cart);
    if (result != null && mounted) {
      _cart.clear();
      setState(() {
        _selected = null;
        _session++;
      });
      await showCheckoutSuccessSheet(context, result);
    }
    _busy = false;
    focusEntry();
  }

  Future<void> _confirmClear() async {
    final ok = await AppDialogs.confirm(
      context,
      title: 'Batalkan transaksi?',
      message: 'Semua barang di keranjang akan dihapus.',
      confirmLabel: 'Batalkan',
      cancelLabel: 'Kembali',
      destructive: true,
    );
    if (ok) {
      _cart.clear();
      setState(() {
        _selected = null;
        _session++;
      });
    }
    focusEntry();
  }

  Future<void> _editQty(int index) async {
    final line = ref.read(cartControllerProvider).lines[index];
    final qty = await AppDialogs.promptNumber(
      context,
      title: 'Jumlah',
      message: line.product.name,
      initial: line.qty,
      suffix: line.product.unitName,
    );
    if (qty != null) _cart.setQty(index, qty);
    setState(() => _selected = qty == 0 ? null : index);
    focusEntry();
  }

  Future<void> _editLineDiscount(int index) async {
    final line = ref.read(cartControllerProvider).lines[index];
    final pct = await AppDialogs.promptNumber(
      context,
      title: 'Potongan Barang',
      message: line.product.name,
      initial: line.discountPercent,
      suffix: '%',
      max: 100,
    );
    if (pct != null) _cart.setLineDiscount(index, pct);
    focusEntry();
  }

  void _remove(int index) {
    _cart.removeAt(index);
    setState(() => _selected = null);
    focusEntry();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartControllerProvider);

    final table = CartTable(
      cart: cart,
      selectedIndex: _selected,
      scrollController: _scroll,
      onSelect: (i) => setState(() => _selected = i),
      onQtyChanged: (i, q) {
        _cart.setQty(i, q);
        if (q <= 0) setState(() => _selected = null);
      },
      onEditQty: _editQty,
      onEditDiscount: _editLineDiscount,
      onRemove: _remove,
    );

    final summary = CartSummaryPanel(
      key: ValueKey(_session),
      cart: cart,
      onDiscountChanged: (type, v) => _cart.setDiscount(type, v),
      onPay: _pay,
      onClear: _confirmClear,
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): _pay,
        const SingleActivator(LogicalKeyboardKey.end): _pay,
        const SingleActivator(LogicalKeyboardKey.f3): () => _openSearch(),
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            final left = Column(
              children: [
                _EntryBar(
                  code: _code,
                  codeFocus: _codeFocus,
                  qty: _qty,
                  codeError: _codeError,
                  onSubmit: _submitCode,
                  onSearch: () => _openSearch(),
                  onCodeChanged: () {
                    if (_codeError != null) setState(() => _codeError = null);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(child: table),
              ],
            );
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: left),
                  const SizedBox(width: AppSpacing.lg),
                  SizedBox(width: 360, child: summary),
                ],
              );
            }
            return Column(
              children: [
                Expanded(child: left),
                const SizedBox(height: AppSpacing.md),
                SizedBox(height: 420, child: summary),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EntryBar extends StatelessWidget {
  const _EntryBar({
    required this.code,
    required this.codeFocus,
    required this.qty,
    required this.codeError,
    required this.onSubmit,
    required this.onSearch,
    required this.onCodeChanged,
  });

  final TextEditingController code;
  final FocusNode codeFocus;
  final TextEditingController qty;
  final String? codeError;
  final VoidCallback onSubmit;
  final VoidCallback onSearch;
  final VoidCallback onCodeChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: AppTextField(
              controller: qty,
              label: 'Jumlah',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onSubmitted: (_) => codeFocus.requestFocus(),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: AppTextField(
              controller: code,
              focusNode: codeFocus,
              autofocus: true,
              label: 'Kode / Barcode',
              placeholder: 'Scan barcode atau ketik kode, lalu Enter',
              prefixIcon: CupertinoIcons.barcode,
              errorText: codeError,
              textInputAction: TextInputAction.done,
              onChanged: (_) => onCodeChanged(),
              onSubmitted: (_) => onSubmit(),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Padding(
            // Sejajarkan tombol dengan field (melewati tinggi label).
            padding: const EdgeInsets.only(top: 22),
            child: AppButton(
              label: 'Cari Barang  (F3)',
              icon: CupertinoIcons.search,
              variant: AppButtonVariant.tinted,
              onPressed: onSearch,
            ),
          ),
        ],
      ),
    );
  }
}
