import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/services/segmentation_service.dart';
import '../core/utils/constants.dart';

enum HdModelStatus { notInstalled, downloading, installed, failed }

@immutable
class HdModelState {
  const HdModelState(this.status, [this.progress = 0]);

  final HdModelStatus status;

  /// 0..1 while downloading.
  final double progress;

  bool get isInstalled => status == HdModelStatus.installed;
  bool get isDownloading => status == HdModelStatus.downloading;
}

/// Downloads, verifies, caches and removes the optional HD cut-out model.
///
/// The file is fetched once, kept in app storage, and used offline from then
/// on. A partly downloaded file is resumed (HTTP Range) instead of restarted,
/// and a finished file is only accepted if its size and SHA-256 match. Every
/// failure ends in [HdModelStatus.failed]; nothing here throws to the UI.
class ModelDownloadService extends ValueNotifier<HdModelState> {
  ModelDownloadService._() : super(const HdModelState(HdModelStatus.notInstalled));

  static final ModelDownloadService instance = ModelDownloadService._();

  /// Set when the automatic first-photo download starts; the editor that is
  /// on screen when it finishes redoes its untouched cut-out in HD.
  bool autoRedoPending = false;

  bool _busy = false;
  bool _cancel = false;

  Future<File> _modelFile() async {
    final dir = await getApplicationSupportDirectory();
    final models = Directory(p.join(dir.path, 'models'));
    if (!models.existsSync()) models.createSync(recursive: true);
    return File(p.join(models.path, kHdModelFileName));
  }

  /// Call once at startup: picks up a model downloaded in an earlier session.
  Future<void> init() async {
    try {
      final f = await _modelFile();
      if (f.existsSync() && f.lengthSync() == kHdModelBytes) {
        _setInstalled(f.path);
      }
    } catch (_) {
      // No model: the bundled one is used.
    }
  }

  void _setInstalled(String path) {
    SegmentationService.instance.hdModelPath = path;
    value = const HdModelState(HdModelStatus.installed, 1);
  }

  void cancel() => _cancel = true;

  /// Starts (or resumes) the download. Safe to call repeatedly.
  Future<void> download() async {
    if (_busy || value.isInstalled) return;
    _busy = true;
    _cancel = false;
    value = const HdModelState(HdModelStatus.downloading, 0);
    HttpClient? client;
    try {
      final target = await _modelFile();
      final part = File('${target.path}.part');
      var have = part.existsSync() ? part.lengthSync() : 0;
      if (have > kHdModelBytes) {
        part.deleteSync();
        have = 0;
      }

      client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
      final request = await client.getUrl(Uri.parse(kHdModelUrl));
      if (have > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
      final response = await request.close();

      if (response.statusCode == HttpStatus.ok) {
        have = 0; // server ignored the range: start over
      } else if (response.statusCode != HttpStatus.partialContent) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      final sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
      var received = have;
      try {
        await for (final chunk
            in response.timeout(const Duration(seconds: 30))) {
          if (_cancel) throw const _Cancelled();
          sink.add(chunk);
          received += chunk.length;
          final prog = (received / kHdModelBytes).clamp(0.0, 1.0);
          if ((prog - value.progress) >= 0.005) {
            value = HdModelState(HdModelStatus.downloading, prog);
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (part.lengthSync() != kHdModelBytes) {
        throw const FormatException('size mismatch');
      }
      final digest = await sha256.bind(part.openRead()).first;
      if (digest.toString() != kHdModelSha256) {
        part.deleteSync();
        throw const FormatException('checksum mismatch');
      }
      if (target.existsSync()) target.deleteSync();
      await part.rename(target.path);
      _setInstalled(target.path);
    } on _Cancelled {
      value = const HdModelState(HdModelStatus.notInstalled);
    } catch (_) {
      value = const HdModelState(HdModelStatus.failed);
    } finally {
      client?.close(force: true);
      _busy = false;
    }
  }

  /// Deletes the downloaded model; the bundled one is used again.
  Future<void> remove() async {
    try {
      cancel();
      final f = await _modelFile();
      if (f.existsSync()) f.deleteSync();
      final part = File('${f.path}.part');
      if (part.existsSync()) part.deleteSync();
    } catch (_) {
      // Ignore: worst case the file stays and is reused next launch.
    }
    SegmentationService.instance.hdModelPath = null;
    value = const HdModelState(HdModelStatus.notInstalled);
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
