import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/core/models/export_job.dart';
import 'package:photosur/core/services/storage_cleanup.dart';
import 'package:photosur/core/utils/constants.dart';
import 'package:photosur/core/utils/low_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  final now = DateTime(2026, 11, 14, 12);
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('cleanup_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  File make(String name, int size, DateTime modified) {
    final f = File(p.join(dir.path, name))
      ..writeAsBytesSync(List.filled(size, 1));
    f.setLastModifiedSync(modified);
    return f;
  }

  group('temp sweep', () {
    test('removes images older than a day, keeps newer ones', () async {
      final old = make('old.jpg', 10, now.subtract(const Duration(days: 2)));
      final fresh = make('new.png', 10, now.subtract(const Duration(hours: 2)));
      await sweepTempImages(dir, now: now);
      expect(old.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
    });

    test('never touches non-image files', () async {
      final other = make('db.sqlite', 10, now.subtract(const Duration(days: 9)));
      await sweepTempImages(dir, now: now);
      expect(other.existsSync(), isTrue);
    });

    test('never deletes files changed in the last 10 minutes, even over cap',
        () async {
      final active = make('a.png', 100, now.subtract(const Duration(minutes: 3)));
      await sweepTempImages(dir, now: now, capBytes: 10);
      expect(active.existsSync(), isTrue);
    });

    test('future modified time is treated as active', () async {
      final f = make('f.png', 10, now.add(const Duration(days: 5)));
      await sweepTempImages(dir, now: now, capBytes: 0);
      expect(f.existsSync(), isTrue);
    });

    test('over the cap: oldest go first until under the cap', () async {
      final a = make('a.jpg', 100, now.subtract(const Duration(hours: 5)));
      final b = make('b.jpg', 100, now.subtract(const Duration(hours: 4)));
      final c = make('c.jpg', 100, now.subtract(const Duration(hours: 3)));
      await sweepTempImages(dir, now: now, capBytes: 150);
      expect(a.existsSync(), isFalse);
      expect(b.existsSync(), isFalse);
      expect(c.existsSync(), isTrue);
    });

    test('clear removes inactive images but keeps active ones', () async {
      final a = make('a.jpg', 5, now.subtract(const Duration(hours: 1)));
      final live = make('b.jpg', 5, now.subtract(const Duration(minutes: 1)));
      await clearTempImages(dir, now: now);
      expect(a.existsSync(), isFalse);
      expect(live.existsSync(), isTrue);
    });

    test('tempImagesBytes counts only images', () async {
      make('a.jpg', 7, now);
      make('b.png', 5, now);
      make('c.txt', 100, now);
      expect(await tempImagesBytes(dir), 12);
    });

    test('missing folder is fine', () async {
      final gone = Directory(p.join(dir.path, 'nope'));
      expect(await sweepTempImages(gone, now: now), 0);
      expect(await tempImagesBytes(gone), 0);
    });

    test('constants match the approved values', () {
      expect(kTempFolderCapBytes, 200 * 1024 * 1024);
      expect(kTempMaxAge, const Duration(days: 1));
      expect(kTempActiveWindow, const Duration(minutes: 10));
    });
  });

  group('orphan sweep', () {
    test('deletes old unreferenced files, keeps referenced and young ones',
        () async {
      final orphan = make('o.png', 5, now.subtract(const Duration(days: 3)));
      final known = make('k.png', 5, now.subtract(const Duration(days: 3)));
      final young = make('y.png', 5, now.subtract(const Duration(hours: 3)));
      await sweepOrphanExports(dir, {'k.png'}, now: now);
      expect(orphan.existsSync(), isFalse);
      expect(known.existsSync(), isTrue);
      expect(young.existsSync(), isTrue);
    });

    test('compares by file name, not full path', () async {
      final f = make('k.webp', 5, now.subtract(const Duration(days: 3)));
      await sweepOrphanExports(dir, {'k.webp'}, now: now);
      expect(f.existsSync(), isTrue);
    });
  });

  group('low storage', () {
    test('unknown free space never blocks', () {
      expect(hasEnoughSpace(null, 1 << 40), isTrue);
    });

    test('needs the estimate plus the margin', () {
      const need = 1000;
      expect(hasEnoughSpace(need + kLowStorageMarginBytes, need), isTrue);
      expect(hasEnoughSpace(need + kLowStorageMarginBytes - 1, need), isFalse);
    });

    test('estimates: png larger than jpg, doubled for two copies', () {
      expect(estimateExportBytes(1000, 1000, ExportFormat.png), 6000000);
      expect(estimateExportBytes(1000, 1000, ExportFormat.jpg), 1000000);
      expect(estimateBatchBytes(3), 3 * kBatchPerPhotoBytes);
    });
  });
}
