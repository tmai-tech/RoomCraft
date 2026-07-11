import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:room_craft/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Home screen loads RoomCraft', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: RoomCraftApp()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('RoomCraft'), findsWidgets);
    expect(find.text('New Blueprint'), findsOneWidget);
  });

  testWidgets('Open manual blueprint editor', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: RoomCraftApp()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Blueprint'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Manually Enter (Draw)'));
    await tester.pumpAndSettle();

    expect(find.text('Pan'), findsOneWidget);
    expect(find.text('Select'), findsOneWidget);
    expect(find.text('Wall'), findsOneWidget);
  });
}
