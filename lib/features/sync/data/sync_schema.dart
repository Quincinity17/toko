import '../../../sync_protocol/sync_protocol.dart';

/// Baris anak yang ikut dikirim bersama induknya (mis. barang faktur).
class SyncChild {
  const SyncChild({
    required this.key,
    required this.table,
    required this.parentColumn,
    this.refs = const {},
  });

  /// Nama daftar di JSON (mis. `items`).
  final String key;
  final String table;

  /// Kolom yang menunjuk id induk.
  final String parentColumn;

  /// Kolom id → tabel yang dirujuk (dikirim sebagai uuid).
  final Map<String, String> refs;
}

/// Cara menyinkronkan satu [SyncEntity]: tabel, kolom yang tidak dikirim,
/// dan kolom rujukan (id lokal ↔ uuid global).
class SyncTableSpec {
  const SyncTableSpec({
    required this.entity,
    required this.table,
    this.skip = const {},
    this.refs = const {},
    this.children = const [],
    this.conflict = 'uuid',
    this.updateColumns,
    this.applyTo,
    this.lenientRefs = false,
  });

  final SyncEntity entity;

  /// Tabel sumber (dikirim dari sini).
  final String table;

  /// Tabel tujuan saat diterima bila berbeda dari [table].
  final String? applyTo;

  String get applyTable => applyTo ?? table;

  /// Rujukan yang tidak ditemukan diisi `null` (bukan error).
  final bool lenientRefs;

  /// Kolom lokal yang tidak dikirim (selain id & seal).
  final Set<String> skip;
  final Map<String, String> refs;
  final List<SyncChild> children;

  /// Kolom unik untuk upsert.
  final String conflict;

  /// Kolom pemicu "berubah" untuk trigger UPDATE; `null` = tidak dilacak.
  final List<String>? updateColumns;

  static const always = {'id', 'seal'};
}

/// Semua tabel yang disinkron, urut terapkan.
const syncSpecs = <SyncTableSpec>[
  SyncTableSpec(
    entity: SyncEntity.store,
    table: 'stores',
    updateColumns: ['name', 'address', 'receipt_template', 'is_active'],
  ),
  SyncTableSpec(
    entity: SyncEntity.user,
    table: 'users',
    skip: {'last_login_at'},
    refs: {'store_id': 'stores'},
    updateColumns: [
      'username',
      'full_name',
      'password_hash',
      'role',
      'store_id',
      'is_active',
    ],
  ),
  SyncTableSpec(
    entity: SyncEntity.unit,
    table: 'units',
    updateColumns: ['name'],
  ),
  SyncTableSpec(
    entity: SyncEntity.tag,
    table: 'tags',
    updateColumns: ['name', 'color', 'code_prefix', 'code_digits'],
  ),
  SyncTableSpec(
    entity: SyncEntity.paymentMethod,
    table: 'payment_methods',
    updateColumns: ['name', 'kind', 'is_active', 'sort_order'],
  ),
  SyncTableSpec(
    entity: SyncEntity.voucher,
    table: 'vouchers',
    // Kolom kuota lama (DB v3) tidak dipakai.
    skip: {'quota', 'used_count'},
    refs: {'store_id': 'stores'},
    updateColumns: [
      'code',
      'name',
      'type',
      'value',
      'max_discount',
      'min_purchase',
      'start_date',
      'end_date',
      'store_id',
      'is_active',
    ],
  ),
  SyncTableSpec(
    entity: SyncEntity.rolePermission,
    table: 'role_permissions',
    conflict: 'role, permission',
    updateColumns: ['role', 'permission'],
  ),
  SyncTableSpec(
    entity: SyncEntity.product,
    table: 'products',
    // category_id & stock: kolom lama yang tidak dipakai lagi.
    skip: {'category_id', 'stock'},
    refs: {'unit_id': 'units'},
    updateColumns: [
      'code',
      'barcode',
      'name',
      'unit_id',
      'purchase_price',
      'selling_price',
      'min_stock',
      'is_active',
    ],
  ),
  SyncTableSpec(
    entity: SyncEntity.productTag,
    table: 'product_tags',
    refs: {'product_id': 'products', 'tag_id': 'tags'},
    conflict: 'product_id, tag_id',
    updateColumns: [],
  ),
  SyncTableSpec(
    entity: SyncEntity.productUnit,
    table: 'product_units',
    refs: {'product_id': 'products'},
    updateColumns: ['name', 'factor', 'barcode', 'selling_price'],
  ),
  SyncTableSpec(
    entity: SyncEntity.priceTier,
    table: 'price_tiers',
    refs: {'product_id': 'products', 'store_id': 'stores'},
    updateColumns: ['min_qty', 'price', 'store_id'],
  ),
  SyncTableSpec(
    entity: SyncEntity.storeProduct,
    table: 'store_products',
    // Stok tidak dikirim: dihitung dari riwayat stok di tiap komputer.
    skip: {'stock'},
    refs: {'store_id': 'stores', 'product_id': 'products'},
    conflict: 'store_id, product_id',
    updateColumns: ['selling_price'],
  ),
  SyncTableSpec(
    entity: SyncEntity.storeUnitPrice,
    table: 'store_unit_prices',
    refs: {'store_id': 'stores', 'product_unit_id': 'product_units'},
    conflict: 'store_id, product_unit_id',
    updateColumns: ['selling_price'],
  ),
  SyncTableSpec(
    entity: SyncEntity.sale,
    table: 'sales',
    refs: {
      'store_id': 'stores',
      'user_id': 'users',
      'voucher_id': 'vouchers',
      'payment_method_id': 'payment_methods',
      'return_of_id': 'sales',
      'exchange_of_id': 'sales',
    },
    children: [
      SyncChild(
        key: 'items',
        table: 'sale_items',
        parentColumn: 'sale_id',
        refs: {'product_id': 'products', 'return_of_item_id': 'sale_items'},
      ),
      SyncChild(
        key: 'payments',
        table: 'sale_payments',
        parentColumn: 'sale_id',
        refs: {'payment_method_id': 'payment_methods'},
      ),
    ],
  ),
  SyncTableSpec(
    entity: SyncEntity.stockMovement,
    table: 'stock_movements',
    // ref_id = id faktur untuk jenis sale/saleReturn (lihat SyncCodec).
    refs: {'product_id': 'products', 'store_id': 'stores', 'user_id': 'users'},
  ),
  SyncTableSpec(
    entity: SyncEntity.auditEntry,
    table: 'audit_log',
    // Disimpan terpisah di komputer master (rantai segel milik pengirim).
    applyTo: 'remote_audit_log',
    refs: {'user_id': 'users', 'store_id': 'stores'},
    lenientRefs: true,
  ),
];

final syncSpecByEntity = {for (final s in syncSpecs) s.entity: s};

/// Trigger sementara (per koneksi) yang mengantrikan perubahan data ke
/// `sync_outbox`. Faktur diantrikan oleh kodenya sendiri (checkout/retur).
/// Saat menerapkan data dari server, `temp.sync_mute` diisi supaya data itu
/// tidak dikirim balik.
List<String> syncTriggerStatements() {
  final out = <String>['CREATE TEMP TABLE IF NOT EXISTS sync_mute (x INTEGER)'];
  String insert(String entity, String row) =>
      'INSERT INTO main.sync_outbox (entity, entity_uuid, created_at, '
      "attempts) VALUES ('$entity', $row.uuid, "
      "CAST(strftime('%s', 'now') AS INTEGER), 0)";
  const when = 'WHEN NOT EXISTS (SELECT 1 FROM temp.sync_mute)';
  for (final s in syncSpecs) {
    if (s.entity == SyncEntity.sale) continue;
    final name = s.entity.name;
    out.add(
      'CREATE TEMP TRIGGER IF NOT EXISTS sync_${name}_ai AFTER INSERT ON '
      'main.${s.table} $when AND NEW.uuid IS NOT NULL '
      'BEGIN ${insert(name, 'NEW')}; END',
    );
    if (!s.entity.master) continue;
    final cols = s.updateColumns;
    if (cols != null && cols.isNotEmpty) {
      out.add(
        'CREATE TEMP TRIGGER IF NOT EXISTS sync_${name}_au AFTER UPDATE OF '
        '${cols.join(', ')} ON main.${s.table} $when AND NEW.uuid IS NOT NULL '
        'BEGIN ${insert(name, 'NEW')}; END',
      );
    }
    out.add(
      'CREATE TEMP TRIGGER IF NOT EXISTS sync_${name}_ad AFTER DELETE ON '
      'main.${s.table} $when AND OLD.uuid IS NOT NULL '
      'BEGIN ${insert(name, 'OLD')}; END',
    );
  }
  return out;
}

List<String> dropSyncTriggerStatements() => [
  for (final s in syncSpecs)
    for (final suffix in ['ai', 'au', 'ad'])
      'DROP TRIGGER IF EXISTS temp.sync_${s.entity.name}_$suffix',
];
