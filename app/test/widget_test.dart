// Session 0 smoke test: the app boots and renders the Hebrew home screen.

import 'package:flutter_test/flutter_test.dart';

import 'package:restaurant_nutrition_app/main.dart';

void main() {
  testWidgets('App boots and shows the welcome screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const RestaurantNutritionApp());

    // Welcome copy and the connectivity-test button are present.
    expect(find.text('ברוכים הבאים 👋'), findsOneWidget);
    expect(find.text('בדיקת חיבור ל-Supabase'), findsOneWidget);
  });
}
