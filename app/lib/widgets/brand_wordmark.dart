import 'package:flutter/material.dart';

/// Two-tone "PhotoSur" wordmark for the left of the home header.
/// Brand name, intentionally not localized.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Kathar',
            style: TextStyle(color: theme.colorScheme.onSurface),
          ),
          TextSpan(
            text: 'Erase',
            style: TextStyle(color: theme.colorScheme.primary),
          ),
        ],
      ),
      style: base,
      semanticsLabel: 'PhotoSur',
    );
  }
}
