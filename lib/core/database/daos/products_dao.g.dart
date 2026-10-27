// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'products_dao.dart';

// ignore_for_file: type=lint
mixin _$ProductsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CategoriesTable get categories => attachedDatabase.categories;
  $UnitsTable get units => attachedDatabase.units;
  $ProductsTable get products => attachedDatabase.products;
  $StoresTable get stores => attachedDatabase.stores;
  $UsersTable get users => attachedDatabase.users;
  $VouchersTable get vouchers => attachedDatabase.vouchers;
  $PaymentMethodsTable get paymentMethods => attachedDatabase.paymentMethods;
  $SalesTable get sales => attachedDatabase.sales;
  $SaleItemsTable get saleItems => attachedDatabase.saleItems;
  $StockMovementsTable get stockMovements => attachedDatabase.stockMovements;
  $StoreProductsTable get storeProducts => attachedDatabase.storeProducts;
  $TagsTable get tags => attachedDatabase.tags;
  $ProductTagsTable get productTags => attachedDatabase.productTags;
  $ProductUnitsTable get productUnits => attachedDatabase.productUnits;
  $PriceTiersTable get priceTiers => attachedDatabase.priceTiers;
  $StoreUnitPricesTable get storeUnitPrices => attachedDatabase.storeUnitPrices;
  ProductsDaoManager get managers => ProductsDaoManager(this);
}

class ProductsDaoManager {
  final _$ProductsDaoMixin _db;
  ProductsDaoManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$UnitsTableTableManager get units =>
      $$UnitsTableTableManager(_db.attachedDatabase, _db.units);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$StoresTableTableManager get stores =>
      $$StoresTableTableManager(_db.attachedDatabase, _db.stores);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$VouchersTableTableManager get vouchers =>
      $$VouchersTableTableManager(_db.attachedDatabase, _db.vouchers);
  $$PaymentMethodsTableTableManager get paymentMethods =>
      $$PaymentMethodsTableTableManager(
        _db.attachedDatabase,
        _db.paymentMethods,
      );
  $$SalesTableTableManager get sales =>
      $$SalesTableTableManager(_db.attachedDatabase, _db.sales);
  $$SaleItemsTableTableManager get saleItems =>
      $$SaleItemsTableTableManager(_db.attachedDatabase, _db.saleItems);
  $$StockMovementsTableTableManager get stockMovements =>
      $$StockMovementsTableTableManager(
        _db.attachedDatabase,
        _db.stockMovements,
      );
  $$StoreProductsTableTableManager get storeProducts =>
      $$StoreProductsTableTableManager(_db.attachedDatabase, _db.storeProducts);
  $$TagsTableTableManager get tags =>
      $$TagsTableTableManager(_db.attachedDatabase, _db.tags);
  $$ProductTagsTableTableManager get productTags =>
      $$ProductTagsTableTableManager(_db.attachedDatabase, _db.productTags);
  $$ProductUnitsTableTableManager get productUnits =>
      $$ProductUnitsTableTableManager(_db.attachedDatabase, _db.productUnits);
  $$PriceTiersTableTableManager get priceTiers =>
      $$PriceTiersTableTableManager(_db.attachedDatabase, _db.priceTiers);
  $$StoreUnitPricesTableTableManager get storeUnitPrices =>
      $$StoreUnitPricesTableTableManager(
        _db.attachedDatabase,
        _db.storeUnitPrices,
      );
}
