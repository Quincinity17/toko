import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../products/domain/product.dart';
import '../../stores/presentation/store_scope.dart';
import '../domain/cart.dart';

/// Keranjang kasir yang sedang berjalan. Tetap ada saat pindah halaman,
/// dan dikosongkan otomatis saat user login/keluar atau admin berpindah toko
/// (harga & stok berbeda per toko).
class CartController extends Notifier<Cart> {
  @override
  Cart build() {
    ref.watch(authControllerProvider.select((u) => u?.id));
    ref.watch(storeScopeProvider);
    return const Cart();
  }

  void add(Product product, {double qty = 1}) =>
      state = state.add(product, qty: qty);

  void setQty(int index, double qty) => state = state.setQty(index, qty);

  void removeAt(int index) => state = state.removeAt(index);

  /// Mengganti seluruh isi keranjang (mis. melanjutkan transaksi tertahan).
  void replace(Cart cart) => state = cart;

  void clear() => state = const Cart();
}

final cartControllerProvider = NotifierProvider<CartController, Cart>(
  CartController.new,
);
