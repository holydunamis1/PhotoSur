import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/models/editable_image_state.dart';
import '../core/providers/image_edit_provider.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/constants.dart';
import '../generated/l10n/app_localizations.dart';
import '../platform/image_prep_service.dart';
import '../platform/model_download_service.dart';
import 'edge_feather_slider.dart';

/// Asks before downloading the HD model (it is large), then starts the
/// download in the background. Returns true when a download was started.
Future<bool> confirmHdDownload(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.hdConfirmTitle),
      content: Text(l10n.hdConfirmBody(kHdModelMegabytes.toString())),
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
                label: Text(l10n.hdGetAction(kHdModelMegabytes.toString())),
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
              onPressed: ModelDownloadService.instance.remove,
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
            subtitle = l10n.settingsHdNotInstalled(kHdModelMegabytes.toString());
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
