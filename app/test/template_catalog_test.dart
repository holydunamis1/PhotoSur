import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/core/theme/app_theme.dart';
import 'package:photosur/core/utils/template_catalog.dart';
import 'package:photosur/generated/l10n/app_localizations.dart';
import 'package:photosur/widgets/editor_tool_dock.dart';

void main() {
  test('template ids are unique and every bundled scene exists', () {
    final ids = kBackgroundTemplates.map((t) => t.id).toSet();
    expect(ids.length, kBackgroundTemplates.length);
    for (final t in kBackgroundTemplates) {
      final f = File(t.asset);
      expect(f.existsSync(), isTrue, reason: t.asset);
      expect(f.lengthSync(), greaterThan(1000), reason: t.asset);
    }
  });

  test('every category has scenes and every featured id exists', () {
    for (final c in TemplateCategory.values) {
      expect(kBackgroundTemplates.where((t) => t.category == c), isNotEmpty);
    }
    for (final id in kFeaturedTemplateIds) {
      expect(templateById(id).id, id);
    }
  });

  test('the bundled scenes stay small (offline, no download)', () {
    final total = kBackgroundTemplates
        .map((t) => File(t.asset).lengthSync())
        .fold<int>(0, (a, b) => a + b);
    expect(total, lessThan(3 * 1024 * 1024));
  });

  for (final code in ['en', 'de', 'ru', 'fil', 'vi', 'ta', 'ar']) {
    testWidgets('dock with five tools fits at 320 dp, large text ($code)',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          locale: Locale(code),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: EditorToolDock(selected: EditorTool.cutout, onSelected: (_) {}),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(InkWell), findsNWidgets(5));
    });
  }
}
