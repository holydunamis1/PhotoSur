import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/models/editable_image_state.dart';
import '../core/providers/image_edit_provider.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/background_presets.dart';
import '../core/utils/constants.dart';
import '../generated/l10n/app_localizations.dart';
import 'labeled_slider.dart';

/// Preset swatches (no color-picker package is in the dependency manifest,
/// so a curated swatch row is used instead of an HSV wheel).
const List<Color> _presetSwatches = [
  Color(0xFFEF4444),
  Color(0xFFF59E0B),
  Color(0xFFEAB308),
  Color(0xFF22C55E),
  Color(0xFF10B981),
  Color(0xFF06B6D4),
  Color(0xFF3B82F6),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
  Color(0xFF6B7280),
];

/// Background tool: White, Transparent, Black, color swatches, and Blur.
class BackgroundSelector extends StatelessWidget {
  const BackgroundSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ImageEditProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context);

    return ValueListenableBuilder<EditableImageState>(
      valueListenable: provider,
      builder: (context, state, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 70,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _Swatch(
                    label: l10n.backgroundWhite,
                    color: Colors.white,
                    selected: state.backgroundType == BackgroundType.white,
                    onTap: () => provider.setBackgroundType(BackgroundType.white),
                  ),
                  _Swatch(
                    label: l10n.backgroundTransparent,
                    color: null,
                    selected: state.backgroundType == BackgroundType.transparent,
                    onTap: () =>
                        provider.setBackgroundType(BackgroundType.transparent),
                  ),
                  _Swatch(
                    label: l10n.backgroundBlack,
                    color: Colors.black,
                    selected: state.backgroundType == BackgroundType.black,
                    onTap: () => provider.setBackgroundType(BackgroundType.black),
                  ),
                  for (var i = 0; i < kGradientPresets.length; i++)
                    _Swatch(
                      label: null,
                      color: null,
                      gradient: [
                        Color(kGradientPresets[i][0]),
                        Color(kGradientPresets[i][1]),
                      ],
                      selected: state.backgroundType == BackgroundType.gradient &&
                          state.gradientIndex == i,
                      onTap: () => provider.setGradient(i),
                    ),
                  _Swatch(
                    label: l10n.backgroundPhoto,
                    color: null,
                    icon: Icons.add_photo_alternate_outlined,
                    selected: state.backgroundType == BackgroundType.image,
                    onTap: () => _pickPhoto(context, provider),
                  ),
                  for (final swatch in _presetSwatches)
                    _Swatch(
                      label: null,
                      color: swatch,
                      selected: state.backgroundType == BackgroundType.solidColor &&
                          state.bgColor == swatch,
                      onTap: () => provider.setBgColor(swatch),
                    ),
                ],
              ),
            ),
            LabeledSlider(
              label: l10n.backgroundBlurLabel,
              value: state.blurRadius,
              min: kBackgroundBlurMinPx,
              max: kBackgroundBlurMaxPx,
              onChanged: provider.setBlurRadius,
              valueText: state.blurRadius.round().toString(),
            ),
          ],
        );
      },
    );
  }
}

Future<void> _pickPhoto(BuildContext context, ImageEditProvider provider) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    if (picked == null) return;
    provider.setBackgroundImage(await picked.readAsBytes());
  } catch (_) {
    messenger?.showSnackBar(SnackBar(content: Text(l10n.backgroundPhotoFailed)));
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    this.gradient,
    this.icon,
  });

  /// Two colours, top to bottom (gradient swatch).
  final List<Color>? gradient;

  /// Glyph shown instead of a fill (the "Photo" swatch).
  final IconData? icon;

  final String? label;
  final Color? color; // null = transparent (checkerboard)
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      width: 68,
      child: InkResponse(
        onTap: onTap,
        radius: 34,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? p.accent : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    gradient: gradient == null
                        ? null
                        : LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: gradient!,
                          ),
                    shape: BoxShape.circle,
                    border: Border.all(color: p.separator, width: 0.5),
                  ),
                  child: icon != null
                      ? Icon(icon, size: 22, color: p.text2)
                      : (color == null && gradient == null
                          ? const CustomPaint(painter: _CheckerPainter())
                          : null),
                ),
              ),
            ),
            if (label != null) ...[
              const SizedBox(height: 2),
              Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const tile = 6.0;
    final light = Paint()..color = const Color(0xFFE6E6EA);
    final dark = Paint()..color = const Color(0xFFB8B8BF);
    canvas.drawRect(Offset.zero & size, light);
    for (var y = 0.0; y < size.height; y += tile) {
      for (var x = 0.0; x < size.width; x += tile) {
        if (((x ~/ tile) + (y ~/ tile)) % 2 == 0) {
          canvas.drawRect(Rect.fromLTWH(x, y, tile, tile), dark);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
