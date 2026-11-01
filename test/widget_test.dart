import 'package:crossdrop/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home shows Receive and Send', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CrossDropApp()));
    expect(find.text('Receive'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
  });
}
