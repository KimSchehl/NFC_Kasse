import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/nfc_service.dart';
import '../utils/formatters.dart';

/// Text field that accepts NFC UIDs from three input paths:
///
/// 1. **USB HID reader**: the reader emulates a keyboard and types the UID
///    followed by `\n` or `\r`. [_onChanged] detects the newline and submits.
/// 2. **Native NFC** (Android): [NfcService.startSession] notifies us via
///    callback when a tag is detected, and we call [_submit] directly. This
///    works purely at the OS level and doesn't need the field focused, so —
///    like the BLE case below — the field defaults to read-only to stop
///    Android's on-screen keyboard from popping up every time it regains
///    focus (switching category, closing a dialog, ...). Unlike BLE, manual
///    UID entry is still offered as a fallback here: tapping the field
///    ([_onTap]) flips it editable until it loses focus again.
/// 3. **BLE reader**: [bleReaderProvider] pushes each scan via GATT notify;
///    a `ref.listen` on its `lastUidSeq` counter submits it. While connected,
///    the field is always read-only (there's nothing to type - input comes
///    over BLE exclusively, no manual-entry fallback).
///
/// In all cases the UID is normalised to uppercase hex and kept visible in the
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

  // True right after an explicit tap on the field while native NFC is
  // available — temporarily lets the user type a UID by hand instead of
  // scanning. Reset the moment focus is lost so the *next* unsolicited
  // refocus (category switch, a dialog closing, ...) goes back to blocking
  // the on-screen keyboard rather than popping it up again.
  bool _manualEntryRequested = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _focusNode.addListener(_onFocusChange);
    _initNfc();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _manualEntryRequested) {
      setState(() => _manualEntryRequested = false);
    }
  }

  void _onTap() {
    if (_nfcAvailable && !_manualEntryRequested) {
      setState(() => _manualEntryRequested = true);
    }
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
    _focusNode.removeListener(_onFocusChange);
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

    // Submit each BLE scan as it arrives (lastUidSeq increments per scan, so
    // this fires even if the same wristband is tapped twice in a row).
    ref.listen(bleReaderProvider, (prev, next) {
      if (next.lastUid != null && next.lastUidSeq != prev?.lastUidSeq) {
        _submit(next.lastUid!);
      }
    });

    final bleConnected = ref.watch(
      bleReaderProvider.select((s) => s.isConnected),
    );

    // Blocks the on-screen keyboard while a hands-free scan path (BLE or
    // native NFC) is the active input method — neither needs the field
    // focused to work, so autofocus/refocus (category switch, a dialog
    // closing, the post-booking requestFocus() below, ...) would otherwise
    // pop the keyboard for no reason. Native NFC still allows a deliberate
    // tap ([_onTap]) to type a UID by hand; BLE never does, there's no other
    // way to feed it.
    final readOnlyNow = bleConnected || (_nfcAvailable && !_manualEntryRequested);

    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      autofocus: true,
      readOnly: readOnlyNow,
      showCursor: !readOnlyNow,
      keyboardType:
          readOnlyNow ? TextInputType.none : TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      textCapitalization: TextCapitalization.characters,
      onTap: _onTap,
      decoration: InputDecoration(
        hintText: bleConnected
            ? 'BLE-Lesegerät verbunden - warte auf Scan...'
            : _nfcAvailable
                ? 'NFC scannen oder UID eingeben...'
                : 'UID eingeben oder USB-Lesegerät verwenden...',
        prefixIcon: Icon(
          bleConnected
              ? Icons.bluetooth_connected
              : _nfcAvailable
                  ? Icons.nfc
                  : Icons.usb,
          color: (bleConnected || _nfcAvailable)
              ? Theme.of(context).colorScheme.primary
              : null,
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
