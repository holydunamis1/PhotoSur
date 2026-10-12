import 'dart:ui';

/// Parses "#RRGGBB", "RRGGBB" or the short "#RGB" form (case-blind) into an
/// opaque colour. Returns null for anything else.
Color? parseHexColor(String input) {
  var s = input.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 3) {
    s = s.split('').map((c) => '$c$c').join();
  }
  if (s.length != 6) return null;
  final value = int.tryParse(s, radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}

/// "#RRGGBB" in upper case, ignoring alpha.
String colorToHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
