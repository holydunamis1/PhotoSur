import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import '../core/utils/extensions.dart';
import '../generated/l10n/app_localizations.dart';

/// Quiet two-tone checkerboard shown behind transparent exports.
class CheckerboardPainter extends CustomPainter {
  const CheckerboardPainter({required this.light, required this.dark, this.tile = 8});

  final Color light;
  final Color dark;
  final double tile;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = light);
    final darkPaint = Paint()..color = dark;
    var row = 0;
    for (var y = 0.0; y < size.height; y += tile, row++) {
      var col = 0;
      for (var x = 0.0; x < size.width; x += tile, col++) {
        if ((row + col).isOdd) {
          canvas.drawRect(Rect.fromLTWH(x, y, tile, tile), darkPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(CheckerboardPainter old) =>
      old.light != light || old.dark != dark || old.tile != tile;
}

/// The checkerboard in the app's light or dark tones.
class ExportCheckerboard extends StatelessWidget {
  const ExportCheckerboard({super.key, this.tile = 8});

  final double tile;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkMode;
    return CustomPaint(
      painter: CheckerboardPainter(
        light: dark ? const Color(0xFF26262A) : const Color(0xFFF3F3F6),
        dark: dark ? const Color(0xFF1E1E21) : const Color(0xFFE6E6EB),
        tile: tile,
      ),
    );
  }
}

/// Placeholder for an export whose file is gone.
class ExportUnavailable extends StatelessWidget {
  const ExportUnavailable({super.key, this.compact = true});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = AppLocalizations.of(context);
    return ColoredBox(
      color: p.muted,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined,
                size: compact ? 22 : 40, color: p.text3),
            SizedBox(height: compact ? 4 : 8),
            Text(
              l10n.exportUnavailable,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: (compact
                      ? Theme.of(context).textTheme.labelSmall
                      : Theme.of(context).textTheme.bodyMedium)
                  ?.copyWith(color: p.text3),
            ),
          ],
        ),
      ),
    );
  }
}

/// A thumbnail decoded at roughly [pixelWidth] (so a grid of large exports
/// stays light), fading in over a checkerboard.
class ExportThumbnail extends StatelessWidget {
  const ExportThumbnail({super.key, required this.path, required this.pixelWidth});

  final String path;
  final int pixelWidth;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ExportCheckerboard(),
        Image.file(
          File(path),
          fit: BoxFit.cover,
          cacheWidth: pixelWidth,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          excludeFromSemantics: true,
          frameBuilder: (context, child, frame, sync) {
            if (sync) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: child,
            );
          },
          errorBuilder: (context, error, stack) => const ExportUnavailable(),
        ),
      ],
    );
  }
}
