import 'dart:convert';
import 'dart:io';

// NOTE on dart:io here: this import is Directory/File path manipulation
// only — no Platform.isIOS or other OS-branching logic is written in this
// file. Per the resolved reading of the core/ architecture rule (see
// project discussion): core/ may use cross-platform plugins whose Dart API
// doesn't differ by platform; only files that branch on OS belong in
// lib/platform/. sqflite and path_provider both fall on the core/ side of
// that line despite pulling in dart:io transitively.
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/export_job.dart';
import '../models/user_settings.dart';

class StorageException implements Exception {
  const StorageException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => 'StorageException: $message'
      '${cause != null ? ' (cause: $cause)' : ''}';
}

const String _exportJobsTable = 'export_jobs';
const String _userSettingsKey = 'user_settings';
const int _dbVersion = 1;

/// Column names of the export_jobs table, exactly as created in
/// [StorageService._database]. json_serializable is configured with
/// `field_rename: snake`, so ExportJob.toJson() emits `file_path` etc. and
/// must never be handed to sqflite directly: the keys would not match.
const List<String> kExportJobColumns = [
  'id',
  'format',
  'quality',
  'width',
  'height',
  'resizeMode',
  'filePath',
  'status',
  'createdAt',
];

Map<String, Object?> exportJobToRow(ExportJob job) => {
      'id': job.id,
      'format': job.format.name,
      'quality': job.quality,
      'width': job.width,
      'height': job.height,
      'resizeMode': job.resizeMode.name,
      'filePath': job.filePath,
      'status': job.status.name,
      'createdAt': job.createdAt.toIso8601String(),
    };

ExportJob exportJobFromRow(Map<String, Object?> row) => ExportJob(
      id: row['id']! as String,
      format: ExportFormat.values.byName(row['format']! as String),
      quality: row['quality']! as int,
      width: row['width']! as int,
      height: row['height']! as int,
      resizeMode: ResizeMode.values.byName(row['resizeMode']! as String),
      filePath: row['filePath']! as String,
      status: ExportStatus.values.byName(row['status']! as String),
      createdAt: DateTime.parse(row['createdAt']! as String),
    );

/// sqflite CRUD for export history (backs the "Recent Exports" grid,
/// Feature/home_screen.dart Phase 5), SharedPreferences for UserSettings,
/// path_provider for temp/cache directories used during compositing.
///
/// Zero backend per Section 1 — everything here is on-device only.
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  Database? _db;

  /// Bumped whenever export history changes, so the home screen can reload
  /// its grid even though it stays mounted underneath the editor.
  final ValueNotifier<int> historyRevision = ValueNotifier<int>(0);

  /// Eagerly opens/creates the database at app startup, so any first-use
  /// failure surfaces during main.dart's init sequence (wrapped there in
  /// try/catch) rather than silently on the first export/history read.
  /// Matches File 47's "sqflite init" startup responsibility.
  Future<void> initialize() async {
    try {
      await _database;
    } catch (e) {
      // Swallow here too — main.dart's graceful-degradation wrapper is
      // the real safety net; storage failures shouldn't block app launch.
    }
  }

  Future<Database> get _database async {
    final existing = _db;
    if (existing != null) return existing;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(dir.path, 'photosur.db');
      final db = await openDatabase(
        dbPath,
        version: _dbVersion,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $_exportJobsTable (
              id TEXT PRIMARY KEY,
              format TEXT NOT NULL,
              quality INTEGER NOT NULL,
              width INTEGER NOT NULL,
              height INTEGER NOT NULL,
              resizeMode TEXT NOT NULL,
              filePath TEXT NOT NULL,
              status TEXT NOT NULL,
              createdAt TEXT NOT NULL
            )
          ''');
        },
      );
      _db = db;
      return db;
    } catch (e) {
      throw StorageException('Failed to open database.', e);
    }
  }

  // ---- Export job CRUD ----

  Future<void> saveExportJob(ExportJob job) async {
    try {
      final db = await _database;
      await db.insert(
        _exportJobsTable,
        exportJobToRow(job),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      historyRevision.value++;
    } catch (e) {
      throw StorageException('Failed to save export job.', e);
    }
  }

  /// Recent exports, newest first. [limit] defaults to 6 to match
  /// home_screen.dart's "recent exports grid (last 6)" (Section 5, File 40).
  Future<List<ExportJob>> getRecentExportJobs({int limit = 6}) async {
    try {
      final db = await _database;
      final rows = await db.query(
        _exportJobsTable,
        orderBy: 'createdAt DESC',
        limit: limit,
      );
      return rows.map(exportJobFromRow).toList();
    } catch (e) {
      throw StorageException('Failed to load export history.', e);
    }
  }


  /// Every export record, newest first (backs the "See all" screen).
  Future<List<ExportJob>> getAllExportJobs() async {
    try {
      final db = await _database;
      final rows = await db.query(_exportJobsTable, orderBy: 'createdAt DESC');
      return rows.map(exportJobFromRow).toList();
    } catch (e) {
      throw StorageException('Failed to load export history.', e);
    }
  }

  /// Removes several records in one transaction (one history notification).
  Future<void> deleteExportJobs(Iterable<String> ids) async {
    try {
      final db = await _database;
      final batch = db.batch();
      for (final id in ids) {
        batch.delete(_exportJobsTable, where: 'id = ?', whereArgs: [id]);
      }
      await batch.commit(noResult: true);
      historyRevision.value++;
    } catch (e) {
      throw StorageException('Failed to delete export jobs.', e);
    }
  }

  Future<void> deleteExportJob(String id) async {
    try {
      final db = await _database;
      await db.delete(_exportJobsTable, where: 'id = ?', whereArgs: [id]);
      historyRevision.value++;
    } catch (e) {
      throw StorageException('Failed to delete export job.', e);
    }
  }

  // ---- Settings (SharedPreferences) ----

  /// Plain-words record of the last settings read and write, shown on the
  /// onboarding screen while diagnostics are on (kShowExportDiagnostics),
  /// so a phone-only check can tell "nothing was saved" from "saving
  /// failed" from "saved data could not be read".
  String settingsDiagnostic = 'settings: not read yet';

  Future<UserSettings> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_userSettingsKey);
      if (raw == null) {
        settingsDiagnostic = 'read: nothing saved yet';
        return const UserSettings();
      }
      final loaded = UserSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      settingsDiagnostic =
          'read: saved, onboarded=${loaded.hasCompletedOnboarding}';
      return loaded;
    } catch (e) {
      // Corrupt/missing prefs shouldn't crash app start — fall back to
      // defaults per the graceful-fallback architecture rule.
      settingsDiagnostic = 'read FAILED: $e';
      return const UserSettings();
    }
  }

  Future<void> saveSettings(UserSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ok = await prefs.setString(
          _userSettingsKey, jsonEncode(settings.toJson()));
      settingsDiagnostic = ok
          ? 'save ok, onboarded=${settings.hasCompletedOnboarding}'
          : 'save returned false';
    } catch (e) {
      settingsDiagnostic = 'save FAILED: $e';
      throw StorageException('Failed to save settings.', e);
    }
  }

  // ---- Temp/cache directories ----

  /// Working directory for in-progress edits (e.g. camera capture before
  /// crop, intermediate composite bytes). Cleared by the OS, not by us.
  Future<String> getTempDirectoryPath() async {
    try {
      final dir = await getTemporaryDirectory();
      return dir.path;
    } catch (e) {
      throw StorageException('Failed to access temp directory.', e);
    }
  }

  /// Persistent app-owned directory for saved export copies referenced by
  /// ExportJob.filePath, distinct from the user's actual photo gallery
  /// (which gal writes to separately).
  Future<String> getExportsDirectoryPath() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final exportsDir = Directory(p.join(dir.path, 'exports'));
      if (!await exportsDir.exists()) {
        await exportsDir.create(recursive: true);
      }
      return exportsDir.path;
    } catch (e) {
      throw StorageException('Failed to access exports directory.', e);
    }
  }
}
