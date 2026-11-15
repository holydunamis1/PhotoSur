import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/core/models/export_job.dart';
import 'package:photosur/core/providers/image_edit_provider.dart';
import 'package:photosur/core/providers/settings_provider.dart';
import 'package:photosur/core/providers/subscription_provider.dart';
import 'package:photosur/core/providers/theme_provider.dart';
import 'package:photosur/core/theme/app_theme.dart';
import 'package:photosur/generated/l10n/app_localizations.dart';
import 'package:photosur/screens/batch_screen.dart';
import 'package:photosur/screens/export_viewer_screen.dart';
import 'package:photosur/widgets/editor_tool_dock.dart';
import 'package:photosur/widgets/editor_tool_panel.dart';
import 'package:provider/provider.dart';

/// Editor tool panels, the batch screen and the export viewer, in every
/// shipped language at 320 dp and 1.3x text. Complements the sweep in
/// locale_overflow_sweep_test.dart, which covers the other screens.
Widget _host(Locale locale, double scale, Widget home) {
  Provider.debugCheckInvalidValueType = null;
  final settings = SettingsProvider();
  return MultiProvider(
    providers: [
      Provider<ImageEditProvider>.value(value: ImageEditProvider()),
      Provider<ThemeProvider>.value(value: ThemeProvider()),
      Provider<SettingsProvider>.value(value: settings),
      Provider<SubscriptionProvider>.value(value: SubscriptionProvider(settings)),
    ],
    child: MaterialApp(
      theme: buildAppTheme(Brightness.light),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    ),
  );
}

ExportJob _job(String id) => ExportJob(
      id: id,
      format: ExportFormat.png,
      quality: 100,
      width: 1600,
      height: 1200,
      resizeMode: ResizeMode.original,
      filePath: '${Directory.systemTemp.path}/missing_$id.png',
      status: ExportStatus.complete,
      createdAt: DateTime(2026, 10, 15),
    );

Future<List<String>> _pumpCollect(
    WidgetTester tester, Locale locale, double scale, Widget home) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(320, 640);
  addTearDown(tester.view.reset);
  final errors = <String>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (d) => errors.add(d.exceptionAsString().split('\n').first);
  addTearDown(() => FlutterError.onError = prev);
  await tester.pumpWidget(_host(locale, scale, home));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 31));
  FlutterError.onError = prev;
  return errors;
}

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    for (final tool in EditorTool.values) {
      testWidgets('$locale 1.3x ${tool.name} panel: no overflow', (tester) async {
        final errors = await _pumpCollect(
          tester,
          locale,
          1.3,
          Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: EditorToolPanel(tool: tool),
            ),
          ),
        );
        expect(errors, isEmpty);
      });
    }
  }

  for (final code in ['en', 'de', 'ru', 'ar', 'hi', 'th', 'fil', 'vi']) {
    final locale = Locale(code);
    testWidgets('$code 1.3x batch screen: no overflow', (tester) async {
      final errors = await _pumpCollect(
        tester,
        locale,
        1.3,
        const BatchScreen(imagePaths: ['/a.jpg', '/b.jpg', '/c.jpg']),
      );
      expect(errors, isEmpty);
    });

    testWidgets('$code 1.3x export viewer: no overflow', (tester) async {
      final errors = await _pumpCollect(
        tester,
        locale,
        1.3,
        ExportViewerScreen(
          args: ExportViewerArgs(jobs: [_job('a'), _job('b')], index: 0),
        ),
      );
      expect(errors, isEmpty);
    });
  }
}
