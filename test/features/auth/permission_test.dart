import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/core/database/tables/audit.dart';
import 'package:toko/core/router/routes.dart';
import 'package:toko/features/audit/data/integrity_service.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/data/role_permission_repository.dart';
import 'package:toko/features/auth/domain/app_user.dart';
import 'package:toko/features/auth/domain/permission.dart';
import 'package:toko/features/auth/domain/user_role.dart';
import 'package:toko/features/payments/data/payment_method_repository.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/sales/data/checkout_service.dart';
import 'package:toko/features/sales/data/held_cart_repository.dart';
import 'package:toko/features/sales/data/return_service.dart';
import 'package:toko/features/sales/domain/cart.dart';
import 'package:toko/features/stock/data/stock_repository.dart';
import 'package:toko/features/stock/domain/stock_adjustment.dart';
import 'package:toko/features/vouchers/data/voucher_repository.dart';
import 'package:toko/features/vouchers/domain/voucher.dart';

import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late AuthRepository auth;
  late AppUser admin;
  late int store;

  setUpAll(() => initializeDateFormatting('id_ID'));

  setUp(() async {
    db = await createSeededDb();
    auth = AuthRepository(db, testHasher);
    admin = await auth.login('admin', 'admin123');
    store = await mainStoreId(db);
  });
  tearDown(() => db.close());

  RolePermissionRepository repo() => RolePermissionRepository(db);
  Future<AppUser> kasir() => auth.login('kasir', 'kasir123');

  Future<void> setKasir(Permission p, bool granted) => repo().set(
    actor: admin,
    role: UserRole.kasir,
    permission: p,
    granted: granted,
  );

  test(
    'database baru: hak bawaan = perilaku lama; admin selalu semua',
    () async {
      final all = await repo().watchAll().first;
      expect(all[UserRole.kasir], PermissionRules.defaults(UserRole.kasir));
      expect(
        all[UserRole.supervisor],
        PermissionRules.defaults(UserRole.supervisor),
      );

      final k = await kasir();
      expect(k.canAccess(AppRoutes.kasir), isTrue);
      expect(k.canAccess(AppRoutes.pengaturan), isTrue);
      expect(k.canAccess(AppRoutes.laporan), isFalse);
      expect(k.canAccess(AppRoutes.stok), isFalse);
      expect(k.can(Permission.openDrawer), isTrue);
      expect(k.can(Permission.returnSale), isFalse);

      expect(admin.permissions, isEmpty); // tidak perlu dimuat
      for (final p in Permission.values) {
        expect(admin.can(p), isTrue);
      }
      expect(admin.canAccess(AppRoutes.hakAkses), isTrue);
    },
  );

  test('admin memberi kasir Laporan & Dashboard: berlaku saat login '
      'berikutnya, tercatat di aktivitas', () async {
    await setKasir(Permission.viewReports, true);
    await setKasir(Permission.viewDashboard, true);
    final k = await kasir();
    expect(k.canAccess(AppRoutes.laporan), isTrue);
    expect(k.canAccess(AppRoutes.dashboard), isTrue);
    // Halaman admin lain tetap tertutup.
    expect(k.canAccess(AppRoutes.produk), isFalse);
    expect(k.canAccess(AppRoutes.kelolaAkun), isFalse);

    final log = await (db.select(
      db.auditLog,
    )..where((a) => a.type.equalsValue(AuditType.permissionsChanged))).get();
    expect(log.map((a) => a.summary), [
      'Kasir: Laporan diizinkan',
      'Kasir: Dashboard diizinkan',
    ]);

    await repo().resetDefaults(actor: admin, role: UserRole.kasir);
    expect((await kasir()).canAccess(AppRoutes.laporan), isFalse);
  });

  test('ubah stok butuh halaman Stok (menyala/mati bersama)', () async {
    await setKasir(Permission.adjustStock, true);
    var k = await kasir();
    expect(k.can(Permission.viewStock), isTrue);
    expect(k.canAdjustStockAt(store), isTrue);
    expect(k.canAdjustStockAt(store + 1), isFalse); // hanya tokonya

    await setKasir(Permission.viewStock, false);
    k = await kasir();
    expect(k.can(Permission.adjustStock), isFalse);
    expect(k.canAccess(AppRoutes.stok), isFalse);
  });

  test('hanya admin yang mengatur; peran admin tidak bisa diatur', () async {
    final k = await kasir();
    expect(
      repo().set(
        actor: k,
        role: UserRole.kasir,
        permission: Permission.viewReports,
        granted: true,
      ),
      throwsA(isA<PermissionFailure>()),
    );
    expect(
      repo().set(
        actor: admin,
        role: UserRole.admin,
        permission: Permission.viewReports,
        granted: false,
      ),
      throwsA(isA<PermissionFailure>()),
    );
  });

  test('hak yang disisipkan di luar aplikasi diabaikan & dilaporkan', () async {
    await db.customStatement(
      "INSERT INTO role_permissions (role, permission, uuid) "
      "VALUES ('kasir', 'returnSale', 'x-1')",
    );
    expect((await kasir()).can(Permission.returnSale), isFalse);
    final issues = (await IntegrityService(db).check()).issues;
    expect(
      issues.map((i) => i.title),
      contains('Hak akses Kasir diubah di luar aplikasi'),
    );
  });

  group('ditegakkan di service, bukan hanya tombol', () {
    Future<Cart> cartOf(String code) async => const Cart().add(
      (await ProductRepository(db).findByCodeOrBarcode(code))!,
    );

    Future<int> tunai() async => (await PaymentMethodRepository(
      db,
    ).watchAll().first).firstWhere((m) => m.name == 'Tunai').id;

    test('retur: kasir diberi hak → bisa retur faktur tokonya', () async {
      final k = await kasir();
      final sold = await CheckoutService(db).checkout(
        cart: await cartOf('BRG001'),
        cashier: k,
        storeId: store,
        paymentMethodId: await tunai(),
        paid: 5000,
      );
      expect(ReturnService.canReturn(k, store), isFalse);
      final sale = await ReturnService(db).load(sold.saleId);
      final all = {for (final l in sale.lines) l.saleItemId: l.returnable};
      expect(
        ReturnService(db)
            .create(actor: k, saleId: sold.saleId, qtys: all, reason: 'x'),
        throwsA(isA<ReturnFailure>()),
      );

      await setKasir(Permission.returnSale, true);
      final k2 = await kasir();
      expect(ReturnService.canReturn(k2, store), isTrue);
      final r = await ReturnService(db)
          .create(actor: k2, saleId: sold.saleId, qtys: all, reason: 'Batal');
      expect(r.refund, 3500);
    });

    test(
      'voucher, transaksi tertahan, dan ubah stok ditolak tanpa hak',
      () async {
        await setKasir(Permission.useVoucher, false);
        await setKasir(Permission.deleteHeldCart, false);
        final k = await kasir();

        await VoucherRepository(db).save(
          actor: admin,
          draft: const VoucherDraft(
            code: 'HEMAT',
            type: VoucherType.amount,
            value: 500,
          ),
        );
        final v = await VoucherRepository(db)
            .findUsable('HEMAT', storeId: store);
        expect(
          CheckoutService(db).checkout(
            cart: (await cartOf('BRG001')).withVoucher(v),
            cashier: k,
            storeId: store,
            paymentMethodId: await tunai(),
            paid: 5000,
          ),
          throwsA(isA<CheckoutFailure>()),
        );

        final held = HeldCartRepository(db);
        await held.hold(
          cart: await cartOf('BRG001'),
          cashier: k,
          storeId: store,
        );
        final id = (await db.select(db.heldCarts).getSingle()).id;
        expect(held.delete(id, actor: k), throwsA(isA<HeldCartFailure>()));
        await held.delete(id, actor: admin);
        expect(await db.select(db.heldCarts).get(), isEmpty);

        expect(k.canAdjustStockAt(store), isFalse);
        final indomie = (await ProductRepository(db)
            .findByCodeOrBarcode('BRG001'))!;
        expect(
          StockRepository(db).adjust(
            actor: k,
            storeId: store,
            productId: indomie.id,
            mode: StockAdjustMode.receive,
            qty: 5,
          ),
          throwsA(isA<StockFailure>()),
        );
      },
    );
  });

  test('migrasi v13 → v14: hak bawaan dibuat & disegel', () async {
    final schema = File('test/fixtures/schema_v13.sql').readAsStringSync();
    final old = AppDatabase(
      NativeDatabase.memory(
        setup: (Database raw) {
          for (final stmt in schema.split(';\n')) {
            if (stmt.trim().isNotEmpty) raw.execute(stmt);
          }
          raw.userVersion = 13;
        },
      ),
    );
    addTearDown(old.close);
    final all = await RolePermissionRepository(old).watchAll().first;
    expect(all[UserRole.kasir], PermissionRules.defaults(UserRole.kasir));
    expect(
      all[UserRole.supervisor],
      PermissionRules.defaults(UserRole.supervisor),
    );
  });
}
