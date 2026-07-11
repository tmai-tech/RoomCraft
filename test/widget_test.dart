import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:room_craft/config/app_config.dart';
import 'package:room_craft/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      AppConfig.onboardingDoneKey: true,
      AppConfig.betaBannerDismissedKey: true,
    });
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

    await tester.tap(find.widgetWithText(ListTile, 'Draw manually'));
    await tester.pumpAndSettle();

    expect(find.text('Pan'), findsOneWidget);
    expect(find.text('Select'), findsOneWidget);
    expect(find.text('Wall'), findsOneWidget);
  });

  testWidgets('Onboarding shows when not completed', (tester) async {
    SharedPreferences.setMockInitialValues({
      AppConfig.onboardingDoneKey: false,
    });
    await tester.pumpWidget(
      const ProviderScope(child: RoomCraftApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Scan your room'), findsOneWidget);
    expect(find.text('Get started'), findsNothing); // page 0 has Next
    expect(find.text('Next'), findsOneWidget);
  });
}
