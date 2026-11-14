import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../utils/constants.dart';
import 'storage_service.dart';

const Set<String> kCleanableExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.heic',
  '.heif',
};

bool _isCleanable(File f) =>
    kCleanableExtensions.contains(p.extension(f.path).toLowerCase());

Future<List<File>> _imageFiles(Directory dir) async {
  if (!await dir.exists()) return const [];
  final out = <File>[];
  await for (final e in dir.list(recursive: true, followLinks: false)) {
    if (e is File && _isCleanable(e)) out.add(e);
  }
  return out;
}

/// A file is "active" when it changed within [window] of [now] (or has a
/// modified time in the future, which cannot be trusted).
bool _isActive(DateTime modified, DateTime now, Duration window) =>
    now.difference(modified) < window;

/// Deletes image files in [dir] older than [maxAge], then the oldest ones
/// until the total is at most [capBytes]. Files changed within
/// [activeWindow] are never deleted. Returns the number of bytes freed.
Future<int> sweepTempImages(
  Directory dir, {
  required DateTime now,
  Duration maxAge = kTempMaxAge,
  Duration activeWindow = kTempActiveWindow,
  int capBytes = kTempFolderCapBytes,
}) async {
  var freed = 0;
  final entries = <({File file, DateTime modified, int size})>[];
  for (final f in await _imageFiles(dir)) {
    try {
      final stat = await f.stat();
      entries.add((file: f, modified: stat.modified, size: stat.size));
    } catch (_) {}
  }

  Future<void> remove(({File file, DateTime modified, int size}) e) async {
    try {
      await e.file.delete();
      freed += e.size;
    } catch (_) {}
  }

  final remaining = <({File file, DateTime modified, int size})>[];
  for (final e in entries) {
    if (_isActive(e.modified, now, activeWindow)) {
      remaining.add(e);
    } else if (now.difference(e.modified) >= maxAge) {
      await remove(e);
    } else {
      remaining.add(e);
    }
  }

  var total = remaining.fold<int>(0, (a, e) => a + e.size);
  if (total > capBytes) {
    remaining.sort((a, b) => a.modified.compareTo(b.modified));
    for (final e in remaining) {
      if (total <= capBytes) break;
      if (_isActive(e.modified, now, activeWindow)) continue;
      await remove(e);
      total -= e.size;
    }
  }
  return freed;
}

/// Removes every inactive image file in [dir] (the Settings "Clear" button).
Future<int> clearTempImages(Directory dir, {required DateTime now}) =>
    sweepTempImages(dir,
        now: now, maxAge: Duration.zero, capBytes: 0);

/// Total size of the cleanable image files in [dir].
Future<int> tempImagesBytes(Directory dir) async {
  var total = 0;
  for (final f in await _imageFiles(dir)) {
    try {
      total += await f.length();
    } catch (_) {}
  }
  return total;
}

/// Deletes image files in [exportsDir] that no history record points to
/// (compared by file name) and that are at least [minAge] old.
Future<int> sweepOrphanExports(
  Directory exportsDir,
  Set<String> knownNames, {
  required DateTime now,
  Duration minAge = kOrphanMinAge,
}) async {
  var freed = 0;
  for (final f in await _imageFiles(exportsDir)) {
    try {
      if (knownNames.contains(p.basename(f.path))) continue;
      final stat = await f.stat();
      if (now.difference(stat.modified) < minAge) continue;
      await f.delete();
      freed += stat.size;
    } catch (_) {}
  }
  return freed;
}

/// App-level wiring of the sweeps. Nothing here throws.
class StorageCleanup {
  StorageCleanup._();
  static final StorageCleanup instance = StorageCleanup._();

  Future<Directory> _temp() async =>
      Directory(await StorageService.instance.getTempDirectoryPath());

  Future<void> runStartupSweep() async {
    final now = DateTime.now();
    try {
      await sweepTempImages(await _temp(), now: now);
    } catch (e) {
      debugPrint('Temp sweep failed: $e');
    }
    try {
      // If history cannot be read, skip: deleting without it would remove
      // exports that are still referenced.
      final jobs = await StorageService.instance.getAllExportJobs();
      final known = jobs.map((j) => p.basename(j.filePath)).toSet();
      final dir =
          Directory(await StorageService.instance.getExportsDirectoryPath());
      await sweepOrphanExports(dir, known, now: now);
    } catch (e) {
      debugPrint('Orphan sweep skipped: $e');
    }
  }

  Future<int> tempBytes() async {
    try {
      return await tempImagesBytes(await _temp());
    } catch (_) {
      return 0;
    }
  }

  Future<void> clearTemp() async {
    try {
      await clearTempImages(await _temp(), now: DateTime.now());
    } catch (e) {
      debugPrint('Clear temp failed: $e');
    }
  }
}
