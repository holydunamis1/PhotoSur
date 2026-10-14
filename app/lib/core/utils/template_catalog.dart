/// Ready-made background scenes (Templates tool). Pure data: the images live
/// in `assets/templates/` and are bundled with the app, so they work offline.
enum TemplateCategory { studio, colorBlock, textures, light, patterns }

class BackgroundTemplate {
  const BackgroundTemplate(this.id, this.category);

  final String id;
  final TemplateCategory category;

  String get asset => 'assets/templates/$id.jpg';
}

const List<BackgroundTemplate> kBackgroundTemplates = [
  BackgroundTemplate('white_cyclorama', TemplateCategory.studio),
  BackgroundTemplate('soft_grey', TemplateCategory.studio),
  BackgroundTemplate('charcoal', TemplateCategory.studio),
  BackgroundTemplate('warm_cream', TemplateCategory.studio),
  BackgroundTemplate('blush_arch', TemplateCategory.colorBlock),
  BackgroundTemplate('sage_arch', TemplateCategory.colorBlock),
  BackgroundTemplate('sky_arch', TemplateCategory.colorBlock),
  BackgroundTemplate('sunset_block', TemplateCategory.colorBlock),
  BackgroundTemplate('white_marble', TemplateCategory.textures),
  BackgroundTemplate('black_marble', TemplateCategory.textures),
  BackgroundTemplate('light_oak', TemplateCategory.textures),
  BackgroundTemplate('dark_walnut', TemplateCategory.textures),
  BackgroundTemplate('linen', TemplateCategory.textures),
  BackgroundTemplate('concrete', TemplateCategory.textures),
  BackgroundTemplate('terrazzo', TemplateCategory.textures),
  BackgroundTemplate('window_light', TemplateCategory.light),
  BackgroundTemplate('palm_shadow', TemplateCategory.light),
  BackgroundTemplate('spotlight_dark', TemplateCategory.light),
  BackgroundTemplate('spotlight_warm', TemplateCategory.light),
  BackgroundTemplate('sunrise', TemplateCategory.patterns),
  BackgroundTemplate('ocean', TemplateCategory.patterns),
  BackgroundTemplate('polka_mint', TemplateCategory.patterns),
  BackgroundTemplate('snowfall', TemplateCategory.patterns),
];

/// The five scenes shown right in the tool panel (one per category).
const List<String> kFeaturedTemplateIds = [
  'white_cyclorama',
  'blush_arch',
  'light_oak',
  'window_light',
  'sunrise',
];

BackgroundTemplate templateById(String id) =>
    kBackgroundTemplates.firstWhere((t) => t.id == id);
