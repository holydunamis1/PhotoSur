import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/models/export_job.dart';
import '../core/services/export_library_service.dart';
import '../core/services/share_service.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/extensions.dart';
import '../generated/l10n/app_localizations.dart';
import 'toast_notification.dart';

enum ExportAction { share, save, edit, delete }

/// Opens the actions for one export as a bottom sheet. A missing file only
/// offers Delete (to clear the dead record).
Future<void> showExportActions(BuildContext context, ExportJob job) async {
  final available = await File(job.filePath).exists();
  if (!context.mounted) return;
  final action = await showModalBottomSheet<ExportAction>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: context.palette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => _ActionSheet(available: available),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case ExportAction.share:
      await shareExport(context, job);
    case ExportAction.save:
      await saveExportToGallery(context, job);
    case ExportAction.edit:
      editExportAgain(context, job);
    case ExportAction.delete:
      await deleteExportsWithConfirm(context, [job]);
  }
}

Future<void> shareExport(BuildContext context, ExportJob job) async {
  final l10n = AppLocalizations.of(context);
  try {
    final file = File(job.filePath);
    if (!await file.exists()) {
      if (context.mounted) {
        ToastNotification.show(context,
            message: l10n.homeExportUnavailable, type: ToastType.error);
      }
      return;
    }
    await ShareService.instance.shareImage(
      await file.readAsBytes(),
      filename: file.uri.pathSegments.last,
    );
  } catch (_) {
    if (context.mounted) {
      ToastNotification.show(context,
          message: l10n.homeShareFailed, type: ToastType.error);
    }
  }
}

/// Shares several exports in one share sheet. Files that no longer exist are
/// skipped; if none are left the user sees the "unavailable" message.
Future<void> shareExports(BuildContext context, List<ExportJob> jobs) async {
  final l10n = AppLocalizations.of(context);
  try {
    final paths = <String>[
      for (final job in jobs)
        if (File(job.filePath).existsSync()) job.filePath,
    ];
    if (paths.isEmpty) {
      if (context.mounted) {
        ToastNotification.show(context,
            message: l10n.homeExportUnavailable, type: ToastType.error);
      }
      return;
    }
    await ShareService.instance.shareFiles(paths);
  } catch (_) {
    if (context.mounted) {
      ToastNotification.show(context,
          message: l10n.homeShareFailed, type: ToastType.error);
    }
  }
}

Future<void> saveExportToGallery(BuildContext context, ExportJob job) async {
  final l10n = AppLocalizations.of(context);
  try {
    final file = File(job.filePath);
    if (!await file.exists()) {
      if (context.mounted) {
        ToastNotification.show(context,
            message: l10n.homeExportUnavailable, type: ToastType.error);
      }
      return;
    }
    final saved = await ShareService.instance.saveToGallery(
      await file.readAsBytes(),
      filePath: job.filePath.toLowerCase().endsWith('.webp')
          ? job.filePath
          : null,
    );
    if (!context.mounted) return;
    ToastNotification.show(
      context,
      message: saved ? l10n.exportSavedToGallery : l10n.exportSaveFailed,
      type: saved ? ToastType.success : ToastType.error,
    );
  } catch (_) {
    if (context.mounted) {
      ToastNotification.show(context,
          message: l10n.exportSaveFailed, type: ToastType.error);
    }
  }
}

/// Reopens the exported image as a new photo (crop, then the editor). The
/// edit session itself is not kept after export, so this starts from the
/// flattened image.
void editExportAgain(BuildContext context, ExportJob job) {
  final l10n = AppLocalizations.of(context);
  if (!File(job.filePath).existsSync()) {
    ToastNotification.show(context,
        message: l10n.homeExportUnavailable, type: ToastType.error);
    return;
  }
  context.push('/crop', extra: job.filePath);
}

/// Confirms, then deletes the files and records. Returns true when deleted.
/// [all] also clears leftover files in the exports folder.
Future<bool> deleteExportsWithConfirm(
  BuildContext context,
  List<ExportJob> jobs, {
  bool all = false,
}) async {
  if (jobs.isEmpty && !all) return false;
  final l10n = AppLocalizations.of(context);
  final title = all
      ? l10n.exportsDeleteAllTitle
      : jobs.length == 1
          ? l10n.exportDeleteTitle
          : l10n.exportsDeleteSelectedTitle(jobs.length);
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: context.palette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => _ConfirmDeleteSheet(title: title),
  );
  if (confirmed != true) return false;
  HapticFeedback.mediumImpact();
  try {
    if (all) {
      await ExportLibraryService.instance.deleteAll();
    } else {
      await ExportLibraryService.instance.deleteMany(jobs);
    }
    return true;
  } catch (_) {
    return false;
  }
}

class _ActionSheet extends StatelessWidget {
  const _ActionSheet({required this.available});

  final bool available;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = context.palette;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.l, 0, AppSpace.l, AppSpace.l),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: p.background,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(AppRadius.l),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (available) ...[
                _Row(
                  icon: Icons.ios_share_rounded,
                  label: l10n.exportShare,
                  action: ExportAction.share,
                ),
                _Divider(color: p.separator),
                _Row(
                  icon: Icons.download_rounded,
                  label: l10n.exportSaveToGallery,
                  action: ExportAction.save,
                ),
                _Divider(color: p.separator),
                _Row(
                  icon: Icons.tune_rounded,
                  label: l10n.exportActionEdit,
                  action: ExportAction.edit,
                ),
                _Divider(color: p.separator),
              ],
              _Row(
                icon: Icons.delete_outline_rounded,
                label: l10n.exportActionDelete,
                action: ExportAction.delete,
                destructive: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      Divider(height: 0.5, thickness: 0.5, indent: 52, color: color);
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.action,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final ExportAction action;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = destructive ? p.danger : p.text;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.l),
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).pop(action);
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.l),
          child: Row(
            children: [
              Icon(icon, size: 22, color: destructive ? p.danger : p.accentText),
              const SizedBox(width: AppSpace.m),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: color, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmDeleteSheet extends StatelessWidget {
  const _ConfirmDeleteSheet({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = context.palette;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.xl, 0, AppSpace.xl, AppSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: p.text, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpace.s),
            Text(
              l10n.exportDeleteBody,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: p.text2),
            ),
            const SizedBox(height: AppSpace.xl),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: p.danger,
                  foregroundColor: context.isDarkMode
                      ? const Color(0xFF2A0705)
                      : Colors.white,
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(AppRadius.m),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.exportActionDelete),
              ),
            ),
            const SizedBox(height: AppSpace.s),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.resetConfirmCancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
