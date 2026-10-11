import 'dart:typed_data';
import 'dart:ui';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'editable_image_state.freezed.dart';

/// Background fill type for Feature 4 (Replace Background).
enum BackgroundType {
  white,
  transparent,
  black,
  solidColor,
  gaussianBlur,
  gradient,
  image,
}

/// A single brush stroke event, used to reconstruct undo/redo history
/// (Feature 6) without storing a full bitmap per step.
///
/// freezed ^3.2.5 syntax: classes using the factory constructor must be
/// declared `abstract class`, not plain `class` (breaking change from
/// freezed 2.x — see pubspec.yaml comment on the freezed pin).
@freezed
abstract class BrushStrokeEvent with _$BrushStrokeEvent {
  const factory BrushStrokeEvent({
    required List<Offset> points,
    required double brushSizePx,
    required bool isRestore, // false = erase, true = restore (Feature 3)
    // Added during Phase 4: brush strength, set from
    // currentBrushOpacity at the moment a stroke completes. Needed for
    // brush_controls.dart's opacity slider to have somewhere to bake its
    // value into each recorded stroke.
    @Default(1.0) double opacity,
  }) = _BrushStrokeEvent;
}

/// Core editor state — drives editor_canvas.dart, brush_controls.dart,
/// background_selector.dart, and bottom_toolbar.dart (Phase 4).
///
/// NOTE: image bytes (processedBytes, maskBytes) are kept in memory only,
/// per Section 1's zero-backend / on-device-only architecture. History is
/// cleared on new image load per Feature 6's acceptance criteria.
@freezed
abstract class EditableImageState with _$EditableImageState {
  const factory EditableImageState({
    String? originalPath,
    Uint8List? processedBytes,
    Uint8List? maskBytes,
    // The untouched AI mask (same size as the image). maskBytes is always
    // derived from this plus the brush history, so undo/redo/reset replay
    // from a stable base instead of re-applying strokes on top of themselves.
    Uint8List? baseMaskBytes,
    @Default([]) List<BrushStrokeEvent> brushHistory,
    @Default(-1) int historyIndex,
    @Default(BackgroundType.transparent) BackgroundType backgroundType,
    Color? bgColor,
    @Default(0.0) double blurRadius,
    @Default(0.0) double edgeFeather,
    @Default(1.0) double zoom,
    @Default(Offset.zero) Offset panOffset,
    @Default(false) bool isProcessing,
    @Default(false) bool showBeforeAfter,
    Size? imageSize,
    // Added during Phase 3 (image_edit_provider.dart): distinguishes
    // "auto-segmentation not yet attempted" (maskBytes == null, this ==
    // false) from "attempted and threw SegmentationException" (this ==
    // true). fallback_manual_editor.dart (File 71) reads this flag to
    // decide whether to show Feature 1's required fallback message.
    // Added during Phase 4 (brush_controls.dart / editor_canvas.dart):
    // "current brush tool" settings — what the NEXT stroke will use, as
    // opposed to brushHistory which stores completed strokes. Follows the
    // same pattern already established by blurRadius/edgeFeather/
    // backgroundType above (current-tool-setting fields living directly
    // on this state, not a separate notifier).
    @Default(20.0) double currentBrushSizePx, // range: kBrushSizeMinPx-kBrushSizeMaxPx (constants.dart)
    @Default(false) bool currentBrushIsRestore, // false = erase (primary tool), true = restore
    @Default(1.0) double currentBrushOpacity,
    @Default(false) bool autoSegmentationFailed,
    // Phase 4: custom backgrounds, drop shadow, subject layout.
    @Default(0) int gradientIndex,
    Uint8List? bgImageBytes,
    @Default(0.0) double shadowOpacity, // 0 = off, max kShadowMaxOpacity
    @Default(1.0) double subjectScale,
    @Default(Offset.zero) Offset subjectOffset, // fractions of the canvas
    double? canvasAspect, // width / height; null = same as the photo
  }) = _EditableImageState;
}
