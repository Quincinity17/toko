import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Isi satu struk (faktur yang sudah tersimpan).
@immutable
class ReceiptData {
  const ReceiptData({
    this.storeId,
    required this.storeName,
    this.storeAddress,
    required this.invoiceNo,
    required this.date,
    required this.cashierName,
    required this.items,
    required this.subtotal,
    this.discount = 0,
    required this.total,
    required this.paid,
    required this.change,
    required this.paymentMethod,
    this.isCash = true,
    this.paymentRef,
  });

  /// Toko faktur (menentukan bentuk struk); `null` untuk contoh.
  final int? storeId;
  final String storeName;
  final String? storeAddress;
  final String invoiceNo;
  final DateTime date;
  final String cashierName;
  final List<ReceiptItem> items;
  final int subtotal;

  /// Hanya faktur lama (sebelum potongan dihapus) yang bisa > 0.
  final int discount;
  final int total;
  final int paid;
  final int change;
  final String paymentMethod;
  final bool isCash;
  final String? paymentRef;

  /// Contoh untuk pratinjau dan tes cetak.
  factory ReceiptData.sample({String? storeName, String? storeAddress}) {
    return ReceiptData(
      storeName: storeName ?? 'Toko Utama',
      storeAddress: storeAddress ?? 'Jl. Merdeka No. 10, Bandung',
      invoiceNo: 'INV-K01-20261002-0001',
      date: DateTime(2026, 10, 2, 14, 5),
      cashierName: 'Kasir',
      items: const [
        ReceiptItem(
          code: 'IDM001',
          name: 'Indomie Goreng',
          unit: 'PCS',
          qty: 5,
          price: 3500,
          total: 17500,
        ),
        ReceiptItem(
          code: 'AQU600',
          name: 'Aqua Botol 600 ml',
          unit: 'BTL',
          qty: 2,
          price: 4000,
          total: 8000,
        ),
        ReceiptItem(
          code: 'GLA1KG',
          name: 'Gula Pasir Gulaku 1 kg',
          unit: 'KG',
          qty: 1.5,
          price: 17000,
          total: 25500,
        ),
      ],
      subtotal: 51000,
      total: 51000,
      paid: 100000,
      change: 49000,
      paymentMethod: 'Tunai',
    );
  }

  static final _num = NumberFormat.decimalPattern('id_ID');
  static final _date = DateFormat('dd/MM/yyyy');
  static final _time = DateFormat('HH:mm');

  static String _n(num v) => _num.format(v);

  static String? _orNull(String? s) {
    final t = s?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  /// Nilai variabel template (lihat `ReceiptVariables`). Angka sudah
  /// diformat (`51.000`); nilai kosong = `null` supaya `{{#x}}` tidak tampil.
  Map<String, Object?> toTemplateValues({String? logo, bool reprint = false}) {
    final qty = items.fold<double>(0, (s, i) => s + i.qty);
    return {
      'toko': {'nama': storeName, 'alamat': _orNull(storeAddress)},
      'logo': logo,
      'faktur': {
        'no': invoiceNo,
        'tanggal': _date.format(date),
        'jam': _time.format(date),
      },
      'kasir': cashierName,
      'barang': [
        for (final (i, item) in items.indexed)
          {
            'no': i + 1,
            'kode': item.code,
            'nama': item.name,
            'qty': _n(item.qty),
            'satuan': _orNull(item.unit) ?? '',
            'harga': _n(item.price),
            'total': _n(item.total),
          },
      ],
      'jumlah_barang': items.length,
      'jumlah_item': _n(qty),
      'subtotal': _n(subtotal),
      'potongan': discount > 0 ? _n(discount) : null,
      'total': _n(total),
      'metode': paymentMethod,
      'bayar': _n(paid),
      'kembali': change > 0 ? _n(change) : null,
      'ref': _orNull(paymentRef),
      'tunai': isCash,
      'cetak_ulang': reprint,
    };
  }
}

@immutable
class ReceiptItem {
  const ReceiptItem({
    required this.code,
    required this.name,
    this.unit,
    required this.qty,
    required this.price,
    required this.total,
  });

  final String code;
  final String name;
  final String? unit;
  final double qty;
  final int price;
  final int total;
}
