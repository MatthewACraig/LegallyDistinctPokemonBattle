import 'package:flutter_test/flutter_test.dart';

import 'package:legally_distinct_pokemon_battle/main.dart';

void main() {
  testWidgets('Battle screen renders expected controls', (WidgetTester tester) async {
    await tester.pumpWidget(const BattleGameApp(enableHardware: false));

    expect(find.text('Legally Distinct Battle'), findsOneWidget);
    expect(find.text('Quick Jab'), findsOneWidget);
    expect(find.text('Plasma Bolt'), findsOneWidget);
    expect(find.text('Guard Break'), findsOneWidget);
    expect(find.text('Reset Battle'), findsOneWidget);
  });
}
