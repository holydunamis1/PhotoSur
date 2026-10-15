import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/export_job.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/date_formatter.dart';
import '../core/utils/extensions.dart';
import '../generated/l10n/app_localizations.dart';
import 'export_thumbnail.dart';

/// One export in the library grid: a squircle thumbnail over a checkerboard,
/// a frosted format badge, date and pixel size, and a "more" button. Tap
/// opens the viewer; long-press or the more button opens the actions.
/// In selection mode it shows a check instead of the more button.
class RecentExportTile extends StatefulWidget {
  const RecentExportTile({
    super.key,
    required this.job,
    required this.onTap,
    required this.onMore,
    this.selectionMode = false,
    this.selected = false,
  });

  final ExportJob job;
  final VoidCallback onTap;
  final VoidCallback onMore;
  final bool selectionMode;
  final bool selected;

  @override
  State<RecentExportTile> createState() => _RecentExportTileState();
}

class _RecentExportTileState extends State<RecentExportTile> {
  static const double _radius = 18;

  late bool _available = File(widget.job.filePath).existsSync();
  bool _pressed = false;

  @override
  void didUpdateWidget(RecentExportTile old) {
    super.didUpdateWidget(old);
    if (old.job.filePath != widget.job.filePath) {
      _available = File(widget.job.filePath).existsSync();
    }
  }

  void _tap() {
    HapticFeedback.selectionClick();
    widget.onTap();
  }

  void _more() {
    HapticFeedback.mediumImpact();
    widget.onMore();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = context.palette;
    final dark = context.isDarkMode;
    final job = widget.job;
    final date = DateFormatter.relative(
      job.createdAt,
      locale: Localizations.localeOf(context).toString(),
      todayLabel: l10n.dateToday,
      yesterdayLabel: l10n.dateYesterday,
    );
    final format = _formatLabel(job.format);
    final size = '${job.width}×${job.height}';
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(_radius),
    );
    final outline = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(_radius),
      side: BorderSide(
        color: widget.selected
            ? p.accent
            : (dark ? p.separator : const Color(0x0F000000)),
        width: widget.selected ? 2.5 : 0.5,
      ),
    );

    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: true,
      selected: widget.selected,
      label: _available ? '$format, $size, $date' : l10n.exportUnavailable,
      onTap: widget.onTap,
      onLongPress: widget.onMore,
      child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: _tap,
          onLongPress: _more,
          child: AnimatedScale(
            scale: _pressed ? 0.97 : 1,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: LayoutBuilder(
              builder: (context, box) {
                final dpr = MediaQuery.devicePixelRatioOf(context);
                final pixelWidth = (box.maxWidth * dpr).round().clamp(64, 1024);
                return DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: shape,
                    color: p.surface,
                    shadows: dark
                        ? const []
                        : const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 14,
                              offset: Offset(0, 5),
                            ),
                            BoxShadow(
                              color: Color(0x0A000000),
                              blurRadius: 2,
                              offset: Offset(0, 1),
                            ),
                          ],
                  ),
                  child: ClipPath(
                    clipper: ShapeBorderClipper(shape: shape),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ExcludeSemantics(
                          child: _available
                              ? ExportThumbnail(
                                  path: job.filePath,
                                  pixelWidth: pixelWidth,
                                )
                              : const ExportUnavailable(),
                        ),
                        if (_available) ...[
                          PositionedDirectional(
                            top: 8,
                            start: 8,
                            child: ExcludeSemantics(
                              child: _Frosted(
                              radius: 7,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              child: Text(
                                format,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: ExcludeSemantics(
                              child: DecoratedBox(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Color(0x00000000), Color(0x8C000000)],
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    9, 16, 9, 7),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      date,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      size,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xCCFFFFFF),
                                        fontSize: 10,
                                        fontFeatures: [
                                          ui.FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            ),
                          ),
                        ],
                        if (widget.selected)
                          ColoredBox(color: p.accent.withValues(alpha: 0.18)),
                        PositionedDirectional(
                          top: 0,
                          end: 0,
                          child: widget.selectionMode
                              ? _SelectionMark(selected: widget.selected)
                              : _MoreButton(onTap: _more),
                        ),
                        IgnorePointer(
                          child: DecoratedBox(
                            decoration: ShapeDecoration(shape: outline),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
    );
  }

  static String _formatLabel(ExportFormat format) => switch (format) {
        ExportFormat.png => 'PNG',
        ExportFormat.jpg => 'JPG',
        ExportFormat.webp => 'WEBP',
      };
}

/// Frosted-glass pill used over thumbnails.
class _Frosted extends StatelessWidget {
  const _Frosted({
    required this.child,
    required this.radius,
    required this.padding,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding,
          color: const Color(0x59000000),
          child: child,
        ),
      ),
    );
  }
}

/// A 44 x 44 touch target holding a 28 px frosted circle.
class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.exportMoreOptions,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: ClipOval(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  width: 28,
                  height: 28,
                  color: const Color(0x59000000),
                  child: const Icon(
                    Icons.more_horiz_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? p.accent : const Color(0x59000000),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: selected
            ? Icon(Icons.check_rounded, size: 16, color: p.onAccent)
            : null,
      ),
    );
  }
}
