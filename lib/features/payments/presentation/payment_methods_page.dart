import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../../core/widgets/large_title_page.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/payment_method_repository.dart';
import '../domain/payment_method.dart';
import 'payment_method_icon.dart';

final _allMethodsProvider = StreamProvider.autoDispose<List<PaymentMethod>>(
  (ref) => ref.watch(paymentMethodRepositoryProvider).watchAll(),
);

/// Pengaturan › Metode Pembayaran (khusus admin).
class PaymentMethodsPage extends ConsumerWidget {
  const PaymentMethodsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final methods = ref.watch(_allMethodsProvider);

    return LargeTitlePage(
      title: 'Metode Pembayaran',
      backLabel: 'Pengaturan',
      onBack: () => context.go(AppRoutes.pengaturan),
      actions: [
        AppButton(
          label: 'Tambah Metode',
          icon: CupertinoIcons.add,
          onPressed: () => _showForm(context),
        ),
      ],
      slivers: [
        methods.when(
          loading: () => const SliverToBoxAdapter(
            child: SizedBox(height: 240, child: LoadingState()),
          ),
          error: (e, _) =>
              SliverToBoxAdapter(child: ErrorBanner(message: '$e')),
          data: (list) => SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: InsetGroupedSection(
                  header: 'Pilihan di popup pembayaran kasir',
                  footer:
                      'Tunai: kasir mengisi uang diterima dan kembalian dihitung. '
                      'Non-tunai: dibayar pas, kasir bisa mengisi nomor '
                      'referensi. Metode yang sudah dipakai transaksi tidak '
                      'bisa dihapus, cukup dinonaktifkan.',
                  dividerIndent: 58,
                  children: [for (final m in list) _MethodTile(method: m)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MethodTile extends ConsumerWidget {
  const _MethodTile({required this.method});

  final PaymentMethod method;

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool active) async {
    try {
      await ref
          .read(paymentMethodRepositoryProvider)
          .save(
            actor: ref.read(authControllerProvider)!,
            id: method.id,
            name: method.name,
            kind: method.kind,
            isActive: active,
          );
    } on PaymentMethodFailure catch (e) {
      if (context.mounted) {
        await AppDialogs.alert(
          context,
          title: 'Tidak bisa',
          message: e.message,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final m = method;
    return InsetGroupedTile(
      leading: TileIcon(
        icon: paymentMethodIcon(m),
        color: !m.isActive
            ? c.labelTertiary
            : m.isCash
            ? c.success
            : c.accent,
      ),
      title: m.name,
      subtitle: m.isActive ? m.kind.label : '${m.kind.label} · nonaktif',
      trailing: CupertinoSwitch(
        value: m.isActive,
        activeTrackColor: c.success,
        onChanged: (v) => _toggle(context, ref, v),
      ),
      showChevron: true,
      onPressed: () => _showForm(context, existing: m),
    );
  }
}

Future<void> _showForm(BuildContext context, {PaymentMethod? existing}) {
  return AppDialogs.sheet<void>(
    context,
    title: existing == null ? 'Metode Baru' : 'Ubah Metode',
    builder: (_) => _MethodForm(existing: existing),
  );
}

class _MethodForm extends ConsumerStatefulWidget {
  const _MethodForm({this.existing});

  final PaymentMethod? existing;

  @override
  ConsumerState<_MethodForm> createState() => _MethodFormState();
}

class _MethodFormState extends ConsumerState<_MethodForm> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late PaymentKind _kind = widget.existing?.kind ?? PaymentKind.nonCash;
  late bool _active = widget.existing?.isActive ?? true;
  String? _nameError, _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.pop(context);
    } on PaymentMethodFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    setState(
      () => _nameError = _name.text.trim().isEmpty ? 'Nama wajib diisi.' : null,
    );
    if (_nameError != null) return;
    await _run(
      () => ref
          .read(paymentMethodRepositoryProvider)
          .save(
            actor: ref.read(authControllerProvider)!,
            id: widget.existing?.id,
            name: _name.text,
            kind: _kind,
            isActive: _active,
          ),
    );
  }

  Future<void> _delete() async {
    final ok = await AppDialogs.confirm(
      context,
      title: 'Hapus ${widget.existing!.name}?',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(
      () => ref
          .read(paymentMethodRepositoryProvider)
          .delete(
            actor: ref.read(authControllerProvider)!,
            id: widget.existing!.id,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _name,
            label: 'Nama metode',
            placeholder: 'mis. QRIS, GoPay, Transfer BCA',
            autofocus: widget.existing == null,
            errorText: _nameError,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: AppSpacing.lg),
          InsetGroupedSection(
            header: 'Jenis',
            children: [
              for (final k in PaymentKind.values)
                InsetGroupedTile(
                  title: k.label,
                  subtitle: k.description,
                  trailing: _kind == k
                      ? Icon(CupertinoIcons.checkmark_alt, color: c.accent)
                      : null,
                  showChevron: false,
                  onPressed: () => setState(() => _kind = k),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          InsetGroupedSection(
            children: [
              InsetGroupedTile(
                title: 'Aktif',
                subtitle: 'Tampil di popup pembayaran kasir',
                trailing: CupertinoSwitch(
                  value: _active,
                  activeTrackColor: c.success,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'Simpan',
            size: AppButtonSize.large,
            expand: true,
            loading: _saving,
            onPressed: _save,
          ),
          if (widget.existing != null) ...[
            const SizedBox(height: AppSpacing.xs),
            AppButton(
              label: 'Hapus Metode',
              variant: AppButtonVariant.plain,
              destructive: true,
              expand: true,
              onPressed: _saving ? null : _delete,
            ),
          ],
        ],
      ),
    );
  }
}
