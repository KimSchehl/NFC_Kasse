import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_kasse_app/utils/layout_utils.dart';

void main() {
  group('clampPanelWidth', () {
    test('passes an in-range value through unchanged', () {
      expect(clampPanelWidth(300, 1000, 40), 300);
    });

    test('clamps up to minWidth when below it', () {
      expect(clampPanelWidth(50, 1000, 40), 220);
    });

    test('clamps down to maxFraction of available width when above it', () {
      // available = 1000 - 40 = 960, maxFraction 0.5 -> max 480
      expect(clampPanelWidth(900, 1000, 40), 480);
    });

    test('custom minWidth/maxFraction are respected', () {
      expect(clampPanelWidth(50, 1000, 40, minWidth: 100), 100);
      expect(
        clampPanelWidth(900, 1000, 40, maxFraction: 0.3),
        closeTo((1000 - 40) * 0.3, 0.001),
      );
    });

    test('regression: does not throw when available*maxFraction would fall below minWidth', () {
      // available = 420 - 280 = 140, 140*0.5 = 70 < minWidth 220 —
      // without the max(minWidth, ...) guard this would call
      // num.clamp(220, 70) and throw.
      expect(() => clampPanelWidth(500, 420, 280), returnsNormally);
      expect(clampPanelWidth(500, 420, 280), 220);
    });

    test('reservedWidth larger than totalWidth still returns minWidth, not negative', () {
      expect(clampPanelWidth(300, 200, 500), 220);
    });
  });
}
