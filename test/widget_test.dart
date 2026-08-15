import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_barcode_counter/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('home screen shows session entry point', (tester) async {
    await tester.pumpWidget(const InventoryCounterApp(showAds: false));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('재고 실사 바코드 카운터'), findsOneWidget);
    expect(find.text('새 실사 시작'), findsOneWidget);
  });
}
