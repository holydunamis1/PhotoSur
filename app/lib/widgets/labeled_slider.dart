import 'package:flutter/material.dart';

/// "Label ———●——— 12": a compact slider row used by every tool panel.
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.valueText,
    this.compact = false,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String valueText;

  /// A shorter row (36 px) for panels that are tight on height.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelMedium;
    return Row(
      children: [
        SizedBox(
          width: 124,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: labelStyle,
          ),
        ),
        Expanded(
          child: SizedBox(
            height: compact ? 36 : null,
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(valueText, textAlign: TextAlign.end, style: labelStyle),
        ),
      ],
    );
  }
}
