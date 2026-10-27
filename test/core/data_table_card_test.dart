import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toko/core/theme/app_theme.dart';
import 'package:toko/core/widgets/data_table_card.dart';

void main() {
  Future<void> pump(WidgetTester tester, double width) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: const DataTableCard(
              columns: [
                TableColumnSpec('Akun', flex: 2),
                TableColumnSpec.number('Batal transaksi', width: 130),
                TableColumnSpec.number('Retur', width: 120),
              ],
              rows: [
                TableRowData([
                  CellText('Kasir Satu'),
                  CellText('3', number: true),
                  CellText('1', number: true),
                ]),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('layar sempit: tabel digeser ke kanan, kolom tidak dijepit', (
    tester,
  ) async {
    await pump(tester, 320);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    // Kolom "Akun" tetap selebar minimalnya (2 × 140), bukan dijepit.
    expect(
      tester.getSize(find.text('Kasir Satu')).width,
      lessThan(2 * DataTableCard.flexUnitMinWidth),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('layar lebar: tanpa geser', (tester) async {
    await pump(tester, 900);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });
}
