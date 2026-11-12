import 'package:flutter/material.dart';
import '../services/nfc_service.dart';
import 'ui_helpers.dart';

class NfcOffer extends StatefulWidget {
  final String payload;
  const NfcOffer({super.key, required this.payload});
  @override
  State<NfcOffer> createState() => _NfcOfferState();
}
class _NfcOfferState extends State<NfcOffer> with WidgetsBindingObserver {
  bool _active = false, _busy = false;
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      NfcService.stop();
      if (mounted) setState(() => _active = false);
    }
  }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); NfcService.stop(); super.dispose(); }
  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      if (_active) { await NfcService.stop(); }
      else {
        final caps = await NfcService.capabilities();
        if (caps['sender'] != true) {
          if (mounted) message(context, 'NFC sending requires Android with HCE support. Use this QR on iPhone or unsupported hardware.');
          return;
        }
        if (caps['enabled'] != true) {
          if (mounted) message(context, 'Enable NFC in system settings, then try again.');
          return;
        }
        await NfcService.offer(widget.payload);
      }
      if (mounted) setState(() => _active = !_active);
    } catch (e) {
      if (mounted) message(context, 'NFC could not start. ${e is Exception ? e.toString() : 'Use QR instead.'}');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(16),
    child: Column(children: [FilledButton.icon(onPressed: _busy ? null : _toggle,
      icon: const Icon(Icons.nfc), label: Text(_active ? 'Stop real NFC' : 'Start real NFC tap')),
      const SizedBox(height: 8), Text(_active ?
        'Ready to read. On the other phone choose Receive → Real NFC. Hold NFC antenna areas together. '
        'Wait for “Payment received” on the receiver. This sender cannot confirm wallet credit.' :
        'Android sender → compatible Android or iPhone reader. Keep both phones unlocked. '
        'iPhone sending uses QR. Mock NFC below is a separate simulation.')])));
}
