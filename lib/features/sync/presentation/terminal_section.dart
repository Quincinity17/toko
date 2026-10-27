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
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/widgets/state_views.dart';
import '../../../sync_protocol/sync_protocol.dart';
import '../data/sync_codec.dart';
import '../data/sync_service.dart';
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
    final isAdmin = ref.watch(authControllerProvider)?.isAdmin ?? false;
    final sync = ref.watch(syncStatusProvider).value ?? const SyncStatus();
    if (terminal == null) return const SizedBox.shrink();
    final server = sync.server == null ? null : Uri.tryParse(sync.server!);

    final example =
        '${InvoiceNumber.prefixFor(DateTime.now(), terminal.code)}0001';

    return InsetGroupedSection(
      header: 'Terminal & Sinkronisasi',
      footer:
          'Kode terminal muncul di nomor faktur, mis. $example, supaya faktur '
          'dari beberapa komputer tidak bentrok. Mengganti kode hanya '
          'berlaku untuk faktur berikutnya.'
          '${isAdmin ? '' : ' Kode hanya bisa diganti admin.'}',
      dividerIndent: 58,
      children: [
        InsetGroupedTile(
          leading: TileIcon(
            icon: CupertinoIcons.desktopcomputer,
            color: c.accent,
          ),
          title: 'Kode terminal',
          value: terminal.code,
          onPressed: isAdmin ? () => _editCode(context, terminal) : null,
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
            color: sync.paired ? c.success : c.labelSecondary,
          ),
          title: 'Server pusat',
          subtitle: !sync.paired
              ? (isAdmin
                    ? 'Belum disambungkan. Ketuk untuk menyambungkan.'
                    : 'Belum disambungkan (diatur admin).')
              : sync.lastError != null
              ? sync.lastError!
              : sync.lastOkAt == null
              ? 'Belum pernah sinkron'
              : 'Sinkron terakhir ${Fmt.dateTime(sync.lastOkAt!)}',
          value: server == null
              ? 'Mandiri'
              : '${server.host}:${server.port} · '
                    '${terminal.isServer ? 'Master' : 'Cabang'}',
          onPressed: isAdmin
              ? () => sync.paired
                    ? _manage(context, ref, sync)
                    : _connect(context)
              : null,
          showChevron: isAdmin,
        ),
        InsetGroupedTile(
          leading: TileIcon(
            icon: CupertinoIcons.arrow_up_circle_fill,
            color: pending == 0 ? c.success : c.warning,
          ),
          title: 'Antrian kirim',
          subtitle: pending == 0
              ? 'Tidak ada data yang menunggu'
              : sync.paired
              ? 'Dikirim otomatis tiap 30 detik saat tersambung'
              : 'Dikirim setelah tersambung ke server pusat',
          value: pending == 0 ? 'Kosong' : '$pending data',
        ),
        if (sync.paired) _SyncNowTile(),
      ],
    );
  }

  Future<void> _connect(BuildContext context) => AppDialogs.popup<void>(
    context,
    title: 'Sambungkan ke Server',
    maxWidth: 520,
    autofocusRoot: false,
    builder: (_) => const _ConnectForm(),
  );

  Future<void> _manage(
    BuildContext context,
    WidgetRef ref,
    SyncStatus sync,
  ) async {
    final action = await AppDialogs.actionSheet<String>(
      context,
      title: 'Server ${sync.server}',
      message: sync.lastError,
      options: const [
        ActionSheetOption(label: 'Sinkron Sekarang', value: 'sync'),
        ActionSheetOption(
          label: 'Putuskan Sambungan',
          value: 'unpair',
          destructive: true,
        ),
      ],
    );
    if (!context.mounted) return;
    if (action == 'sync') {
      await _syncNow(context, ref);
    } else if (action == 'unpair') {
      final ok = await AppDialogs.confirm(
        context,
        title: 'Putuskan sambungan?',
        message:
            'Komputer ini berhenti sinkron. Data di komputer ini tetap ada. '
            'Data yang belum terkirim tetap di antrian.',
        confirmLabel: 'Putuskan',
        destructive: true,
      );
      if (!ok || !context.mounted) return;
      await ref
          .read(syncServiceProvider)
          .unpair(actor: ref.read(authControllerProvider)!);
    }
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

Future<void> _syncNow(BuildContext context, WidgetRef ref) async {
  try {
    final r = await ref.read(syncServiceProvider).syncNow();
    if (context.mounted) {
      await AppDialogs.alert(
        context,
        title: 'Sinkron selesai',
        message: '${r.sent} data dikirim, ${r.received} data diterima.',
      );
    }
  } on SyncFailure catch (e) {
    if (context.mounted) {
      await AppDialogs.alert(context, title: 'Gagal sinkron', message: '$e');
    }
  }
}

class _SyncNowTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SyncNowTile> createState() => _SyncNowTileState();
}

class _SyncNowTileState extends ConsumerState<_SyncNowTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InsetGroupedTile(
      leading: TileIcon(
        icon: CupertinoIcons.arrow_2_circlepath,
        color: c.accent,
      ),
      title: _busy ? 'Menyinkronkan…' : 'Sinkron Sekarang',
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              await _syncNow(context, ref);
              if (mounted) setState(() => _busy = false);
            },
    );
  }
}

/// Popup pairing: alamat server, kode pairing, peran komputer.
class _ConnectForm extends ConsumerStatefulWidget {
  const _ConnectForm();

  @override
  ConsumerState<_ConnectForm> createState() => _ConnectFormState();
}

class _ConnectFormState extends ConsumerState<_ConnectForm> {
  final _address = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  SyncRole _role = SyncRole.client;
  bool _busy = false;
  String? _error;
  String? _ok;

  @override
  void dispose() {
    _address.dispose();
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = null;
      _ok = null;
    });
    try {
      final uri = await ref.read(syncServiceProvider).check(_address.text);
      setState(() => _ok = 'Server ditemukan di ${uri.host}:${uri.port}.');
    } on SyncFailure catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    if (_role == SyncRole.client) {
      final ok = await AppDialogs.confirm(
        context,
        title: 'Jadikan komputer cabang?',
        message:
            'Data barang, toko, dan akun di komputer ini diganti data dari '
            'server. Setelah itu semua user login lagi dengan akun dari '
            'server.',
        confirmLabel: 'Sambungkan',
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final replaced = await ref
          .read(syncServiceProvider)
          .pair(
            actor: ref.read(authControllerProvider)!,
            address: _address.text,
            code: _code.text,
            role: _role,
            name: _name.text,
          );
      if (!mounted) return;
      Navigator.pop(context);
      // Akun komputer cabang sekarang dari server: login ulang.
      if (replaced) ref.read(authControllerProvider.notifier).logout();
    } on SyncFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget role(SyncRole value, String title, String text) => PressableScale(
      onPressed: _busy ? null : () => setState(() => _role = value),
      pressedScale: 0.98,
      borderRadius: AppRadius.mdAll,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: _role == value ? c.accentTint : c.fillSecondary,
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: _role == value ? c.accent : const Color(0x00000000),
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.headline.copyWith(color: c.label)),
            const SizedBox(height: 2),
            Text(
              text,
              style: AppTypography.footnote.copyWith(color: c.labelSecondary),
            ),
          ],
        ),
      ),
    );

    return SingleChildScrollView(
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
            controller: _address,
            label: 'Alamat server',
            placeholder: 'mis. 192.168.1.10 atau 100.64.0.5 (VPN)',
            helper:
                'Lihat di layar program toko_server (port bawaan '
                '${SyncApi.defaultPort}).',
            autofocus: true,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _code,
            label: 'Kode pairing',
            placeholder: '6 angka',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _name,
            label: 'Nama komputer (opsional)',
            placeholder: 'mis. Kasir Cabang Dago',
          ),
          const SizedBox(height: AppSpacing.lg),
          role(
            SyncRole.client,
            'Komputer kasir cabang',
            'Komputer baru di toko/cabang lain. Barang, harga, dan akun '
                'diambil dari server; faktur dikirim ke server.',
          ),
          const SizedBox(height: AppSpacing.sm),
          role(
            SyncRole.master,
            'Komputer server (master)',
            'Komputer yang sudah berisi data toko (biasanya yang menjalankan '
                'program server). Semua datanya dikirim ke server; hanya '
                'komputer ini yang bisa mengubah barang, akun, dan '
                'pengaturan toko.',
          ),
          if (_ok != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _ok!,
              style: AppTypography.footnote.copyWith(color: c.success),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Cek Sambungan',
                  variant: AppButtonVariant.gray,
                  size: AppButtonSize.large,
                  expand: true,
                  onPressed: _busy ? null : _check,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  label: 'Sambungkan',
                  size: AppButtonSize.large,
                  expand: true,
                  loading: _busy,
                  onPressed: _busy ? null : _connect,
                ),
              ),
            ],
          ),
        ],
      ),
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
