import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Kolom input bergaya iOS: label kecil di atas, field abu-abu membulat,
/// dan pesan error merah di bawah.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.placeholder,
    this.helper,
    this.errorText,
    this.prefixIcon,
    this.password = false,
    this.enabled = true,
    this.autofocus = false,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? placeholder;

  /// Keterangan abu-abu di bawah field (disembunyikan saat ada error).
  final String? helper;
  final String? errorText;
  final IconData? prefixIcon;

  /// Menyembunyikan teks dan menampilkan tombol mata.
  final bool password;
  final bool enabled;
  final bool autofocus;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasError = widget.errorText != null;
    final note = widget.errorText ?? widget.helper;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null)
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xxs,
              bottom: AppSpacing.xs - 2,
            ),
            child: Text(
              widget.label!,
              style: AppTypography.footnote.copyWith(
                color: c.labelSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        CupertinoTextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          obscureText: widget.password && _obscure,
          autocorrect: !widget.password,
          enableSuggestions: !widget.password,
          keyboardType: widget.keyboardType,
          inputFormatters: widget.inputFormatters,
          textInputAction: widget.textInputAction,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          placeholder: widget.placeholder,
          placeholderStyle: AppTypography.body.copyWith(color: c.labelTertiary),
          style: AppTypography.body.copyWith(
            color: widget.enabled ? c.label : c.labelSecondary,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          prefix: widget.prefixIcon == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  child: Icon(
                    widget.prefixIcon,
                    size: 18,
                    color: c.labelSecondary,
                  ),
                ),
          suffix: widget.password
              ? CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  minimumSize: const Size(40, 40),
                  onPressed: () => setState(() => _obscure = !_obscure),
                  child: Icon(
                    _obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                    size: 20,
                    color: c.labelSecondary,
                  ),
                )
              : null,
          decoration: BoxDecoration(
            color: c.fill,
            borderRadius: AppRadius.mdAll,
            border: Border.all(
              color: hasError ? c.danger : Colors.transparent,
              width: 1.5,
            ),
          ),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xxs,
              top: AppSpacing.xxs + 2,
            ),
            child: Text(
              note,
              style: AppTypography.footnote.copyWith(
                color: hasError ? c.danger : c.labelSecondary,
              ),
            ),
          ),
      ],
    );
  }
}
