import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../products/domain/product.dart';
import '../../vouchers/domain/voucher.dart';
import '../domain/cart.dart';

/// Keranjang kasir yang sedang berjalan. Tetap ada saat pindah halaman,
/// dan dikosongkan otomatis saat user login/keluar.
class CartController extends Notifier<Cart> {
  @override
  Cart build() {
    ref.watch(authControllerProvider.select((u) => u?.id));
    return const Cart();
  }

  void add(Product product, {double qty = 1}) =>
      state = state.add(product, qty: qty);

  void setQty(int index, double qty) => state = state.setQty(index, qty);

  void removeAt(int index) => state = state.removeAt(index);

  void setVoucher(Voucher? voucher) => state = state.withVoucher(voucher);

  void clear() => state = const Cart();
}

final cartControllerProvider = NotifierProvider<CartController, Cart>(
  CartController.new,
);
