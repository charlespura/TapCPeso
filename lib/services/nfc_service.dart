import 'dart:async';
import 'package:flutter/services.dart';
import 'crypto_service.dart';

class NfcService {
  static const _channel = MethodChannel('tapcpeso/nfc');
  static Future<Map<String, dynamic>> capabilities() async {
    try {
      return Map<String, dynamic>.from(await _channel.invokeMapMethod<String, dynamic>('capabilities') ?? {});
    } on MissingPluginException { return {'reader': false, 'sender': false, 'enabled': false}; }
  }
  static Future<void> offer(String payload) async {
    CryptoService.decode(payload);
    await _channel.invokeMethod<void>('offer', payload);
  }
  static Future<String> read() async {
    try {
      final payload = await _channel.invokeMethod<String>('read').timeout(const Duration(seconds: 45));
      if (payload == null) throw const WalletException('No NFC payment received.');
      return payload;
    } on TimeoutException {
      await stop();
      throw const WalletException('NFC timed out. Keep both phones unlocked and try again, or scan QR.');
    }
  }
  static Future<void> stop() async {
    try { await _channel.invokeMethod<void>('stop'); } catch (_) { /* Platform may be unavailable. */ }
  }
}
