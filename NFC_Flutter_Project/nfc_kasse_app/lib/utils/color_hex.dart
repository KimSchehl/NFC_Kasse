import 'package:flutter/material.dart';

/// Parses the backend's '#RRGGBB' form. Null for null input.
Color? hexToColor(String? hex) {
  if (hex == null) return null;
  final clean = hex.replaceAll('#', '');
  final value = int.tryParse('FF$clean', radix: 16);
  return value != null ? Color(value) : null;
}

String colorToHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
