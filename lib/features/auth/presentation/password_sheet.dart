import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/state_views.dart';
import '../data/user_repository.dart';
import '../domain/account_rules.dart';
import '../domain/app_user.dart';
import 'auth_controller.dart';

/// Membuka sheet ganti password milik user yang login (butuh password lama).
Future<void> showChangeOwnPasswordSheet(BuildContext context) async {
  final changed = await AppDialogs.sheet<bool>(
    context,
    title: 'Ganti Password',
    builder: (_) => const _PasswordForm(target: null),
  );
  if (changed == true && context.mounted) {
    await AppDialogs.alert(context, title: 'Password berhasil diganti');
  }
}

/// Membuka sheet reset password akun lain (khusus admin).
Future<void> showResetPasswordSheet(
  BuildContext context,
  AppUser target,
) async {
  final changed = await AppDialogs.sheet<bool>(
    context,
    title: 'Reset Password',
    builder: (_) => _PasswordForm(target: target),
  );
  if (changed == true && context.mounted) {
    await AppDialogs.alert(
      context,
      title: 'Password direset',
      message: 'Beri tahu ${target.fullName} password barunya.',
    );
  }
}

class _PasswordForm extends ConsumerStatefulWidget {
  const _PasswordForm({required this.target});

  /// `null` = ganti password sendiri.
  final AppUser? target;

  @override
  ConsumerState<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends ConsumerState<_PasswordForm> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();

  String? _currentError, _newError, _confirmError, _error;
  bool _saving = false;

  bool get _isOwn => widget.target == null;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _currentError = _isOwn && _current.text.isEmpty
          ? 'Isi password lama.'
          : null;
      _newError = AccountRules.password(_new.text);
      _confirmError = AccountRules.confirmPassword(_new.text, _confirm.text);
      _error = null;
    });
    if (_currentError != null || _newError != null || _confirmError != null) {
      return;
    }

    final me = ref.read(authControllerProvider)!;
    final repo = ref.read(userRepositoryProvider);
    setState(() => _saving = true);
    try {
      if (_isOwn) {
        await repo.changeOwnPassword(
          user: me,
          currentPassword: _current.text,
          newPassword: _new.text,
        );
      } else {
        await repo.resetPassword(
          actor: me,
          id: widget.target!.id,
          newPassword: _new.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on AccountFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
          if (!_isOwn) ...[
            Text(
              'Password baru untuk ${widget.target!.fullName} '
              '(@${widget.target!.username}).',
              style: AppTypography.subheadline.copyWith(
                color: c.labelSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (_isOwn) ...[
            AppTextField(
              controller: _current,
              label: 'Password lama',
              password: true,
              autofocus: true,
              errorText: _currentError,
              prefixIcon: CupertinoIcons.lock,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          AppTextField(
            controller: _new,
            label: 'Password baru',
            password: true,
            autofocus: !_isOwn,
            errorText: _newError,
            helper: 'Minimal ${AccountRules.minPasswordLength} karakter.',
            prefixIcon: CupertinoIcons.lock_fill,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _confirm,
            label: 'Ulangi password baru',
            password: true,
            errorText: _confirmError,
            prefixIcon: CupertinoIcons.lock_fill,
            onSubmitted: (_) => _save(),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'Simpan Password',
            size: AppButtonSize.large,
            expand: true,
            loading: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
