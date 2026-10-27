import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../auth/domain/permission.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/cashier_audit.dart';
import '../../data/held_cart_repository.dart';
import '../../domain/cart.dart';
import '../../domain/held_cart.dart';

/// Popup "Tahan Transaksi": meminta catatan opsional. Mengembalikan catatan
/// (boleh kosong), atau `null` jika batal.
Future<String?> showHoldDialog(BuildContext context, Cart cart) {
  return AppDialogs.popup<String>(
    context,
    title: 'Tahan Transaksi',
    autofocusRoot: false,
    builder: (_) => _HoldForm(cart: cart),
  );
}

/// Popup daftar transaksi tertahan hari ini di toko [storeId]. Mengembalikan
/// id transaksi yang dipilih untuk dilanjutkan, atau `null` jika ditutup.
Future<int?> showHeldCartsDialog(BuildContext context, int storeId) {
  return AppDialogs.popup<int>(
    context,
    title: 'Transaksi Tertahan',
    maxWidth: 560,
    builder: (_) => _HeldList(storeId: storeId),
  );
}

class _HoldForm extends StatefulWidget {
  const _HoldForm({required this.cart});

  final Cart cart;

  @override
  State<_HoldForm> createState() => _HoldFormState();
}

class _HoldFormState extends State<_HoldForm> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _note.text.trim());

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cart = widget.cart;

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
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: c.fillSecondary,
              borderRadius: AppRadius.mdAll,
            ),
            child: Row(
              children: [
                Text(
                  '${cart.lines.length} barang',
                  style: AppTypography.headline.copyWith(color: c.label),
                ),
                const Spacer(),
                Text(
                  Fmt.rupiah(cart.total),
                  style: AppTypography.title3.copyWith(
                    color: c.label,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _note,
            autofocus: true,
            label: 'Catatan (opsional)',
            placeholder: 'mis. Ibu baju merah, masih ambil minyak',
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Keranjang dikosongkan untuk pelanggan berikutnya. Transaksi bisa '
            'dilanjutkan lewat tombol Tertahan (F5) sampai hari ini berakhir.',
            style: AppTypography.footnote.copyWith(color: c.labelSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Tahan Transaksi',
            icon: CupertinoIcons.pause_fill,
            size: AppButtonSize.large,
            expand: true,
            onPressed: _submit,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Enter = tahan · Esc = batal',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: c.labelTertiary),
          ),
        ],
      ),
    );
  }
}

class _HeldList extends ConsumerWidget {
  const _HeldList({required this.storeId});

  final int storeId;

  Future<void> _delete(BuildContext context, WidgetRef ref, HeldCart h) async {
    final ok = await AppDialogs.confirm(
      context,
      title: 'Hapus transaksi tertahan?',
      message:
          '${h.note ?? 'Tanpa catatan'} · ${h.items.length} barang. '
          'Barang-barangnya tidak jadi dibeli.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref
          .read(heldCartRepositoryProvider)
          .delete(h.id, actor: ref.read(authControllerProvider)!);
    } on HeldCartFailure catch (e) {
      if (context.mounted) {
        await AppDialogs.alert(context, title: 'Gagal', message: e.message);
      }
      return;
    }
    await ref
        .read(cashierAuditProvider)
        .heldCartDeleted(
          note: h.note,
          itemCount: h.items.length,
          total: h.total,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final held = ref.watch(heldCartsProvider(storeId));
    final canDelete =
        ref.watch(authControllerProvider)?.can(Permission.deleteHeldCart) ??
        false;

    return held.when(
      loading: () => const SizedBox(height: 160, child: LoadingState()),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ErrorBanner(message: '$e'),
      ),
      data: (list) => list.isEmpty
          ? const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.lg),
              child: EmptyState(
                icon: CupertinoIcons.pause_circle,
                title: 'Tidak ada transaksi tertahan',
                message: 'Tekan Tahan (F4) saat pelanggan masih lihat-lihat.',
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, i) => _HeldTile(
                held: list[i],
                onResume: () => Navigator.pop(context, list[i].id),
                onDelete: canDelete
                    ? () => _delete(context, ref, list[i])
                    : null,
              ),
            ),
    );
  }
}

class _HeldTile extends StatelessWidget {
  const _HeldTile({
    required this.held,
    required this.onResume,
    required this.onDelete,
  });

  final HeldCart held;
  final VoidCallback onResume;

  /// `null` = tidak punya hak menghapus (tombol disembunyikan).
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final names = held.items.map((i) => i.name).toList();
    final preview = names.length <= 3
        ? names.join(', ')
        : '${names.take(3).join(', ')}, +${names.length - 3} lainnya';
    final muted = AppTypography.footnote.copyWith(color: c.labelSecondary);

    return PressableScale(
      onPressed: onResume,
      pressedScale: 0.98,
      borderRadius: AppRadius.mdAll,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm + 2,
          AppSpacing.xs,
          AppSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: c.fillSecondary,
          borderRadius: AppRadius.mdAll,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    held.note ?? 'Tanpa catatan',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.headline.copyWith(
                      color: held.note == null ? c.labelSecondary : c.label,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${DateFormat('HH:mm').format(held.createdAt)} · '
                    '${held.cashierName} · ${held.items.length} barang',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: c.labelTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              Fmt.rupiah(held.total),
              style: AppTypography.headline.copyWith(
                color: c.label,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppButton(
              label: 'Lanjutkan',
              size: AppButtonSize.small,
              onPressed: onResume,
            ),
            if (onDelete != null)
              AppIconButton(
                icon: CupertinoIcons.trash,
                tooltip: 'Hapus',
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}
