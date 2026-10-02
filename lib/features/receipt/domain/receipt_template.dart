import 'package:flutter/foundation.dart';

import 'default_receipt_html.dart';

/// Bentuk struk satu toko: template HTML + CSS dan logo, diubah admin di
/// Pengaturan › Struk & Printer.
///
/// Template memakai variabel Mustache (`{{total}}`, `{{#barang}}…{{/barang}}`),
/// lihat [ReceiptVariables]. Disimpan sebagai JSON di `stores.receipt_template`
/// (ikut data toko, jadi nanti tersinkron ke komputer kasir lain).
@immutable
class ReceiptTemplate {
  const ReceiptTemplate({this.html = defaultReceiptHtml, this.logo});

  /// Batas ukuran file logo yang dipilih. Logo diperkecil ke lebar kertas
  /// 80 mm sebelum disimpan, jadi yang tersimpan jauh lebih kecil.
  static const maxLogoBytes = 5 * 1024 * 1024;

  /// Template HTML + `<style>`.
  final String html;

  /// Logo sebagai data URI (`data:image/png;base64,…`), dipakai lewat
  /// `{{logo}}` di template. `null` = tanpa logo.
  final String? logo;

  ReceiptTemplate copyWith({String? html, String? Function()? logo}) =>
      ReceiptTemplate(
        html: html ?? this.html,
        logo: logo == null ? this.logo : logo(),
      );

  Map<String, Object?> toJson() => {'html': html, 'logo': logo};

  /// Nilai yang hilang/rusak memakai default.
  factory ReceiptTemplate.fromJson(Map<String, Object?> json) {
    final html = json['html'];
    final logo = json['logo'];
    return ReceiptTemplate(
      html: html is String && html.trim().isNotEmpty
          ? html
          : defaultReceiptHtml,
      logo: logo is String && logo.startsWith('data:image/') ? logo : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReceiptTemplate && other.html == html && other.logo == logo;

  @override
  int get hashCode => Object.hash(html, logo);
}

/// Daftar variabel template untuk panduan di layar pengaturan.
class ReceiptVariables {
  const ReceiptVariables._();

  static const all = <(String, String)>[
    ('{{toko.nama}}', 'Nama toko'),
    ('{{toko.alamat}}', 'Alamat toko'),
    ('{{logo}}', 'Logo, mis. <img src="{{logo}}">'),
    ('{{faktur.no}}', 'Nomor faktur'),
    ('{{faktur.tanggal}}', 'Tanggal, mis. 02/10/2026'),
    ('{{faktur.jam}}', 'Jam, mis. 14:05'),
    ('{{kasir}}', 'Nama kasir'),
    ('{{#barang}}…{{/barang}}', 'Ulangi untuk setiap barang'),
    ('{{no}}', 'Nomor urut barang (di dalam barang)'),
    ('{{kode}}', 'Kode barang (di dalam barang)'),
    ('{{nama}}', 'Nama barang (di dalam barang)'),
    ('{{qty}}', 'Jumlah (di dalam barang)'),
    ('{{satuan}}', 'Satuan (di dalam barang)'),
    ('{{harga}}', 'Harga satuan (di dalam barang)'),
    ('{{total}}', 'Total baris (di dalam barang) / total faktur'),
    ('{{jumlah_barang}}', 'Banyak jenis barang'),
    ('{{jumlah_item}}', 'Total qty semua barang'),
    ('{{subtotal}}', 'Subtotal'),
    ('{{#potongan}}…{{/potongan}}', 'Hanya faktur lama yang punya potongan'),
    ('{{metode}}', 'Metode bayar (Tunai, QRIS, …)'),
    ('{{bayar}}', 'Uang dibayar'),
    ('{{#kembali}}…{{/kembali}}', 'Kembalian (tampil jika ada)'),
    ('{{#ref}}…{{/ref}}', 'No. referensi non-tunai (jika ada)'),
    ('{{#tunai}}…{{/tunai}}', 'Hanya untuk pembayaran tunai'),
    ('{{#cetak_ulang}}…{{/cetak_ulang}}', 'Hanya saat cetak ulang'),
    ('{{^x}}…{{/x}}', 'Kebalikan: tampil jika x kosong'),
  ];
}
