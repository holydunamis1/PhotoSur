import 'dart:io';
import 'dart:ui' show Color, Offset;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/models/batch_background.dart';
import '../core/models/export_job.dart';
import '../core/providers/image_edit_provider.dart'
    show PostprocessArgs, postprocessInIsolate;
import '../core/services/export_service.dart';
import '../core/services/segmentation_service.dart';
import '../core/services/share_service.dart';
import '../core/services/storage_service.dart';
import '../core/utils/marketplace_presets.dart';
import 'image_prep_service.dart';

/// Cuts the background out of one photo with no editing step and saves the
/// result to the gallery. Uses exactly the same pipeline as the editor
/// (prepare, model, mask clean-up, export), just with default settings.
class BatchService {
  BatchService._();
  static final BatchService instance = BatchService._();

  /// Returns true when the finished image reached the gallery. Never throws:
  /// any failure for this photo is reported as false so the batch carries on.
  Future<bool> processOne(
    String path, {
    required BatchBackground background,
    required int serial,
    MarketplacePreset? preset,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final prepared = await prepareImage(path, tempDir.path);
      final probs = await SegmentationService.instance.infer(prepared.modelInput);
      final mask = await compute(
        postprocessInIsolate,
        PostprocessArgs(probs, prepared.width, prepared.height, prepared.guideGray),
      );
      final originalBytes = await File(prepared.path).readAsBytes();

      final out = resolveBatchOutput(background, preset);
      final format = out.format;
      final bg = out.background;
      final fit = preset == null
          ? null
          : marketplaceSubjectLayout(
              preset, mask, prepared.width, prepared.height);
      final quality = preset?.quality ?? 92;
      final bytes = await ExportService.instance.compositeAndExport(
        originalBytes: originalBytes,
        maskBytes: mask,
        backgroundType: bg.type,
        bgColor: bg.color ?? const Color(0xFFFFFFFF),
        gradientIndex: bg.gradientIndex,
        bgImageBytes: bg.imageBytes,
        blurRadius: bg.blurRadius,
        format: format,
        quality: quality,
        resizeMode: preset == null ? ResizeMode.original : ResizeMode.custom,
        customWidth: preset?.width,
        customHeight: preset?.height,
        subjectScale: fit?.scale ?? 1.0,
        subjectOffset: fit == null ? Offset.zero : Offset(fit.offsetX, fit.offsetY),
        maxBytes: preset?.maxBytes,
        minQuality: preset?.minQuality ?? 60,
      );

      final exportsDir = await StorageService.instance.getExportsDirectoryPath();
      final id = '${DateTime.now().microsecondsSinceEpoch}_$serial';
      final filePath = p.join(
        exportsDir,
        '$id.${format == ExportFormat.jpg ? 'jpg' : 'png'}',
      );
      await File(filePath).writeAsBytes(bytes);

      try {
        await StorageService.instance.saveExportJob(
          ExportJob(
            id: id,
            format: format,
            quality: quality,
            width: preset?.width ?? prepared.width,
            height: preset?.height ?? prepared.height,
            resizeMode: preset == null ? ResizeMode.original : ResizeMode.custom,
            filePath: filePath,
            status: ExportStatus.complete,
            createdAt: DateTime.now(),
          ),
        );
      } catch (e) {
        debugPrint('Batch: history write failed: $e'); // not fatal
      }

      return await ShareService.instance.saveToGallery(bytes);
    } catch (e) {
      debugPrint('Batch: photo failed: $e');
      return false;
    }
  }
}
