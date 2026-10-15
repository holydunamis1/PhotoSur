import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/core/models/export_job.dart';
import 'package:photosur/core/services/export_library_service.dart';
import 'package:photosur/core/utils/export_grouping.dart';
import 'package:photosur/core/utils/extensions.dart';

ExportJob _job(String id, DateTime at) => ExportJob(
      id: id,
      format: ExportFormat.png,
      quality: 100,
      width: 100,
      height: 100,
      resizeMode: ResizeMode.original,
      filePath: '/x/$id.png',
      status: ExportStatus.complete,
      createdAt: at,
    );

void main() {
  group('groupExports', () {
    final now = DateTime(2026, 10, 15, 12);

    test('splits into Today / Yesterday / This week / Earlier in order', () {
      final jobs = [
        _job('a', DateTime(2026, 10, 15, 9)),
        _job('b', DateTime(2026, 10, 14, 23)),
        _job('c', DateTime(2026, 10, 10)),
        _job('d', DateTime(2026, 10, 1)),
        _job('e', DateTime(2026, 9, 1)),
      ];
      final groups = groupExports(jobs, now);
      expect(groups.map((g) => g.age).toList(), [
        ExportAge.today,
        ExportAge.yesterday,
        ExportAge.thisWeek,
        ExportAge.earlier,
      ]);
      expect(groups.last.jobs.map((j) => j.id).toList(), ['d', 'e']);
    });

    test('drops empty sections', () {
      final groups = groupExports([_job('a', DateTime(2026, 1, 1))], now);
      expect(groups.length, 1);
      expect(groups.single.age, ExportAge.earlier);
    });

    test('a date later than now still counts as today', () {
      expect(exportAgeOf(DateTime(2026, 10, 16), now), ExportAge.today);
    });

    test('empty list gives no sections', () {
      expect(groupExports(const [], now), isEmpty);
    });
  });

  group('export files', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('exports_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('deleteFiles removes files and ignores ones already gone', () async {
      final a = File('${dir.path}/a.png')..writeAsBytesSync([1, 2, 3]);
      await ExportLibraryService.deleteFiles([a.path, '${dir.path}/missing.png']);
      expect(a.existsSync(), isFalse);
    });

    test('directoryBytes sums the files in the folder', () async {
      File('${dir.path}/a.png').writeAsBytesSync(List.filled(1000, 1));
      File('${dir.path}/b.jpg').writeAsBytesSync(List.filled(500, 1));
      expect(await ExportLibraryService.directoryBytes(dir.path), 1500);
    });

    test('directoryBytes is 0 for a folder that does not exist', () async {
      expect(await ExportLibraryService.directoryBytes('${dir.path}/nope'), 0);
    });
  });

  test('storage label uses KB and MB', () {
    expect(2048.toHumanFileSize, '2.0 KB');
    expect((5 * 1024 * 1024).toHumanFileSize, '5.0 MB');
  });
}
