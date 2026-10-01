import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/shake.dart';
import '../data/auth_repository.dart';
import 'auth_controller.dart';

/// Layar login: ketik username dan password. Daftar akun sengaja tidak
/// ditampilkan. Setelah berhasil, router mengarahkan ke halaman awal sesuai
/// peran.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  final _shakeKey = GlobalKey<ShakeState>();

  bool _loading = false;
  String? _error;

  bool get _canSubmit =>
      !_loading &&
      _username.text.trim().isNotEmpty &&
      _password.text.isNotEmpty;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(_username.text, _password.text);
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

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          const Positioned.fill(child: _AmbientBackground()),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: GlassPanel(
                  tint: c.card,
                  opacity: 0.78,
                  blur: 40,
                  borderRadius: AppRadius.xlAll,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Header(),
                        const SizedBox(height: AppSpacing.xl),
                        Shake(
                          key: _shakeKey,
                          child: _CredentialFields(
                            username: _username,
                            password: _password,
                            passwordFocus: _passwordFocus,
                            enabled: !_loading,
                            hasError: _error != null,
                            onChanged: () => setState(() {}),
                            onSubmit: _submit,
                          ),
                        ),
                        AnimatedSize(
                          duration: AppDurations.medium,
                          curve: SpringCurve.smooth,
                          child: _error == null
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  padding: const EdgeInsets.only(
                                    top: AppSpacing.sm,
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
                        AppButton(
                          label: 'Masuk',
                          size: AppButtonSize.large,
                          expand: true,
                          loading: _loading,
                          onPressed: _canSubmit ? _submit : null,
                        ),
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
          'Masukkan username dan password.',
          textAlign: TextAlign.center,
          style: AppTypography.subheadline.copyWith(color: c.labelSecondary),
        ),
      ],
    );
  }
}

/// Username dan password dalam satu kotak membulat dengan pemisah tipis,
/// seperti form login iOS. Enter di username pindah ke password; Enter di
/// password langsung masuk.
class _CredentialFields extends StatefulWidget {
  const _CredentialFields({
    required this.username,
    required this.password,
    required this.passwordFocus,
    required this.enabled,
    required this.hasError,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController username;
  final TextEditingController password;
  final FocusNode passwordFocus;
  final bool enabled;
  final bool hasError;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;

  @override
  State<_CredentialFields> createState() => _CredentialFieldsState();
}

class _CredentialFieldsState extends State<_CredentialFields> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    Widget field({
      required TextEditingController controller,
      required String placeholder,
      required IconData icon,
      FocusNode? focusNode,
      bool autofocus = false,
      bool obscure = false,
      Widget? suffix,
      TextInputAction? action,
      ValueChanged<String>? onSubmitted,
    }) {
      return CupertinoTextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        enabled: widget.enabled,
        obscureText: obscure,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: action,
        onChanged: (_) => widget.onChanged(),
        onSubmitted: onSubmitted,
        placeholder: placeholder,
        placeholderStyle: AppTypography.body.copyWith(color: c.labelTertiary),
        style: AppTypography.body.copyWith(color: c.label),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm + 2,
        ),
        prefix: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.md),
          child: Icon(icon, size: 18, color: c.labelSecondary),
        ),
        suffix: suffix,
        decoration: const BoxDecoration(),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: c.fill,
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: widget.hasError ? c.danger : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          field(
            controller: widget.username,
            placeholder: 'Username',
            icon: CupertinoIcons.person_fill,
            autofocus: true,
            action: TextInputAction.next,
            onSubmitted: (_) => widget.passwordFocus.requestFocus(),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 46),
            child: Container(height: 0.5, color: c.separator),
          ),
          field(
            controller: widget.password,
            focusNode: widget.passwordFocus,
            placeholder: 'Password',
            icon: CupertinoIcons.lock_fill,
            obscure: _obscure,
            action: TextInputAction.done,
            onSubmitted: (_) => widget.onSubmit(),
            suffix: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              minimumSize: const Size(AppSizes.touchTarget, 40),
              onPressed: () => setState(() => _obscure = !_obscure),
              child: Icon(
                _obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                size: 20,
                color: c.labelSecondary,
              ),
            ),
          ),
        ],
      ),
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
