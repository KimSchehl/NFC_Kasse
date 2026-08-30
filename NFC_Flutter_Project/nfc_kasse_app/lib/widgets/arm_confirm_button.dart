import 'dart:async';

import 'package:flutter/material.dart';

/// A button that requires two taps to trigger [onConfirmed] — the first tap
/// only "arms" it (relabels/recolors as a visual cue) and starts a
/// [armedDuration] countdown; a second tap before that expires actually
/// confirms. No tap within the window reverts to the idle state.
///
/// This is a deliberately new interaction pattern for this app — every other
/// destructive action here instead opens a separate confirmation dialog
/// (see `cancel_booking_dialog.dart`, `edit_product_dialog.dart`'s
/// `_delete()`). Used for the pager list's "Fertig" button, where a modal
/// dialog would be more friction than the action warrants.
///
/// Error handling for [onConfirmed] is the caller's responsibility (e.g. a
/// SnackBar on failure) — this widget only tracks the arm/busy state.
class ArmConfirmButton extends StatefulWidget {
  final String idleLabel;
  final String armedLabel;
  final Duration armedDuration;
  final Future<void> Function() onConfirmed;

  const ArmConfirmButton({
    super.key,
    this.idleLabel = 'Fertig',
    this.armedLabel = 'Wirklich fertig?',
    this.armedDuration = const Duration(seconds: 3),
    required this.onConfirmed,
  });

  @override
  State<ArmConfirmButton> createState() => _ArmConfirmButtonState();
}

class _ArmConfirmButtonState extends State<ArmConfirmButton> {
  bool _armed = false;
  bool _busy = false;
  Timer? _revertTimer;

  @override
  void dispose() {
    _revertTimer?.cancel();
    super.dispose();
  }

  void _onTap() {
    if (_busy) return;

    if (!_armed) {
      setState(() => _armed = true);
      _revertTimer = Timer(widget.armedDuration, () {
        if (mounted) setState(() => _armed = false);
      });
      return;
    }

    _revertTimer?.cancel();
    setState(() {
      _armed = false;
      _busy = true;
    });
    widget.onConfirmed().whenComplete(() {
      if (mounted) setState(() => _busy = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FilledButton.tonal(
      onPressed: _busy ? null : _onTap,
      style: FilledButton.styleFrom(
        backgroundColor: _armed ? theme.colorScheme.errorContainer : null,
        foregroundColor: _armed ? theme.colorScheme.onErrorContainer : null,
      ),
      child: _busy
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(_armed ? widget.armedLabel : widget.idleLabel),
    );
  }
}
