import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/number_input.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/voucher_repository.dart';
import '../domain/voucher.dart';

/// Form tambah (`existing == null`) atau ubah voucher.
Future<void> showVoucherFormSheet(BuildContext context, {Voucher? existing}) {
  return AppDialogs.sheet<void>(
    context,
    title: existing == null ? 'Voucher Baru' : 'Ubah Voucher',
    builder: (_) => _VoucherForm(existing: existing),
  );
}

class _VoucherForm extends ConsumerStatefulWidget {
  const _VoucherForm({this.existing});

  final Voucher? existing;

  @override
  ConsumerState<_VoucherForm> createState() => _VoucherFormState();
}

class _VoucherFormState extends ConsumerState<_VoucherForm> {
  Voucher? get _v => widget.existing;

  late final _code = TextEditingController(text: _v?.code);
  late final _name = TextEditingController(text: _v?.name);
  late final _value = TextEditingController(
    text: _v == null
        ? ''
        : _v!.type == VoucherType.amount
        ? Fmt.number(_v!.value.round())
        : Fmt.number(_v!.value),
  );
  late final _maxDiscount = TextEditingController(
    text: _v?.maxDiscount == null ? '' : Fmt.number(_v!.maxDiscount!),
  );
  late final _minPurchase = TextEditingController(
    text: (_v?.minPurchase ?? 0) == 0 ? '' : Fmt.number(_v!.minPurchase),
  );

  late VoucherType _type = _v?.type ?? VoucherType.percent;
  late DateTime? _start = _v?.startDate;
  late DateTime? _end = _v?.endDate;
  late bool _active = _v?.isActive ?? true;

  String? _codeError, _valueError, _periodError, _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_code, _name, _value, _maxDiscount, _minPurchase]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _int(TextEditingController c) => parseIdNumber(c.text)?.round();

  Future<void> _save() async {
    final value = parseIdNumber(_value.text);
    setState(() {
      _codeError = VoucherRules.code(_code.text);
      _valueError = VoucherRules.value(_type, value);
      _periodError = VoucherRules.period(_start, _end);
      _error = null;
    });
    if ([_codeError, _valueError, _periodError].any((e) => e != null)) {
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(voucherRepositoryProvider)
          .save(
            actor: ref.read(authControllerProvider)!,
            id: _v?.id,
            draft: VoucherDraft(
              code: _code.text,
              name: _name.text,
              type: _type,
              value: value,
              maxDiscount: _type == VoucherType.percent
                  ? _int(_maxDiscount)
                  : null,
              minPurchase: _int(_minPurchase) ?? 0,
              startDate: _start,
              endDate: _end,
              isActive: _active,
            ),
          );
      if (mounted) Navigator.pop(context);
    } on VoucherFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await AppDialogs.confirm(
      context,
      title: 'Hapus voucher ${_v!.code}?',
      message: 'Voucher dihapus permanen.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(voucherRepositoryProvider)
          .delete(actor: ref.read(authControllerProvider)!, id: _v!.id);
      if (mounted) Navigator.pop(context);
    } on VoucherFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pick({required bool start}) async {
    final picked = await AppDialogs.pickDate(
      context,
      title: start ? 'Berlaku mulai' : 'Berlaku sampai',
      initial: (start ? _start : _end) ?? DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
      _periodError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isPercent = _type == VoucherType.percent;

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  controller: _code,
                  label: 'Kode voucher',
                  placeholder: 'HEMAT10',
                  autofocus: widget.existing == null,
                  errorText: _codeError,
                  helper: 'Yang diketik kasir. Huruf/angka tanpa spasi.',
                  prefixIcon: CupertinoIcons.tag_fill,
                  inputFormatters: [_UpperCase()],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppTextField(
                  controller: _name,
                  label: 'Keterangan (opsional)',
                  placeholder: 'Promo akhir bulan',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _TypePicker(
            value: _type,
            onChanged: (t) => setState(() {
              _type = t;
              _value.clear();
              _valueError = null;
            }),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  controller: _value,
                  label: isPercent ? 'Diskon (%)' : 'Potongan (Rp)',
                  placeholder: isPercent ? '10' : '5.000',
                  errorText: _valueError,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [if (!isPercent) RupiahInputFormatter()],
                ),
              ),
              if (isPercent) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppTextField(
                    controller: _maxDiscount,
                    label: 'Maks. potongan (Rp, opsional)',
                    placeholder: 'Tanpa batas',
                    keyboardType: TextInputType.number,
                    inputFormatters: [RupiahInputFormatter()],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  controller: _minPurchase,
                  label: 'Min. belanja (Rp, opsional)',
                  placeholder: 'Tanpa minimal',
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          InsetGroupedSection(
            header: 'Masa berlaku',
            footer:
                _periodError ?? 'Kosongkan untuk berlaku tanpa batas tanggal.',
            children: [
              _DateTile(
                title: 'Mulai',
                value: _start,
                onPick: () => _pick(start: true),
                onClear: () => setState(() => _start = null),
              ),
              _DateTile(
                title: 'Sampai',
                value: _end,
                onPick: () => _pick(start: false),
                onClear: () => setState(() => _end = null),
              ),
              InsetGroupedTile(
                title: 'Voucher aktif',
                subtitle: _active
                    ? 'Bisa dipakai kasir'
                    : 'Tidak bisa dipakai kasir sampai diaktifkan lagi',
                trailing: CupertinoSwitch(
                  value: _active,
                  activeTrackColor: c.success,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _active = v),
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
            label: widget.existing == null ? 'Simpan Voucher' : 'Simpan',
            size: AppButtonSize.large,
            expand: true,
            loading: _saving,
            onPressed: _save,
          ),
          if (widget.existing != null) ...[
            const SizedBox(height: AppSpacing.xs),
            AppButton(
              label: 'Hapus Voucher',
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

class _TypePicker extends StatelessWidget {
  const _TypePicker({required this.value, required this.onChanged});

  final VoucherType value;
  final ValueChanged<VoucherType> onChanged;

  static const _info = {
    VoucherType.percent: (
      CupertinoIcons.percent,
      'Diskon persen dari total belanja, bisa diberi batas maksimal.',
    ),
    VoucherType.amount: (
      CupertinoIcons.money_dollar,
      'Potongan nominal tetap, mis. Rp 5.000.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        for (final t in VoucherType.values) ...[
          if (t != VoucherType.values.first)
            const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(t),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: value == t ? c.accentTint : c.fillSecondary,
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(
                      color: value == t ? c.accent : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(_info[t]!.$1, size: 18, color: c.accent),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            t.label,
                            style: AppTypography.headline.copyWith(
                              color: c.label,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            value == t
                                ? CupertinoIcons.checkmark_circle_fill
                                : CupertinoIcons.circle,
                            size: 20,
                            color: value == t ? c.accent : c.labelTertiary,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        _info[t]!.$2,
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
        ],
      ],
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.title,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final String title;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InsetGroupedTile(
      title: title,
      value: value == null ? 'Tidak dibatasi' : Fmt.dateShort(value!),
      onPressed: onPick,
      trailing: value == null
          ? null
          : CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(32, 32),
              onPressed: onClear,
              child: Icon(
                CupertinoIcons.xmark_circle_fill,
                size: 18,
                color: c.labelTertiary,
              ),
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
