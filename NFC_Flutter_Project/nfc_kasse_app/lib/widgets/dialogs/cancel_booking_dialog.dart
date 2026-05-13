import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../utils/formatters.dart';

/// Dialog that cancels the most recent booking stored in [lastBookingProvider].
///
/// A booking may span multiple sale rows (one per product unit). Each sale_id
/// is cancelled individually so the server can refund the correct price for
/// that specific row. The total refund is accumulated client-side and applied
/// to the displayed customer balance.
class CancelBookingDialog extends ConsumerStatefulWidget {
  const CancelBookingDialog({super.key});

  @override
  ConsumerState<CancelBookingDialog> createState() => _CancelBookingDialogState();
}

class _CancelBookingDialogState extends ConsumerState<CancelBookingDialog> {
  bool _loading = false;
  String? _error;

  Future<void> _cancel() async {
    final booking = ref.read(lastBookingProvider);
    if (booking == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final svc = ref.read(salesServiceProvider);
      final saleIds = (booking['sale_ids'] as List).cast<int>();

      // Cancel each sale row individually and accumulate the total refund.
      double refunded = 0;
      for (final id in saleIds) {
        final result = await svc.cancelSale(id);
        refunded += (result['refunded_amount'] as num).toDouble();
      }

      // Update customer balance
      final customer = ref.read(customerProvider);
      if (customer != null) {
        ref.read(customerProvider.notifier).state =
            customer.withBalance(customer.balance + refunded);
      }

      ref.read(lastBookingProvider.notifier).state = null;
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Fehler: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = ref.watch(lastBookingProvider);
    if (booking == null) {
      return AlertDialog(
        title: const Text('Storno'),
        content: const Text('Keine Buchung zum Stornieren.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    }

    final items = (booking['items'] as List<Map<String, dynamic>>);
    final total = (booking['total'] as double);

    return AlertDialog(
      title: const Text('Buchung stornieren?'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Buchung vom ${formatTime(booking['booked_at'] as String)} Uhr',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'Kunde: ${booking['nfc_uid']}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 20),
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(item['name'] as String)),
                      Text(formatPrice(item['price'] as double)),
                    ],
                  ),
                )),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Gesamt:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(formatPrice(total), style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _loading ? null : _cancel,
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: _loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Buchung stornieren'),
        ),
      ],
    );
  }
}
