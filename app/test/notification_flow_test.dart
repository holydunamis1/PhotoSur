import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/core/providers/image_edit_provider.dart';
import 'package:photosur/platform/notification_service.dart';

void main() {
  group('unfinished-edit tracking', () {
    test('no image loaded -> nothing unfinished', () {
      expect(ImageEditProvider().hasUnfinishedEdit, isFalse);
    });

    test('loaded but not exported -> unfinished', () {
      final provider = ImageEditProvider()
        ..loadImage('/tmp/a.jpg', const Size(10, 10));
      expect(provider.hasUnfinishedEdit, isTrue);
    });

    test('exported -> no longer unfinished', () {
      final provider = ImageEditProvider()
        ..loadImage('/tmp/a.jpg', const Size(10, 10))
        ..markExported();
      expect(provider.hasUnfinishedEdit, isFalse);
    });

    test('loading a new image makes it unfinished again', () {
      final provider = ImageEditProvider()
        ..loadImage('/tmp/a.jpg', const Size(10, 10))
        ..markExported()
        ..loadImage('/tmp/b.jpg', const Size(10, 10));
      expect(provider.hasUnfinishedEdit, isTrue);
    });
  });

  group('NotificationService before init', () {
    test('is a safe no-op and never throws', () async {
      final service = NotificationService.instance;
      expect(service.isInitialized, isFalse);
      await service.scheduleUnfinishedEditReminder(
        title: 't',
        body: 'b',
        channelName: 'c',
        channelDescription: 'd',
      );
      await service.cancelUnfinishedEditReminder();
      expect(await service.requestPermission(), isFalse);
    });
  });
}
