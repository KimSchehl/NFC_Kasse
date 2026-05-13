import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_kasse_app/models/customer_model.dart';

void main() {
  group('CustomerModel.fromJson', () {
    test('parses all fields', () {
      final c = CustomerModel.fromJson({
        'nfc_uid': 'AABBCCDD',
        'balance': 12.50,
        'is_new_customer': false,
      });
      expect(c.nfcUid, 'AABBCCDD');
      expect(c.balance, 12.50);
      expect(c.isNew, false);
    });

    test('is_new_customer defaults to false when missing', () {
      final c = CustomerModel.fromJson({'nfc_uid': 'X', 'balance': 0.0});
      expect(c.isNew, false);
    });

    test('parses new customer flag', () {
      final c = CustomerModel.fromJson({
        'nfc_uid': 'X', 'balance': 0.0, 'is_new_customer': true,
      });
      expect(c.isNew, true);
    });

    test('balance can be negative', () {
      final c = CustomerModel.fromJson({'nfc_uid': 'X', 'balance': -5.0});
      expect(c.balance, -5.0);
    });
  });

  group('CustomerModel.withBalance', () {
    test('returns a new instance with updated balance', () {
      const original = CustomerModel(nfcUid: 'UID', balance: 10.0);
      final updated = original.withBalance(7.50);
      expect(updated.balance, 7.50);
      expect(updated.nfcUid, 'UID');
      expect(updated.isNew, false);
    });

    test('does not mutate the original', () {
      const original = CustomerModel(nfcUid: 'UID', balance: 10.0);
      original.withBalance(0.0);
      expect(original.balance, 10.0);
    });

    test('preserves isNew flag', () {
      const original = CustomerModel(nfcUid: 'UID', balance: 0.0, isNew: true);
      final updated = original.withBalance(5.0);
      expect(updated.isNew, true);
    });
  });
}
