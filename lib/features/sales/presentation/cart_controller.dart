import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../products/domain/product.dart';
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

  void setLineDiscount(int index, double percent) =>
      state = state.setLineDiscount(index, percent);

  void removeAt(int index) => state = state.removeAt(index);

  void setDiscount(DiscountType type, double value) =>
      state = state.setDiscount(type, value);

  void clear() => state = const Cart();
}

final cartControllerProvider = NotifierProvider<CartController, Cart>(
  CartController.new,
);
