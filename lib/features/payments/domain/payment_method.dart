import 'package:flutter/foundation.dart';

enum PaymentKind {
  /// Uang diterima bisa lebih dari total; ada kembalian.
  cash('Tunai', 'Isi uang diterima, kembalian dihitung otomatis'),

  /// Dibayar pas sesuai total (QRIS, transfer, kartu, e-wallet).
  nonCash('Non-tunai', 'Dibayar pas, bisa isi nomor referensi');

  const PaymentKind(this.label, this.description);

  final String label;
  final String description;
}

@immutable
class PaymentMethod {
  const PaymentMethod({
    required this.id,
    required this.name,
    required this.kind,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final int id;
  final String name;
  final PaymentKind kind;
  final bool isActive;
  final int sortOrder;

  bool get isCash => kind == PaymentKind.cash;

  @override
  bool operator ==(Object other) =>
      other is PaymentMethod &&
      other.id == id &&
      other.name == name &&
      other.kind == kind &&
      other.isActive == isActive &&
      other.sortOrder == sortOrder;

  @override
  int get hashCode => Object.hash(id, name, kind, isActive, sortOrder);
}
