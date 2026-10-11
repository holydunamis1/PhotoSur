import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/editable_image_state.dart';
import '../core/providers/image_edit_provider.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/background_presets.dart';
import '../generated/l10n/app_localizations.dart';
import 'labeled_slider.dart';

/// Layout tool: canvas shape, subject size, drop shadow, auto-center.
/// (Dragging / pinching the subject happens on the canvas itself.)
class LayoutControls extends StatelessWidget {
  const LayoutControls({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ImageEditProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context);
    final p = context.palette;

    return ValueListenableBuilder<EditableImageState>(
      valueListenable: provider,
      builder: (context, state, _) {
        final aspects = <(double?, String)>[
          (null, l10n.exportResizeOriginal),
          (1.0, l10n.cropAspect1x1),
          (4 / 5, l10n.cropAspect4x5),
          (9 / 16, l10n.cropAspect9x16),
        ];
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (aspect, label) in aspects)
                  ChoiceChip(
                    label: Text(label),
                    selected: state.canvasAspect == aspect,
                    onSelected: (_) => provider.setCanvasAspect(aspect),
                  ),
                ActionChip(
                  avatar: Icon(Icons.center_focus_strong_rounded,
                      size: 18, color: p.accentText),
                  label: Text(l10n.layoutAutoCenter),
                  onPressed: provider.autoCenterSubject,
                ),
                ActionChip(
                  avatar: Icon(Icons.restart_alt_rounded, size: 18, color: p.text2),
                  label: Text(l10n.toolbarReset),
                  onPressed: provider.resetSubjectLayout,
                ),
              ],
            ),
            LabeledSlider(
              label: l10n.layoutSizeLabel,
              value: state.subjectScale,
              min: 0.2,
              max: 3.0,
              onChanged: provider.setSubjectScale,
              valueText: '${(state.subjectScale * 100).round()}%',
            ),
            LabeledSlider(
              label: l10n.layoutShadowLabel,
              value: state.shadowOpacity,
              min: 0.0,
              max: kShadowMaxOpacity,
              onChanged: provider.setShadow,
              valueText: '${(state.shadowOpacity / kShadowMaxOpacity * 100).round()}%',
            ),
          ],
        );
      },
    );
  }
}
