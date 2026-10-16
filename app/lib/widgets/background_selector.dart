import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/models/editable_image_state.dart';
import '../core/providers/image_edit_provider.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/background_presets.dart';
import '../core/utils/color_hex.dart';
import '../core/utils/constants.dart';
import '../generated/l10n/app_localizations.dart';
import 'labeled_slider.dart';

/// Preset colours, kept as one-tap shortcuts next to the custom colour picker.
const List<Color> kPresetBackgroundColors = [
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

/// Fixed part of the swatch row's height (circle + gap + safety); the label's
/// own height is added on top, scaled with the user's text size.
const double kSwatchRowBaseHeight = 40;

/// Background tool: two labelled buttons (custom background photo, custom
/// colour) that are always visible, one row of quick choices and preset
/// colours (the only sideways-scrolling part, with a fade at the edge), and
/// Blur.
class BackgroundSelector extends StatelessWidget {
  const BackgroundSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ImageEditProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<EditableImageState>(
      valueListenable: provider,
      builder: (context, state, _) {
        final customColor = state.backgroundType == BackgroundType.solidColor
            ? state.bgColor
            : null;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: BackgroundChoiceButton(
                    icon: Icons.add_photo_alternate_outlined,
                    label: l10n.backgroundAddCustom,
                    selected: state.backgroundType == BackgroundType.image,
                    onTap: () => _pickPhoto(context, provider),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: BackgroundChoiceButton(
                    icon: Icons.palette_outlined,
                    label: l10n.backgroundCustomColor,
                    swatch: customColor,
                    selected: customColor != null,
                    onTap: () => showCustomColorSheet(context, provider),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: kSwatchRowBaseHeight +
                  MediaQuery.textScalerOf(context).scale(16),
              child: FadingSwatchRow(
                children: [
                  BackgroundSwatch(
                    label: l10n.backgroundWhite,
                    color: Colors.white,
                    selected: state.backgroundType == BackgroundType.white,
                    onTap: () =>
                        provider.setBackgroundType(BackgroundType.white),
                  ),
                  BackgroundSwatch(
                    label: l10n.backgroundTransparent,
                    color: null,
                    selected:
                        state.backgroundType == BackgroundType.transparent,
                    onTap: () =>
                        provider.setBackgroundType(BackgroundType.transparent),
                  ),
                  BackgroundSwatch(
                    label: l10n.backgroundBlack,
                    color: Colors.black,
                    selected: state.backgroundType == BackgroundType.black,
                    onTap: () =>
                        provider.setBackgroundType(BackgroundType.black),
                  ),
                  for (var i = 0; i < kGradientPresets.length; i++)
                    BackgroundSwatch(
                      label: null,
                      color: null,
                      gradient: [
                        Color(kGradientPresets[i][0]),
                        Color(kGradientPresets[i][1]),
                      ],
                      selected:
                          state.backgroundType == BackgroundType.gradient &&
                              state.gradientIndex == i,
                      onTap: () => provider.setGradient(i),
                    ),
                  for (final swatch in kPresetBackgroundColors)
                    BackgroundSwatch(
                      label: null,
                      color: swatch,
                      selected:
                          state.backgroundType == BackgroundType.solidColor &&
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
              compact: true,
            ),
          ],
        );
      },
    );
  }
}

/// A sideways row of quick choices with a soft fade at the trailing edge, so
/// it is obvious there is more. Only shortcuts live here: the two main
/// actions above it are never inside a scroll.
class FadingSwatchRow extends StatelessWidget {
  const FadingSwatchRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
        end: rtl ? Alignment.centerLeft : Alignment.centerRight,
        colors: const [Colors.black, Colors.black, Colors.transparent],
        stops: const [0, 0.88, 1],
      ).createShader(rect),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: children,
      ),
    );
  }
}

class BackgroundChoiceButton extends StatelessWidget {
  const BackgroundChoiceButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.swatch,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? swatch;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: selected ? p.accentTint : p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.m),
        side: BorderSide(
          color: selected ? p.accent : p.separator,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.m),
        ),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            children: [
              swatch == null
                  ? Icon(icon, size: 20, color: p.accentText)
                  : Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: swatch,
                        shape: BoxShape.circle,
                        border: Border.all(color: p.separator),
                      ),
                    ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom colour: hue, saturation and brightness sliders, a hex field and
/// a live preview. Changes apply to the photo straight away.
Future<void> showCustomColorSheet(
  BuildContext context,
  ImageEditProvider provider,
) {
  return showColorPickerSheet(
    context,
    initial: provider.value.bgColor ?? kPresetBackgroundColors[4],
    onChanged: provider.setBgColor,
  );
}

/// The same picker for any caller (editor and batch): [onChanged] fires on
/// every change.
Future<void> showColorPickerSheet(
  BuildContext context, {
  required Color initial,
  required ValueChanged<Color> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CustomColorSheet(onChanged: onChanged, initial: initial),
  );
}

class _CustomColorSheet extends StatefulWidget {
  const _CustomColorSheet({required this.onChanged, required this.initial});

  final ValueChanged<Color> onChanged;
  final Color initial;

  @override
  State<_CustomColorSheet> createState() => _CustomColorSheetState();
}

class _CustomColorSheetState extends State<_CustomColorSheet> {
  late HSVColor _hsv;
  late final TextEditingController _hex;
  bool _hexInvalid = false;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hex = TextEditingController(text: colorToHex(widget.initial));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _setHsv(HSVColor hsv) {
    setState(() {
      _hsv = hsv;
      _hexInvalid = false;
      _hex.text = colorToHex(hsv.toColor());
    });
    widget.onChanged(hsv.toColor());
  }

  void _onHexChanged(String text) {
    final c = parseHexColor(text);
    if (c == null) {
      setState(() => _hexInvalid = text.trim().isNotEmpty);
      return;
    }
    setState(() {
      _hsv = HSVColor.fromColor(c);
      _hexInvalid = false;
    });
    widget.onChanged(c);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = context.palette;
    final color = _hsv.toColor();
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    // The sheet reaches the screen's bottom edge, so keep the Done button
    // clear of the system navigation bar (or above the keyboard).
    final bottom = insets > 0 ? insets : MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.backgroundCustomColor,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppRadius.m),
                border: Border.all(color: p.separator),
              ),
            ),
            const SizedBox(height: 12),
            _SatValueSquare(
              hsv: _hsv,
              onChanged: _setHsv,
            ),
            const SizedBox(height: 8),
            _GradientSlider(
              label: l10n.colorHue,
              value: _hsv.hue,
              max: 360,
              colors: [
                for (var h = 0; h <= 360; h += 60)
                  HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
              ],
              onChanged: (v) => _setHsv(_hsv.withHue(v)),
            ),
            _GradientSlider(
              label: l10n.colorSaturation,
              value: _hsv.saturation,
              max: 1,
              colors: [
                _hsv.withSaturation(0).toColor(),
                _hsv.withSaturation(1).toColor(),
              ],
              onChanged: (v) => _setHsv(_hsv.withSaturation(v)),
            ),
            _GradientSlider(
              label: l10n.colorBrightness,
              value: _hsv.value,
              max: 1,
              colors: [
                _hsv.withValue(0).toColor(),
                _hsv.withValue(1).toColor(),
              ],
              onChanged: (v) => _setHsv(_hsv.withValue(v)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _hex,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l10n.colorHexLabel,
                errorText: _hexInvalid ? ' ' : null,
                isDense: true,
              ),
              onChanged: _onHexChanged,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.colorPickerDone),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.colors,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final List<Color> colors;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        SizedBox(
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    gradient: LinearGradient(colors: colors),
                  ),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 14,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbColor: Colors.white,
                  overlayColor: Colors.black12,
                ),
                child: Slider(
                  value: value.clamp(0, max).toDouble(),
                  min: 0,
                  max: max,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<void> _pickPhoto(BuildContext context, ImageEditProvider provider) async {
  final bytes = await pickBackgroundPhoto(context);
  if (bytes != null) provider.setBackgroundImage(bytes);
}

/// Lets the user choose a photo from the gallery to use as a background.
/// Returns null when cancelled or when the photo can't be read (a message is
/// shown in that case).
Future<Uint8List?> pickBackgroundPhoto(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    if (picked == null) return null;
    return await picked.readAsBytes();
  } catch (_) {
    messenger?.showSnackBar(SnackBar(content: Text(l10n.backgroundPhotoFailed)));
    return null;
  }
}

class BackgroundSwatch extends StatelessWidget {
  const BackgroundSwatch({
    super.key,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    this.gradient,
  });

  /// Two colours, top to bottom (gradient swatch).
  final List<Color>? gradient;

  final String? label;
  final Color? color; // null = transparent (checkerboard)
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      width: 60,
      child: InkResponse(
        onTap: onTap,
        radius: 30,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(2),
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
                  child: color == null && gradient == null
                      ? const CustomPaint(painter: _CheckerPainter())
                      : null,
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

/// Saturation (left to right) and brightness (bottom to top) for the current
/// hue, picked by touching or dragging on the square.
class _SatValueSquare extends StatelessWidget {
  const _SatValueSquare({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: LayoutBuilder(
        builder: (context, box) {
          void pick(Offset o) {
            final s = (o.dx / box.maxWidth).clamp(0.0, 1.0);
            final v = 1 - (o.dy / box.maxHeight).clamp(0.0, 1.0);
            onChanged(hsv.withSaturation(s).withValue(v));
          }

          return GestureDetector(
            onPanDown: (d) => pick(d.localPosition),
            onPanUpdate: (d) => pick(d.localPosition),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.m),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white,
                            HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: hsv.saturation * box.maxWidth - 11,
                    top: (1 - hsv.value) * box.maxHeight - 11,
                    child: IgnorePointer(
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hsv.toColor(),
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
