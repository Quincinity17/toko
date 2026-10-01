import 'package:flutter/foundation.dart';

import '../../../core/utils/formatters.dart';

enum VoucherType {
  percent('Persen'),
  amount('Nominal');

  const VoucherType(this.label);

  final String label;
}

enum VoucherStatus {
  active('Aktif'),
  scheduled('Belum berlaku'),
  expired('Kedaluwarsa'),
  inactive('Nonaktif');

  const VoucherStatus(this.label);

  final String label;
}

/// Voucher potongan, tanpa kuota (cukup aktif/nonaktif oleh admin).
/// Semua aturan pemakaian ada di sini supaya kasir,
/// halaman admin, dan proses checkout memakai logika yang sama.
@immutable
class Voucher {
  const Voucher({
    required this.id,
    required this.code,
    this.name = '',
    required this.type,
    required this.value,
    this.maxDiscount,
    this.minPurchase = 0,
    this.startDate,
    this.endDate,
    this.isActive = true,
  });

  final int id;
  final String code;
  final String name;
  final VoucherType type;

  /// Persen (0–100) atau nominal Rupiah.
  final double value;
  final int? maxDiscount;
  final int minPurchase;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isActive;

  VoucherStatus statusAt(DateTime now) {
    if (!isActive) return VoucherStatus.inactive;
    if (startDate != null && now.isBefore(_startOfDay(startDate!))) {
      return VoucherStatus.scheduled;
    }
    if (endDate != null && !now.isBefore(_startOfDay(endDate!).add(_day))) {
      return VoucherStatus.expired;
    }
    return VoucherStatus.active;
  }

  /// Alasan voucher tidak bisa dipakai untuk belanja [subtotal] pada [now],
  /// atau `null` jika bisa.
  String? problemFor({required int subtotal, required DateTime now}) {
    switch (statusAt(now)) {
      case VoucherStatus.inactive:
        return 'Voucher $code tidak aktif.';
      case VoucherStatus.scheduled:
        return 'Voucher $code baru berlaku mulai ${Fmt.dateShort(startDate!)}.';
      case VoucherStatus.expired:
        return 'Voucher $code sudah kedaluwarsa (${Fmt.dateShort(endDate!)}).';
      case VoucherStatus.active:
        break;
    }
    if (subtotal < minPurchase) {
      return 'Voucher $code butuh minimal belanja ${Fmt.rupiah(minPurchase)}.';
    }
    return null;
  }

  /// Potongan dalam Rupiah untuk [subtotal]; tidak pernah melebihi subtotal.
  int discountFor(int subtotal) {
    var d = switch (type) {
      VoucherType.percent => (subtotal * value / 100).round(),
      VoucherType.amount => value.round(),
    };
    if (type == VoucherType.percent && maxDiscount != null) {
      d = d > maxDiscount! ? maxDiscount! : d;
    }
    return d.clamp(0, subtotal);
  }

  /// Ringkasan aturan, mis. "Diskon 10% (maks Rp 5.000) · min. Rp 50.000".
  String get summary {
    final parts = <String>[
      switch (type) {
        VoucherType.percent =>
          'Diskon ${Fmt.number(value)}%'
              '${maxDiscount != null ? ' (maks ${Fmt.rupiah(maxDiscount!)})' : ''}',
        VoucherType.amount => 'Potongan ${Fmt.rupiah(value)}',
      },
      if (minPurchase > 0) 'min. belanja ${Fmt.rupiah(minPurchase)}',
    ];
    return parts.join(' · ');
  }

  static const _day = Duration(days: 1);
  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  bool operator ==(Object other) =>
      other is Voucher &&
      other.id == id &&
      other.code == code &&
      other.name == name &&
      other.type == type &&
      other.value == value &&
      other.maxDiscount == maxDiscount &&
      other.minPurchase == minPurchase &&
      other.startDate == startDate &&
      other.endDate == endDate &&
      other.isActive == isActive;

  @override
  int get hashCode => Object.hash(
    id,
    code,
    name,
    type,
    value,
    maxDiscount,
    minPurchase,
    startDate,
    endDate,
    isActive,
  );
}

/// Validasi isian form voucher. Mengembalikan pesan error atau `null`.
class VoucherRules {
  const VoucherRules._();

  static final _codePattern = RegExp(r'^[A-Z0-9_-]+$');

  static String normalizeCode(String v) => v.trim().toUpperCase();

  static String? code(String v) {
    final c = normalizeCode(v);
    if (c.isEmpty) return 'Kode wajib diisi.';
    if (c.length < 3 || c.length > 20) return 'Kode 3–20 karakter.';
    if (!_codePattern.hasMatch(c)) {
      return 'Hanya huruf, angka, - atau _ (tanpa spasi).';
    }
    return null;
  }

  static String? value(VoucherType type, double? v) {
    if (v == null || v <= 0) return 'Isi nilai potongan lebih dari 0.';
    if (type == VoucherType.percent && v > 100) return 'Maksimal 100%.';
    return null;
  }

  static String? period(DateTime? start, DateTime? end) {
    if (start != null && end != null && end.isBefore(start)) {
      return 'Tanggal berakhir tidak boleh sebelum tanggal mulai.';
    }
    return null;
  }
}
