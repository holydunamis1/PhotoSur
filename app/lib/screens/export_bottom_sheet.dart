import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../core/models/export_job.dart';
import '../core/providers/ad_provider.dart';
import '../core/providers/image_edit_provider.dart';
import '../core/providers/subscription_provider.dart';
import '../core/services/export_service.dart';
import '../core/services/share_service.dart';
import '../core/services/storage_service.dart';
import '../core/utils/constants.dart' show kShowExportDiagnostics;
import '../core/utils/marketplace_presets.dart';
import '../core/models/editable_image_state.dart' show BackgroundType;
import '../generated/l10n/app_localizations.dart';
import '../platform/notification_service.dart';
import '../widgets/loading_overlay.dart';
import '../widgets/primary_button.dart';
import '../widgets/toast_notification.dart';

class ExportBottomSheet extends StatefulWidget {
  const ExportBottomSheet({super.key});

  @override
  State<ExportBottomSheet> createState() => _ExportBottomSheetState();
}

class _ExportBottomSheetState extends State<ExportBottomSheet> {
  ExportFormat _format = ExportFormat.png;
  int _quality = 90;
  ResizeMode _resizeMode = ResizeMode.original;
  // When set, the marketplace's size, format, file-size cap and layout rules
  // replace the manual format / resize choices.
  MarketplacePreset? _marketplace;
  bool _isExporting = false;
  // Shown INSIDE the sheet: a toast would appear on the page behind it,
  // hidden by the sheet itself.
  String? _errorMessage;
  String? _errorDetail;
  final TextEditingController _customWidthController = TextEditingController();
  final TextEditingController _customHeightController = TextEditingController();

  @override
  void dispose() {
    _customWidthController.dispose();
    _customHeightController.dispose();
    super.dispose();
  }

  bool get _showQualitySlider =>
      _format == ExportFormat.jpg || _format == ExportFormat.webp;

  void _chooseMarketplace(MarketplacePreset? preset) {
    setState(() {
      _marketplace = preset;
      if (preset != null) {
        _format = preset.format;
        _quality = preset.quality;
      }
    });
  }

  String _generateId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = (now * 2654435761) % 0xFFFFFFFF;
    return '$now-${rand.toRadixString(16)}';
  }

  Future<void> _export(BuildContext context, {required bool alsoShare}) async {
    if (_errorMessage != null) {
      setState(() {
        _errorMessage = null;
        _errorDetail = null;
      });
    }
    final l10n = AppLocalizations.of(context);
    final imageProvider = Provider.of<ImageEditProvider>(context, listen: false);
    final state = imageProvider.value;
    if (state.originalPath == null || state.imageSize == null) return;

    setState(() => _isExporting = true);
    var stage = 'read photo';
    try {
      final originalBytes = await File(state.originalPath!).readAsBytes();

      final maskLength =
          state.imageSize!.width.round() * state.imageSize!.height.round();
      final maskBytes = state.maskBytes ??
          (Uint8List(maskLength)..fillRange(0, maskLength, 255));

      stage = 'compose image';
      final preset = _marketplace;
      final fit = preset == null
          ? null
          : marketplaceSubjectLayout(
              preset,
              maskBytes,
              state.imageSize!.width.round(),
              state.imageSize!.height.round(),
            );
      final exportBytes = await ExportService.instance.compositeAndExport(
        originalBytes: originalBytes,
        maskBytes: maskBytes,
        backgroundType: (preset?.pureWhite ?? false)
            ? BackgroundType.white
            : state.backgroundType,
        bgColor: state.bgColor,
        blurRadius: state.blurRadius,
        edgeFeather: state.edgeFeather,
        gradientIndex: state.gradientIndex,
        bgImageBytes: state.bgImageBytes,
        shadowOpacity:
            (preset?.pureWhite ?? false) ? 0.0 : state.shadowOpacity,
        subjectScale: fit?.scale ?? state.subjectScale,
        subjectOffset: fit == null
            ? state.subjectOffset
            : Offset(fit.offsetX, fit.offsetY),
        canvasAspect: preset == null ? state.canvasAspect : null,
        format: _format,
        quality: _quality,
        resizeMode: preset == null ? _resizeMode : ResizeMode.custom,
        customWidth: preset != null
            ? preset.width
            : (_resizeMode == ResizeMode.custom
                ? int.tryParse(_customWidthController.text)
                : null),
        customHeight: preset != null
            ? preset.height
            : (_resizeMode == ResizeMode.custom
                ? int.tryParse(_customHeightController.text)
                : null),
        maxBytes: preset?.maxBytes,
        minQuality: preset?.minQuality ?? 60,
      );

      stage = 'write file';
      final exportsDir = await StorageService.instance.getExportsDirectoryPath();
      final ext = switch (_format) {
        ExportFormat.png => 'png',
        ExportFormat.jpg => 'jpg',
        ExportFormat.webp => 'webp',
      };
      final filename = '${_generateId()}.$ext';
      final filePath = p.join(exportsDir, filename);
      await File(filePath).writeAsBytes(exportBytes);

      // Recent-exports history is a convenience: if it can't be written the
      // export itself still succeeded, so carry on to save/share.
      try {
        stage = 'save history';
        final job = ExportJob(
          id: _generateId(),
          format: _format,
          quality: _quality,
          width: _marketplace?.width ?? state.imageSize!.width.round(),
          height: _marketplace?.height ?? state.imageSize!.height.round(),
          resizeMode: _marketplace == null ? _resizeMode : ResizeMode.custom,
          filePath: filePath,
          status: ExportStatus.complete,
          createdAt: DateTime.now(),
        );
        await StorageService.instance.saveExportJob(job);
      } catch (e) {
        debugPrint('Saving export history failed: $e');
      }

      // The edit is finished: no reminder needed.
      imageProvider.markExported();
      await NotificationService.instance.cancelUnfinishedEditReminder();

      stage = 'save to gallery';
      final saved = await ShareService.instance.saveToGallery(exportBytes);
      stage = 'share';
      if (!saved && context.mounted) {
        await ShareService.instance.shareImage(exportBytes, filename: filename);
      } else if (alsoShare) {
        await ShareService.instance.shareImage(exportBytes, filename: filename);
      }

      if (context.mounted) {
        ToastNotification.show(context, message: l10n.exportSuccess, type: ToastType.success);
      }

      if (context.mounted) {
        final subscriptionProvider =
            Provider.of<SubscriptionProvider>(context, listen: false);
        if (!subscriptionProvider.value) {
          final adProvider = Provider.of<AdProvider>(context, listen: false);
          await adProvider.maybeShowPostExportInterstitial(personalized: false);
        }
      }

      if (context.mounted) {
        Navigator.of(context).pop();
        context.go('/');
      }
    } catch (e, stack) {
      debugPrint('EXPORT FAILED: $e\n$stack');
      if (mounted) {
        setState(() {
          _errorMessage = l10n.exportFailed;
          final text = '$stage: ${e.runtimeType}: $e';
          _errorDetail = text.length > 240 ? '${text.substring(0, 240)}…' : text;
        });
      }
      if (context.mounted) {
        ToastNotification.show(context, message: l10n.exportFailed, type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        // SafeArea keeps the buttons clear of the system navigation bar;
        // the scroll view keeps them reachable on short screens.
        child: SafeArea(
          top: false,
          child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.exportTitle, style: Theme.of(context).textTheme.titleLarge),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  if (kShowExportDiagnostics && _errorDetail != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: SelectableText(
                        _errorDetail!,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                SegmentedButton<ExportFormat>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: ExportFormat.png, label: Text(l10n.exportFormatPng)),
                    ButtonSegment(value: ExportFormat.jpg, label: Text(l10n.exportFormatJpg)),
                    ButtonSegment(value: ExportFormat.webp, label: Text(l10n.exportFormatWebp)),
                  ],
                  selected: {_format},
                  onSelectionChanged: (s) => setState(() {
                    _format = s.first;
                    _marketplace = null;
                  }),
                ),
                if (_showQualitySlider) ...[
                  const SizedBox(height: 12),
                  Text(
                    l10n.exportQualityLabel(_quality),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  Slider(
                    value: _quality.toDouble(),
                    min: 1,
                    max: 100,
                    onChanged: (v) => setState(() => _quality = v.round()),
                  ),
                ],
                const SizedBox(height: 12),
                Text(l10n.exportMarketplaceLabel, style: Theme.of(context).textTheme.labelMedium),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final preset in kMarketplacePresets)
                      ChoiceChip(
                        label: Text(preset.name),
                        selected: _marketplace == preset,
                        onSelected: (on) => _chooseMarketplace(on ? preset : null),
                      ),
                  ],
                ),
                if (_marketplace != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    [
                      l10n.exportMarketplaceSummary(
                        _marketplace!.width,
                        _marketplace!.height,
                        switch (_marketplace!.format) {
                          ExportFormat.png => 'PNG',
                          ExportFormat.jpg => 'JPG',
                          ExportFormat.webp => 'WEBP',
                        },
                      ),
                      if (_marketplace!.pureWhite) l10n.exportMarketplaceWhiteFill,
                      if (_marketplace!.maxBytes != null)
                        l10n.exportMarketplaceSizeCap(
                          (_marketplace!.maxBytes! / 1000000).toStringAsFixed(
                            _marketplace!.maxBytes! % 1000000 == 0 ? 0 : 1,
                          ),
                        ),
                    ].join('\n'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                Text(l10n.exportResizeLabel, style: Theme.of(context).textTheme.labelMedium),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(l10n.exportResizeOriginal),
                      selected: _marketplace == null && _resizeMode == ResizeMode.original,
                      onSelected: (_) => setState(() {
                        _resizeMode = ResizeMode.original;
                        _marketplace = null;
                      }),
                    ),
                    ChoiceChip(
                      label: Text(l10n.cropAspect1x1),
                      selected: _marketplace == null && _resizeMode == ResizeMode.square1x1,
                      onSelected: (_) => setState(() {
                        _resizeMode = ResizeMode.square1x1;
                        _marketplace = null;
                      }),
                    ),
                    ChoiceChip(
                      label: Text(l10n.cropAspect4x5),
                      selected: _marketplace == null && _resizeMode == ResizeMode.portrait4x5,
                      onSelected: (_) => setState(() {
                        _resizeMode = ResizeMode.portrait4x5;
                        _marketplace = null;
                      }),
                    ),
                    ChoiceChip(
                      label: Text(l10n.cropAspect9x16),
                      selected: _marketplace == null && _resizeMode == ResizeMode.portrait9x16,
                      onSelected: (_) => setState(() {
                        _resizeMode = ResizeMode.portrait9x16;
                        _marketplace = null;
                      }),
                    ),
                    ChoiceChip(
                      label: Text(l10n.exportResizeCustom),
                      selected: _marketplace == null && _resizeMode == ResizeMode.custom,
                      onSelected: (_) => setState(() {
                        _resizeMode = ResizeMode.custom;
                        _marketplace = null;
                      }),
                    ),
                  ],
                ),
                if (_marketplace == null && _resizeMode == ResizeMode.custom) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _customWidthController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: l10n.exportWidthLabel),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _customHeightController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: l10n.exportHeightLabel),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                PrimaryButton(
                  label: l10n.exportSaveToGallery,
                  icon: Icons.download,
                  isLoading: _isExporting,
                  onPressed: () => _export(context, alsoShare: false),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _isExporting ? null : () => _export(context, alsoShare: true),
                  icon: const Icon(Icons.ios_share),
                  label: Text(l10n.exportShare),
                ),
              ],
            ),
            ),
            LoadingOverlay(visible: _isExporting, message: l10n.exportInProgress),
          ],
        ),
        ),
      ),
    );
  }
}
