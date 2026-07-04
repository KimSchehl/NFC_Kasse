import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/help_model.dart';
import '../providers/providers.dart';

class HelpButton extends ConsumerWidget {
  const HelpButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myRequest = ref.watch(helpProvider).myRequest;

    final Color color;
    final IconData icon;
    final String label;

    if (myRequest == null) {
      color = Colors.red;
      icon = Icons.warning_amber_rounded;
      label = 'HILFE';
    } else {
      final primary = myRequest.primaryResponse;
      if (primary == null) {
        color = Colors.orange;
        icon = Icons.warning_amber_rounded;
        label = 'HILFE Angefordert';
      } else if (primary.response == 'on_way') {
        color = Colors.green;
        icon = Icons.directions_run;
        label = 'Hilfe Kommt!';
      } else if (primary.response == '5min') {
        color = Colors.green;
        icon = Icons.access_time;
        label = 'Hilfe Kommt (5min)';
      } else {
        // everyone said 'cannot'
        color = Colors.orange;
        icon = Icons.warning_amber_rounded;
        label = 'HILFE Angefordert';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ElevatedButton(
        onPressed: () => _onPressed(context, ref),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  void _onPressed(BuildContext context, WidgetRef ref) {
    final helpState = ref.read(helpProvider);
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    if (helpState.myRequest != null) {
      showDialog(
        context: context,
        builder: (_) => _ActiveRequestDialog(requestId: helpState.myRequest!.id),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => const _SendHelpDialog(),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Dialog: confirm sending help request
// ---------------------------------------------------------------------------

class _SendHelpDialog extends ConsumerStatefulWidget {
  const _SendHelpDialog();

  @override
  ConsumerState<_SendHelpDialog> createState() => _SendHelpDialogState();
}

class _SendHelpDialogState extends ConsumerState<_SendHelpDialog> {
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red),
          SizedBox(width: 8),
          Text('Hilfe anfordern'),
        ],
      ),
      content: const Text(
        'Hiermit senden Sie eine Hilfe-Anfrage an alle Notfall-Kontakte.\n\nFortfahren?',
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _sending ? null : _send,
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('HILFE ANFORDERN'),
        ),
      ],
    );
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await ref.read(helpProvider.notifier).requestHelp();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Senden der Hilfe-Anfrage')),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Dialog: active request — show responses, allow resolve
// ---------------------------------------------------------------------------

class _ActiveRequestDialog extends ConsumerStatefulWidget {
  final int requestId;
  const _ActiveRequestDialog({required this.requestId});

  @override
  ConsumerState<_ActiveRequestDialog> createState() =>
      _ActiveRequestDialogState();
}

class _ActiveRequestDialogState extends ConsumerState<_ActiveRequestDialog> {
  bool _popped = false;

  void _safePop() {
    if (_popped || !mounted) return;
    _popped = true;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final helpState = ref.watch(helpProvider);
    final request = helpState.allRequests
            .where((r) => r.id == widget.requestId)
            .firstOrNull ??
        helpState.myRequest;

    if (request == null) {
      // Resolved externally — auto-close without double-pop risk.
      WidgetsBinding.instance.addPostFrameCallback((_) => _safePop());
      return const SizedBox.shrink();
    }

    final primary = request.primaryResponse;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Text('Hilfe angefordert'),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (request.responses.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Warte auf Rückmeldung...',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else ...[
              if (primary != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primary.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: primary.color.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.person, color: primary.color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${primary.responderName}: ${primary.label}',
                          style: TextStyle(
                            color: primary.color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const Text(
                'Alle Rückmeldungen:',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              ...request.responses.map(
                (r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 8, color: r.color),
                      const SizedBox(width: 6),
                      Text('${r.responderName}: ${r.label}'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _safePop,
          child: const Text('Schließen'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            await ref
                .read(helpProvider.notifier)
                .resolve(widget.requestId);
            _safePop();
          },
          icon: const Icon(Icons.check),
          label: const Text('Erledigt'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.green),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog: responder sees incoming requests + respond buttons
// ---------------------------------------------------------------------------

class HelpResponderOverlay extends ConsumerWidget {
  const HelpResponderOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final helpState = ref.watch(helpProvider);
    final user = ref.read(authProvider).valueOrNull;
    if (user == null || !user.hasPermission('help.receive')) {
      return const SizedBox.shrink();
    }

    final myId = user.id;
    final unanswered = helpState.allRequests
        .where((r) => !r.responses.any((resp) => resp.responderId == myId))
        .toList();
    if (unanswered.isEmpty) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 60, right: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: unanswered
                .map((req) => _ResponderCard(request: req))
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _ResponderCard extends ConsumerStatefulWidget {
  final HelpRequest request;
  const _ResponderCard({required this.request});

  @override
  ConsumerState<_ResponderCard> createState() => _ResponderCardState();
}

class _ResponderCardState extends ConsumerState<_ResponderCard> {
  bool _responding = false;

  Future<void> _respond(String response) async {
    setState(() => _responding = true);
    try {
      await ref.read(helpProvider.notifier).respond(widget.request.id, response);
    } finally {
      if (mounted) setState(() => _responding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final helpState = ref.watch(helpProvider);
    final req = helpState.allRequests
        .where((r) => r.id == widget.request.id)
        .firstOrNull;
    if (req == null) return const SizedBox.shrink();

    final myId = ref.read(authProvider).valueOrNull?.id;
    final myResponse = req.responses
        .where((r) => r.responderId == myId)
        .firstOrNull;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.red.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Colors.red, size: 18),
                const SizedBox(width: 6),
                Text(
                  '${req.requesterName} braucht Hilfe!',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (req.someoneOnWay && myResponse?.response != 'on_way')
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Jemand ist bereits unterwegs',
                  style: TextStyle(fontSize: 12, color: Colors.green),
                ),
              ),
            const SizedBox(height: 8),
            if (myResponse != null)
              Text(
                'Meine Antwort: ${myResponse.label}',
                style: TextStyle(fontSize: 12, color: myResponse.color),
              )
            else
              Wrap(
                spacing: 6,
                children: [
                  _ResponseButton(
                    label: 'Auf dem Weg',
                    color: Colors.green,
                    loading: _responding,
                    onPressed: () => _respond('on_way'),
                  ),
                  _ResponseButton(
                    label: '5 Minuten',
                    color: Colors.orange,
                    loading: _responding,
                    onPressed: () => _respond('5min'),
                  ),
                  _ResponseButton(
                    label: 'Nicht möglich',
                    color: Colors.red,
                    loading: _responding,
                    onPressed: () => _respond('cannot'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ResponseButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool loading;
  final VoidCallback onPressed;

  const _ResponseButton({
    required this.label,
    required this.color,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: loading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12),
      ),
      child: Text(label),
    );
  }
}
