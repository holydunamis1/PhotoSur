// Measurement only (no assertions): prints the natural height of the
// Background tool's content so the panel height can be chosen from numbers.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katharerase/core/providers/image_edit_provider.dart';
import 'package:katharerase/core/theme/app_theme.dart';
import 'package:katharerase/generated/l10n/app_localizations.dart';
import 'package:katharerase/widgets/background_selector.dart';
import 'package:provider/provider.dart';

Future<double> _measure(
  WidgetTester tester,
  String code,
  double width,
  double scale,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Provider<ImageEditProvider>.value(
      value: ImageEditProvider(),
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        locale: Locale(code),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsetsDirectional.fromSTEB(16, 8, 12, 4),
            child: BackgroundSelector(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.getSize(find.byType(BackgroundSelector)).height;
}

void main() {
  setUpAll(() => Provider.debugCheckInvalidValueType = null);

  testWidgets('MEASURE summary', (tester) async {
    final out = <String>[];
    for (final code in ['en', 'de', 'ru', 'fil', 'vi', 'ta']) {
      final cells = <String>[];
      for (final width in [320.0, 360.0]) {
        for (final scale in [1.0, 1.3]) {
          final h = await _measure(tester, code, width, scale);
          cells.add('${width.toInt()}x$scale=${h.toStringAsFixed(0)}');
        }
      }
      out.add('$code ${cells.join(' ')}');
    }
    // ignore: avoid_print
    print('MEASURE-ALL ${out.join(' | ')}');
  });
}
