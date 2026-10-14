import 'dart:io';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photosur/core/providers/settings_provider.dart';
import 'package:photosur/core/providers/subscription_provider.dart';
import 'package:photosur/generated/l10n/app_localizations.dart';
import 'package:photosur/screens/crop_rotate_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('choosing 1:1, 4:5, 9:16 and Free changes the crop ratio',
      (tester) async {
    late final String path;
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('crop_test');
      path = '${dir.path}/photo.png';
      await File(path).writeAsBytes(
        img.encodePng(img.Image(width: 400, height: 300)),
      );
    });

    // Ad-free: the banner slot loads nothing (this test is about cropping).
    Provider.debugCheckInvalidValueType = null;
    final subscription = SubscriptionProvider(SettingsProvider())..value = true;
    final app = Provider<SubscriptionProvider>.value(
      value: subscription,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CropRotateScreen(imagePath: path),
      ),
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(app);
      // Let the photo file load (real async work).
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    await tester.pump();

    double? ratio() => tester.widget<Crop>(find.byType(Crop)).aspectRatio;

    expect(ratio(), isNull); // Free

    await tester.tap(find.text('1:1'));
    await tester.pump();
    expect(ratio(), 1.0);

    await tester.tap(find.text('4:5'));
    await tester.pump();
    expect(ratio(), closeTo(4 / 5, 1e-9));

    await tester.tap(find.text('9:16'));
    await tester.pump();
    expect(ratio(), closeTo(9 / 16, 1e-9));

    await tester.tap(find.text('Free'));
    await tester.pump();
    expect(ratio(), isNull);
  });
}
