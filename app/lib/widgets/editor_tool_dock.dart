import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_tokens.dart';
import '../generated/l10n/app_localizations.dart';

/// The editing tools, shown as a bottom dock. Each tool shows its own
/// controls in the panel above the dock, one tool at a time.
enum EditorTool { cutout, brush, background, layout }

class EditorToolDock extends StatelessWidget {
  const EditorToolDock({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final EditorTool selected;
  final ValueChanged<EditorTool> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = context.palette;
    final items = <(EditorTool, IconData, String)>[
      (EditorTool.cutout, Icons.content_cut_rounded, l10n.editorToolCutout),
      (EditorTool.brush, Icons.brush_rounded, l10n.editorToolBrush),
      (EditorTool.background, Icons.wallpaper_rounded, l10n.editorToolBackground),
      (EditorTool.layout, Icons.open_with_rounded, l10n.editorToolLayout),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.separator, width: 0.5)),
      ),
      child: Row(
        children: [
          for (final (tool, icon, label) in items)
            Expanded(
              child: _DockItem(
                icon: icon,
                label: label,
                selected: tool == selected,
                onTap: () {
                  if (tool != selected) HapticFeedback.selectionClick();
                  onSelected(tool);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = selected ? p.accentText : p.text2;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
