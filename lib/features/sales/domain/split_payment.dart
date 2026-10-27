import 'package:flutter/foundation.dart';

import '../../../core/utils/formatters.dart';

/// Satu bagian pembayaran yang diisi kasir (split payment). Tunai: [amount]
/// = uang diterima (boleh lebih, ada kembalian). Non-tunai: [amount] = nilai
/// yang dibayar lewat metode itu (pas).
@immutable
class PaymentPart {
  const PaymentPart({
    required this.methodId,
    required this.name,
    required this.isCash,
    required this.amount,
    this.ref,
  });

  final int methodId;
  final String name;
  final bool isCash;
  final int amount;
  final String? ref;

  PaymentPart copyWith({int? amount, String? ref}) => PaymentPart(
    methodId: methodId,
    name: name,
    isCash: isCash,
    amount: amount ?? this.amount,
    ref: ref ?? this.ref,
  );
}

/// Bagian pembayaran yang sudah dihitung: [applied] = nilai yang benar-benar
/// masuk ke metode itu (tunai: setelah kembalian).
@immutable
class SettledPart {
  const SettledPart(this.part, {required this.applied});

  final PaymentPart part;
  final int applied;
}

/// Pembayaran tersimpan (`sale_payments`) untuk rincian, struk, dan total
/// per metode. Nota retur: [amount] negatif.
@immutable
class SalePart {
  const SalePart({
    this.methodId,
    required this.name,
    required this.amount,
    required this.isCash,
    this.tendered,
    this.ref,
  });

  final int? methodId;
  final String name;
  final int amount;
  final bool isCash;

  /// Tunai: uang diterima.
  final int? tendered;
  final String? ref;
}

class SplitPaymentFailure implements Exception {
  const SplitPaymentFailure(this.message);

  final String message;

  @override
  String toString() => 'SplitPaymentFailure: $message';
}

/// Aturan split payment (satu faktur dibayar dengan beberapa metode).
class SplitPayment {
  const SplitPayment._();

  /// Nama gabungan untuk `sales.payment_method`, mis. "Tunai + QRIS".
  static String joinedName(Iterable<String> names) => names.join(' + ');

  /// Menghitung bagian [parts] terhadap [due]. Non-tunai dibayar pas
  /// (jumlahnya tidak boleh melebihi [due]); sisanya dibayar tunai, dan
  /// kelebihan uang tunai menjadi kembalian. Tunai ditaruh paling depan.
  static ({List<SettledPart> parts, int change}) settle(
    List<PaymentPart> parts,
    int due,
  ) {
    if (parts.length < 2) {
      throw const SplitPaymentFailure('Pilih minimal dua metode pembayaran.');
    }
    if (parts.map((p) => p.methodId).toSet().length != parts.length) {
      throw const SplitPaymentFailure('Metode pembayaran tidak boleh dobel.');
    }
    final cash = parts.where((p) => p.isCash).toList();
    if (cash.length > 1) {
      throw const SplitPaymentFailure('Hanya boleh satu bagian tunai.');
    }
    for (final p in parts) {
      if (p.amount <= 0) {
        throw SplitPaymentFailure('Isi jumlah untuk ${p.name}.');
      }
    }
    final nonCash = parts.where((p) => !p.isCash).toList();
    final nonCashSum = nonCash.fold(0, (s, p) => s + p.amount);
    if (nonCashSum > due) {
      throw SplitPaymentFailure(
        'Pembayaran non-tunai (${Fmt.rupiah(nonCashSum)}) melebihi total '
        '${Fmt.rupiah(due)}.',
      );
    }
    final rest = due - nonCashSum;
    if (cash.isEmpty) {
      if (rest > 0) {
        throw SplitPaymentFailure('Masih kurang ${Fmt.rupiah(rest)}.');
      }
      return (
        parts: [for (final p in nonCash) SettledPart(p, applied: p.amount)],
        change: 0,
      );
    }
    final c = cash.single;
    if (rest == 0) {
      throw const SplitPaymentFailure(
        'Non-tunai sudah menutup total. Hapus bagian tunai.',
      );
    }
    if (c.amount < rest) {
      throw SplitPaymentFailure(
        'Uang tunai kurang ${Fmt.rupiah(rest - c.amount)}.',
      );
    }
    return (
      parts: [
        SettledPart(c, applied: rest),
        for (final p in nonCash) SettledPart(p, applied: p.amount),
      ],
      change: c.amount - rest,
    );
  }

  /// Membagi uang kembali [refund] ke metode faktur asal ([remaining] = sisa
  /// per metode yang belum dikembalikan, urut faktur). Tunai dulu (dari
  /// laci), lalu metode lain sesuai urutan.
  static List<SalePart> allocateRefund(List<SalePart> remaining, int refund) {
    final order = [
      ...remaining.where((p) => p.isCash),
      ...remaining.where((p) => !p.isCash),
    ];
    var left = refund;
    final out = <SalePart>[];
    for (final p in order) {
      if (left <= 0) break;
      final take = p.amount < left ? p.amount : left;
      if (take <= 0) continue;
      out.add(
        SalePart(
          methodId: p.methodId,
          name: p.name,
          amount: -take,
          isCash: p.isCash,
        ),
      );
      left -= take;
    }
    if (left > 0) {
      // Tidak seharusnya terjadi (uang kembali ≤ sisa faktur); sisanya ke
      // metode pertama supaya total nota tetap cocok.
      final first = order.first;
      final i = out.indexWhere((p) => p.methodId == first.methodId);
      final prev = i == -1 ? 0 : -out[i].amount;
      final fixed = SalePart(
        methodId: first.methodId,
        name: first.name,
        amount: -(prev + left),
        isCash: first.isCash,
      );
      if (i == -1) {
        out.add(fixed);
      } else {
        out[i] = fixed;
      }
    }
    return out;
  }
}
