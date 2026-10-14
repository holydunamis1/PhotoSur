import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

class ShareException implements Exception {
  const ShareException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => 'ShareException: $message'
      '${cause != null ? ' (cause: $cause)' : ''}';
}

/// Wraps share_plus (Feature 15, Direct Share) and gal (Feature 5, Save to
/// Gallery — Android 13+ scoped-storage safe per the plugin's own docs).
/// Falls back to the system share sheet if gal fails, so the user always
/// has a path to keep their image even if the direct gallery write breaks
/// on a given device.
///
/// API note: share_plus v13+ deprecated the old static Share.* methods in
/// favor of SharePlus.instance.share(ShareParams(...)) — confirmed live
/// against the current changelog before writing this file.
class ShareService {
  ShareService._();
  static final ShareService instance = ShareService._();

  /// Feature 5: Save to Gallery. Returns true on success. On gal failure,
  /// does NOT throw — caller (export_bottom_sheet.dart, Phase 5) should
  /// offer the share sheet as the fallback path via [shareImage] below,
  /// per the architecture rule that every third-party call degrades
  /// gracefully rather than surfacing a raw error.
  Future<bool> saveToGallery(Uint8List imageBytes, {String? album}) async {
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) return false;
      }
      await Gal.putImageBytes(imageBytes, album: album ?? 'PhotoSur');
      return true;
    } on GalException catch (e) {
      // Known, typed failure (permission denied, unsupported format, out
      // of space) — log and let the caller fall back to share sheet.
      // ignore: avoid_print
      print('Gal save failed: ${e.type}');
      return false;
    } catch (e) {
      // ignore: avoid_print
      print('Gal save failed with unexpected error: $e');
      return false;
    }
  }

  /// Text-only share — no image attached. Added for settings_screen.dart's
  /// "Share App" action, which promotes the app via text/link only.
  /// Kept separate from shareImage rather than passing empty bytes through
  /// XFile.fromData, which would produce a broken 0-byte attachment on
  /// some platforms' share sheets.
  Future<void> shareText(String text) async {
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } catch (e) {
      throw ShareException('Share failed.', e);
    }
  }

  /// Feature 15: Direct Share. Shares the processed image via the system
  /// share sheet. Also used as gal's fallback path per File 16's stated
  /// purpose ("Falls back to share sheet on gal failure").
  Future<void> shareImage(
    Uint8List imageBytes, {
    required String filename,
    String? text,
  }) async {
    try {
      final xFile = XFile.fromData(
        imageBytes,
        name: filename,
        mimeType: _mimeTypeForFilename(filename),
      );
      await SharePlus.instance.share(
        ShareParams(files: [xFile], text: text),
      );
    } catch (e) {
      throw ShareException('Share failed.', e);
    }
  }

  String _mimeTypeForFilename(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
