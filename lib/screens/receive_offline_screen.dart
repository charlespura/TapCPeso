import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../database/db_helper.dart';
import '../models/user_model.dart';
import '../models/transaction_model.dart';
import 'ui_helpers.dart';
import '../services/nfc_service.dart';

class ReceiveOfflineScreen extends StatefulWidget {
  final UserModel user;
  const ReceiveOfflineScreen({super.key, required this.user});
  @override
  State<ReceiveOfflineScreen> createState() => _ReceiveOfflineScreenState();
}
class _ReceiveOfflineScreenState extends State<ReceiveOfflineScreen> {
  final _payload = TextEditingController();
  bool _mock = true, _busy = false;
  bool _nfcReading = false;
  List<TransactionModel> _inbox = [];
  @override
  void initState() { super.initState(); _loadInbox(); }
  @override
  void dispose() { NfcService.stop(); _payload.dispose(); super.dispose(); }
  Future<void> _readNfc() async {
    setState(() { _nfcReading = true; _mock = true; });
    try {
      final caps = await NfcService.capabilities();
      if (caps['reader'] != true || caps['enabled'] != true) {
        if (mounted) message(context, 'NFC reader is unavailable or disabled. Enable NFC or use QR.');
        return;
      }
      final payload = await NfcService.read();
      if (mounted) await _receive(payload);
    } catch (e) {
      if (mounted) message(context, 'NFC transfer stopped. Keep the phones together and retry, or scan QR.');
    } finally { if (mounted) setState(() => _nfcReading = false); }
  }
  Future<void> _loadInbox() async {
    try {
      final inbox = await DBHelper.instance.mockInbox(widget.user.mobileNumber);
      if (mounted) setState(() => _inbox = inbox);
    } catch (e) { if (mounted) message(context, errorMessage(e)); }
  }
  Future<void> _receive(String payload) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final tx = await DBHelper.instance.receive(widget.user.id, payload);
      if (!mounted) return;
      await showDialog<void>(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline), title: const Text('Payment received'),
        content: Text('${money(tx.amount)} from ${tx.senderMobile}\n\nCredited locally · OFFLINE_PENDING'),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))]));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        message(context, errorMessage(e));
        // Stop the camera after an error to avoid repeated detections and snackbars.
        setState(() => _mock = true);
      }
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !_busy, child: Scaffold(
    appBar: AppBar(title: const Text('Receive offline')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text('Receiving as ${widget.user.fullName}', style: Theme.of(context).textTheme.titleLarge),
      SelectableText(widget.user.mobileNumber),
      const SizedBox(height: 12), FilledButton.tonalIcon(
        onPressed: _busy || _nfcReading ? null : _readNfc,
        icon: const Icon(Icons.nfc), label: Text(_nfcReading ? 'Hold near the Android sender…' : 'Receive via real NFC')),
      if (_nfcReading) TextButton(onPressed: () => NfcService.stop(), child: const Text('Cancel NFC')),
      SwitchListTile(value: _mock, title: const Text('Mock NFC mode'),
        subtitle: const Text('Turn off to scan a sender’s QR code.'),
        onChanged: _busy || _nfcReading ? null : (value) { setState(() => _mock = value); if (value) _loadInbox(); }),
      if (_busy || _nfcReading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
      else if (!_mock) ...[
        SizedBox(height: 340, child: ClipRRect(borderRadius: BorderRadius.circular(16), child: MobileScanner(
          onDetect: (capture) {
            for (final barcode in capture.barcodes) {
              final text = barcode.rawValue;
              if (text != null && text.isNotEmpty) { _receive(text); break; }
            }
          }, errorBuilder: (context, error) => Center(child: Padding(padding: const EdgeInsets.all(20),
            child: Text('Camera unavailable (${error.errorCode.name}). Enable camera permission in Settings, '
              'or use Mock NFC mode.')))))),
        const SizedBox(height: 12), const Text('Point the camera at the sender’s payment QR. Credit occurs immediately after validation.'),
      ] else ...[
        const Card(child: Padding(padding: EdgeInsets.all(16), child: Text(
          'Mock NFC simulates delivery only. It uses the same signature, recipient, and replay checks as QR. '
          'It does not transmit over radio.'))),
        const SizedBox(height: 16), TextField(controller: _payload, minLines: 3, maxLines: 7,
          decoration: const InputDecoration(labelText: 'Paste signed transfer JSON')),
        const SizedBox(height: 12), FilledButton.icon(onPressed: () => _receive(_payload.text.trim()),
          icon: const Icon(Icons.nfc), label: const Text('Simulate NFC tap')),
        const SizedBox(height: 24), Row(children: [
          const Expanded(child: Text('Same-device demo payments')),
          IconButton(onPressed: _loadInbox, icon: const Icon(Icons.refresh))]),
        if (_inbox.isEmpty) const Text('No waiting payments. Send from the other local account first.'),
        ..._inbox.map((tx) => Card(child: ListTile(title: Text(money(tx.amount)),
          subtitle: Text('From ${tx.senderMobile}'), trailing: const Icon(Icons.nfc),
          onTap: () => _receive(tx.payload)))),
      ],
    ])));
}
