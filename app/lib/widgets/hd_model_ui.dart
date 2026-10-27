import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/models/editable_image_state.dart';
import '../core/providers/image_edit_provider.dart';
import '../core/providers/settings_provider.dart';
import '../core/theme/app_tokens.dart';
import '../generated/l10n/app_localizations.dart';
import '../platform/image_prep_service.dart';
import '../platform/model_download_service.dart';
import 'background_selector.dart' show BackgroundChoiceButton;
import 'edge_feather_slider.dart';

/// Asks before downloading the HD model (it is large), then starts the
/// download in the background. Returns true when a download was started.
Future<bool> confirmHdDownload(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.hdConfirmTitle),
      content: Text(l10n.hdConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.resetConfirmCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.hdDownload),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    if (context.mounted) {
      Provider.of<SettingsProvider>(context, listen: false)
          .setHdRemovedByUser(false);
    }
  } catch (_) {
    // No settings in scope: the download still starts.
  }
  ModelDownloadService.instance.download();
  return true;
}

/// Re-runs the automatic cut-out on the open photo (now with the HD model).
Future<void> redoCutout(ImageEditProvider provider) async {
  final path = provider.value.originalPath;
  final size = provider.value.imageSize;
  if (path == null || size == null) return;
  try {
    final dir = await getTemporaryDirectory();
    final prepared = await prepareImage(path, dir.path);
    await provider.autoSegment(
      prepared.modelInput,
      prepared.width,
      prepared.height,
      guideGray: prepared.guideGray,
    );
  } catch (_) {
    // autoSegment reports its own failure state; a prep failure keeps the
    // current cut-out untouched.
  }
}

/// Cut-out tool panel: edge smoothness plus the HD cut-out action.
class CutoutControls extends StatelessWidget {
  const CutoutControls({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EdgeFeatherSlider(),
        _HdCutoutChip(),
      ],
    );
  }
}

class _HdCutoutChip extends StatelessWidget {
  const _HdCutoutChip();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = context.palette;
    final provider = Provider.of<ImageEditProvider>(context, listen: false);
    return ValueListenableBuilder<HdModelState>(
      valueListenable: ModelDownloadService.instance,
      builder: (context, hd, _) {
        return ValueListenableBuilder<EditableImageState>(
          valueListenable: provider,
          builder: (context, state, _) {
            final Widget chip;
            if (hd.isDownloading) {
              chip = ActionChip(
                avatar: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: hd.progress > 0 ? hd.progress : null,
                  ),
                ),
                label: Text(l10n.hdDownloading((hd.progress * 100).round().toString())),
                onPressed: null,
              );
            } else if (hd.isInstalled) {
              chip = ActionChip(
                avatar: Icon(Icons.auto_fix_high_rounded, size: 18, color: p.accentText),
                label: Text(l10n.hdRedoAction),
                onPressed: state.isProcessing || state.originalPath == null
                    ? null
                    : () => redoCutout(provider),
              );
            } else {
              chip = ActionChip(
                avatar: Icon(Icons.download_rounded, size: 18, color: p.accentText),
                label: Text(l10n.hdGetAction),
                onPressed: () => confirmHdDownload(context),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  chip,
                  if (hd.status == HdModelStatus.failed)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        l10n.hdFailed,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: p.danger),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Settings row: download, see progress, or remove the HD model.
class HdModelTile extends StatelessWidget {
  const HdModelTile({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<HdModelState>(
      valueListenable: ModelDownloadService.instance,
      builder: (context, hd, _) {
        final String subtitle;
        Widget? trailing;
        VoidCallback? onTap;
        switch (hd.status) {
          case HdModelStatus.installed:
            subtitle = l10n.settingsHdInstalled;
            trailing = TextButton(
              onPressed: () {
                try {
                  Provider.of<SettingsProvider>(context, listen: false)
                      .setHdRemovedByUser(true);
                } catch (_) {
                  // No settings in scope: removal itself still happens.
                }
                ModelDownloadService.instance.remove();
              },
              child: Text(l10n.settingsHdRemove),
            );
          case HdModelStatus.downloading:
            subtitle = l10n.hdDownloading((hd.progress * 100).round().toString());
            trailing = SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: hd.progress > 0 ? hd.progress : null,
              ),
            );
          case HdModelStatus.failed:
            subtitle = l10n.hdFailed;
            onTap = () => confirmHdDownload(context);
          case HdModelStatus.notInstalled:
            subtitle = l10n.settingsHdNotInstalled;
            onTap = () => confirmHdDownload(context);
        }
        return ListTile(
          leading: const Icon(Icons.auto_fix_high_rounded),
          title: Text(l10n.settingsHdTitle),
          subtitle: Text(subtitle),
          trailing: trailing,
          onTap: onTap,
        );
      },
    );
  }
}


/// The HD model as a button next to the other batch options: get it, watch
/// the download, or see that it is installed. Installed means every photo in
/// the batch is cut out with it.
class HdModelButton extends StatelessWidget {
  const HdModelButton({super.key, this.enabled = true});

  /// False while a batch runs, so the model can't change mid-batch.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = context.palette;
    return ValueListenableBuilder<HdModelState>(
      valueListenable: ModelDownloadService.instance,
      builder: (context, hd, _) {
        final Widget button;
        if (hd.isDownloading) {
          button = BackgroundChoiceButton(
            icon: Icons.downloading_rounded,
            label: l10n.hdDownloadingShort((hd.progress * 100).round().toString()),
            selected: false,
            onTap: () {},
          );
        } else if (hd.isInstalled) {
          button = BackgroundChoiceButton(
            icon: Icons.check_circle_outline_rounded,
            label: l10n.settingsHdTitle,
            selected: true,
            onTap: () {},
          );
        } else {
          button = BackgroundChoiceButton(
            icon: Icons.download_rounded,
            label: l10n.hdGetAction,
            selected: false,
            onTap: enabled ? () => confirmHdDownload(context) : () {},
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            button,
            if (hd.status == HdModelStatus.failed)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  l10n.hdFailed,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: p.danger),
                ),
              ),
          ],
        );
      },
    );
  }
}
