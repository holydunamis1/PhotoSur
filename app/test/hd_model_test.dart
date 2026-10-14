// The HD model chip must fit the fixed tool panel next to the edge slider
// (no scrolling at normal text), and the download constants must be sane.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/core/providers/image_edit_provider.dart';
import 'package:photosur/core/theme/app_theme.dart';
import 'package:photosur/core/utils/constants.dart';
import 'package:photosur/generated/l10n/app_localizations.dart';
import 'package:photosur/widgets/editor_tool_panel.dart';
import 'package:photosur/widgets/hd_model_ui.dart';
import 'package:provider/provider.dart';

Future<double> _height(WidgetTester tester, String code, double scale) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(320, 700);
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
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsetsDirectional.fromSTEB(16, 6, 12, 2),
            child: CutoutControls(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.getSize(find.byType(CutoutControls)).height;
}

void main() {
  setUpAll(() => Provider.debugCheckInvalidValueType = null);

  test('HD model constants are well formed', () {
    expect(kHdModelUrl.startsWith('https://'), isTrue);
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(kHdModelSha256), isTrue);
    expect(kHdModelBytes, greaterThan(50 * 1024 * 1024));
    expect((kHdModelBytes / 1000000).round(), kHdModelMegabytes);
  });

  testWidgets('cut-out content fits the panel at normal text', (tester) async {
    final out = <String>[];
    for (final code in ['en', 'de', 'ru', 'fil', 'vi', 'ta']) {
      final h = await _height(tester, code, 1.0);
      final h13 = await _height(tester, code, 1.3);
      out.add('$code=$h/$h13');
      expect(h, lessThanOrEqualTo(kEditorToolPanelHeight - 8), reason: code);
    }
    // ignore: avoid_print
    print('CUTOUT-FIT ${out.join(' ')}');
  });
}
