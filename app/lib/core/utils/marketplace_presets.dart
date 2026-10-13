import 'dart:typed_data';

import '../models/export_job.dart';
import 'subject_layout.dart';

/// Export presets that follow marketplace image rules.
///
/// Verified 2026-10-13 against the marketplaces' own help pages where they
/// could be read (eBay, Etsy, Shopify) and against several current seller
/// guides for Amazon, whose own page needs a seller login. Where sources
/// disagreed the preset takes the choice that satisfies all of them. Rules
/// change: re-check before editing a number here.
///
/// - eBay: min 500x500, ~1600x1600 suggested, up to 12 MB, white background
///   generally best, no overlays.
/// - Etsy: >=2000 px on the shortest side recommended; files over 1 MB may
///   fail to upload; transparent PNG is not supported (shows black).
/// - Shopify: up to 5000x5000 and under 20 MB; 2048x2048 squares usually
///   display best; PNG recommended.
/// - Amazon (main image): pure white (255,255,255) background, 1000 px on the
///   longest side minimum for zoom and 2000 px recommended, product filling
///   about 85% of the frame, no text or logos.
enum Marketplace { amazon, ebay, etsy, shopify }

class MarketplacePreset {
  const MarketplacePreset({
    required this.marketplace,
    required this.name,
    required this.width,
    required this.height,
    required this.format,
    required this.quality,
    this.maxBytes,
    this.minQuality = 60,
    this.pureWhite = false,
    this.subjectFill,
  });

  final Marketplace marketplace;

  /// Proper noun, shown as is in every language.
  final String name;
  final int width;
  final int height;
  final ExportFormat format;

  /// Starting JPG quality (1-100).
  final int quality;

  /// JPG files are re-encoded at lower quality until they fit, but never
  /// below [minQuality]. Null means no cap.
  final int? maxBytes;
  final int minQuality;

  /// Force a pure white background with no shadow.
  final bool pureWhite;

  /// Fraction of the frame the product should fill (null = keep the layout
  /// chosen in the editor).
  final double? subjectFill;
}

const List<MarketplacePreset> kMarketplacePresets = [
  MarketplacePreset(
    marketplace: Marketplace.amazon,
    name: 'Amazon',
    width: 2000,
    height: 2000,
    format: ExportFormat.jpg,
    quality: 92,
    maxBytes: 10000000,
    pureWhite: true,
    subjectFill: 0.86,
  ),
  MarketplacePreset(
    marketplace: Marketplace.ebay,
    name: 'eBay',
    width: 1600,
    height: 1600,
    format: ExportFormat.jpg,
    quality: 90,
    maxBytes: 12000000,
  ),
  MarketplacePreset(
    marketplace: Marketplace.etsy,
    name: 'Etsy',
    // 4:3 landscape with the shortest side at Etsy's recommended 2000 px.
    width: 2667,
    height: 2000,
    format: ExportFormat.jpg,
    quality: 90,
    maxBytes: 1000000,
    minQuality: 70,
  ),
  MarketplacePreset(
    marketplace: Marketplace.shopify,
    name: 'Shopify',
    width: 2048,
    height: 2048,
    format: ExportFormat.png,
    quality: 90,
  ),
];

/// Scale and offset that make the subject fill [preset.subjectFill] of the
/// preset's frame, or null when the preset keeps the editor's layout (or the
/// mask is empty).
({double scale, double offsetX, double offsetY})? marketplaceSubjectLayout(
  MarketplacePreset preset,
  Uint8List mask,
  int imageWidth,
  int imageHeight,
) {
  final fill = preset.subjectFill;
  if (fill == null) return null;
  final bounds = subjectBounds(mask, imageWidth, imageHeight);
  if (bounds == null) return null;
  return autoCenterLayout(
    bounds: bounds,
    imageWidth: imageWidth.toDouble(),
    imageHeight: imageHeight.toDouble(),
    canvasWidth: preset.width.toDouble(),
    canvasHeight: preset.height.toDouble(),
    margin: (1 - fill) / 2,
    // A small product in a wide frame needs more than the editor's 3x cap.
    maxScale: 20,
  );
}
