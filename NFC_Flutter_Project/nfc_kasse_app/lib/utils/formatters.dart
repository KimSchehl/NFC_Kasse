import 'package:intl/intl.dart';

/// Normalises any NFC UID format to uppercase colon-separated hex bytes.
///
/// Accepts three scanner output formats for the same physical tag:
///   - Decimal (little-endian int):  "1040208355"
///   - Hex without separators:       "00E351003E"  (leading 00 prefix stripped)
///   - Formatted hex:                "E3:51:00:3E" (already canonical)
///
/// Returns null if the input cannot be parsed as a valid UID.
String? normalizeUid(String input) {
  final stripped = input.trim().replaceAll(RegExp(r'[:.\s\-]'), '');
  if (stripped.isEmpty) return null;

  String hexStr;

  if (RegExp(r'^\d+$').hasMatch(stripped)) {
    // Decimal input — bytes were encoded as a little-endian integer by the reader.
    final decimal = int.tryParse(stripped);
    if (decimal == null || decimal < 0) return null;
    // Determine byte count from hex length — avoids large literals that
    // exceed JavaScript's safe integer range (dart2js / web builds).
    final hex = decimal.toRadixString(16);
    final byteCount = hex.length <= 8 ? 4 : hex.length <= 14 ? 7 : null;
    if (byteCount == null) return null;
    final paddedHex = hex.padLeft(byteCount * 2, '0');
    // Reverse bytes to recover big-endian UID order.
    final bytes = <String>[];
    for (int i = paddedHex.length - 2; i >= 0; i -= 2) {
      bytes.add(paddedHex.substring(i, i + 2));
    }
    hexStr = bytes.join();
  } else {
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(stripped)) return null;
    hexStr = stripped.toLowerCase();
    if (hexStr.length.isOdd) hexStr = '0$hexStr';
    // Some readers prepend a 00 byte — strip leading 00 pairs until a standard
    // NFC UID length is reached (4, 7 or 10 bytes = 8, 14 or 20 hex chars).
    const standard = [8, 14, 20];
    while (!standard.contains(hexStr.length) && hexStr.length > 8 && hexStr.startsWith('00')) {
      hexStr = hexStr.substring(2);
    }
  }

  if (hexStr.length % 2 != 0) return null;
  final result = <String>[];
  for (int i = 0; i < hexStr.length; i += 2) {
    result.add(hexStr.substring(i, i + 2).toUpperCase());
  }
  return result.join(':');
}

// NumberFormat.currency with a locale name needs bundled locale data
// (intl package includes de_DE by default).
final _currencyFmt = NumberFormat.currency(locale: 'de_DE', symbol: '€');

// DateFormat with an explicit skeleton string ('HH:mm', 'dd.MM.yyyy') does NOT
// require initializeDateFormatting() — only locale-based patterns (e.g.
// DateFormat.yMd('de_DE')) do. Using the skeleton avoids the
// LocaleDataException that would otherwise be thrown at runtime.
final _timeFmt = DateFormat('HH:mm');
final _dateFmt = DateFormat('dd.MM.yyyy');

/// Formats [price] as a German currency string, e.g. `"3,50 €"` or `"- 2,00 €"`.
///
/// Negative prices are prefixed with `"- "` so the minus sign appears before
/// the currency symbol, matching common German typographic conventions.
String formatPrice(double price) {
  if (price < 0) return '- ${_currencyFmt.format(price.abs())}';
  return _currencyFmt.format(price);
}

/// Like [formatPrice] but always shows `"+"` or `"-"` prefix.
/// Used for refund/topup items where the sign is meaningful (e.g. `"+10,00 €"`).
String formatPriceSigned(double price) {
  if (price < 0) return '- ${_currencyFmt.format(price.abs())}';
  if (price > 0) return '+ ${_currencyFmt.format(price)}';
  return _currencyFmt.format(price);
}

/// Parses an ISO-8601 string and returns a local-time `"HH:mm"` string.
/// Returns the original string unchanged if parsing fails.
String formatTime(String isoString) {
  try {
    return _timeFmt.format(DateTime.parse(isoString).toLocal());
  } catch (_) {
    return isoString;
  }
}

/// Parses an ISO-8601 string and returns a `"dd.MM.yyyy"` date string.
/// Returns the original string unchanged if parsing fails.
String formatDate(String isoString) {
  try {
    return _dateFmt.format(DateTime.parse(isoString).toLocal());
  } catch (_) {
    return isoString;
  }
}

String formatDateTime(String isoString) {
  try {
    final dt = DateTime.parse(isoString).toLocal();
    return '${_dateFmt.format(dt)} ${_timeFmt.format(dt)}';
  } catch (_) {
    return isoString;
  }
}
