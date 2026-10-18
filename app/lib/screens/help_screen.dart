import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import '../generated/l10n/app_localizations.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/app_scaffold.dart';

/// One topic on the help screen: an icon, a title and its paragraphs.
class HelpTopic {
  const HelpTopic(this.icon, this.title, this.paragraphs);

  final IconData icon;
  final String title;
  final List<String> paragraphs;
}

/// The help topics, in reading order. Everything here describes what the app
/// does today; when a feature changes, its paragraph changes with it.
List<HelpTopic> helpTopics(AppLocalizations l) => [
      HelpTopic(Icons.rocket_launch_outlined, l.helpStartTitle,
          [l.helpStart1, l.helpStart2, l.helpStart3]),
      HelpTopic(Icons.crop_rotate_rounded, l.helpCropTitle,
          [l.helpCrop1, l.helpCrop2]),
      HelpTopic(Icons.content_cut_rounded, l.helpCutoutTitle,
          [l.helpCutout1, l.helpCutout2, l.helpCutout3, l.helpCutout4]),
      HelpTopic(Icons.brush_rounded, l.helpBrushTitle,
          [l.helpBrush1, l.helpBrush2, l.helpBrush3, l.helpBrush4]),
      HelpTopic(Icons.wallpaper_rounded, l.helpBackgroundTitle, [
        l.helpBackground1,
        l.helpBackground2,
        l.helpBackground3,
        l.helpBackground4,
      ]),
      HelpTopic(Icons.auto_awesome_mosaic_rounded, l.helpTemplatesTitle,
          [l.helpTemplates1, l.helpTemplates2]),
      HelpTopic(Icons.open_with_rounded, l.helpLayoutTitle,
          [l.helpLayout1, l.helpLayout2, l.helpLayout3, l.helpLayout4]),
      HelpTopic(Icons.ios_share_rounded, l.helpExportTitle, [
        l.helpExport1,
        l.helpExport2,
        l.helpExport3,
        l.helpExport4,
        l.helpExport5,
        l.helpExport6,
        l.helpExport7,
      ]),
      HelpTopic(Icons.collections_rounded, l.helpBatchTitle, [
        l.helpBatch1,
        l.helpBatch2,
        l.helpBatch3,
        l.helpBatch4,
        l.helpBatch5,
        l.helpBatch6,
        l.helpBatch7,
      ]),
      HelpTopic(Icons.photo_library_outlined, l.helpLibraryTitle, [
        l.helpLibrary1,
        l.helpLibrary2,
        l.helpLibrary3,
        l.helpLibrary4,
        l.helpLibrary5,
      ]),
      HelpTopic(Icons.lock_outline_rounded, l.helpPrivacyTitle,
          [l.helpPrivacy1, l.helpPrivacy2, l.helpPrivacy3]),
      HelpTopic(Icons.settings_outlined, l.helpSettingsTitle, [
        l.helpSettings1,
        l.helpSettings2,
        l.helpSettings3,
        l.helpSettings4,
      ]),
      HelpTopic(Icons.help_outline_rounded, l.helpFixTitle,
          [l.helpFix1, l.helpFix2, l.helpFix3]),
    ];

/// Help & how to use: every feature explained, one expandable card per topic.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final topics = helpTopics(l10n);
    return AppScaffold(
      appBar: AppBar(title: Text(l10n.helpTitle)),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.l, AppSpace.s, AppSpace.l, AppSpace.l),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.m),
                  child: Text(
                    l10n.helpIntro,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: context.palette.text2),
                  ),
                ),
                for (final topic in topics) _TopicCard(topic: topic),
              ],
            ),
          ),
          const AdBannerSlot(personalized: false),
        ],
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic});

  final HelpTopic topic;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.s),
      child: Material(
        color: p.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(AppRadius.l),
          side: BorderSide(color: p.separator, width: 0.5),
        ),
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsetsDirectional.fromSTEB(
                AppSpace.l, AppSpace.xs, AppSpace.m, AppSpace.xs),
            childrenPadding: const EdgeInsetsDirectional.fromSTEB(
                AppSpace.l, 0, AppSpace.l, AppSpace.l),
            expandedAlignment: AlignmentDirectional.centerStart,
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            iconColor: p.accentText,
            collapsedIconColor: p.text2,
            leading: Container(
              width: 36,
              height: 36,
              decoration:
                  BoxDecoration(color: p.accentTint, shape: BoxShape.circle),
              child: Icon(topic.icon, size: 20, color: p.accentText),
            ),
            title: Text(
              topic.title,
              style:
                  theme.textTheme.titleSmall?.copyWith(color: p.text),
            ),
            children: [
              for (var i = 0; i < topic.paragraphs.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                      bottom: i == topic.paragraphs.length - 1
                          ? 0
                          : AppSpace.m),
                  child: Text(
                    topic.paragraphs[i],
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: p.text2, height: 1.45),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
