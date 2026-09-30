import 'package:flutter/cupertino.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/large_title_page.dart';
import '../../../core/widgets/state_views.dart';

/// Placeholder master barang; dibangun di Langkah 3.
class ProductsPage extends StatelessWidget {
  const ProductsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LargeTitlePage(
      title: 'Produk',
      actions: [
        AppButton(
          label: 'Import',
          icon: CupertinoIcons.arrow_down_doc,
          variant: AppButtonVariant.gray,
          onPressed: () {},
        ),
        AppButton(label: 'Tambah', icon: CupertinoIcons.add, onPressed: () {}),
      ],
      bottom: const SizedBox(
        height: 40,
        child: CupertinoSearchTextField(
          placeholder: 'Cari nama, kode, atau barcode',
          style: AppTypography.body,
        ),
      ),
      child: const EmptyState(
        icon: CupertinoIcons.cube_box,
        title: 'Belum ada produk',
        message: 'Tambah produk satu per satu atau import dari file iPOS.',
      ),
    );
  }
}
