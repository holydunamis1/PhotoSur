import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/core/models/export_job.dart';
import 'package:photosur/generated/l10n/app_localizations.dart';
import 'package:photosur/widgets/recent_export_tile.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

ExportJob _job(String path) => ExportJob(
      id: 'j1',
      format: ExportFormat.png,
      quality: 100,
      width: 1600,
      height: 1200,
      resizeMode: ResizeMode.original,
      filePath: path,
      status: ExportStatus.complete,
      createdAt: DateTime.now(),
    );

Widget _host(Widget tile) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(child: SizedBox(width: 104, height: 104, child: tile)),
      ),
    );

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    dir = Directory.systemTemp.createTempSync('tile_test');
    file = File('${dir.path}/a.png')..writeAsBytesSync(base64Decode(_png));
  });

  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('a missing file shows the Unavailable state', (tester) async {
    await tester.pumpWidget(_host(RecentExportTile(
      job: _job('${dir.path}/gone.png'),
      onTap: () {},
      onMore: () {},
    )));
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('PNG'), findsNothing);
  });

  testWidgets('shows format, pixel size and date', (tester) async {
    await tester.pumpWidget(_host(RecentExportTile(
      job: _job(file.path),
      onTap: () {},
      onMore: () {},
    )));
    expect(find.text('PNG'), findsOneWidget);
    expect(find.text('1600×1200'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('tap, more button and long-press reach the right callbacks',
      (tester) async {
    var taps = 0;
    var mores = 0;
    await tester.pumpWidget(_host(RecentExportTile(
      job: _job(file.path),
      onTap: () => taps++,
      onMore: () => mores++,
    )));

    await tester.tapAt(tester.getCenter(find.byType(RecentExportTile)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(taps, 1);
    expect(mores, 0);

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pump(const Duration(milliseconds: 200));
    expect(taps, 1);
    expect(mores, 1);

    await tester.longPress(find.byType(RecentExportTile));
    await tester.pump(const Duration(milliseconds: 200));
    expect(mores, 2);
  });

  testWidgets('the more button is labelled for screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(RecentExportTile(
      job: _job(file.path),
      onTap: () {},
      onMore: () {},
    )));
    expect(find.bySemanticsLabel('More options'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('selection mode swaps the more button for a check',
      (tester) async {
    await tester.pumpWidget(_host(RecentExportTile(
      job: _job(file.path),
      onTap: () {},
      onMore: () {},
      selectionMode: true,
      selected: true,
    )));
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
  });
}
