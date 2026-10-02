import 'package:drift/drift.dart';

import 'stores.dart';
import 'users.dart';

/// Transaksi yang ditahan kasir (pelanggan masih lihat-lihat) agar antrian
/// berikutnya bisa dilayani. Hanya milik komputer ini (tidak disinkron) dan
/// hanya berlaku hari itu; yang lebih lama dihapus otomatis.
@DataClassName('HeldCartRow')
class HeldCarts extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Kasir yang menahan.
  IntColumn get userId => integer().references(Users, #id)();

  /// v6: toko tempat transaksi ditahan (harga & stok mengikuti toko ini).
  IntColumn get storeId => integer().nullable().references(Stores, #id)();

  /// Catatan bebas, mis. "Ibu baju merah".
  TextColumn get note => text().nullable()();

  /// Isi keranjang dalam JSON: `[{"id":1,"code":"..","name":"..","qty":2}]`.
  /// Harga tidak disimpan; saat dilanjutkan memakai harga barang terbaru.
  TextColumn get items => text()();

  /// Salinan untuk daftar, tanpa perlu membaca [items].
  IntColumn get itemCount => integer()();
  IntColumn get total => integer()();
  DateTimeColumn get createdAt => dateTime()();
}
