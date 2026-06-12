import 'package:flutter/material.dart';

const List<Color?> productColorPalette = [
  null,
  Color(0xFFA5D6A7),
  Color(0xFF81C784),
  Color(0xFF80DEEA),
  Color(0xFFFFF176),
  Color(0xFFFFCC80),
  Color(0xFFEF9A9A),
  Color(0xFFF48FB1),
  Color(0xFFCE93D8),
  Color(0xFFBA68C8),
  Color(0xFFBCAAA4),
  Color(0xFFB0BEC5),
];

class ProductColorPicker extends StatelessWidget {
  final Color? selected;
  final ValueChanged<Color?> onChanged;

  const ProductColorPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: productColorPalette
          .map((c) => _Swatch(
                color: c,
                isSelected: selected == c,
                onTap: () => onChanged(c),
              ))
          .toList(),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color? color;
  final bool isSelected;
  final VoidCallback onTap;

  const _Swatch({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  static Color _contrast(Color bg) {
    final l = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
    return l > 0.5 ? Colors.black87 : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNone = color == null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isNone ? theme.colorScheme.surfaceContainerHigh : color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: isSelected ? 3 : 1,
          ),
        ),
        child: isNone
            ? Icon(Icons.block, size: 18, color: theme.colorScheme.onSurfaceVariant)
            : isSelected
                ? Icon(Icons.check, size: 18, color: _contrast(color!))
                : null,
      ),
    );
  }
}
