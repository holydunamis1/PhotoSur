// Measurement only (no assertions): prints the natural height of the
// Background tool's content so the panel height can be chosen from numbers.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katharerase/core/providers/image_edit_provider.dart';
import 'package:katharerase/core/theme/app_theme.dart';
import 'package:katharerase/generated/l10n/app_localizations.dart';
import 'package:katharerase/widgets/background_selector.dart';
import 'package:provider/provider.dart';

void main() {
  setUpAll(() => Provider.debugCheckInvalidValueType = null);

  for (final code in ['en', 'de', 'ru', 'fil', 'vi', 'ta']) {
    for (final width in [320.0, 360.0, 411.0]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('measure $code ${width.toInt()} x$scale', (tester) async {
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
          final h = tester.getSize(find.byType(BackgroundSelector)).height;
          final buttons = tester.getSize(find.byType(Row).first).height;
          // ignore: avoid_print
          print('MEASURE $code w=${width.toInt()} scale=$scale '
              'content=${h.toStringAsFixed(1)} buttons=${buttons.toStringAsFixed(1)}');
        });
      }
    }
  }
}
