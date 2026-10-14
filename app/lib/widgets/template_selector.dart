import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/providers/image_edit_provider.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/template_catalog.dart';
import '../generated/l10n/app_localizations.dart';

String _categoryLabel(AppLocalizations l10n, TemplateCategory c) => switch (c) {
      TemplateCategory.studio => l10n.templatesStudio,
      TemplateCategory.colorBlock => l10n.templatesColorBlock,
      TemplateCategory.textures => l10n.templatesTextures,
      TemplateCategory.light => l10n.templatesLight,
      TemplateCategory.patterns => l10n.templatesPatterns,
    };

/// Applies [t] as the photo's background. Never throws: a missing or broken
/// asset just shows the same "could not load" message as a bad gallery photo.
Future<bool> applyTemplate(
  BuildContext context,
  ImageEditProvider provider,
  BackgroundTemplate t,
) async {
  final bytes = await loadTemplateBytes(context, t);
  if (bytes == null) return false;
  provider.setBackgroundImage(bytes);
  return true;
}

/// Reads a bundled scene. Returns null (and shows a message) if it can't be
/// loaded.
Future<Uint8List?> loadTemplateBytes(
  BuildContext context,
  BackgroundTemplate t,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final data = await rootBundle.load(t.asset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    messenger?.showSnackBar(SnackBar(content: Text(l10n.backgroundPhotoFailed)));
    return null;
  }
}

/// Templates tool panel: five featured scenes plus a button that opens the
/// full gallery. Nothing is hidden in a sideways scroll.
class TemplateSelector extends StatelessWidget {
  const TemplateSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ImageEditProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context);
    final p = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < kFeaturedTemplateIds.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _TemplateThumb(
                    template: templateById(kFeaturedTemplateIds[i]),
                    onTap: (t) => applyTemplate(context, provider, t),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Material(
          color: p.accentTint,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.m),
            side: BorderSide(color: p.accent),
          ),
          child: InkWell(
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.m),
            ),
            onTap: () => showTemplateGallery(context, provider),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_awesome_mosaic_rounded,
                        size: 20, color: p.accentText),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        l10n.templatesTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: p.accentText,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TemplateThumb extends StatelessWidget {
  const _TemplateThumb({required this.template, required this.onTap});

  final BackgroundTemplate template;
  final ValueChanged<BackgroundTemplate> onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: _categoryLabel(l10n, template.category),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => onTap(template),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.s),
            border: Border.all(color: p.separator),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.s - 1),
            child: Image.asset(
              template.asset,
              fit: BoxFit.cover,
              cacheWidth: 240,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => ColoredBox(color: p.surface),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full gallery: every scene, grouped by category, one vertical scroll.
Future<void> showTemplateGallery(
  BuildContext context,
  ImageEditProvider provider,
) {
  return showTemplatePicker(
    context,
    (sheetContext, t) => applyTemplate(sheetContext, provider, t),
  );
}

/// The gallery for any caller: [onPick] returns true when the scene was
/// applied, which closes the sheet.
Future<void> showTemplatePicker(
  BuildContext context,
  Future<bool> Function(BuildContext sheetContext, BackgroundTemplate t) onPick,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(
              16, 0, 16, 24 + MediaQuery.viewPaddingOf(sheetContext).bottom),
          children: [
            Text(l10n.templatesTitle,
                style: Theme.of(sheetContext).textTheme.titleLarge),
            for (final c in TemplateCategory.values) ...[
              Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 8),
                child: Text(_categoryLabel(l10n, c),
                    style: Theme.of(sheetContext).textTheme.titleSmall),
              ),
              GridView.count(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.8,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final t
                      in kBackgroundTemplates.where((t) => t.category == c))
                    _TemplateThumb(
                      template: t,
                      onTap: (t) async {
                        final ok = await onPick(sheetContext, t);
                        if (ok && sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );
}
