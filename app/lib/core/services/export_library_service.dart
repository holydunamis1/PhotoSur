import 'dart:io';

import '../models/export_job.dart';
import 'storage_service.dart';

/// Everything the exports library needs beyond the history table: deleting
/// the image files that belong to records, measuring how much space exports
/// use, and clearing out files that have no record (for example exports made
/// before history saving worked).
class ExportLibraryService {
  ExportLibraryService._();
  static final ExportLibraryService instance = ExportLibraryService._();

  Future<List<ExportJob>> loadAll() => StorageService.instance.getAllExportJobs();

  /// Deletes the files first, then the records. A file that is already gone
  /// or cannot be deleted never blocks removing its record.
  Future<void> deleteMany(Iterable<ExportJob> jobs) async {
    final list = jobs.toList();
    if (list.isEmpty) return;
    await deleteFiles(list.map((j) => j.filePath));
    await StorageService.instance.deleteExportJobs(list.map((j) => j.id));
  }

  Future<void> delete(ExportJob job) => deleteMany([job]);

  /// Removes every record and every file in the exports folder.
  Future<void> deleteAll() async {
    final all = await loadAll();
    await deleteMany(all);
    try {
      final dir = Directory(await StorageService.instance.getExportsDirectoryPath());
      await deleteFiles(
        dir.listSync().whereType<File>().map((f) => f.path),
      );
    } catch (_) {
      // Records are already gone; leftover files are harmless.
    }
  }

  /// Total size of the exports folder, in bytes (0 if it cannot be read).
  Future<int> totalBytes() async {
    try {
      final path = await StorageService.instance.getExportsDirectoryPath();
      return await directoryBytes(path);
    } catch (_) {
      return 0;
    }
  }

  static Future<void> deleteFiles(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Best effort: see deleteMany.
      }
    }
  }

  static Future<int> directoryBytes(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }
}
