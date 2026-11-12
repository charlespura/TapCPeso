import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import '../models/transaction_model.dart';

class WalletException implements Exception {
  final String message;
  const WalletException(this.message);
  @override
  String toString() => message;
}

class CryptoService {
  // Deliberately shared across demo installations. NOT a production secret.
  static const _demoKey = 'TapCPeso/offline/prototype/shared-key/v1';
  static final _mobile = RegExp(r'^09[0-9]{9}$');
  static bool validMobile(String value) => _mobile.hasMatch(value);
  static String randomToken() => List.generate(24, (_) => Random.secure().nextInt(256)
    .toRadixString(16).padLeft(2, '0')).join();
  static String pinHash(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();
  static bool equal(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) { difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i); }
    return difference == 0;
  }
  static int parseAmount(String input) {
    final text = input.trim();
    if (!RegExp(r'^[0-9]{1,7}(\.[0-9]{1,2})?$').hasMatch(text)) {
      throw const WalletException('Enter a positive amount with up to two decimal places.');
    }
    final parts = text.split('.');
    final cents = int.parse(parts[0]) * 100 + (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
    if (cents <= 0 || cents > 100000000) throw const WalletException('Amount must be between PHP 0.01 and PHP 1,000,000.');
    return cents;
  }
  static String sign(TransactionModel tx) => Hmac(sha256, utf8.encode(_demoKey))
    .convert(utf8.encode(jsonEncode(tx.signedFields))).toString();
  static bool verify(TransactionModel tx) => equal(sign(tx), tx.signatureToken);
  static TransactionModel create(String sender, String receiver, int cents) {
    final tx = TransactionModel(txId: randomToken(), senderMobile: sender,
      receiverMobile: receiver, amountCents: cents,
      timestamp: DateTime.now().toUtc().toIso8601String(), signatureToken: '');
    return TransactionModel.fromMap({...tx.toMap(), 'signature_token': sign(tx)});
  }
  static TransactionModel decode(String payload) {
    try {
      if (payload.length > 4096) throw const FormatException();
      final m = jsonDecode(payload);
      if (m is! Map<String, dynamic> || m.length != 7 || m['version'] != 1 ||
          m['tx_id'] is! String || !RegExp(r'^[0-9a-f]{48}$').hasMatch(m['tx_id'] as String) ||
          m['sender_mobile'] is! String || !validMobile(m['sender_mobile'] as String) ||
          m['receiver_mobile'] is! String || !validMobile(m['receiver_mobile'] as String) ||
          m['sender_mobile'] == m['receiver_mobile'] || m['amount'] is! num ||
          m['timestamp'] is! String || m['signature_token'] is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(m['signature_token'] as String)) {
        throw const FormatException();
      }
      final amount = (m['amount'] as num).toDouble();
      if (!amount.isFinite || amount <= 0 || amount > 1000000 ||
          (amount * 100 - (amount * 100).round()).abs() > 0.000001) throw const FormatException();
      final date = DateTime.tryParse(m['timestamp'] as String);
      if (date == null || !date.isUtc || date.toIso8601String() != m['timestamp'] ||
          date.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 5)))) throw const FormatException();
      final tx = TransactionModel.fromMap(m);
      if (!verify(tx)) throw const WalletException('Invalid signature. Payload may have been altered.');
      return tx;
    } on WalletException { rethrow; }
    catch (_) { throw const WalletException('Invalid wallet QR / transfer payload.'); }
  }
}
