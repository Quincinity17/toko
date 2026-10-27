/// Protokol sinkron aplikasi kasir ↔ server (HTTP + JSON). Murni Dart
/// (tanpa Flutter) supaya dipakai bersama oleh aplikasi dan `toko_server`.
library;

/// Jenis data yang disinkron. Nama = nilai `entity` di JSON dan di
/// `sync_outbox.entity`.
enum SyncEntity {
  // Data master: hanya dikirim komputer server (master), urutan = urutan
  // terapkan (yang dirujuk lebih dulu).
  store(master: true),
  user(master: true),
  unit(master: true),
  tag(master: true),
  paymentMethod(master: true),
  voucher(master: true),
  rolePermission(master: true),
  product(master: true),
  productTag(master: true),
  productUnit(master: true),
  priceTier(master: true),
  storeProduct(master: true),
  storeUnitPrice(master: true),

  // Transaksi: dikirim semua komputer, tidak pernah diubah setelah dibuat.
  sale(master: false),
  stockMovement(master: false),

  /// Catatan aktivitas (anti-kecurangan). Hanya diteruskan server ke
  /// komputer master.
  auditEntry(master: false);

  const SyncEntity({required this.master});

  /// Data master (satu penulis: komputer server).
  final bool master;

  static SyncEntity? byName(String? name) => _byName[name];
  static final _byName = {for (final e in values) e.name: e};
}

/// Peran komputer di sinkron.
enum SyncRole {
  /// Komputer server/master: satu-satunya yang mengubah data master.
  master,

  /// Komputer kasir cabang.
  client,
}

/// Satu perubahan. [data] `null` = baris dihapus (hanya data master).
class SyncChange {
  const SyncChange({
    required this.entity,
    required this.uuid,
    this.data,
    this.seq,
    this.origin,
  });

  final SyncEntity entity;
  final String uuid;
  final Map<String, Object?>? data;

  /// Nomor urut di server (hanya saat ditarik).
  final int? seq;

  /// ID terminal pengirim (hanya saat ditarik).
  final String? origin;

  bool get deleted => data == null;

  Map<String, Object?> toJson() => {
    'entity': entity.name,
    'uuid': uuid,
    'data': data,
    'seq': ?seq,
    'origin': ?origin,
  };

  static SyncChange fromJson(Map<String, Object?> json) {
    final entity = SyncEntity.byName(json['entity'] as String?);
    final uuid = json['uuid'];
    if (entity == null || uuid is! String || uuid.isEmpty) {
      throw const SyncProtocolError('Data sinkron tidak dikenal.');
    }
    return SyncChange(
      entity: entity,
      uuid: uuid,
      data: (json['data'] as Map?)?.cast<String, Object?>(),
      seq: json['seq'] as int?,
      origin: json['origin'] as String?,
    );
  }
}

class SyncProtocolError implements Exception {
  const SyncProtocolError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Alamat & nama di protokol.
abstract final class SyncApi {
  static const defaultPort = 8787;
  static const serverName = 'toko-server';

  /// Versi protokol; server menolak klien dengan versi lain.
  static const version = 1;

  static const health = '/health';
  static const pair = '/pair';
  static const push = '/push';
  static const pull = '/pull';
  static const status = '/status';

  /// Batas perubahan per permintaan.
  static const pageSize = 500;

  /// `192.168.1.10` / `toko-pusat:8787` / `http://…` → URL dasar.
  static Uri? parseAddress(String text) {
    var t = text.trim();
    if (t.isEmpty) return null;
    if (!t.contains('://')) t = 'http://$t';
    final uri = Uri.tryParse(t);
    if (uri == null || uri.host.isEmpty) return null;
    return uri.replace(
      port: uri.hasPort ? uri.port : defaultPort,
      path: '',
      query: null,
      fragment: null,
    );
  }
}
