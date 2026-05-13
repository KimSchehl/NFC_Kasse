import 'package:intl/intl.dart';

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
