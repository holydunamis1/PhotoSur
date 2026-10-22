import 'dart:async' show unawaited;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/models/editable_image_state.dart';
import '../core/providers/image_edit_provider.dart';
import '../core/providers/settings_provider.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/constants.dart';
import '../generated/l10n/app_localizations.dart';
import '../platform/image_prep_service.dart';
import '../platform/model_download_service.dart';
import '../platform/notification_service.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/editor_canvas.dart';
import '../widgets/editor_tool_dock.dart';
import '../widgets/editor_tool_panel.dart';
import '../widgets/editor_top_bar.dart';
import '../widgets/fallback_manual_editor.dart';
import '../widgets/hd_model_ui.dart' show redoCutout;
import '../widgets/loading_overlay.dart';
import 'export_bottom_sheet.dart';


class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.imagePath});

  final String imagePath;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with WidgetsBindingObserver {
  EditorTool _tool = EditorTool.cutout;
  late final ImageEditProvider _provider;
  late final SettingsProvider _settings;

  // Reminder text, captured while a BuildContext is available so it can be
  // used later from dispose / lifecycle callbacks.
  String _reminderTitle = '';
  String _reminderBody = '';
  String _reminderChannelName = '';
  String _reminderChannelDescription = '';

  @override
  void initState() {
    super.initState();
    _provider = Provider.of<ImageEditProvider>(context, listen: false);
    _settings = Provider.of<SettingsProvider>(context, listen: false);
    WidgetsBinding.instance.addObserver(this);
    // The user is editing again: any pending reminder is obsolete.
    unawaited(NotificationService.instance.cancelUnfinishedEditReminder());
    if (kNotificationsEnabled && _settings.value.remindersEnabled) {
      // At most one OS prompt per app session.
      unawaited(NotificationService.instance.ensurePermissionOncePerSession());
    }
    _loadAndSegment();
    _startAutoHd();
  }

  // ---- HD model: fetched automatically on the very first photo ----------
  void _startAutoHd() {
    final hd = ModelDownloadService.instance;
    if (hd.value.isInstalled) return;
    if (!hd.value.isDownloading && !_settings.value.hdAutoDownloadTried) {
      hd.autoRedoPending = true;
      // Deferred until after the first frame: changing settings straight from
      // initState makes the router rebuild mid-build, which built the editor
      // twice and cut every photo out twice. The flag is recorded before the
      // download starts, so a failure or a later removal in Settings never
      // triggers another silent download.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_settings.markHdAutoDownloadTried());
        unawaited(hd.download());
      });
    }
    // Whichever editor is on screen when the download ends does the redo, so
    // this listener belongs to every editor instance, not just the first.
    if (hd.autoRedoPending) hd.addListener(_onHdChanged);
  }

  // When the download finishes while this photo is still untouched, redo the
  // cut-out with HD. Any brush stroke means the user is editing: leave it.
  void _onHdChanged() {
    final hd = ModelDownloadService.instance;
    if (hd.value.status == HdModelStatus.downloading) return;
    hd.removeListener(_onHdChanged);
    if (!hd.autoRedoPending) return;
    hd.autoRedoPending = false;
    if (hd.value.isInstalled) _redoWhenIdle();
  }

  // The first (standard) cut-out may still be computing when HD arrives:
  // wait for it to finish, then redo once if the user has not edited.
  void _redoWhenIdle() {
    if (!mounted) return;
    final state = _provider.value;
    if (state.isProcessing) {
      void once() {
        if (_provider.value.isProcessing) return;
        _provider.removeListener(once);
        _redoWhenIdle();
      }

      _provider.addListener(once);
      return;
    }
    if (state.autoSegmentationFailed || state.historyIndex >= 0) return;
    unawaited(redoCutout(_provider));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context);
    _reminderTitle = l10n.reminderTitle;
    _reminderBody = l10n.reminderBody;
    _reminderChannelName = l10n.reminderChannelName;
    _reminderChannelDescription = l10n.reminderChannelDescription;
  }

  void _scheduleReminderIfUnfinished() {
    if (!kNotificationsEnabled ||
        !_settings.value.remindersEnabled ||
        !_provider.hasUnfinishedEdit) {
      return;
    }
    unawaited(
      NotificationService.instance.scheduleUnfinishedEditReminder(
        title: _reminderTitle,
        body: _reminderBody,
        channelName: _reminderChannelName,
        channelDescription: _reminderChannelDescription,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _scheduleReminderIfUnfinished();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(NotificationService.instance.cancelUnfinishedEditReminder());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ModelDownloadService.instance.removeListener(_onHdChanged);
    // Leaving the editor without exporting.
    _scheduleReminderIfUnfinished();
    super.dispose();
  }

  Future<void> _loadAndSegment() async {
    // Show the spinner immediately; decoding, EXIF rotation, resizing and
    // model preprocessing all run in a background isolate.
    _provider.value = const EditableImageState(isProcessing: true);
    try {
      final tempDir = await getTemporaryDirectory();
      final prepared = await prepareImage(widget.imagePath, tempDir.path);
      if (!mounted) return;
      _provider.loadImage(
        prepared.path,
        ui.Size(prepared.width.toDouble(), prepared.height.toDouble()),
      );
      await _provider.autoSegment(
        prepared.modelInput,
        prepared.width,
        prepared.height,
        guideGray: prepared.guideGray,
      );
    } catch (_) {
      if (!mounted) return;
      _provider.value = _provider.value.copyWith(
        isProcessing: false,
        autoSegmentationFailed: true,
      );
    }
  }

  void _openExportSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const ExportBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: ValueListenableBuilder<EditableImageState>(
          valueListenable: _provider,
          builder: (context, state, _) {
            final failed = state.autoSegmentationFailed;
            return Column(
              children: [
                EditorTopBar(
                  onBack: () => context.pop(),
                  onExport: _openExportSheet,
                  showEditActions: !failed,
                ),
                Expanded(
                  child: failed
                      // Auto-removal unavailable: manual brush only, with
                      // its own controls.
                      ? const FallbackManualEditor()
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.l),
                            child: ColoredBox(
                              color: palette.surface,
                              child: Stack(
                                children: [
                                  EditorCanvas(
                                    brushEnabled: _tool == EditorTool.brush,
                                    moveEnabled: _tool == EditorTool.layout,
                                  ),
                                  LoadingOverlay(visible: state.isProcessing),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
                if (!failed) ...[
                  EditorToolPanel(tool: _tool),
                  EditorToolDock(
                    selected: _tool,
                    onSelected: (tool) => setState(() => _tool = tool),
                  ),
                ],
                const AdBannerSlot(personalized: false),
              ],
            );
          },
        ),
      ),
    );
  }
}
