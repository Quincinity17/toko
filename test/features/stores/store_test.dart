import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/data/user_repository.dart';
import 'package:toko/features/auth/domain/app_user.dart';
import 'package:toko/features/auth/domain/permission.dart';
import 'package:toko/features/auth/domain/user_role.dart';
import 'package:toko/features/payments/data/payment_method_repository.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/products/domain/product.dart';
import 'package:toko/features/reports/data/report_repository.dart';
import 'package:toko/features/reports/domain/report_models.dart';
import 'package:toko/features/sales/data/checkout_service.dart';
import 'package:toko/features/sales/domain/cart.dart';
import 'package:toko/features/stock/data/stock_repository.dart';
import 'package:toko/features/stock/domain/stock_adjustment.dart';
import 'package:toko/features/stores/data/store_repository.dart';

import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late StoreRepository stores;
  late ProductRepository products;
  late AppUser admin;
  late AppUser kasirA;
  late int storeA;
  late int storeB;

  setUpAll(() => initializeDateFormatting('id_ID'));

  setUp(() async {
    db = await createSeededDb();
    stores = StoreRepository(db);
    products = ProductRepository(db);
    final auth = AuthRepository(db, testHasher);
    admin = await auth.login('admin', 'admin123');
    kasirA = await auth.login('kasir', 'kasir123');
    storeA = await mainStoreId(db);
    storeB = (await stores.save(actor: admin, name: 'Cabang Pasar')).id;
  });

  tearDown(() => db.close());

  /// Akun baru di toko [storeId] yang sudah login.
  Future<AppUser> account(String username, UserRole role, int? storeId) async {
    await UserRepository(db, testHasher).create(
      actor: admin,
      username: username,
      fullName: username,
      role: role,
      storeId: storeId,
      password: 'rahasia1',
    );
    return AuthRepository(db, testHasher).login(username, 'rahasia1');
  }

  Future<int> stockAt(int storeId, String code) async {
    final p = (await products.findByCodeOrBarcode(code, storeId: storeId))!;
    return p.stock.round();
  }

  group('kelola toko', () {
    test('data lama masuk Toko Utama; nama toko unik', () async {
      final all = await stores.watchAll().first;
      expect(
        all.map((s) => s.name),
        containsAll(['Toko Utama', 'Cabang Pasar']),
      );
      expect(kasirA.storeId, storeA);
      expect(admin.storeId, isNull);
      expect(
        stores.save(actor: admin, name: 'cabang pasar'),
        throwsA(isA<StoreFailure>()),
      );
      expect(
        stores.save(actor: kasirA, name: 'Toko Baru'),
        throwsA(isA<StoreFailure>()),
      );
    });

    test(
      'minimal satu toko aktif; toko terpakai hanya dinonaktifkan',
      () async {
        expect(
          await stores.remove(actor: admin, id: storeB),
          StoreRemoval.deleted,
        );
        expect(
          stores.remove(actor: admin, id: storeA),
          throwsA(isA<StoreFailure>()),
        );
        final c = await stores.save(actor: admin, name: 'Cabang C');
        expect(
          await stores.remove(actor: admin, id: storeA),
          StoreRemoval.deactivated,
        );
        expect((await stores.findById(storeA))!.isActive, isFalse);
        expect((await stores.findById(c.id))!.isActive, isTrue);
      },
    );

    test('akun toko nonaktif tidak bisa login', () async {
      await stores.save(actor: admin, name: 'Cabang C');
      await stores.save(
        actor: admin,
        id: storeA,
        name: 'Toko Utama',
        isActive: false,
      );
      expect(
        AuthRepository(db, testHasher).login('kasir', 'kasir123'),
        throwsA(isA<AuthFailure>()),
      );
      // Admin tidak terikat toko.
      await AuthRepository(db, testHasher).login('admin', 'admin123');
    });
  });

  group('akun', () {
    test('supervisor & kasir wajib punya toko, admin tidak', () async {
      expect(
        account('siti', UserRole.kasir, null),
        throwsA(
          isA<AccountFailure>().having(
            (e) => e.message,
            'message',
            contains('toko'),
          ),
        ),
      );
      final admin2 = await account('admin2', UserRole.admin, storeB);
      expect(admin2.storeId, isNull);
      final spv = await account('budi', UserRole.supervisor, storeB);
      expect(spv.storeId, storeB);
    });

    test('hak akses supervisor: Kasir dan Stok saja', () {
      expect(_withDefaults(UserRole.supervisor).canAccess('/kasir'), isTrue);
      expect(_withDefaults(UserRole.supervisor).canAccess('/stok'), isTrue);
      expect(_withDefaults(UserRole.supervisor).canAccess('/produk'), isFalse);
      expect(_withDefaults(UserRole.supervisor).canAccess('/laporan'), isFalse);
      expect(_withDefaults(UserRole.kasir).canAccess('/stok'), isFalse);
    });
  });

  group('stok & harga per toko', () {
    test('harga khusus toko dan stok terpisah', () async {
      final indomie = (await products.findByCodeOrBarcode('BRG001'))!;
      await products.save(
        actor: admin,
        id: indomie.id,
        draft: ProductDraft(
          code: indomie.code,
          barcode: indomie.barcode,
          name: indomie.name,
          unitName: indomie.unitName,
          purchasePrice: indomie.purchasePrice,
          sellingPrice: 3500,
        ),
        stores: [StoreProductValues(storeId: storeB, stock: 30, price: 4000)],
      );

      final atA = (await products.findByCodeOrBarcode(
        'BRG001',
        storeId: storeA,
      ))!;
      final atB = (await products.findByCodeOrBarcode(
        'BRG001',
        storeId: storeB,
      ))!;
      expect(atA.sellingPrice, 3500);
      expect(atA.stock, 120);
      expect(atB.sellingPrice, 4000);
      expect(atB.hasStorePrice, isTrue);
      expect(atB.stock, 30);
      // Semua toko: stok dijumlah, harga default.
      final all = (await products.findByCodeOrBarcode('BRG001'))!;
      expect(all.stock, 150);
      expect(all.sellingPrice, 3500);
    });

    test('checkout mengurangi stok toko itu saja; kasir tidak bisa '
        'berjualan di toko lain', () async {
      final tunai = (await PaymentMethodRepository(db).watchAll().first).first;
      final kasirB = await account('kasirb', UserRole.kasir, storeB);
      await StockRepository(db).adjust(
        actor: admin,
        storeId: storeB,
        productId: (await products.findByCodeOrBarcode('BRG001'))!.id,
        mode: StockAdjustMode.receive,
        qty: 10,
      );
      final atB = (await products.findByCodeOrBarcode(
        'BRG001',
        storeId: storeB,
      ))!;

      await CheckoutService(db).checkout(
        cart: const Cart().add(atB, qty: 4),
        cashier: kasirB,
        storeId: storeB,
        paymentMethodId: tunai.id,
        paid: 100000,
      );
      expect(await stockAt(storeB, 'BRG001'), 6);
      expect(await stockAt(storeA, 'BRG001'), 120);
      final sale = await db.select(db.sales).getSingle();
      expect(sale.storeId, storeB);

      expect(
        CheckoutService(db).checkout(
          cart: const Cart().add(atB),
          cashier: kasirA,
          storeId: storeB,
          paymentMethodId: tunai.id,
          paid: 100000,
        ),
        throwsA(isA<CheckoutFailure>()),
      );

      // Laporan per toko vs semua toko.
      final today = ReportRange.preset(RangePreset.today, DateTime.now());
      expect(
        (await ReportRepository(db, storeId: storeB).summary(today))
            .transactions,
        1,
      );
      expect(
        (await ReportRepository(db, storeId: storeA).summary(today))
            .transactions,
        0,
      );
      expect((await ReportRepository(db).summary(today)).revenue, 14000);
    });
  });

  group('halaman Stok', () {
    test(
      'supervisor mengubah stok tokonya sendiri; kasir tidak bisa',
      () async {
        final spv = await account('budi', UserRole.supervisor, storeA);
        final repo = StockRepository(db);
        final aqua = (await products.findByCodeOrBarcode('BRG009'))!;

        // Barang masuk, keluar, lalu opname.
        expect(
          await repo.adjust(
            actor: spv,
            storeId: storeA,
            productId: aqua.id,
            mode: StockAdjustMode.receive,
            qty: 12,
            note: 'kiriman supplier',
          ),
          await stockAt(storeA, 'BRG009'),
        );
        final before = await stockAt(storeA, 'BRG009');
        await repo.adjust(
          actor: spv,
          storeId: storeA,
          productId: aqua.id,
          mode: StockAdjustMode.remove,
          qty: 2,
        );
        expect(await stockAt(storeA, 'BRG009'), before - 2);
        await repo.adjust(
          actor: spv,
          storeId: storeA,
          productId: aqua.id,
          mode: StockAdjustMode.count,
          qty: 50,
        );
        expect(await stockAt(storeA, 'BRG009'), 50);

        final history = await repo.watchHistory(storeA, aqua.id).first;
        expect(history.first.note, 'Stok Opname');
        expect(history.first.userName, 'budi');
        expect(history[2].note, 'Barang Masuk: kiriman supplier');

        expect(
          repo.adjust(
            actor: spv,
            storeId: storeB,
            productId: aqua.id,
            mode: StockAdjustMode.receive,
            qty: 1,
          ),
          throwsA(isA<StockFailure>()),
        );
        expect(
          repo.adjust(
            actor: kasirA,
            storeId: storeA,
            productId: aqua.id,
            mode: StockAdjustMode.receive,
            qty: 1,
          ),
          throwsA(isA<StockFailure>()),
        );
      },
    );

    test('stok toko lain tidak berubah', () async {
      final aqua = (await products.findByCodeOrBarcode('BRG009'))!;
      await StockRepository(db).adjust(
        actor: admin,
        storeId: storeB,
        productId: aqua.id,
        mode: StockAdjustMode.count,
        qty: 7,
      );
      expect(await stockAt(storeB, 'BRG009'), 7);
      expect(await stockAt(storeA, 'BRG009'), aqua.stock.round());
      final row =
          await (db.select(db.storeProducts)..where(
                (s) => s.storeId.equals(storeB) & s.productId.equals(aqua.id),
              ))
              .getSingle();
      expect(row.sellingPrice, isNull);
      expect(row.stock, 7);
    });
  });
}

/// User dengan hak akses bawaan perannya (= perilaku sebelum bisa diatur).
AppUser _withDefaults(UserRole role) => AppUser(
  id: 1,
  username: 'u',
  fullName: 'U',
  role: role,
  permissions: PermissionRules.defaults(role),
);
