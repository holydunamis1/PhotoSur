import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/export_job.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/date_formatter.dart';
import '../generated/l10n/app_localizations.dart';
import '../widgets/export_actions.dart';
import '../widgets/export_thumbnail.dart';

/// What the viewer needs: the exports to page through and where to start.
class ExportViewerArgs {
  const ExportViewerArgs({required this.jobs, required this.index});

  final List<ExportJob> jobs;
  final int index;
}

/// Full-screen viewer: swipe between exports, pinch to zoom, and the same
/// actions as the tile menu in a bar at the bottom.
class ExportViewerScreen extends StatefulWidget {
  const ExportViewerScreen({super.key, required this.args});

  final ExportViewerArgs args;

  @override
  State<ExportViewerScreen> createState() => _ExportViewerScreenState();
}

class _ExportViewerScreenState extends State<ExportViewerScreen> {
  late final List<ExportJob> _jobs = List.of(widget.args.jobs);
  late final PageController _controller = PageController(
    initialPage: widget.args.index.clamp(0, widget.args.jobs.length - 1),
  );
  late int _page = _controller.initialPage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ExportJob get _current => _jobs[_page];

  Future<void> _delete() async {
    final job = _current;
    final deleted = await deleteExportsWithConfirm(context, [job]);
    if (!deleted || !mounted) return;
    if (_jobs.length == 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _jobs.removeAt(_page);
      if (_page >= _jobs.length) _page = _jobs.length - 1;
    });
    if (_controller.hasClients) _controller.jumpToPage(_page);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final job = _current;
    final date = DateFormatter.relative(
      job.createdAt,
      locale: Localizations.localeOf(context).toString(),
      todayLabel: l10n.dateToday,
      yesterdayLabel: l10n.dateYesterday,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: _jobs.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => _ViewerPage(job: _jobs[i]),
            ),
            PositionedDirectional(
              top: 0,
              start: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.s),
                  child: IconButton.filledTonal(
                    tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0x66000000),
                      foregroundColor: Colors.white,
                      fixedSize: const Size(44, 44),
                    ),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xCC000000)],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpace.l, AppSpace.xxl, AppSpace.l, AppSpace.m),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${job.width}×${job.height} · $date',
                          style: const TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: AppSpace.m),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _BarAction(
                              icon: Icons.ios_share_rounded,
                              label: l10n.exportShare,
                              onTap: () => shareExport(context, job),
                            ),
                            _BarAction(
                              icon: Icons.download_rounded,
                              label: l10n.exportSaveToGallery,
                              onTap: () => saveExportToGallery(context, job),
                            ),
                            _BarAction(
                              icon: Icons.tune_rounded,
                              label: l10n.exportActionEdit,
                              onTap: () => editExportAgain(context, job),
                            ),
                            _BarAction(
                              icon: Icons.delete_outline_rounded,
                              label: l10n.exportActionDelete,
                              color: const Color(0xFFFF6B61),
                              onTap: _delete,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerPage extends StatefulWidget {
  const _ViewerPage({required this.job});

  final ExportJob job;

  @override
  State<_ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<_ViewerPage> {
  late final bool _available = File(widget.job.filePath).existsSync();

  @override
  Widget build(BuildContext context) {
    if (!_available) return const ExportUnavailable(compact: false);
    final job = widget.job;
    final ratio = job.width > 0 && job.height > 0 ? job.width / job.height : 1.0;
    return InteractiveViewer(
      minScale: 1,
      maxScale: 5,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 120, top: 56),
          child: Center(
            child: AspectRatio(
              aspectRatio: ratio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ExportCheckerboard(tile: 12),
                  Image(
                    image: ResizeImage(
                      FileImage(File(job.filePath)),
                      width: 2048,
                    ),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                    errorBuilder: (context, error, stack) =>
                        const ExportUnavailable(compact: false),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  const _BarAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.m),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(
          width: 76,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.s),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 24, color: color),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
