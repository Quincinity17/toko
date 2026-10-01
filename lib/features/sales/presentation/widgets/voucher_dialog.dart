import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../vouchers/data/voucher_repository.dart';
import '../../../vouchers/domain/voucher.dart';

/// Popup memasukkan kode voucher (F4). Mengembalikan voucher yang valid,
/// atau `null` jika dibatalkan.
Future<Voucher?> showVoucherDialog(BuildContext context) {
  return AppDialogs.popup<Voucher>(
    context,
    title: 'Pakai Voucher',
    maxWidth: 420,
    autofocusRoot: false,
    builder: (_) => const _VoucherForm(),
  );
}

class _VoucherForm extends ConsumerStatefulWidget {
  const _VoucherForm();

  @override
  ConsumerState<_VoucherForm> createState() => _VoucherFormState();
}

class _VoucherFormState extends ConsumerState<_VoucherForm> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  String? _error;
  bool _checking = false;

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final voucher = await ref
          .read(voucherRepositoryProvider)
          .findUsable(_code.text);
      if (mounted) Navigator.pop(context, voucher);
    } on VoucherFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      _code.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _code.text.length,
      );
      _focus.requestFocus();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          AppTextField(
            controller: _code,
            focusNode: _focus,
            autofocus: true,
            placeholder: 'Kode voucher, mis. HEMAT10',
            prefixIcon: CupertinoIcons.tag_fill,
            errorText: _error,
            inputFormatters: [_UpperCaseFormatter()],
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _apply(),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Pakai Voucher',
            size: AppButtonSize.large,
            expand: true,
            loading: _checking,
            onPressed: _apply,
          ),
        ],
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}
