import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_kasse_app/utils/formatters.dart';

void main() {
  group('formatPrice', () {
    test('formats a positive amount in German locale', () {
      expect(formatPrice(2.50), '2,50 €');
    });

    test('formats zero', () {
      expect(formatPrice(0.0), '0,00 €');
    });

    test('formats a negative amount with leading dash', () {
      expect(formatPrice(-2.50), '- 2,50 €');
    });

    test('formats large amount', () {
      expect(formatPrice(1000.0), '1.000,00 €');
    });
  });

  group('formatPriceSigned', () {
    test('positive amounts get a plus prefix', () {
      expect(formatPriceSigned(2.50), '+ 2,50 €');
    });

    test('negative amounts get a dash prefix', () {
      expect(formatPriceSigned(-2.50), '- 2,50 €');
    });

    test('zero has no sign prefix', () {
      expect(formatPriceSigned(0.0), '0,00 €');
    });
  });

  group('formatTime', () {
    test('returns a HH:mm shaped string for a valid ISO timestamp', () {
      final result = formatTime('2024-06-15T14:30:00');
      expect(result, matches(RegExp(r'^\d{2}:\d{2}$')));
    });

    test('returns the original string on invalid input', () {
      expect(formatTime('not-a-date'), 'not-a-date');
    });
  });

  group('formatDate', () {
    test('returns a dd.MM.yyyy shaped string for a valid ISO date', () {
      final result = formatDate('2024-06-15T00:00:00');
      expect(result, matches(RegExp(r'^\d{2}\.\d{2}\.\d{4}$')));
    });

    test('returns the original string on invalid input', () {
      expect(formatDate('bad-input'), 'bad-input');
    });
  });

  group('formatDateTime', () {
    test('returns a combined date and time string', () {
      final result = formatDateTime('2024-06-15T14:30:00');
      expect(result, matches(RegExp(r'^\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}$')));
    });

    test('returns the original string on invalid input', () {
      expect(formatDateTime('bad'), 'bad');
    });
  });
}
