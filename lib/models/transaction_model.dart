import 'dart:convert';

class TransactionModel {
  final String txId, senderMobile, receiverMobile, timestamp, signatureToken, status;
  final int amountCents;
  const TransactionModel({required this.txId, required this.senderMobile,
    required this.receiverMobile, required this.amountCents, required this.timestamp,
    required this.signatureToken, this.status = 'OFFLINE_PENDING'});
  double get amount => amountCents / 100;
  Map<String, Object?> get signedFields => {
    'version': 1, 'tx_id': txId, 'sender_mobile': senderMobile,
    'receiver_mobile': receiverMobile, 'amount': amount, 'timestamp': timestamp,
  };
  String get payload => jsonEncode({...signedFields, 'signature_token': signatureToken});
  Map<String, Object?> toMap() => {
    'tx_id': txId, 'sender_mobile': senderMobile, 'receiver_mobile': receiverMobile,
    'amount': amount, 'timestamp': timestamp, 'signature_token': signatureToken, 'status': status,
  };
  factory TransactionModel.fromMap(Map<String, Object?> m) => TransactionModel(
    txId: m['tx_id'] as String, senderMobile: m['sender_mobile'] as String,
    receiverMobile: m['receiver_mobile'] as String,
    amountCents: ((m['amount'] as num) * 100).round(), timestamp: m['timestamp'] as String,
    signatureToken: m['signature_token'] as String,
    status: m['status'] as String? ?? 'OFFLINE_PENDING');
}
