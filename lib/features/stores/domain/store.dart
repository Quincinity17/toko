import 'package:flutter/foundation.dart';

/// Toko (cabang).
@immutable
class Store {
  const Store({
    required this.id,
    required this.name,
    this.address,
    this.isActive = true,
  });

  final int id;
  final String name;
  final String? address;
  final bool isActive;

  @override
  bool operator ==(Object other) =>
      other is Store &&
      other.id == id &&
      other.name == name &&
      other.address == address &&
      other.isActive == isActive;

  @override
  int get hashCode => Object.hash(id, name, address, isActive);
}
