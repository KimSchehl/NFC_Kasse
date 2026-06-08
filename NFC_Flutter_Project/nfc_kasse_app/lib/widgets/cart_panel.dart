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
/// - Shows locked "Chip Pfand" deduction line when customer.isNew is true
/// - Shows locked "Chip Pfand Rückgabe" line when a payout product is in cart
/// - Shows "Gesamt" total and "Rest Guthaben" (balance after purchase, red if < 0)
/// - For payout: shows "Auszahlungsbetrag" (balance + deposit) instead
/// - Disables the Buchen button when the result would be a negative balance
/// - Shows the "Letzte Buchung stornieren" button after a successful booking
class CartPanel extends ConsumerWidget {
  final bool showHeader;

  const CartPanel({super.key, this.showHeader = true});

  Future<void> _book(BuildContext context, WidgetRef ref) async {
    final cart = ref.read(cartProvider.notifier);
    final customer = ref.read(customerProvider);
    if (customer == null || cart.productIds.isEmpty) return;

    final isPayout = ref.read(cartProvider).any((i) => i.product.isPayout);

    try {
      final svc = ref.read(salesServiceProvider);
      final result = await svc.book(customer.nfcUid, cart.productIds);

      if (isPayout) {
        // Chip returned — clear customer and suppress storno button.
        ref.read(customerProvider.notifier).state = null;
        ref.read(lastBookingProvider.notifier).state = null;
      } else {
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
        ref.read(customerProvider.notifier).state = null;
      }

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

    final chipDeposit = customer?.chipDeposit ?? 0.0;
    final hasPayout = items.any((i) => i.product.isPayout);

    // Show Pfand deduction only on new customer without payout product.
    final showPfandDeduction = (customer?.isNew ?? false) && !hasPayout && chipDeposit > 0;
    // Show Pfand refund whenever a payout product is in the cart.
    final showPfandRefund = hasPayout && chipDeposit > 0;

    // Effective total: for payout the customer receives balance + deposit;
    // for normal bookings the Pfand deduction increases the cost.
    final realTotal = cart.total;
    final payoutTotal = customer != null ? customer.balance + chipDeposit : 0.0;
    final adjustedTotal = hasPayout
        ? payoutTotal
        : realTotal + (showPfandDeduction ? chipDeposit : 0.0);

    final restBalance = customer != null && !hasPayout
        ? customer.balance - adjustedTotal
        : 0.0;

    // Client-side guard: disabled when balance would go negative.
    // Payout is always allowed as long as a customer is loaded.
    final canBook = items.isNotEmpty &&
        customer != null &&
        (hasPayout || restBalance >= 0);

    final cartTextScale = ref.watch(cartTextScaleProvider);

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(cartTextScale),
      ),
      child: Column(
      children: [
        // Header (hidden in narrow layout where the drag handle shows the title)
        if (showHeader)
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
        // "Leeren" button when header is hidden (narrow layout)
        if (!showHeader && items.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => ref.read(cartProvider.notifier).clear(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                textStyle: theme.textTheme.titleMedium,
              ),
              child: const Text('Leeren'),
            ),
          ),

        // Items
        Expanded(
          child: (items.isEmpty && !showPfandDeduction)
              ? Center(
                  child: Text(
                    'Bitte Artikel auswählen',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 0),
                  children: [
                    // Regular cart items
                    ...items.map((item) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(item.product.name,
                                        style: theme.textTheme.titleMedium?.copyWith(fontSize: 20)),
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
                                onTap: () =>
                                    ref.read(cartProvider.notifier).removeItem(item.product.id),
                                child: const Icon(Icons.close, size: 22),
                              ),
                            ],
                          ),
                        )),

                    // Locked Pfand deduction (new customer)
                    if (showPfandDeduction)
                      _VirtualCartLine(
                        label: 'Chip Pfand',
                        amount: chipDeposit,
                        color: theme.colorScheme.error,
                      ),

                    // Locked Pfand refund (payout)
                    if (showPfandRefund)
                      _VirtualCartLine(
                        label: 'Chip Pfand Rückgabe',
                        amount: chipDeposit,
                        color: Colors.green,
                        isRefund: true,
                      ),
                  ],
                ),
        ),

        // Totals
        if (items.isNotEmpty || showPfandDeduction) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      hasPayout ? 'Auszahlungsbetrag:' : 'Gesamt:',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      formatPrice(adjustedTotal.abs()),
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                if (customer != null && !hasPayout) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Rest Guthaben:',
                          style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
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

        // Book + Storno buttons — wrapped in SafeArea so they stay above the
        // system navigation bar on both phones and tablets.
        SafeArea(
          top: false,
          left: false,
          right: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: FilledButton.icon(
                  onPressed: canBook ? () => _book(context, ref) : null,
                  icon: Icon(hasPayout ? Icons.payments_outlined : Icons.check, size: 22),
                  label: Text(hasPayout ? 'Auszahlen' : 'Buchen'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
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
          ),
        ),
      ],
      ),
    );
  }
}

/// A locked, non-removable virtual line item shown for automatic Pfand
/// deductions and refunds.
class _VirtualCartLine extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final bool isRefund;

  const _VirtualCartLine({
    required this.label,
    required this.amount,
    required this.color,
    this.isRefund = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 16,
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          Text(
            '${isRefund ? '+' : ''}${formatPrice(isRefund ? amount : -amount)}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          // Spacer to align with the close-button column of regular items
          const SizedBox(width: 30),
        ],
      ),
    );
  }
}
