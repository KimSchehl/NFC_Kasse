import 'package:dio/dio.dart';

import '../models/cart_item.dart';
import 'api_client.dart';

enum PrintOutcome { done, failed, timeout }

class PrintResult {
  final PrintOutcome outcome;
  final String? errorMessage;

  const PrintResult(this.outcome, [this.errorMessage]);
}

/// Calls the backend's /api/print/bon endpoint.
/// The backend handles booking to the BAR virtual chip AND printing.
class PrintService {
  final ApiClient _client;

  PrintService(this._client);

  /// Books [items] to the BAR chip and queues one ESC/POS bon per unit.
  /// Returns the raw response (`bons_printed`, `print_job_ids`,
  /// `low_stock_warnings`, ...). Throws [DioException] on network error,
  /// HTTP 503 if the database is busy.
  Future<Map<String, dynamic>> printBons(List<CartItem> items) async {
    final payload = {
      'items': items
          .map((i) => {'product_id': i.product.id, 'quantity': i.quantity})
          .toList(),
    };
    final response = await _client.dio.post('/api/print/bon', data: payload);
    return response.data as Map<String, dynamic>;
  }

  /// Polls the queued [jobIds] until the printer has handled all of them or
  /// [timeout] passes. Transient network errors are retried until the deadline.
  Future<PrintResult> waitForPrintJobs(
    List<int> jobIds, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      try {
        final resp = await _client.dio.get(
          '/api/print/jobs',
          queryParameters: {'ids': jobIds.join(',')},
        );
        final jobs = (resp.data['jobs'] as List).cast<Map<String, dynamic>>();

        final failed = jobs.where((j) => j['status'] == 'error');
        if (failed.isNotEmpty) {
          return PrintResult(PrintOutcome.failed, failed.first['error_msg'] as String?);
        }
        if (jobs.length == jobIds.length && jobs.every((j) => j['status'] == 'done')) {
          return const PrintResult(PrintOutcome.done);
        }
      } on DioException {
        // Retried below until the deadline.
      }

      if (DateTime.now().isAfter(deadline)) {
        return const PrintResult(PrintOutcome.timeout);
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
}
