import 'package:flutter/cupertino.dart';

import '../../../core/widgets/large_title_page.dart';
import '../../../core/widgets/state_views.dart';

/// Placeholder layar kasir; dibangun di Langkah 5.
class PosPage extends StatelessWidget {
  const PosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const LargeTitlePage(
      title: 'Kasir',
      child: EmptyState(
        icon: CupertinoIcons.cart,
        title: 'Layar kasir belum tersedia',
        message:
            'Grid produk, keranjang, dan pembayaran dibuat di langkah '
            'transaksi penjualan.',
      ),
    );
  }
}
