import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/uuid.dart';
import '../../../sync_protocol/sync_protocol.dart';
import '../../audit/domain/sale_digest.dart';
import 'sync_schema.dart';

class SyncFailure implements Exception {
  const SyncFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Data merujuk data lain yang belum diterima (mis. masih di halaman
/// berikutnya): ditunda lalu dicoba lagi.
class SyncMissingRef extends SyncFailure {
  const SyncMissingRef(super.message);
}

/// Mengubah baris database lokal ↔ [SyncChange]. Kolom dikirim apa adanya
/// (nama kolom SQL), kecuali id lokal: rujukan ke tabel lain dikirim
/// sebagai uuid ([SyncTableSpec.refs]). Kolom yang tidak dikenal komputer
/// penerima diabaikan, jadi versi aplikasi yang sedikit berbeda tetap bisa
/// bertukar data.
class SyncCodec {
  SyncCodec(this._db);

  final AppDatabase _db;
  final _columns = <String, Set<String>>{};

  Future<Set<String>> _cols(String table) async => _columns[table] ??= {
    for (final r in await _db.customSelect('PRAGMA table_info($table)').get())
      r.read<String>('name'),
  };

  Future<String?> _uuidOf(String table, Object? id) async {
    if (id == null) return null;
    final r = await _db
        .customSelect(
          'SELECT uuid FROM $table WHERE id = ?',
          variables: [Variable(id)],
        )
        .getSingleOrNull();
    return r?.read<String?>('uuid');
  }

  Future<int?> _idOf(String table, Object? uuid) async {
    if (uuid == null) return null;
    final r = await _db
        .customSelect(
          'SELECT id FROM $table WHERE uuid = ?',
          variables: [Variable(uuid)],
        )
        .getSingleOrNull();
    return r?.read<int>('id');
  }

  Future<Map<String, Object?>> _rowToJson(
    Map<String, Object?> row,
    Set<String> skip,
    Map<String, String> refs,
  ) async {
    final out = <String, Object?>{};
    for (final MapEntry(:key, :value) in row.entries) {
      if (SyncTableSpec.always.contains(key) || skip.contains(key)) continue;
      out[key] = refs.containsKey(key)
          ? await _uuidOf(refs[key]!, value)
          : value;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Ekspor
  // ---------------------------------------------------------------------------

  /// Data terbaru baris [uuid]; `data == null` bila barisnya sudah dihapus.
  Future<SyncChange> export(SyncEntity entity, String uuid) async {
    final spec = syncSpecByEntity[entity]!;
    final row = await _db
        .customSelect(
          'SELECT * FROM ${spec.table} WHERE uuid = ?',
          variables: [Variable(uuid)],
        )
        .getSingleOrNull();
    if (row == null) return SyncChange(entity: entity, uuid: uuid);
    final data = await _rowToJson(row.data, spec.skip, spec.refs);
    if (entity == SyncEntity.auditEntry) data['remote_id'] = row.data['id'];
    if (entity == SyncEntity.stockMovement) {
      final type = row.data['type'];
      data['ref_id'] = type == 'sale' || type == 'saleReturn'
          ? await _uuidOf('sales', row.data['ref_id'])
          : null;
    }
    for (final child in spec.children) {
      final rows = await _db
          .customSelect(
            'SELECT * FROM ${child.table} WHERE ${child.parentColumn} = ? '
            'ORDER BY id',
            variables: [Variable(row.data['id'])],
          )
          .get();
      data[child.key] = [
        for (final r in rows)
          await _rowToJson(r.data, {child.parentColumn}, child.refs),
      ];
    }
    return SyncChange(entity: entity, uuid: uuid, data: data);
  }

  /// Semua uuid [entity] yang ada (untuk kiriman awal komputer master).
  Future<List<String>> allUuids(SyncEntity entity) async {
    final spec = syncSpecByEntity[entity]!;
    final rows = await _db
        .customSelect(
          'SELECT uuid FROM ${spec.table} WHERE uuid IS NOT NULL '
          '${await _cols(spec.table).then((c) => c.contains('id') ? 'ORDER BY id' : '')}',
        )
        .get();
    return [for (final r in rows) r.read<String>('uuid')];
  }

  // ---------------------------------------------------------------------------
  // Terapkan
  // ---------------------------------------------------------------------------

  /// Menerapkan [changes] (dari server) dalam satu transaksi. Data yang
  /// diterapkan tidak dikirim balik (`temp.sync_mute`). Mengembalikan
  /// ringkasan untuk catatan aktivitas.
  Future<SyncApplied> apply(List<SyncChange> changes) async {
    final order = {for (final (i, s) in syncSpecs.indexed) s.entity: i};
    final sorted = [...changes]
      ..sort((a, b) {
        final e = order[a.entity]!.compareTo(order[b.entity]!);
        return e != 0 ? e : (a.seq ?? 0).compareTo(b.seq ?? 0);
      });
    final applied = SyncApplied();
    await _mute();
    await _db.transaction(() async {
      await _db.customStatement('INSERT INTO temp.sync_mute VALUES (1)');
      try {
        for (final c in sorted) {
          try {
            // Savepoint: data yang gagal tidak meninggalkan sisa.
            await _db.transaction(() => _applyOne(c, applied));
          } on SyncMissingRef catch (e) {
            applied.deferred.add(c);
            applied.lastMissing = e.message;
          }
        }
        await _reseal(applied.resealed);
      } finally {
        await _db.customStatement('DELETE FROM temp.sync_mute');
      }
    });
    return applied;
  }

  Future<void> _applyOne(SyncChange c, SyncApplied applied) async {
    final spec = syncSpecByEntity[c.entity]!;
    final data = c.data;
    if (data == null) {
      await _delete(spec, c.uuid);
      applied.master++;
      return;
    }
    if (!c.entity.master) {
      // Transaksi tidak pernah berubah: yang sudah ada dilewati.
      if (await _idOf(spec.applyTable, c.uuid) != null) return;
    }
    final id = await _upsert(spec.applyTable, spec, c.uuid, {
      ...data,
      if (c.entity == SyncEntity.auditEntry) 'origin': c.origin,
    });
    switch (c.entity) {
      case SyncEntity.sale:
        for (final child in spec.children) {
          for (final item in (data[child.key] as List? ?? const [])) {
            final values = (item as Map).cast<String, Object?>();
            await _upsert(
              child.table,
              null,
              values['uuid'] as String? ?? newUuid(),
              {...values, child.parentColumn: id},
              refs: child.refs,
              keepIds: {child.parentColumn},
            );
          }
        }
        applied.sales.add(await _digestOf(id, c.uuid));
      case SyncEntity.stockMovement:
        await _applyStock(id);
        applied.movements++;
      case SyncEntity.auditEntry:
        applied.audit++;
      default:
        applied.master++;
        applied.resealed.add((spec.applyTable, id));
    }
  }

  /// Menyegel ulang baris master yang baru diterapkan (segel memakai kunci
  /// perangkat ini). Hanya baris yang berubah, bukan seluruh database.
  Future<void> _reseal(Set<(String, int)> rows) async {
    final seals = _db.sealsDao;
    final pricing = <int>{};
    for (final (table, id) in rows) {
      switch (table) {
        case 'users':
          await seals.resealUser(id);
        case 'products':
          await seals.resealProduct(id);
        case 'role_permissions':
          await seals.resealRolePermission(id);
        case 'store_products':
          final r = await (_db.select(
            _db.storeProducts,
          )..where((t) => t.id.equals(id))).getSingleOrNull();
          if (r != null) {
            await seals.resealStoreProduct(r.storeId, r.productId);
          }
        case 'store_unit_prices':
          final r = await _db
              .customSelect(
                'SELECT pu.product_id FROM store_unit_prices s JOIN '
                'product_units pu ON pu.id = s.product_unit_id WHERE s.id = ?',
                variables: [Variable.withInt(id)],
              )
              .getSingleOrNull();
          if (r != null) pricing.add(r.read<int>('product_id'));
        case 'product_units' || 'price_tiers':
          final r = await _db
              .customSelect(
                'SELECT product_id FROM $table WHERE id = ?',
                variables: [Variable.withInt(id)],
              )
              .getSingleOrNull();
          if (r != null) pricing.add(r.read<int>('product_id'));
      }
    }
    for (final productId in pricing) {
      await seals.resealPricing(productId);
    }
  }

  /// Sisip/ubah baris [uuid]; rujukan uuid → id lokal. Mengembalikan id.
  Future<int> _upsert(
    String table,
    SyncTableSpec? spec,
    String uuid,
    Map<String, Object?> data, {
    Map<String, String>? refs,
    Set<String> keepIds = const {},
  }) async {
    final local = await _cols(table);
    final refMap = refs ?? spec!.refs;
    final values = <String, Object?>{'uuid': uuid};
    for (final MapEntry(:key, :value) in data.entries) {
      if (!local.contains(key) || SyncTableSpec.always.contains(key)) continue;
      if (key == 'uuid') continue;
      if (spec != null && spec.skip.contains(key)) continue;
      if (keepIds.contains(key)) {
        values[key] = value;
      } else if (refMap.containsKey(key)) {
        final id = await _idOf(refMap[key]!, value);
        if (value != null && id == null && !(spec?.lenientRefs ?? false)) {
          throw SyncMissingRef(
            'Data $table merujuk ${refMap[key]} yang belum ada ($value).',
          );
        }
        values[key] = id;
      } else if (key == 'ref_id' && table == 'stock_movements') {
        values[key] = await _idOf('sales', value);
      } else {
        values[key] = value;
      }
    }
    final cols = values.keys.toList();
    final conflict = spec?.conflict ?? 'uuid';
    final conflictCols = {for (final c in conflict.split(',')) c.trim()};
    final update = [
      for (final c in cols)
        if (!conflictCols.contains(c)) '$c = excluded.$c',
    ];
    await _db.customStatement(
      'INSERT INTO $table (${cols.join(', ')}) '
      'VALUES (${List.filled(cols.length, '?').join(', ')}) '
      'ON CONFLICT($conflict) DO '
      '${update.isEmpty ? 'NOTHING' : 'UPDATE SET ${update.join(', ')}'}',
      [for (final c in cols) values[c]],
    );
    if (!local.contains('id')) return 0;
    return (await _idOf(table, uuid))!;
  }

  Future<void> _delete(SyncTableSpec spec, String uuid) async {
    try {
      if (spec.entity == SyncEntity.product) {
        final id = await _idOf('products', uuid);
        if (id != null) {
          await _db.customStatement(
            'DELETE FROM stock_movements WHERE product_id = ?',
            [id],
          );
        }
      }
      await _db.customStatement('DELETE FROM ${spec.table} WHERE uuid = ?', [
        uuid,
      ]);
    } catch (_) {
      // Masih dirujuk transaksi di komputer ini: nonaktifkan saja.
      if ((await _cols(spec.table)).contains('is_active')) {
        await _db.customStatement(
          'UPDATE ${spec.table} SET is_active = 0 WHERE uuid = ?',
          [uuid],
        );
      }
    }
  }

  /// Riwayat stok dari komputer lain: stok toko ikut berubah.
  Future<void> _applyStock(int movementId) async {
    final m = await (_db.select(
      _db.stockMovements,
    )..where((t) => t.id.equals(movementId))).getSingle();
    if (m.storeId == null) return;
    await _db.customStatement(
      'INSERT INTO store_products (uuid, store_id, product_id, stock) '
      'VALUES (?, ?, ?, ?) ON CONFLICT (store_id, product_id) '
      'DO UPDATE SET stock = stock + ?',
      [newUuid(), m.storeId, m.productId, m.qtyChange, m.qtyChange],
    );
    await _db.sealsDao.resealStoreProduct(m.storeId!, m.productId);
  }

  Future<ReceivedSale> _digestOf(int saleId, String uuid) async {
    final s = await (_db.select(
      _db.sales,
    )..where((t) => t.id.equals(saleId))).getSingle();
    final items = await _db.salesDao.itemsOf(saleId);
    return ReceivedSale(
      uuid: uuid,
      invoice: s.invoiceNo,
      digest: saleDigest(
        uuid: uuid,
        invoiceNo: s.invoiceNo,
        total: s.total,
        items: [
          for (final i in items)
            (
              productId: i.productId,
              qty: i.qty,
              price: i.price,
              subtotal: i.subtotal,
            ),
        ],
      ),
    );
  }

  /// Menghapus data master & transaksi lokal sebelum komputer cabang
  /// mengambil data dari server (pairing pertama). Catatan aktivitas tetap.
  Future<void> wipeForClient() async {
    await _mute();
    await _wipe();
  }

  Future<void> _mute() => _db.customStatement(
    'CREATE TEMP TABLE IF NOT EXISTS sync_mute (x INTEGER)',
  );

  Future<void> _wipe() => _db.transaction(() async {
    await _db.customStatement('INSERT INTO temp.sync_mute VALUES (1)');
    try {
      for (final t in [
        'sale_payments',
        'sale_items',
        'stock_movements',
        'held_carts',
        'sync_outbox',
        'sales',
        'promo_actions',
        'store_unit_prices',
        'price_tiers',
        'product_units',
        'product_tags',
        'store_products',
        'products',
        'categories',
        'tags',
        'units',
        'vouchers',
        'role_permissions',
        'payment_methods',
        'users',
        'stores',
      ]) {
        await _db.customStatement('DELETE FROM $t');
      }
    } finally {
      await _db.customStatement('DELETE FROM temp.sync_mute');
    }
  });
}

/// Faktur yang diterima dari server (untuk catatan aktivitas: pemeriksaan
/// keutuhan tetap bisa mendeteksi faktur kiriman yang diubah setelahnya).
class ReceivedSale {
  const ReceivedSale({
    required this.uuid,
    required this.invoice,
    required this.digest,
  });

  final String uuid;
  final String invoice;
  final String digest;

  Map<String, Object> toJson() => {
    'uuid': uuid,
    'invoice': invoice,
    'digest': digest,
  };
}

class SyncApplied {
  int master = 0;
  int movements = 0;
  int audit = 0;

  /// Belum bisa diterapkan karena rujukannya belum ada; dicoba lagi
  /// bersama halaman berikutnya.
  final deferred = <SyncChange>[];
  String? lastMissing;

  /// Baris master yang diterapkan `(tabel, id)`, untuk disegel ulang.
  final resealed = <(String, int)>{};
  final sales = <ReceivedSale>[];

  int get total => master + movements + audit + sales.length;
}
