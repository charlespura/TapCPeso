import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/transaction_model.dart';
import 'ui_helpers.dart';
import 'nfc_offer.dart';

class TransferCard extends StatelessWidget {
  final TransactionModel transfer;
  const TransferCard({super.key, required this.transfer});
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.check_circle_outline, size: 40), const SizedBox(height: 8),
    Text(money(transfer.amount), style: Theme.of(context).textTheme.headlineMedium),
    Text('To ${transfer.receiverMobile}'), const SizedBox(height: 12),
    const Text('Debited locally. Ask the receiver to scan this QR.'),
    const SizedBox(height: 12), Container(color: Colors.white, child: QrImageView(
      data: transfer.payload, version: QrVersions.auto, size: 280, gapless: true,
      errorCorrectionLevel: QrErrorCorrectLevel.M)),
    const SizedBox(height: 12), SelectableText('Transfer ID: ${transfer.txId}'),
    const SizedBox(height: 12), OutlinedButton.icon(
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: transfer.payload));
        if (context.mounted) message(context, 'Payload copied. Paste it into the receiver’s mock NFC screen.');
      }, icon: const Icon(Icons.copy), label: const Text('Copy mock NFC payload')),
    const Text('You can reopen this QR from transaction history. Do not send again if scanning fails.'),
    NfcOffer(payload: transfer.payload),
  ]);
}
