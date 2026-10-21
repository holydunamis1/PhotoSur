import 'dart:io';
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../core/services/storage_service.dart';
import '../core/theme/app_tokens.dart';
import '../generated/l10n/app_localizations.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/loading_overlay.dart';
import '../widgets/primary_button.dart';
import '../widgets/toast_notification.dart';

enum _AspectOption { free, square1x1, portrait4x5, portrait9x16 }

/// Pre-edit: rotate 90° CW/CCW, aspect ratio toggle (free/1:1/4:5/9:16),
/// crop. "Continue" to editor.
///
/// Rotation is handled via package:image (img.copyRotate) on the raw
/// bytes before handing them to crop_your_image's Crop widget — that
/// package explicitly states it does NOT do rotation/resize itself (see
/// its own docs), only cropping.
class CropRotateScreen extends StatefulWidget {
  const CropRotateScreen({super.key, required this.imagePath});

  final String imagePath;

  @override
  State<CropRotateScreen> createState() => _CropRotateScreenState();
}

class _CropRotateScreenState extends State<CropRotateScreen> {
  final CropController _cropController = CropController();
  Uint8List? _imageBytes;
  _AspectOption _aspect = _AspectOption.free;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadBytes();
  }

  Future<void> _loadBytes() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      if (mounted) setState(() => _imageBytes = bytes);
    } catch (e) {
      if (mounted) {
        ToastNotification.show(
          context,
          message: AppLocalizations.of(context).cropLoadFailed,
          type: ToastType.error,
        );
      }
    }
  }

  Future<void> _rotate(bool clockwise) async {
    final bytes = _imageBytes;
    if (bytes == null || _isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('decode failed');
      final rotated = img.copyRotate(decoded, angle: clockwise ? 90 : -90);
      final encoded = Uint8List.fromList(img.encodePng(rotated));
      if (mounted) setState(() => _imageBytes = encoded);
    } catch (e) {
      if (mounted) {
        ToastNotification.show(
          context,
          message: AppLocalizations.of(context).cropRotateFailed,
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  double? get _aspectRatio => switch (_aspect) {
        _AspectOption.free => null,
        _AspectOption.square1x1 => 1.0,
        _AspectOption.portrait4x5 => 4 / 5,
        _AspectOption.portrait9x16 => 9 / 16,
      };

  Future<void> _onCropped(CropResult result) async {
    final l10n = AppLocalizations.of(context);
    switch (result) {
      case CropSuccess(:final croppedImage):
        try {
          final tempDir = await StorageService.instance.getTempDirectoryPath();
          final outPath = p.join(
            tempDir,
            'cropped_${DateTime.now().millisecondsSinceEpoch}.png',
          );
          await File(outPath).writeAsBytes(croppedImage);
          if (mounted) {
            setState(() => _isProcessing = false);
            context.push('/editor', extra: outPath);
          }
        } catch (e) {
          if (mounted) {
            setState(() => _isProcessing = false);
            ToastNotification.show(context, message: l10n.cropSaveFailed, type: ToastType.error);
          }
        }
      case CropFailure(:final cause):
        if (mounted) {
          setState(() => _isProcessing = false);
          ToastNotification.show(context, message: l10n.cropFailed, type: ToastType.error);
        }
        // ignore: avoid_print
        print('Crop failed: $cause');
    }
  }

  void _continue() {
    setState(() => _isProcessing = true);
    _cropController.crop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AppScaffold(
      appBar: AppBar(title: Text(l10n.cropTitle)),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                if (_imageBytes != null)
                  Crop(
                    // The crop widget reads aspectRatio only when it is
                    // created, so a new ratio needs a new widget: keying on
                    // the ratio makes Free / 1:1 / 4:5 / 9:16 take effect.
                    key: ValueKey<double?>(_aspectRatio),
                    image: _imageBytes!,
                    controller: _cropController,
                    aspectRatio: _aspectRatio,
                    // Free mode starts with the frame on the whole photo, so
                    // tapping Continue without touching it keeps everything.
                    // (The package's own default is a smaller centred box.)
                    initialRectBuilder: _aspectRatio == null
                        ? InitialRectBuilder.withBuilder(
                            (viewportRect, imageRect) => imageRect,
                          )
                        : null,
                    onCropped: _onCropped,
                    baseColor: Colors.black,
                    maskColor: Colors.black.withValues(alpha: 0.6),
                  )
                else
                  const Center(child: CircularProgressIndicator()),
                LoadingOverlay(visible: _isProcessing),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              color: context.palette.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.xl),
              ),
              border: Border(
                top: BorderSide(color: context.palette.separator, width: 0.5),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      icon: const Icon(Icons.rotate_left_rounded),
                      onPressed: () => _rotate(false),
                    ),
                    const SizedBox(width: 16),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.rotate_right_rounded),
                      onPressed: () => _rotate(true),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<_AspectOption>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: _AspectOption.free, label: Text(l10n.cropAspectFree)),
                      ButtonSegment(value: _AspectOption.square1x1, label: Text(l10n.cropAspect1x1)),
                      ButtonSegment(value: _AspectOption.portrait4x5, label: Text(l10n.cropAspect4x5)),
                      ButtonSegment(value: _AspectOption.portrait9x16, label: Text(l10n.cropAspect9x16)),
                    ],
                    selected: {_aspect},
                    onSelectionChanged: (s) => setState(() => _aspect = s.first),
                  ),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: l10n.cropContinue,
                  isLoading: _isProcessing,
                  onPressed: _imageBytes == null ? null : _continue,
                ),
              ],
            ),
          ),
          const AdBannerSlot(personalized: false),
        ],
      ),
    );
  }
}
