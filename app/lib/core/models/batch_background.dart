import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../utils/marketplace_presets.dart';
import 'editable_image_state.dart' show BackgroundType;
import 'export_job.dart' show ExportFormat;

part 'batch_background.freezed.dart';

/// The one background every photo in a batch gets: the same choices as the
/// editor's Background tool (colour, gradient, blur, photo or template).
@freezed
abstract class BatchBackground with _$BatchBackground {
  const factory BatchBackground({
    @Default(BackgroundType.transparent) BackgroundType type,
    Color? color,
    @Default(0) int gradientIndex,
    Uint8List? imageBytes,
    @Default(12.0) double blurRadius,
  }) = _BatchBackground;

  const BatchBackground._();

  bool get isTransparent => type == BackgroundType.transparent;
}

/// What a batch photo is really exported as, after the marketplace preset
/// (if any) has had its say: pure-white presets force a white background, and
/// a JPG can't hold transparency so it always gets white instead.
({BatchBackground background, ExportFormat format}) resolveBatchOutput(
  BatchBackground chosen,
  MarketplacePreset? preset,
) {
  var bg = chosen;
  if (preset != null && preset.pureWhite) {
    bg = const BatchBackground(type: BackgroundType.white);
  }
  final format = preset?.format ??
      (bg.isTransparent ? ExportFormat.png : ExportFormat.jpg);
  if (format == ExportFormat.jpg && bg.isTransparent) {
    bg = const BatchBackground(type: BackgroundType.white);
  }
  return (background: bg, format: format);
}
