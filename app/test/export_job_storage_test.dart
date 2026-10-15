import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/core/models/export_job.dart';
import 'package:photosur/core/services/storage_service.dart';

void main() {
  final job = ExportJob(
    id: 'abc',
    format: ExportFormat.webp,
    quality: 80,
    width: 1600,
    height: 1200,
    resizeMode: ResizeMode.portrait4x5,
    filePath: '/data/exports/abc.webp',
    status: ExportStatus.complete,
    createdAt: DateTime.utc(2026, 10, 15, 12, 30),
  );

  test('row keys match the export_jobs table columns exactly', () {
    expect(exportJobToRow(job).keys.toSet(), kExportJobColumns.toSet());
  });

  test('a job survives the trip to a row and back', () {
    expect(exportJobFromRow(exportJobToRow(job)), job);
  });

  test('toJson() is not usable as a row: its keys are renamed by the generator',
      () {
    // This is the bug that kept Recent Exports empty: json_serializable is
    // set to field_rename: snake, so these keys never matched the columns.
    expect(job.toJson().keys.toSet(), isNot(kExportJobColumns.toSet()));
  });
}
