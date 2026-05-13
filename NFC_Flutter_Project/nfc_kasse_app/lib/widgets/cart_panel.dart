import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../utils/formatters.dart';
import 'dialogs/cancel_booking_dialog.dart';

/// The shopping cart panel shown on the right side (wide layout) or the bottom
/// half (narrow layout) of the POS screen.
///
/// Responsibilities:
/// - Displays cart items with remove buttons
/// - Shows "Gesamt" total and "Rest Guthaben" (balance after purchase, red if < 0)
/// - Disables the Buchen button when the result would be a negative balance
/// - Shows the "Letzte Buchung stornieren" button after a successful booking
class CartPanel extends ConsumerWidget {
  const CartPanel({super.key});

  Future<void> _book(BuildContext context, WidgetRef ref) async {
    final cart = ref.read(cartProvider.notifier);
    final customer = ref.read(customerProvider);
    if (customer == null || cart.productIds.isEmpty) return;

    try {
      final svc = ref.read(salesServiceProvider);
      final result = await svc.book(customer.nfcUid, cart.productIds);

      // Store for potential storno
      final items = ref.read(cartProvider)
          .map((i) => {'name': i.product.name, 'price': i.subtotal})
          .toList();
      ref.read(lastBookingProvider.notifier).state = {
        'sale_ids': result['sale_ids'],
        'items': items,
        'total': cart.total,
        'nfc_uid': customer.nfcUid,
        'booked_at': DateTime.now().toIso8601String(),
      };

      // Update displayed balance
      ref.read(customerProvider.notifier).state =
          customer.withBalance((result['new_balance'] as num).toDouble());

      cart.clear();
    } on Exception catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _storno(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (_) => const CancelBookingDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartProvider);
    final cart = ref.read(cartProvider.notifier);
    final customer = ref.watch(customerProvider);
    final lastBooking = ref.watch(lastBookingProvider);
    final theme = Theme.of(context);

    final total = cart.total;
    final restBalance = customer != null ? customer.balance - total : 0.0;
    // Client-side balance guard: the server allows negative balances, but we
    // disable Buchen when the result would go below 0 so staff can't
    // accidentally overdraw a wristband. The button is re-enabled only after
    // the guest tops up or the vendor removes items.
    final canBook = items.isNotEmpty && customer != null && restBalance >= 0;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          color: theme.colorScheme.surfaceContainerHigh,
          child: Row(
            children: [
              Text('Warenkorb', style: theme.textTheme.headlineSmall),
              const Spacer(),
              if (items.isNotEmpty)
                TextButton(
                  onPressed: () => ref.read(cartProvider.notifier).clear(),
                  style: TextButton.styleFrom(
                    textStyle: theme.textTheme.titleMedium,
                  ),
                  child: const Text('Leeren'),
                ),
            ],
          ),
        ),

        // Items
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    'Bitte Artikel auswählen',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: items.length,
                  padding: const EdgeInsets.symmetric(vertical: 0),
                  itemBuilder: (_, i) {
                    final item = items[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(item.product.name, style: theme.textTheme.titleMedium?.copyWith(fontSize: 20)),
                                if (item.quantity > 1)
                                  Text(
                                    '${item.quantity}×  ${formatPrice(item.product.price)}',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            formatPrice(item.subtotal),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: item.product.isRefund ? Colors.green : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => ref
                                .read(cartProvider.notifier)
                                .removeItem(item.product.id),
                            child: const Icon(Icons.close, size: 22),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),

        // Totals
        if (items.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Gesamt:', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    Text(formatPrice(total), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
                if (customer != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Rest Guthaben:',
                          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      Text(
                        formatPrice(restBalance),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: restBalance < 0
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],

        // Book button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: FilledButton.icon(
            onPressed: canBook ? () => _book(context, ref) : null,
            icon: const Icon(Icons.check, size: 22),
            label: const Text('Buchen'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ),

        // Storno button
        if (lastBooking != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _storno(context),
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Letzte Buchung stornieren'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}
