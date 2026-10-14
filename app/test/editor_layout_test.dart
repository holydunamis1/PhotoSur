import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/core/providers/image_edit_provider.dart';
import 'package:photosur/core/providers/settings_provider.dart';
import 'package:photosur/core/providers/subscription_provider.dart';
import 'package:photosur/core/providers/theme_provider.dart';
import 'package:photosur/core/theme/app_theme.dart';
import 'package:photosur/generated/l10n/app_localizations.dart';
import 'package:photosur/screens/settings_screen.dart';
import 'package:photosur/widgets/editor_tool_dock.dart';
import 'package:photosur/widgets/editor_tool_panel.dart';
import 'package:provider/provider.dart';

Widget _app(Widget home, {double textScale = 1.0, ImageEditProvider? edit}) {
  return Provider<ImageEditProvider>.value(
    value: edit ?? ImageEditProvider(),
    child: MaterialApp(
      theme: buildAppTheme(Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(body: home),
    ),
  );
}

void main() {
  setUpAll(() {
    // The real app switches this off in PhotoSurApp.build.
    Provider.debugCheckInvalidValueType = null;
  });

  group('tool dock', () {
    testWidgets('shows every tool and reports taps', (tester) async {
      EditorTool? tapped;
      await tester.pumpWidget(
        _app(
          Align(
            alignment: Alignment.bottomCenter,
            child: EditorToolDock(
              selected: EditorTool.cutout,
              onSelected: (t) => tapped = t,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Cut-out'), findsOneWidget);
      expect(find.text('Brush'), findsOneWidget);
      expect(find.text('Background'), findsOneWidget);
      expect(find.text('Templates'), findsOneWidget);
      expect(find.text('Layout'), findsOneWidget);

      await tester.tap(find.text('Brush'));
      expect(tapped, EditorTool.brush);
      await tester.tap(find.text('Background'));
      expect(tapped, EditorTool.background);
    });

    testWidgets('every tool is a comfortable tap target (>= 48 px)',
        (tester) async {
      await tester.pumpWidget(
        _app(
          Align(
            alignment: Alignment.bottomCenter,
            child: EditorToolDock(
              selected: EditorTool.cutout,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      final items = find.byType(InkWell);
      expect(items, findsNWidgets(EditorTool.values.length));
      for (var i = 0; i < EditorTool.values.length; i++) {
        final size = tester.getSize(items.at(i));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(size.width, greaterThanOrEqualTo(48));
      }
    });
  });

  group('tool panel', () {
    for (final tool in EditorTool.values) {
      testWidgets('${tool.name} panel has the fixed height', (tester) async {
        await tester.pumpWidget(
          _app(Align(alignment: Alignment.bottomCenter, child: EditorToolPanel(tool: tool))),
        );
        await tester.pump();
        expect(
          tester.getSize(find.byType(EditorToolPanel)).height,
          kEditorToolPanelHeight,
        );
      });

      testWidgets(
        '${tool.name} panel never overflows (narrow screen, large text)',
        (tester) async {
          tester.view.devicePixelRatio = 1.0;
          tester.view.physicalSize = const Size(320, 640);
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            _app(
              Align(alignment: Alignment.bottomCenter, child: EditorToolPanel(tool: tool)),
              textScale: 1.3,
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'the photo canvas is exactly the same size for every tool',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(400, 800);
        addTearDown(tester.view.reset);

        final canvasKey = GlobalKey();
        final sizes = <EditorTool, Size>{};
        for (final tool in EditorTool.values) {
          await tester.pumpWidget(
            _app(
              Column(
                children: [
                  Expanded(child: SizedBox(key: canvasKey, width: double.infinity)),
                  EditorToolPanel(tool: tool),
                  EditorToolDock(selected: tool, onSelected: (_) {}),
                ],
              ),
            ),
          );
          await tester.pump();
          sizes[tool] = tester.getSize(find.byKey(canvasKey));
        }

        expect(sizes[EditorTool.cutout], sizes[EditorTool.brush]);
        expect(sizes[EditorTool.brush], sizes[EditorTool.background]);
      },
    );
  });

  testWidgets('settings screen builds with four grouped cards',
      (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ThemeProvider>.value(value: ThemeProvider()),
          Provider<SettingsProvider>.value(value: SettingsProvider()),
          Provider<SubscriptionProvider>.value(
            value: SubscriptionProvider(SettingsProvider())..value = true,
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(Card), findsNWidgets(4));
    expect(find.text('HD cut-out model'), findsOneWidget);
    expect(find.text('Open-source licenses'), findsOneWidget);
  });
}
