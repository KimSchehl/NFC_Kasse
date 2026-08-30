import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_kasse_app/widgets/arm_confirm_button.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('first tap arms the button without confirming', (tester) async {
    var confirmed = false;
    await tester.pumpWidget(_wrap(ArmConfirmButton(onConfirmed: () async => confirmed = true)));

    expect(find.text('Fertig'), findsOneWidget);

    await tester.tap(find.byType(ArmConfirmButton));
    await tester.pump();

    expect(find.text('Wirklich fertig?'), findsOneWidget);
    expect(confirmed, isFalse);
  });

  testWidgets('second tap while armed confirms', (tester) async {
    var confirmed = false;
    await tester.pumpWidget(_wrap(ArmConfirmButton(onConfirmed: () async => confirmed = true)));

    await tester.tap(find.byType(ArmConfirmButton));
    await tester.pump();
    await tester.tap(find.byType(ArmConfirmButton));
    await tester.pump();

    expect(confirmed, isTrue);
  });

  testWidgets('reverts to idle label if not confirmed within armedDuration', (tester) async {
    await tester.pumpWidget(_wrap(ArmConfirmButton(
      armedDuration: const Duration(seconds: 3),
      onConfirmed: () async {},
    )));

    await tester.tap(find.byType(ArmConfirmButton));
    await tester.pump();
    expect(find.text('Wirklich fertig?'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Fertig'), findsOneWidget);
  });

  testWidgets('disposing while armed does not throw (timer is cancelled)', (tester) async {
    await tester.pumpWidget(_wrap(ArmConfirmButton(onConfirmed: () async {})));
    await tester.tap(find.byType(ArmConfirmButton));
    await tester.pump();

    // Replaces the whole tree, disposing ArmConfirmButton while its
    // auto-revert timer is still pending. If dispose() didn't cancel it,
    // the timer would later call setState() on a disposed State and this
    // test would fail when the pump below flushes it.
    await tester.pumpWidget(_wrap(const SizedBox()));
    await tester.pump(const Duration(seconds: 4));
  });
}
