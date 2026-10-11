/// Two-stop vertical gradients (top colour, bottom colour) as ARGB ints.
/// Shared by the editor preview and the exporter so both draw the same thing.
const List<List<int>> kGradientPresets = [
  [0xFFFDE68A, 0xFFF97316], // sunrise
  [0xFFBAE6FD, 0xFF3B82F6], // sky
  [0xFFA7F3D0, 0xFF059669], // mint
  [0xFFFBCFE8, 0xFF8B5CF6], // dusk
  [0xFFF3F4F6, 0xFF9CA3AF], // studio grey
  [0xFF1F2937, 0xFF000000], // night
];

/// Drop shadow: strength is the user's slider (0 = off). Blur and drop are
/// fractions of the canvas' longer side so they look the same at any size.
const double kShadowMaxOpacity = 0.6;
const double kShadowBlurFraction = 0.025;
const double kShadowDropFraction = 0.015;
