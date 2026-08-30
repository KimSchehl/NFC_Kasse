import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_kasse_app/models/pager_order_model.dart';

void main() {
  group('PagerOrderModel.fromJson', () {
    test('parses all fields', () {
      final o = PagerOrderModel.fromJson({
        'id': 1,
        'item_summary': '2× Pizza Salami, Steak',
        'pager_number': 7,
        'status': 'open',
        'created_at': '2026-08-30 20:50:03',
        'done_at': null,
      });
      expect(o.id, 1);
      expect(o.itemSummary, '2× Pizza Salami, Steak');
      expect(o.pagerNumber, 7);
      expect(o.status, 'open');
      expect(o.createdAt, '2026-08-30 20:50:03');
      expect(o.doneAt, null);
    });

    test('parses a done order with done_at set', () {
      final o = PagerOrderModel.fromJson({
        'id': 2,
        'item_summary': 'Pizza Salami',
        'pager_number': 3,
        'status': 'done',
        'created_at': '2026-08-30 20:50:03',
        'done_at': '2026-08-30 20:55:00',
      });
      expect(o.status, 'done');
      expect(o.doneAt, '2026-08-30 20:55:00');
    });
  });

  group('PagerOrderModel.isOpen', () {
    test('true for status open', () {
      final o = PagerOrderModel.fromJson({
        'id': 1, 'item_summary': 'x', 'pager_number': 1,
        'status': 'open', 'created_at': 'now',
      });
      expect(o.isOpen, true);
    });

    test('false for status done', () {
      final o = PagerOrderModel.fromJson({
        'id': 1, 'item_summary': 'x', 'pager_number': 1,
        'status': 'done', 'created_at': 'now',
      });
      expect(o.isOpen, false);
    });
  });
}
