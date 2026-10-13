import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import 'background_selector.dart';
import 'layout_controls.dart';
import 'brush_controls.dart';
import 'edge_feather_slider.dart';
import 'editor_tool_dock.dart';

/// Every tool's panel is exactly this tall, so the photo canvas above never
/// changes size when you switch tools (it used to jump, which made the photo
/// look stretched).
const double kEditorToolPanelHeight = 176;

class EditorToolPanel extends StatelessWidget {
  const EditorToolPanel({super.key, required this.tool});

  final EditorTool tool;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: kEditorToolPanelHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(color: p.surface),
        // Scrolls instead of overflowing when text is scaled up.
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 12, 4),
          child: switch (tool) {
            EditorTool.cutout => const EdgeFeatherSlider(),
            EditorTool.brush => const BrushControls(),
            EditorTool.background => const BackgroundSelector(),
            EditorTool.layout => const LayoutControls(),
          },
        ),
      ),
    );
  }
}
