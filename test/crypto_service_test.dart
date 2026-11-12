import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapc_peso/services/crypto_service.dart';

void main() {
  test('signed payload survives JSON roundtrip and detects every signed field change', () {
    final tx = CryptoService.create('09171111111', '09172222222', 12345);
    expect(CryptoService.decode(tx.payload).amountCents, 12345);
    final changes = <String, Object>{'amount': 123.46, 'receiver_mobile': '09173333333',
      'sender_mobile': '09174444444', 'timestamp': '2026-01-01T00:00:00.000Z',
      'tx_id': '0' * 48};
    for (final entry in changes.entries) {
      final map = jsonDecode(tx.payload) as Map<String, dynamic>;
      map[entry.key] = entry.value;
      expect(() => CryptoService.decode(jsonEncode(map)), throwsA(isA<WalletException>()));
    }
  });
  test('rejects malformed, unsupported and sub-cent payloads', () {
    final tx = CryptoService.create('09171111111', '09172222222', 1);
    for (final value in ['', '[]', '{}', 'not json']) {
      expect(() => CryptoService.decode(value), throwsA(isA<WalletException>()));
    }
    final map = jsonDecode(tx.payload) as Map<String, dynamic>;
    map['amount'] = 0.001;
    expect(() => CryptoService.decode(jsonEncode(map)), throwsA(isA<WalletException>()));
    map['version'] = 2;
    expect(() => CryptoService.decode(jsonEncode(map)), throwsA(isA<WalletException>()));
  });
  test('amounts use exact integer cent parsing', () {
    expect(CryptoService.parseAmount('0.01'), 1);
    expect(CryptoService.parseAmount('10.5'), 1050);
    expect(CryptoService.parseAmount('1000000'), 100000000);
    for (final value in ['0', '-1', 'NaN', '1.001', '1e3', '1000000.01']) {
      expect(() => CryptoService.parseAmount(value), throwsA(isA<WalletException>()));
    }
  });
}
