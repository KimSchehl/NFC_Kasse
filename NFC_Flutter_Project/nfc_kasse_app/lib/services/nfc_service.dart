import 'dart:typed_data';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';

class NfcService {
  static Future<bool> isAvailable() async {
    try {
      return await NfcManager.instance.isAvailable();
    } catch (_) {
      return false;
    }
  }

  static Future<void> startSession(void Function(String uid) onUid) async {
    await NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        final uid = _extractUid(tag);
        if (uid != null) onUid(uid);
      },
    );
  }

  static Future<void> stopSession() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
  }

  static String? _extractUid(NfcTag tag) {
    Uint8List? bytes;

    final nfca = NfcA.from(tag);
    if (nfca != null) bytes = nfca.identifier;

    if (bytes == null) {
      final nfcb = NfcB.from(tag);
      if (nfcb != null) bytes = nfcb.identifier;
    }

    if (bytes == null) {
      final nfcf = NfcF.from(tag);
      if (nfcf != null) bytes = nfcf.identifier;
    }

    if (bytes == null) {
      final nfcv = NfcV.from(tag);
      if (nfcv != null) bytes = nfcv.identifier;
    }

    if (bytes == null) {
      final mifare = MiFare.from(tag);
      if (mifare != null) bytes = mifare.identifier;
    }

    if (bytes == null) return null;
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
  }
}
