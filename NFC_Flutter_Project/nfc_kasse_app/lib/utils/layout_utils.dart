import 'dart:math';

/// Clamps a drag-resized side-panel width to a sane range.
///
/// [reservedWidth] is however much of [totalWidth] is already spoken for by
/// other UI in the same row (e.g. the other, independently resizable side
/// panel, plus any drag handles) — pass the *current* value of that other
/// width, not a fixed constant, so two side panels sharing one row can't
/// jointly starve the content between them.
///
/// The `max(minWidth, ...)` is required, not cosmetic: with two independent
/// side panels in play, `totalWidth - reservedWidth` can legitimately dip
/// below `minWidth` while the user is still dragging, and `num.clamp(min,
/// max)` throws if `min > max` instead of returning a sensible value.
double clampPanelWidth(
  double raw,
  double totalWidth,
  double reservedWidth, {
  double minWidth = 220.0,
  double maxFraction = 0.5,
}) {
  final available = max(0.0, totalWidth - reservedWidth);
  final maxWidth = max(minWidth, available * maxFraction);
  return raw.clamp(minWidth, maxWidth);
}
