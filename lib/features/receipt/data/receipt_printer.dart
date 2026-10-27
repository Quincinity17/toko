import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../payments/domain/payment_method.dart';
import '../../sales/data/sales_repository.dart';
import '../domain/escpos.dart';
import '../domain/printer_config.dart';
import '../domain/receipt.dart';
import '../domain/receipt_html.dart';
import '../domain/receipt_template.dart';
import 'printer_failure.dart';
import 'printer_transport.dart';
import 'receipt_renderer.dart';
import 'receipt_settings_repository.dart';

/// Apa yang dilakukan setelah transaksi selesai.
enum AfterCheckout {
  /// Printer belum diatur, atau cetak otomatis & buka laci dimatikan.
  nothing,

  /// Struk dicetak (dan laci dibuka bila tunai).
  printed,

  /// Hanya laci dibuka (cetak otomatis mati).
  drawerOpened,
}

/// Mencetak struk faktur dan membuka laci uang.
class ReceiptPrinter {
  ReceiptPrinter(this._db, this._settings, this._transport, this._rasterizer);

  final AppDatabase _db;
  final ReceiptSettingsRepository _settings;
  final PrinterTransport _transport;
  final ReceiptRasterizer _rasterizer;

  /// Isi struk faktur [saleId] dari database.
  Future<ReceiptData> load(int saleId) async {
    final found = await _db.salesDao.findWithCashier(saleId);
    if (found == null) throw const PrinterFailure('Faktur tidak ditemukan.');
    final (sale, cashier) = found;
    final store = sale.storeId == null
        ? null
        : await _db.storesDao.findById(sale.storeId!);
    final items = await _db.salesDao.itemsOf(saleId);
    final method = sale.paymentMethodId == null
        ? null
        : await _db.paymentMethodsDao.findById(sale.paymentMethodId!);
    final sales = SalesRepository(_db);
    final exchange = sale.exchangeOfId == null
        ? null
        : await sales.exchangeInfo(sale.exchangeOfId!);
    final original = sale.returnOfId == null
        ? null
        : await (_db.select(
            _db.sales,
          )..where((s) => s.id.equals(sale.returnOfId!))).getSingleOrNull();
    final payments = await sales.paymentsOf(saleId);
    return ReceiptData(
      storeId: sale.storeId,
      storeName: store?.name ?? 'Toko',
      storeAddress: store?.address,
      invoiceNo: sale.invoiceNo,
      date: sale.saleDate,
      cashierName: cashier,
      items: [
        for (final i in items)
          ReceiptItem(
            code: i.productCode,
            name: i.productName,
            unit: i.unitName,
            qty: i.qty,
            price: i.price,
            total: i.subtotal,
          ),
      ],
      subtotal: sale.subtotal,
      discount: sale.discount,
      voucherCode: sale.voucherCode,
      exchangeCredit: exchange?.credit ?? 0,
      exchangeFrom: exchange?.originalNo,
      total: sale.total,
      paid: sale.paid,
      change: sale.changeAmount,
      paymentMethod: sale.paymentMethod,
      isCash: payments.isEmpty
          ? method == null || method.kind == PaymentKind.cash
          : payments.any((p) => p.isCash),
      paymentRef: sale.paymentRef,
      payments: payments,
      returnOf: sale.returnOfId == null
          ? null
          : original?.invoiceNo ?? '(faktur dihapus)',
      returnReason: sale.returnReason,
    );
  }

  /// Mencetak struk faktur [saleId]. [reprint] menambah tanda "CETAK ULANG".
  Future<void> printSale(
    int saleId, {
    bool reprint = false,
    bool openDrawer = false,
  }) async {
    final config = await _settings.printer();
    final data = await load(saleId);
    final template = data.storeId == null
        ? const ReceiptTemplate()
        : await _settings.templateFor(data.storeId!);
    await _send(
      config,
      template,
      data,
      reprint: reprint,
      openDrawer: openDrawer,
      jobName: data.invoiceNo,
    );
  }

  /// Dipanggil setelah checkout atau retur (nota retur): cetak otomatis dan/atau buka laci sesuai
  /// pengaturan. Gagal cetak dilempar sebagai [PrinterFailure]; transaksi
  /// sendiri sudah tersimpan.
  Future<AfterCheckout> afterCheckout(
    int saleId, {
    required bool isCash,
  }) async {
    final config = await _settings.printer();
    if (!config.isReady) return AfterCheckout.nothing;
    final drawer = isCash && config.openDrawer;
    if (config.autoPrint) {
      await printSale(saleId, openDrawer: drawer);
      return AfterCheckout.printed;
    }
    if (drawer) {
      await _transport.send(
        config,
        buildDrawerKick(pin: config.drawerPin),
        jobName: 'Buka laci',
      );
      return AfterCheckout.drawerOpened;
    }
    return AfterCheckout.nothing;
  }

  /// Membuka laci uang tanpa mencetak.
  Future<void> openDrawer() async {
    final config = await _settings.printer();
    await _transport.send(
      config,
      buildDrawerKick(pin: config.drawerPin),
      jobName: 'Buka laci',
    );
  }

  /// Mencetak struk contoh dengan pengaturan printer [config] (belum tentu
  /// tersimpan) dan bentuk struk toko [storeId] (`null` = bawaan).
  Future<void> testPrint(PrinterConfig config, {required int? storeId}) async {
    final store = storeId == null
        ? null
        : await _db.storesDao.findById(storeId);
    final template = storeId == null
        ? const ReceiptTemplate()
        : await _settings.templateFor(storeId);
    await _send(
      config,
      template,
      ReceiptData.sample(storeName: store?.name, storeAddress: store?.address),
      jobName: 'Tes cetak',
    );
  }

  /// Memastikan printer [config] bisa dihubungi tanpa mencetak.
  Future<void> checkConnection(PrinterConfig config) =>
      _transport.check(config);

  /// Membuka laci memakai pengaturan yang sedang diubah.
  Future<void> testDrawer(PrinterConfig config) => _transport.send(
    config,
    buildDrawerKick(pin: config.drawerPin),
    jobName: 'Tes laci',
  );

  Future<void> _send(
    PrinterConfig config,
    ReceiptTemplate template,
    ReceiptData data, {
    bool reprint = false,
    bool openDrawer = false,
    required String jobName,
  }) async {
    // Periksa printer dulu supaya tidak merender percuma.
    if (!config.isReady) {
      throw const PrinterFailure(
        'Printer belum diatur. Atur lewat tombol Printer Nota di layar Kasir.',
      );
    }
    final String html;
    try {
      html = ReceiptHtml.render(
        // Template buatan admin tanpa bagian retur / bayar terpisah: bagian
        // itu ditambahkan otomatis.
        ReceiptSections.withFallbacks(template.html),
        data.toTemplateValues(logo: template.logo, reprint: reprint),
      );
    } on ReceiptTemplateError catch (e) {
      throw PrinterFailure('Template struk salah. ${e.message}');
    }
    final image = await _rasterizer.rasterize(html, config.paperWidth);
    final bytes = buildReceiptJob(
      image,
      feedLines: config.feedLines,
      cut: config.autoCut,
      openDrawer: openDrawer,
      drawerPin: config.drawerPin,
    );
    await _transport.send(config, bytes, jobName: jobName);
  }
}

final receiptPrinterProvider = Provider<ReceiptPrinter>(
  (ref) => ReceiptPrinter(
    ref.watch(appDatabaseProvider),
    ref.watch(receiptSettingsRepositoryProvider),
    ref.watch(printerTransportProvider),
    ref.watch(receiptRasterizerProvider),
  ),
);
