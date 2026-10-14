import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/generated/l10n/app_localizations.dart';
import 'package:photosur/screens/export_bottom_sheet.dart';

Widget _host() => const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ExportBottomSheet(),
        ),
      ),
    );

bool _selected(WidgetTester tester, String label) => tester
    .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
    .selected;

void main() {
  testWidgets('tapping a resize chip selects it and deselects the others',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(_selected(tester, 'Original'), isTrue);

    await tester.tap(find.widgetWithText(ChoiceChip, '1:1'));
    await tester.pump();
    expect(_selected(tester, '1:1'), isTrue);
    expect(_selected(tester, 'Original'), isFalse);

    await tester.tap(find.widgetWithText(ChoiceChip, '9:16'));
    await tester.pump();
    expect(_selected(tester, '9:16'), isTrue);
    expect(_selected(tester, '1:1'), isFalse);
  });

  testWidgets('Custom reveals width and height fields', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Custom'));
    await tester.pump();
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('JPG shows the quality slider, PNG does not', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();
    expect(find.byType(Slider), findsNothing);

    await tester.tap(find.text('JPG'));
    await tester.pump();
    expect(find.byType(Slider), findsOneWidget);

    await tester.tap(find.text('PNG'));
    await tester.pump();
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('buttons stay clear of the system navigation bar',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 900);
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.pump();

    final share = find.byWidgetPredicate((w) => w is OutlinedButton);
    expect(share, findsOneWidget);
    // Bottom edge of the Share button must sit above the 48px nav bar.
    expect(tester.getRect(share).bottom, lessThanOrEqualTo(900 - 48 + 0.5));
  });

  testWidgets('a short screen scrolls instead of overflowing',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 420);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
