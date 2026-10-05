import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../audit/data/audit_repository.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../stores/presentation/store_scope.dart';
import '../domain/cart.dart';

/// Catatan aktivitas tindakan kasir yang tidak meninggalkan faktur (dan
/// karena itu rawan dipakai curang): batal transaksi, barang dikurangi/
/// dihapus setelah di-scan, transaksi tertahan dihapus, laci dibuka tanpa
/// transaksi.
class CashierAudit {
  CashierAudit(this._audit, this._actor, this._storeId);

  final AuditRepository _audit;
  final AppUser? _actor;
  final int? _storeId;

  Future<void> _record(
    AuditType type,
    String summary,
    Map<String, Object?> data,
  ) => _audit.record(
    type,
    summary,
    actor: _actor,
    storeId: _storeId,
    data: data,
  );

  static List<Map<String, Object?>> _items(Iterable<CartLine> lines) => [
    for (final l in lines)
      {
        'code': l.product.code,
        'name': l.product.name,
        'qty': l.qty,
        'total': l.total,
      },
  ];

  Future<void> cartCleared(Cart cart) {
    if (cart.isEmpty) return Future.value();
    return _record(
      AuditType.cartCleared,
      'Batal transaksi: ${cart.lines.length} barang '
      '(${Fmt.rupiah(cart.total)})',
      {'total': cart.total, 'items': _items(cart.lines)},
    );
  }

  /// Jumlah barang [line] dikurangi dari [from] ke [to] (0 = dihapus).
  Future<void> itemReduced(CartLine line, double from, double to) {
    if (to >= from) return Future.value();
    return _record(
      AuditType.cartItemReduced,
      to <= 0
          ? 'Hapus ${line.product.name} (${Fmt.number(from)}) dari keranjang'
          : '${line.product.name}: ${Fmt.number(from)} → ${Fmt.number(to)}',
      {
        'code': line.product.code,
        'name': line.product.name,
        'from': from,
        'to': to,
        'value': ((from - to) * line.price).round(),
      },
    );
  }

  Future<void> heldCartDeleted({
    required String? note,
    required int itemCount,
    required int total,
  }) => _record(
    AuditType.heldCartDeleted,
    'Hapus transaksi tertahan${note == null || note.isEmpty ? '' : ' "$note"'}'
    ': $itemCount barang (${Fmt.rupiah(total)})',
    {'note': note, 'items': itemCount, 'total': total},
  );

  Future<void> drawerOpened() =>
      _record(AuditType.drawerOpened, 'Laci dibuka tanpa transaksi', {});
}

final cashierAuditProvider = Provider<CashierAudit>(
  (ref) => CashierAudit(
    ref.watch(auditRepositoryProvider),
    ref.watch(authControllerProvider),
    ref.watch(storeScopeProvider),
  ),
);
