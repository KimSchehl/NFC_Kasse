import 'dart:math';

final _rand = Random();
const _chars = '0123456789abcdefghijklmnopqrstuvwxyz';

/// Generates a short, roughly-sortable ID (millisecond timestamp + random
/// suffix, base36) for correlating log entries (`trace_id`) or naming a
/// device (`device_id`).
///
/// Hand-rolled instead of pulling in the `uuid` package: these are internal
/// correlation tokens, not security tokens (the JWT remains the actual
/// security boundary), so the much smaller collision-resistance of a
/// timestamp+random scheme is more than sufficient at this scale.
String generateId([String? prefix]) {
  final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final suffix =
      List.generate(8, (_) => _chars[_rand.nextInt(_chars.length)]).join();
  final id = '$ts$suffix';
  return prefix == null ? id : '$prefix-$id';
}
