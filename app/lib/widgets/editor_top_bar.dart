import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/models/editable_image_state.dart';
import '../core/providers/image_edit_provider.dart';
import '../generated/l10n/app_localizations.dart';
import 'before_after_toggle.dart';
import 'icon_button_48.dart';

/// Back on the left; Undo, Redo, Before/After and the primary Export action
/// on the right.
class EditorTopBar extends StatelessWidget {
  const EditorTopBar({
    super.key,
    required this.onBack,
    required this.onExport,
    this.showEditActions = true,
  });

  final VoidCallback onBack;
  final VoidCallback onExport;
  final bool showEditActions;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ImageEditProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 12, 4),
      child: Row(
        children: [
          IconButton48(
            icon: Icons.arrow_back_ios_new_rounded,
            mirror: true,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: onBack,
          ),
          // The edit actions shrink to fit when the screen is narrow or the
          // Export label is long, instead of overflowing.
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: showEditActions
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: ValueListenableBuilder<EditableImageState>(
                        valueListenable: provider,
                        builder: (context, state, _) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton48(
                                icon: Icons.undo_rounded,
                                mirror: true,
                                tooltip: l10n.toolbarUndo,
                                onPressed: provider.canUndo ? provider.undo : null,
                              ),
                              IconButton48(
                                icon: Icons.redo_rounded,
                                mirror: true,
                                tooltip: l10n.toolbarRedo,
                                onPressed: provider.canRedo ? provider.redo : null,
                              ),
                              const BeforeAfterToggle(),
                            ],
                          );
                        },
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 132),
            child: FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: const StadiumBorder(),
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                onExport();
              },
              child: Text(
                l10n.toolbarExport,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
