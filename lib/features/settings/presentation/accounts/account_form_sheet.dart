import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/inset_grouped_list.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../auth/data/user_repository.dart';
import '../../../auth/domain/account_rules.dart';
import '../../../auth/domain/app_user.dart';
import '../../../auth/domain/user_role.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../auth/presentation/password_sheet.dart';
import '../../../../core/widgets/option_picker.dart';
import '../../../stores/data/store_repository.dart';
import '../../../stores/domain/store.dart';
import '../../../stores/presentation/store_scope.dart';

/// Membuka form tambah akun (`existing == null`) atau ubah akun.
Future<void> showAccountFormSheet(BuildContext context, {AppUser? existing}) {
  return AppDialogs.sheet<void>(
    context,
    title: existing == null ? 'Akun Baru' : 'Ubah Akun',
    builder: (_) => _AccountForm(existing: existing),
  );
}

class _AccountForm extends ConsumerStatefulWidget {
  const _AccountForm({this.existing});

  final AppUser? existing;

  @override
  ConsumerState<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends ConsumerState<_AccountForm> {
  late final _fullName = TextEditingController(text: widget.existing?.fullName);
  late final _username = TextEditingController(text: widget.existing?.username);
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  late UserRole _role = widget.existing?.role ?? UserRole.kasir;
  late bool _active = widget.existing?.isActive ?? true;

  /// Toko supervisor/kasir yang dipilih. Akun baru: toko yang sedang dipilih
  /// di sidebar (lihat juga [_effectiveStoreId]).
  late int? _storeId = widget.existing?.storeId ?? ref.read(storeScopeProvider);
  String? _storeError;

  /// Pilihan user, atau satu-satunya toko aktif bila belum memilih.
  int? get _effectiveStoreId {
    if (_storeId != null) return _storeId;
    final active = _activeStores.where((s) => s.isActive).toList();
    return active.length == 1 ? active.first.id : null;
  }

  List<Store> get _activeStores =>
      (ref.read(storesProvider).value ?? const <Store>[])
          .where((s) => s.isActive || s.id == _storeId)
          .toList();

  Future<void> _pickStore() async {
    final stores = _activeStores;
    final current = stores.where((s) => s.id == _effectiveStoreId).firstOrNull;
    final pick = await showOptionPicker(
      context,
      title: 'Toko',
      options: [for (final s in stores) s.name],
      selected: current?.name,
    );
    final name = pick?.value;
    if (name == null) return;
    setState(() {
      _storeId = stores.firstWhere((s) => s.name == name).id;
      _storeError = null;
    });
  }

  String? _fullNameError, _usernameError, _passwordError, _confirmError;
  String? _error;
  bool _saving = false;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _fullName.dispose();
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool _validate() {
    setState(() {
      _fullNameError = AccountRules.fullName(_fullName.text);
      _usernameError = _isNew ? AccountRules.username(_username.text) : null;
      _passwordError = _isNew ? AccountRules.password(_password.text) : null;
      _confirmError = _isNew
          ? AccountRules.confirmPassword(_password.text, _confirm.text)
          : null;
      _storeError = _role.needsStore && _effectiveStoreId == null
          ? 'Pilih toko untuk ${_role.label.toLowerCase()}.'
          : null;
      _error = null;
    });
    return [
      _storeError,
      _fullNameError,
      _usernameError,
      _passwordError,
      _confirmError,
    ].every((e) => e == null);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
    } on AccountFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (!_validate()) return;
    final me = ref.read(authControllerProvider)!;
    final repo = ref.read(userRepositoryProvider);

    await _run(() async {
      if (_isNew) {
        await repo.create(
          actor: me,
          username: _username.text,
          fullName: _fullName.text,
          role: _role,
          storeId: _effectiveStoreId,
          password: _password.text,
        );
      } else {
        final updated = await repo.update(
          actor: me,
          id: widget.existing!.id,
          fullName: _fullName.text,
          role: _role,
          storeId: _effectiveStoreId,
          isActive: _active,
        );
        ref.read(authControllerProvider.notifier).refreshIfCurrent(updated);
      }
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _delete() async {
    final target = widget.existing!;
    final ok = await AppDialogs.confirm(
      context,
      title: 'Hapus akun ${target.fullName}?',
      message:
          'Akun dihapus permanen. Jika hanya ingin mencegah login, '
          'nonaktifkan saja.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;

    final me = ref.read(authControllerProvider)!;
    await _run(() async {
      await ref.read(userRepositoryProvider).delete(actor: me, id: target.id);
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final me = ref.watch(authControllerProvider);
    final isSelf = !_isNew && widget.existing!.id == me?.id;
    final stores = ref.watch(storesProvider).value ?? const <Store>[];
    final storeName = stores
        .where((s) => s.id == _effectiveStoreId)
        .firstOrNull
        ?.name;

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
          _RolePicker(
            value: _role,
            enabled: !isSelf && !_saving,
            onChanged: (r) => setState(() => _role = r),
          ),
          if (isSelf)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Peran dan status akun sendiri tidak bisa diubah.',
                style: AppTypography.footnote.copyWith(color: c.labelSecondary),
              ),
            ),
          if (_role.needsStore) ...[
            const SizedBox(height: AppSpacing.lg),
            InsetGroupedSection(
              footer: _storeError,
              children: [
                InsetGroupedTile(
                  leading: TileIcon(
                    icon: CupertinoIcons.building_2_fill,
                    color: _storeError == null ? c.accent : c.danger,
                  ),
                  title: 'Toko',
                  value: storeName ?? 'Pilih toko',
                  onPressed: _saving ? null : _pickStore,
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _fullName,
            label: 'Nama lengkap',
            placeholder: 'contoh: Siti Aminah',
            autofocus: _isNew,
            errorText: _fullNameError,
            prefixIcon: CupertinoIcons.person,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _username,
            label: 'Username',
            placeholder: 'contoh: siti',
            enabled: _isNew,
            errorText: _usernameError,
            helper: _isNew
                ? 'Dipakai untuk login. Huruf kecil, angka, titik, garis bawah.'
                : 'Username tidak bisa diubah.',
            prefixIcon: CupertinoIcons.at,
          ),
          if (_isNew) ...[
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _password,
              label: 'Password',
              password: true,
              errorText: _passwordError,
              helper: 'Minimal ${AccountRules.minPasswordLength} karakter.',
              prefixIcon: CupertinoIcons.lock_fill,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _confirm,
              label: 'Ulangi password',
              password: true,
              errorText: _confirmError,
              prefixIcon: CupertinoIcons.lock_fill,
              onSubmitted: (_) => _save(),
            ),
          ],
          if (!_isNew) ...[
            const SizedBox(height: AppSpacing.lg),
            InsetGroupedSection(
              children: [
                InsetGroupedTile(
                  title: 'Akun aktif',
                  subtitle: _active ? 'Bisa login' : 'Tidak bisa login',
                  trailing: CupertinoSwitch(
                    value: _active,
                    activeTrackColor: c.success,
                    onChanged: isSelf || _saving
                        ? null
                        : (v) => setState(() => _active = v),
                  ),
                ),
                if (!isSelf)
                  InsetGroupedTile(
                    title: 'Reset password',
                    onPressed: _saving
                        ? null
                        : () =>
                              showResetPasswordSheet(context, widget.existing!),
                  ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: _isNew ? 'Tambah Akun' : 'Simpan',
            size: AppButtonSize.large,
            expand: true,
            loading: _saving,
            onPressed: _save,
          ),
          if (!_isNew && !isSelf) ...[
            const SizedBox(height: AppSpacing.xs),
            AppButton(
              label: 'Hapus Akun',
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

/// Dua kartu pilihan peran dengan penjelasan hak akses.
class _RolePicker extends StatelessWidget {
  const _RolePicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final UserRole value;
  final bool enabled;
  final ValueChanged<UserRole> onChanged;

  static const _descriptions = {
    UserRole.admin:
        'Semua toko dan semua menu, termasuk produk, laporan, dan pengaturan.',
    UserRole.supervisor:
        'Kasir dan Stok di tokonya: bisa menambah, mengurangi, dan '
        'menghitung ulang stok.',
    UserRole.kasir:
        'Hanya layar Kasir di tokonya: transaksi dan pembayaran hari ini.',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        for (final role in UserRole.values) ...[
          if (role != UserRole.values.first)
            const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: GestureDetector(
              onTap: enabled ? () => onChanged(role) : null,
              child: MouseRegion(
                cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: value == role ? c.accentTint : c.fillSecondary,
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(
                      color: value == role ? c.accent : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Opacity(
                    opacity: enabled || value == role ? 1 : 0.4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                role.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.headline.copyWith(
                                  color: c.label,
                                ),
                              ),
                            ),
                            Icon(
                              value == role
                                  ? CupertinoIcons.checkmark_circle_fill
                                  : CupertinoIcons.circle,
                              size: 22,
                              color: value == role ? c.accent : c.labelTertiary,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          _descriptions[role]!,
                          style: AppTypography.footnote.copyWith(
                            color: c.labelSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
