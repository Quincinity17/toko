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
    ('{{kode}}', 'Barcode barang (di dalam barang)'),
    ('{{nama}}', 'Nama barang (di dalam barang)'),
    ('{{qty}}', 'Jumlah (di dalam barang)'),
    ('{{satuan}}', 'Satuan (di dalam barang)'),
    ('{{harga}}', 'Harga satuan (di dalam barang)'),
    ('{{total}}', 'Total baris (di dalam barang) / total faktur'),
    ('{{jumlah_barang}}', 'Banyak jenis barang'),
    ('{{jumlah_item}}', 'Total qty semua barang'),
    ('{{subtotal}}', 'Subtotal'),
    ('{{#potongan}}…{{/potongan}}', 'Potongan voucher (tampil jika ada)'),
    ('{{voucher}}', 'Kode voucher yang dipakai'),
    (
      '{{#tukar}}…{{/tukar}}',
      'Tukar barang: {{tukar.dari}} (faktur asal), {{tukar.kredit}}',
    ),
    ('{{metode}}', 'Metode bayar (Tunai, QRIS, …; split: "Tunai + QRIS")'),
    (
      '{{#pembayaran}}…{{/pembayaran}}',
      'Bayar terpisah: ulangi per metode, {{metode}} {{jumlah}} {{ref}}',
    ),
    (
      '{{#retur}}…{{/retur}}',
      'Nota retur: {{retur.dari}} (faktur asal), {{retur.alasan}}, '
          '{{retur.kembali}} (uang kembali). Angka nota retur negatif.',
    ),
    ('{{bayar}}', 'Uang dibayar'),
    ('{{#kembali}}…{{/kembali}}', 'Kembalian (tampil jika ada)'),
    ('{{#ref}}…{{/ref}}', 'No. referensi non-tunai (jika ada)'),
    ('{{#tunai}}…{{/tunai}}', 'Hanya untuk pembayaran tunai'),
    ('{{#cetak_ulang}}…{{/cetak_ulang}}', 'Hanya saat cetak ulang'),
    ('{{^x}}…{{/x}}', 'Kebalikan: tampil jika x kosong'),
  ];
}

/// Bagian struk yang ditambahkan aplikasi pada template buatan admin yang
/// belum memilikinya, supaya nota retur tidak terlihat seperti struk
/// penjualan dan bayar terpisah tetap terinci.
abstract final class ReceiptSections {
  static const _row = 'display: flex; justify-content: space-between';

  /// Judul & keterangan nota retur (di atas struk).
  static const returnHeader =
      '{{#retur}}<div style="text-align: center; font-weight: bold; '
      'font-size: 26px">NOTA RETUR</div>'
      '<div style="text-align: center">Retur dari {{retur.dari}}</div>'
      '{{#retur.alasan}}<div style="text-align: center">Alasan: '
      '{{retur.alasan}}</div>{{/retur.alasan}}'
      '<div style="$_row; font-weight: bold"><span>Dikembalikan '
      '({{metode}})</span><span>{{retur.kembali}}</span></div>'
      '<div style="border-top: 2px solid #000; margin: 8px 0"></div>'
      '{{/retur}}\n';

  /// Rincian bayar terpisah (di bawah struk).
  static const payments =
      '\n{{#pembayaran}}<div style="$_row"><span>{{metode}}</span>'
      '<span>{{jumlah}}</span></div>{{#ref}}<div>Ref: {{ref}}</div>{{/ref}}'
      '{{/pembayaran}}';

  /// Bagian yang belum ada di [html] (label untuk peringatan editor).
  static List<String> missing(String html) => [
    if (!html.contains('{{#retur}}')) 'nota retur',
    if (!html.contains('{{#pembayaran}}')) 'bayar terpisah',
  ];

  /// [html] + bagian yang belum ada. Untuk struk biasa tidak mengubah apa
  /// pun (bagian itu hanya tampil untuk nota retur / bayar terpisah).
  static String withFallbacks(String html) {
    var out = html;
    if (!out.contains('{{#retur}}')) out = returnHeader + out;
    if (!out.contains('{{#pembayaran}}')) out = out + payments;
    return out;
  }
}
