import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/seed.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/shake.dart';
import '../../../core/widgets/state_views.dart';
import '../data/auth_repository.dart';
import '../domain/app_user.dart';
import 'auth_controller.dart';
import 'widgets/user_avatar.dart';

/// Layar login: pilih akun (admin/kasir terlihat jelas dari warna dan label),
/// lalu masukkan password. Setelah berhasil, router mengarahkan ke halaman
/// awal sesuai peran.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  final _shakeKey = GlobalKey<ShakeState>();

  AppUser? _selected;
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pilih otomatis akun yang terakhir login.
    ref.listenManual(loginUsersProvider, fireImmediately: true, (_, next) {
      final list = next.value;
      if (_selected != null || list == null || list.isEmpty) return;
      final recent = [...list]
        ..sort((a, b) {
          final at = a.lastLoginAt, bt = b.lastLoginAt;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });
      // Fokus field baru bisa diminta setelah frame pertama selesai.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selected == null) _select(recent.first);
      });
    });
  }

  @override
  void dispose() {
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _select(AppUser user) {
    setState(() {
      _selected = user;
      _error = null;
      _password.clear();
    });
    _passwordFocus.requestFocus();
  }

  Future<void> _submit() async {
    final user = _selected;
    if (user == null || _loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(user.username, _password.text);
      // Router otomatis pindah halaman setelah state login berubah.
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      _password.clear();
      _shakeKey.currentState?.shake();
      _passwordFocus.requestFocus();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final users = ref.watch(loginUsersProvider);

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          const Positioned.fill(child: _AmbientBackground()),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: GlassPanel(
                  tint: c.card,
                  opacity: 0.78,
                  blur: 40,
                  borderRadius: AppRadius.xlAll,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xxl,
                      AppSpacing.xxl,
                      AppSpacing.xxl,
                      AppSpacing.xl,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Header(),
                        const SizedBox(height: AppSpacing.xl),
                        users.when(
                          loading: () => const SizedBox(
                            height: 120,
                            child: LoadingState(),
                          ),
                          error: (e, _) => Text(
                            'Gagal memuat akun: $e',
                            textAlign: TextAlign.center,
                            style: AppTypography.subheadline.copyWith(
                              color: c.danger,
                            ),
                          ),
                          data: (list) => _UserPicker(
                            users: list,
                            selected: _selected,
                            onSelected: _loading ? null : _select,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        Shake(
                          key: _shakeKey,
                          child: _PasswordField(
                            controller: _password,
                            focusNode: _passwordFocus,
                            obscure: _obscure,
                            enabled: _selected != null && !_loading,
                            hasError: _error != null,
                            onToggleObscure: () =>
                                setState(() => _obscure = !_obscure),
                            onSubmitted: (_) => _submit(),
                          ),
                        ),
                        AnimatedSize(
                          duration: AppDurations.medium,
                          curve: SpringCurve.smooth,
                          child: _error == null
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  padding: const EdgeInsets.only(
                                    top: AppSpacing.xs,
                                  ),
                                  child: Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: AppTypography.footnote.copyWith(
                                      color: c.danger,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        ListenableBuilder(
                          listenable: _password,
                          builder: (context, _) => AppButton(
                            label: 'Masuk',
                            size: AppButtonSize.large,
                            expand: true,
                            loading: _loading,
                            onPressed:
                                _selected == null || _password.text.isEmpty
                                ? null
                                : _submit,
                          ),
                        ),
                        if (kDebugMode) ...[
                          const SizedBox(height: AppSpacing.lg),
                          const _DebugAccountsHint(),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: c.accent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            CupertinoIcons.bag_fill,
            size: 32,
            color: CupertinoColors.white,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Masuk ke Toko',
          textAlign: TextAlign.center,
          style: AppTypography.title1.copyWith(color: c.label),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Pilih akun, lalu masukkan password.',
          textAlign: TextAlign.center,
          style: AppTypography.subheadline.copyWith(color: c.labelSecondary),
        ),
      ],
    );
  }
}

class _UserPicker extends StatelessWidget {
  const _UserPicker({
    required this.users,
    required this.selected,
    required this.onSelected,
  });

  final List<AppUser> users;
  final AppUser? selected;
  final ValueChanged<AppUser>? onSelected;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const EmptyState(
        icon: CupertinoIcons.person_crop_circle_badge_exclam,
        title: 'Belum ada akun aktif',
      );
    }
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        for (final u in users)
          UserTile(
            user: u,
            selected: u == selected,
            onPressed: onSelected == null ? null : () => onSelected!(u),
          ),
      ],
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.focusNode,
    required this.obscure,
    required this.enabled,
    required this.hasError,
    required this.onToggleObscure,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool obscure;
  final bool enabled;
  final bool hasError;
  final VoidCallback onToggleObscure;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CupertinoTextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.done,
      onSubmitted: onSubmitted,
      placeholder: 'Password',
      placeholderStyle: AppTypography.body.copyWith(color: c.labelTertiary),
      style: AppTypography.body.copyWith(color: c.label),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm + 2,
      ),
      prefix: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.sm),
        child: Icon(
          CupertinoIcons.lock_fill,
          size: 18,
          color: c.labelSecondary,
        ),
      ),
      suffix: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        minimumSize: const Size(AppSizes.touchTarget, AppSizes.touchTarget),
        onPressed: onToggleObscure,
        child: Icon(
          obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
          size: 20,
          color: c.labelSecondary,
        ),
      ),
      decoration: BoxDecoration(
        color: c.fill,
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: hasError ? c.danger : Colors.transparent,
          width: 1.5,
        ),
      ),
    );
  }
}

class _DebugAccountsHint extends StatelessWidget {
  const _DebugAccountsHint();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = DatabaseSeeder.defaultAccounts
        .map((a) => '${a.username} / ${a.password}')
        .join('   ·   ');
    return Text(
      'Mode debug — akun awal: $text',
      textAlign: TextAlign.center,
      style: AppTypography.caption.copyWith(color: c.labelTertiary),
    );
  }
}

/// Bercak warna lembut di belakang kartu kaca agar efek blur terlihat.
class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget blob(Color color, double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.35),
      ),
    );
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
      child: Stack(
        children: [
          Align(
            alignment: const Alignment(-0.7, -0.6),
            child: blob(c.accent, 420),
          ),
          Align(
            alignment: const Alignment(0.8, 0.7),
            child: blob(c.success, 360),
          ),
          Align(
            alignment: const Alignment(0.6, -0.8),
            child: blob(c.warning, 240),
          ),
        ],
      ),
    );
  }
}
