import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/models/batch_progress.dart';
import '../core/providers/ad_provider.dart';
import '../core/theme/app_tokens.dart';
import '../generated/l10n/app_localizations.dart';
import '../platform/batch_service.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/primary_button.dart';

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
  bool _white = false;
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
        whiteBackground: _white,
        serial: i,
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(
                            l10n.batchOutputTransparent,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(
                            l10n.batchOutputWhite,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                      selected: {_white},
                      onSelectionChanged: progress.running
                          ? null
                          : (s) => setState(() => _white = s.first),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: widget.imagePaths.length,
                    itemBuilder: (context, i) => _Row(
                      path: widget.imagePaths[i],
                      status: progress.items[i],
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
