import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../sales/domain/invoice_number.dart';
import '../data/terminal_repository.dart';
import '../domain/terminal.dart';

/// Bagian "Terminal & Sinkronisasi" di halaman Pengaturan.
class TerminalSection extends ConsumerWidget {
  const TerminalSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final terminal = ref.watch(terminalProvider).value;
    final pending = ref.watch(pendingSyncCountProvider).value ?? 0;
    if (terminal == null) return const SizedBox.shrink();

    final example =
        '${InvoiceNumber.prefixFor(DateTime.now(), terminal.code)}0001';

    return InsetGroupedSection(
      header: 'Terminal & Sinkronisasi',
      footer:
          'Kode terminal muncul di nomor faktur, mis. $example, supaya faktur '
          'dari beberapa komputer tidak bentrok. Mengganti kode hanya '
          'berlaku untuk faktur berikutnya.',
      dividerIndent: 58,
      children: [
        InsetGroupedTile(
          leading: TileIcon(
            icon: CupertinoIcons.desktopcomputer,
            color: c.accent,
          ),
          title: 'Kode terminal',
          value: terminal.code,
          onPressed: () => _editCode(context, terminal),
        ),
        InsetGroupedTile(
          leading: TileIcon(
            icon: CupertinoIcons.number,
            color: c.labelSecondary,
          ),
          title: 'ID terminal',
          value: terminal.id.isEmpty ? '–' : '${terminal.id.substring(0, 8)}…',
        ),
        InsetGroupedTile(
          leading: TileIcon(
            icon: CupertinoIcons.antenna_radiowaves_left_right,
            color: c.labelSecondary,
          ),
          title: 'Peran komputer',
          subtitle: 'Sambungan ke server pusat belum diatur',
          value: terminal.isServer ? 'Server (mandiri)' : terminal.mode.label,
        ),
        InsetGroupedTile(
          leading: TileIcon(
            icon: CupertinoIcons.arrow_up_circle_fill,
            color: pending == 0 ? c.success : c.warning,
          ),
          title: 'Antrian kirim',
          subtitle: pending == 0
              ? 'Tidak ada data yang menunggu'
              : 'Dikirim otomatis setelah tersambung ke server pusat',
          value: pending == 0 ? 'Kosong' : '$pending transaksi',
        ),
      ],
    );
  }

  Future<void> _editCode(BuildContext context, Terminal terminal) {
    return AppDialogs.popup<void>(
      context,
      title: 'Kode Terminal',
      maxWidth: 400,
      autofocusRoot: false,
      builder: (_) => _CodeForm(initial: terminal.code),
    );
  }
}

class _CodeForm extends ConsumerStatefulWidget {
  const _CodeForm({required this.initial});

  final String initial;

  @override
  ConsumerState<_CodeForm> createState() => _CodeFormState();
}

class _CodeFormState extends ConsumerState<_CodeForm> {
  late final _code = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await ref
          .read(terminalRepositoryProvider)
          .setCode(actor: ref.read(authControllerProvider)!, code: _code.text);
      if (mounted) Navigator.pop(context);
    } on TerminalFailure catch (e) {
      setState(() => _error = e.message);
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
            autofocus: true,
            placeholder: 'mis. K01, PST, CBG2',
            errorText: _error,
            helper:
                '2–6 huruf/angka. Setiap komputer harus punya kode berbeda.',
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
              LengthLimitingTextInputFormatter(6),
              _UpperCase(),
            ],
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Simpan',
            size: AppButtonSize.large,
            expand: true,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}
