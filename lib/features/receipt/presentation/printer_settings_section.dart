import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../../core/widgets/option_picker.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/printer_failure.dart';
import '../data/printer_transport.dart';
import '../data/receipt_printer.dart';
import '../data/receipt_settings_repository.dart';
import '../domain/printer_config.dart';

/// Popup pengaturan printer dari layar Kasir (semua peran). Tes cetak
/// memakai bentuk struk toko [storeId].
Future<void> showPrinterSettingsDialog(
  BuildContext context, {
  required int? storeId,
}) {
  return AppDialogs.popup<void>(
    context,
    title: 'Printer Nota',
    maxWidth: 620,
    builder: (_) => SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: PrinterSettingsSection(storeId: storeId),
    ),
  );
}

/// Pengaturan printer komputer ini: sambungan, lebar kertas, tes cetak, dan
/// perilaku setelah transaksi (cetak otomatis, laci, potong). Setiap
/// perubahan langsung disimpan.
class PrinterSettingsSection extends ConsumerStatefulWidget {
  const PrinterSettingsSection({super.key, required this.storeId});

  /// Toko yang bentuk struknya dipakai untuk tes cetak.
  final int? storeId;

  @override
  ConsumerState<PrinterSettingsSection> createState() =>
      _PrinterSettingsSectionState();
}

class _PrinterSettingsSectionState
    extends ConsumerState<PrinterSettingsSection> {
  PrinterConfig? _config;
  final _host = TextEditingController();
  final _port = TextEditingController();

  String? _status;
  bool _statusError = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await ref.read(receiptSettingsRepositoryProvider).printer();
    if (!mounted) return;
    _host.text = p.host;
    _port.text = '${p.port}';
    setState(() => _config = p);
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _set(PrinterConfig p) async {
    setState(() => _config = p);
    try {
      await ref
          .read(receiptSettingsRepositoryProvider)
          .savePrinter(ref.read(authControllerProvider)!, p);
    } on PrinterFailure catch (e) {
      if (mounted) {
        await AppDialogs.alert(context, title: 'Gagal', message: e.message);
      }
    }
  }

  Future<void> _pickPrinter() async {
    final names = await ref.read(printerTransportProvider).listPrinters();
    if (!mounted) return;
    if (names.isEmpty) {
      await AppDialogs.alert(
        context,
        title: 'Tidak ada printer',
        message:
            'Belum ada printer yang terpasang di komputer ini. Pasang driver '
            'printer thermal (atau "Generic / Text Only") di Windows lalu '
            'coba lagi.',
      );
      return;
    }
    final pick = await showOptionPicker(
      context,
      title: 'Pilih Printer',
      options: names,
      selected: _config!.printerName,
    );
    if (pick?.value != null) {
      await _set(_config!.copyWith(printerName: pick!.value));
    }
  }

  Future<void> _pickSerialPort() async {
    final ports = await ref.read(printerTransportProvider).listSerialPorts();
    if (!mounted) return;
    if (ports.isEmpty) {
      await AppDialogs.alert(
        context,
        title: 'Tidak ada port',
        message:
            'Belum ada port serial/Bluetooth. Nyalakan printer, lalu '
            'pasangkan di Pengaturan Windows › Bluetooth & perangkat, dan '
            'coba lagi.',
      );
      return;
    }
    final pick = await showOptionPicker(
      context,
      title: 'Pilih Port',
      options: ports,
      selected: _config!.serialPort,
    );
    if (pick?.value != null) {
      await _set(_config!.copyWith(serialPort: pick!.value));
    }
  }

  Future<void> _pickBaudRate() async {
    final pick = await showOptionPicker(
      context,
      title: 'Baud Rate',
      options: [for (final b in PrinterConfig.baudRates) '$b'],
      selected: '${_config!.baudRate}',
    );
    final value = int.tryParse(pick?.value ?? '');
    if (value != null) await _set(_config!.copyWith(baudRate: value));
  }

  Future<void> _checkConnection() async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _status = null;
    });
    try {
      await ref.read(receiptPrinterProvider).checkConnection(_config!);
      _setStatus('Printer tersambung (${_config!.summary}).');
    } on PrinterFailure catch (e) {
      _setStatus(e.message, error: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _test({required bool drawer}) async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _status = null;
    });
    final printer = ref.read(receiptPrinterProvider);
    try {
      if (drawer) {
        await printer.testDrawer(_config!);
      } else {
        await printer.testPrint(_config!, storeId: widget.storeId);
      }
      _setStatus(
        drawer ? 'Perintah buka laci terkirim.' : 'Tes cetak terkirim.',
      );
    } on PrinterFailure catch (e) {
      _setStatus(e.message, error: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _setStatus(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _status = message;
      _statusError = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _config;
    if (p == null) return const SizedBox(height: 160, child: LoadingState());
    final c = context.colors;
    Widget toggle(bool value, ValueChanged<bool> onChanged) => CupertinoSwitch(
      value: value,
      activeTrackColor: c.success,
      onChanged: onChanged,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InsetGroupedSection(
          header: 'Printer Komputer Ini',
          footer: switch (p.connection) {
            PrinterConnection.none =>
              'Pilih cara menyambung printer thermal. Pengaturan printer '
                  'berlaku untuk komputer ini saja.',
            PrinterConnection.system =>
              'Printer USB yang sudah dipasang di Windows. Jika tidak ada '
                  'driver dari pabrik, pasang driver "Generic / Text Only".',
            PrinterConnection.network =>
              'Printer LAN/WiFi. Alamat IP biasanya tercetak saat printer '
                  'dinyalakan sambil menekan tombol FEED.',
            PrinterConnection.serial =>
              'Pasangkan (pair) printer Bluetooth di Pengaturan Windows dulu; '
                  'printer muncul sebagai port COM ("Serial over Bluetooth"). '
                  'Jika ada dua port, coba yang keluar (outgoing). Baud rate '
                  'umumnya 9600; lihat cetakan self-test printer.',
          },
          dividerIndent: 58,
          children: [
            // Empat pilihan: satu baris penuh supaya muat di popup kasir.
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      TileIcon(icon: CupertinoIcons.link, color: c.accent),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Sambungan',
                        style: AppTypography.body.copyWith(color: c.label),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: Segmented<PrinterConnection>(
                      value: p.connection,
                      options: const {
                        PrinterConnection.none: 'Tidak ada',
                        PrinterConnection.system: 'Terpasang (USB)',
                        PrinterConnection.network: 'Jaringan',
                        PrinterConnection.serial: 'Bluetooth',
                      },
                      onChanged: (v) => _set(p.copyWith(connection: v)),
                    ),
                  ),
                ],
              ),
            ),
            if (p.connection == PrinterConnection.system)
              InsetGroupedTile(
                leading: TileIcon(
                  icon: CupertinoIcons.printer_fill,
                  color: c.labelSecondary,
                ),
                title: 'Printer',
                value: p.printerName.isEmpty ? 'Pilih…' : p.printerName,
                onPressed: _pickPrinter,
              ),
            if (p.connection == PrinterConnection.network) ...[
              _FieldTile(
                icon: CupertinoIcons.globe,
                title: 'Alamat IP',
                controller: _host,
                placeholder: '192.168.1.100',
                onChanged: (v) => _set(p.copyWith(host: v.trim())),
              ),
              _FieldTile(
                icon: CupertinoIcons.number,
                title: 'Port',
                controller: _port,
                placeholder: '${PrinterConfig.defaultPort}',
                width: 100,
                digitsOnly: true,
                onChanged: (v) => _set(
                  p.copyWith(
                    port: int.tryParse(v) ?? PrinterConfig.defaultPort,
                  ),
                ),
              ),
            ],
            if (p.connection == PrinterConnection.serial) ...[
              InsetGroupedTile(
                leading: TileIcon(
                  icon: CupertinoIcons.bluetooth,
                  color: c.labelSecondary,
                ),
                title: 'Port',
                value: p.serialPort.isEmpty ? 'Pilih port…' : p.serialPort,
                onPressed: _pickSerialPort,
              ),
              InsetGroupedTile(
                leading: TileIcon(
                  icon: CupertinoIcons.speedometer,
                  color: c.labelSecondary,
                ),
                title: 'Baud rate',
                value: '${p.baudRate}',
                onPressed: _pickBaudRate,
              ),
            ],
            InsetGroupedTile(
              leading: TileIcon(
                icon: CupertinoIcons.arrow_left_right,
                color: c.labelSecondary,
              ),
              title: 'Lebar kertas',
              trailing: Segmented<PaperWidth>(
                value: p.paperWidth,
                options: {for (final w in PaperWidth.values) w: w.label},
                onChanged: (v) => _set(p.copyWith(paperWidth: v)),
              ),
            ),
            if (p.connection != PrinterConnection.none)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppButton(
                      label: 'Cek Sambungan',
                      icon: CupertinoIcons.antenna_radiowaves_left_right,
                      variant: AppButtonVariant.gray,
                      expand: true,
                      onPressed: p.isReady && !_testing
                          ? _checkConnection
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            label: 'Tes Cetak',
                            icon: CupertinoIcons.doc_text,
                            variant: AppButtonVariant.tinted,
                            expand: true,
                            loading: _testing,
                            onPressed: p.isReady
                                ? () => _test(drawer: false)
                                : null,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: AppButton(
                            label: 'Tes Buka Laci',
                            icon: CupertinoIcons.tray_arrow_down,
                            variant: AppButtonVariant.gray,
                            expand: true,
                            onPressed: p.isReady && !_testing
                                ? () => _test(drawer: true)
                                : null,
                          ),
                        ),
                      ],
                    ),
                    if (_status != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _statusError
                                ? CupertinoIcons.exclamationmark_circle_fill
                                : CupertinoIcons.checkmark_circle_fill,
                            size: 18,
                            color: _statusError ? c.danger : c.success,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              _status!,
                              style: AppTypography.footnote.copyWith(
                                color: c.label,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        InsetGroupedSection(
          header: 'Saat Transaksi Selesai',
          footer:
              'Laci uang dicolok ke printer (kabel RJ11), bukan ke komputer. '
              'Jika laci tidak terbuka, coba pin 5. Baris kosong di akhir '
              'supaya tulisan terakhir tidak ikut terpotong.',
          dividerIndent: 58,
          children: [
            InsetGroupedTile(
              leading: TileIcon(icon: CupertinoIcons.printer, color: c.accent),
              title: 'Cetak struk otomatis',
              subtitle: p.autoPrint
                  ? null
                  : 'Struk dicetak lewat tombol di popup transaksi berhasil',
              trailing: toggle(
                p.autoPrint,
                (v) => _set(p.copyWith(autoPrint: v)),
              ),
            ),
            InsetGroupedTile(
              leading: TileIcon(
                icon: CupertinoIcons.tray_arrow_down_fill,
                color: c.success,
              ),
              title: 'Buka laci saat bayar tunai',
              trailing: toggle(
                p.openDrawer,
                (v) => _set(p.copyWith(openDrawer: v)),
              ),
            ),
            InsetGroupedTile(
              leading: TileIcon(
                icon: CupertinoIcons.bolt_fill,
                color: c.labelSecondary,
              ),
              title: 'Pin laci',
              trailing: Segmented<int>(
                value: p.drawerPin,
                options: const {2: 'Pin 2', 5: 'Pin 5'},
                onChanged: (v) => _set(p.copyWith(drawerPin: v)),
              ),
            ),
            InsetGroupedTile(
              leading: TileIcon(
                icon: CupertinoIcons.scissors,
                color: c.labelSecondary,
              ),
              title: 'Potong kertas otomatis',
              subtitle: 'Diabaikan jika printer tidak punya pemotong',
              trailing: toggle(p.autoCut, (v) => _set(p.copyWith(autoCut: v))),
            ),
            InsetGroupedTile(
              leading: TileIcon(
                icon: CupertinoIcons.arrow_down_to_line,
                color: c.labelSecondary,
              ),
              title: 'Baris kosong di akhir',
              trailing: _Stepper(
                value: p.feedLines,
                max: PrinterConfig.maxFeedLines,
                onChanged: (v) => _set(p.copyWith(feedLines: v)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Segmented control kecil untuk baris pengaturan.
class Segmented<T extends Object> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return CupertinoSlidingSegmentedControl<T>(
      groupValue: value,
      onValueChanged: (v) {
        if (v != null && v != value) onChanged(v);
      },
      children: {
        for (final MapEntry(:key, :value) in options.entries)
          key: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(value, style: AppTypography.footnote),
          ),
      },
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconButton(
          icon: CupertinoIcons.minus,
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 32,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: AppTypography.headline.copyWith(
              color: c.label,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        AppIconButton(
          icon: CupertinoIcons.plus,
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

/// Baris berisi kolom teks satu baris (alamat IP, port).
class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.icon,
    required this.title,
    required this.controller,
    required this.placeholder,
    required this.onChanged,
    this.width = 200,
    this.digitsOnly = false,
  });

  final IconData icon;
  final String title;
  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String> onChanged;
  final double width;
  final bool digitsOnly;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InsetGroupedTile(
      leading: TileIcon(icon: icon, color: c.labelSecondary),
      title: title,
      trailing: SizedBox(
        width: width,
        child: CupertinoTextField(
          controller: controller,
          placeholder: placeholder,
          textAlign: TextAlign.right,
          keyboardType: digitsOnly ? TextInputType.number : TextInputType.url,
          inputFormatters: digitsOnly
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
          onChanged: onChanged,
          style: AppTypography.body.copyWith(color: c.label),
          placeholderStyle: AppTypography.body.copyWith(color: c.labelTertiary),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: c.fill,
            borderRadius: AppRadius.smAll,
          ),
        ),
      ),
    );
  }
}
