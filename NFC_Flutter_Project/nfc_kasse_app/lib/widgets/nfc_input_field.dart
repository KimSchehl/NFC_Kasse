import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/nfc_service.dart';
import '../utils/formatters.dart';

/// Text field that accepts NFC UIDs from two input paths:
///
/// 1. **USB HID reader**: the reader emulates a keyboard and types the UID
///    followed by `\n` or `\r`. [_onChanged] detects the newline and submits.
/// 2. **Native NFC** (Android): [NfcService.startSession] notifies us via
///    callback when a tag is detected, and we call [_submit] directly.
///
/// In both cases the UID is normalised to uppercase hex and kept visible in the
/// field so staff can see which wristband is loaded. The next scan overwrites it.
class NfcInputField extends ConsumerStatefulWidget {
  final void Function(String uid) onSubmit;

  const NfcInputField({super.key, required this.onSubmit});

  @override
  ConsumerState<NfcInputField> createState() => _NfcInputFieldState();
}

class _NfcInputFieldState extends ConsumerState<NfcInputField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _nfcAvailable = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _initNfc();
  }

  Future<void> _initNfc() async {
    final available = await NfcService.isAvailable();
    if (!mounted) return;
    setState(() => _nfcAvailable = available);
    if (available) {
      NfcService.startSession((uid) {
        if (!mounted) return;
        _submit(uid);
      });
    }
  }

  void _clearField() {
    _controller.clear();
    ref.read(customerProvider.notifier).state = null;
  }

  void _submit(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    final uid = normalizeUid(trimmed) ?? trimmed.toUpperCase();
    _controller.text = uid;
    _controller.selection = TextSelection.collapsed(offset: uid.length);
    widget.onSubmit(uid);
  }

  void _onChanged(String value) {
    // HID readers append \n or \r after the UID — submit immediately.
    if (value.endsWith('\n') || value.endsWith('\r')) {
      _submit(value.replaceAll(RegExp(r'[\r\n]'), ''));
    }
  }

  @override
  void dispose() {
    if (_nfcAvailable) NfcService.stopSession();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Clear the UID field whenever a booking completes.
    ref.listen(lastBookingProvider, (prev, next) {
      if (next != null) {
        _controller.clear();
        _focusNode.requestFocus();
      }
    });

    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      autofocus: true,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        hintText: _nfcAvailable
            ? 'NFC scannen oder UID eingeben...'
            : 'UID eingeben oder USB-Lesegerät verwenden...',
        prefixIcon: Icon(
          _nfcAvailable ? Icons.nfc : Icons.usb,
          color: _nfcAvailable ? Theme.of(context).colorScheme.primary : null,
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_controller.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearField,
                tooltip: 'Feld leeren',
              ),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: () => _submit(_controller.text),
              tooltip: 'Kunde laden',
            ),
          ],
        ),
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[A-Fa-f0-9:\- \r\n]')),
      ],
      onChanged: _onChanged,
      onSubmitted: _submit,
    );
  }
}
