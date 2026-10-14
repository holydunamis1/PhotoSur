import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/models/batch_background.dart';
import '../core/models/batch_progress.dart';
import '../core/models/editable_image_state.dart' show BackgroundType;
import '../core/providers/ad_provider.dart';
import '../core/models/export_job.dart' show ExportFormat;
import '../core/theme/app_tokens.dart';
import '../core/utils/background_presets.dart';
import '../core/utils/marketplace_presets.dart';
import '../generated/l10n/app_localizations.dart';
import '../platform/batch_service.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/background_selector.dart';
import '../widgets/primary_button.dart';
import '../widgets/template_selector.dart';

/// Batch cut-out: several photos, one background choice, one tap. Photos
/// are processed one after another (the model runs one image at a time) and
/// each result is saved to the gallery. No editing step, by design.
class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key, required this.imagePaths});

  final List<String> imagePaths;

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  late final ValueNotifier<BatchProgress> _progress;
  BatchBackground _bg = const BatchBackground();
  MarketplacePreset? _marketplace;
  bool _stopRequested = false;

  @override
  void initState() {
    super.initState();
    _progress = ValueNotifier(BatchProgress.initial(widget.imagePaths.length));
  }

  @override
  void dispose() {
    _stopRequested = true;
    _progress.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_progress.value.running) return;
    _stopRequested = false;
    _progress.value = BatchProgress.initial(widget.imagePaths.length)
        .copyWith(running: true);

    for (var i = 0; i < widget.imagePaths.length; i++) {
      if (_stopRequested || !mounted) break;
      _progress.value = _progress.value.withItem(i, BatchItemStatus.working);
      final ok = await BatchService.instance.processOne(
        widget.imagePaths[i],
        background: _bg,
        serial: i,
        preset: _marketplace,
      );
      if (!mounted) return;
      _progress.value = _progress.value
          .withItem(i, ok ? BatchItemStatus.done : BatchItemStatus.failed);
    }
    if (!mounted) return;
    _progress.value = _progress.value.copyWith(running: false, finished: true);

    if (_progress.value.doneCount > 0) {
      try {
        await Provider.of<AdProvider>(context, listen: false)
            .maybeShowPostExportInterstitial(personalized: false);
      } catch (_) {
        // An ad problem must never affect the finished batch.
      }
    }
  }

  void _setBackground(BatchBackground bg) {
    setState(() {
      _bg = bg;
      // A pure-white marketplace preset forces white, so picking another
      // background means leaving that preset.
      if (_marketplace?.pureWhite == true && bg.type != BackgroundType.white) {
        _marketplace = null;
      }
    });
  }

  Future<void> _pickPhoto() async {
    final bytes = await pickBackgroundPhoto(context);
    if (bytes != null && mounted) {
      _setBackground(BatchBackground(type: BackgroundType.image, imageBytes: bytes));
    }
  }

  Future<void> _pickTemplate() {
    return showTemplatePicker(context, (sheetContext, t) async {
      final bytes = await loadTemplateBytes(sheetContext, t);
      if (bytes == null || !mounted) return false;
      _setBackground(BatchBackground(type: BackgroundType.image, imageBytes: bytes));
      return true;
    });
  }

  Widget _options(BuildContext context, bool running) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    const grey = Color(0xFFB0BEC5);

    Widget swatch({
      String? label,
      Color? color,
      List<Color>? gradient,
      required bool selected,
      required BatchBackground value,
    }) =>
        BackgroundSwatch(
          label: label,
          color: color,
          gradient: gradient,
          selected: selected,
          onTap: running ? () {} : () => _setBackground(value),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.editorToolBackground, style: theme.textTheme.labelMedium),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: BackgroundChoiceButton(
                  icon: Icons.add_photo_alternate_outlined,
                  label: l10n.backgroundAddCustom,
                  selected: _bg.type == BackgroundType.image,
                  onTap: running ? () {} : _pickPhoto,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: BackgroundChoiceButton(
                  icon: Icons.palette_outlined,
                  label: l10n.backgroundCustomColor,
                  selected: _bg.type == BackgroundType.solidColor &&
                      !kPresetBackgroundColors.contains(_bg.color),
                  swatch: _bg.type == BackgroundType.solidColor ? _bg.color : null,
                  onTap: running
                      ? () {}
                      : () => showColorPickerSheet(
                            context,
                            initial: _bg.color ?? kPresetBackgroundColors[4],
                            onChanged: (c) => _setBackground(
                              BatchBackground(
                                  type: BackgroundType.solidColor, color: c),
                            ),
                          ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          BackgroundChoiceButton(
            icon: Icons.auto_awesome_mosaic_rounded,
            label: l10n.editorToolTemplates,
            selected: false,
            onTap: running ? () {} : _pickTemplate,
          ),
          const SizedBox(height: 8),
          Wrap(
            runSpacing: 4,
            children: [
              swatch(
                label: l10n.backgroundWhite,
                color: Colors.white,
                selected: _bg.type == BackgroundType.white,
                value: const BatchBackground(type: BackgroundType.white),
              ),
              swatch(
                label: l10n.backgroundTransparent,
                selected: _bg.type == BackgroundType.transparent,
                value: const BatchBackground(),
              ),
              swatch(
                label: l10n.backgroundBlack,
                color: Colors.black,
                selected: _bg.type == BackgroundType.black,
                value: const BatchBackground(type: BackgroundType.black),
              ),
              swatch(
                label: l10n.backgroundBlurLabel,
                color: grey,
                selected: _bg.type == BackgroundType.gaussianBlur,
                value: const BatchBackground(type: BackgroundType.gaussianBlur),
              ),
              for (var i = 0; i < kGradientPresets.length; i++)
                swatch(
                  gradient: [
                    Color(kGradientPresets[i][0]),
                    Color(kGradientPresets[i][1]),
                  ],
                  selected: _bg.type == BackgroundType.gradient &&
                      _bg.gradientIndex == i,
                  value: BatchBackground(
                      type: BackgroundType.gradient, gradientIndex: i),
                ),
              for (final c in kPresetBackgroundColors)
                swatch(
                  color: c,
                  selected: _bg.type == BackgroundType.solidColor && _bg.color == c,
                  value: BatchBackground(type: BackgroundType.solidColor, color: c),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(l10n.exportMarketplaceLabel, style: theme.textTheme.labelMedium),
          Wrap(
            spacing: 8,
            children: [
              for (final preset in kMarketplacePresets)
                ChoiceChip(
                  label: Text(preset.name),
                  selected: _marketplace == preset,
                  onSelected: running
                      ? null
                      : (on) => setState(() {
                            _marketplace = on ? preset : null;
                            if (on && preset.pureWhite) {
                              _bg = const BatchBackground(type: BackgroundType.white);
                            }
                          }),
                ),
            ],
          ),
          if (_marketplace != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.exportMarketplaceSummary(
                  _marketplace!.width,
                  _marketplace!.height,
                  _marketplace!.format == ExportFormat.png ? 'PNG' : 'JPG',
                ),
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final theme = Theme.of(context);

    return ValueListenableBuilder<BatchProgress>(
      valueListenable: _progress,
      builder: (context, progress, _) {
        return PopScope(
          canPop: !progress.running,
          child: AppScaffold(
            appBar: AppBar(title: Text(l10n.batchTitle)),
            body: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: widget.imagePaths.length + 1,
                    itemBuilder: (context, i) => i == 0
                        ? _options(context, progress.running)
                        : _Row(
                            path: widget.imagePaths[i - 1],
                            status: progress.items[i - 1],
                          ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    border: Border(
                      top: BorderSide(color: palette.separator, width: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (progress.running || progress.finished) ...[
                        LinearProgressIndicator(
                          value: progress.total == 0
                              ? 0
                              : progress.processedCount / progress.total,
                        ),
                        const SizedBox(height: AppSpace.s),
                        Text(
                          progress.finished
                              ? [
                                  l10n.batchSaved(progress.doneCount),
                                  if (progress.failedCount > 0)
                                    l10n.batchSomeFailed(progress.failedCount),
                                ].join('\n')
                              : l10n.batchProgress(
                                  progress.processedCount, progress.total),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: palette.text2),
                        ),
                        const SizedBox(height: AppSpace.m),
                      ],
                      if (progress.running)
                        OutlinedButton(
                          onPressed: () => _stopRequested = true,
                          child: Text(l10n.batchStop),
                        )
                      else if (progress.finished)
                        PrimaryButton(
                          label: l10n.batchDone,
                          onPressed: () => context.go('/'),
                        )
                      else
                        PrimaryButton(
                          label: l10n.batchStart,
                          onPressed: _start,
                        ),
                    ],
                  ),
                ),
                const AdBannerSlot(personalized: false),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.path, required this.status});

  final String path;
  final BatchItemStatus status;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final Widget trailing = switch (status) {
      BatchItemStatus.waiting =>
        Icon(Icons.schedule_rounded, color: p.text3),
      BatchItemStatus.working => const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      BatchItemStatus.done =>
        Icon(Icons.check_circle_rounded, color: p.accent),
      BatchItemStatus.failed =>
        Icon(Icons.error_outline_rounded, color: p.text3),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.s),
            child: SizedBox(
              width: 56,
              height: 56,
              child: Image.file(
                File(path),
                fit: BoxFit.cover,
                cacheWidth: 112,
                excludeFromSemantics: true,
                errorBuilder: (_, __, ___) =>
                    ColoredBox(color: p.separator),
              ),
            ),
          ),
          const Spacer(),
          trailing,
        ],
      ),
    );
  }
}
