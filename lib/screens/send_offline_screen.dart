import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../database/db_helper.dart';
import '../models/user_model.dart';
import '../models/transaction_model.dart';
import '../services/crypto_service.dart';
import 'transfer_card.dart';
import 'ui_helpers.dart';

class SendOfflineScreen extends StatefulWidget {
  final UserModel user;
  const SendOfflineScreen({super.key, required this.user});
  @override
  State<SendOfflineScreen> createState() => _SendOfflineScreenState();
}
class _SendOfflineScreenState extends State<SendOfflineScreen> {
  final _receiver = TextEditingController(), _amount = TextEditingController();
  bool _busy = false, _mock = false;
  TransactionModel? _transfer;
  @override
  void dispose() { _receiver.dispose(); _amount.dispose(); super.dispose(); }
  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final cents = CryptoService.parseAmount(_amount.text);
      final receiver = _receiver.text.trim();
      if (!CryptoService.validMobile(receiver) || receiver == widget.user.mobileNumber) {
        throw const WalletException('Enter a different receiver’s valid 09 mobile number.');
      }
      // Wallet PIN ties authorization to the selected account on a shared demo device.
      final pin = await requestValue(context, title: 'Authorize ${money(cents / 100)}', label: 'Wallet PIN', secret: true);
      if (pin == null) return;
      await DBHelper.instance.login(widget.user.mobileNumber, pin);
      final auth = LocalAuthentication();
      if (!await auth.isDeviceSupported()) {
        throw const WalletException('Set up a device screen-lock PIN or biometrics before sending. Emulators need a screen lock too.');
      }
      final authorized = await auth.authenticate(
        localizedReason: 'Approve ${money(cents / 100)} to $receiver',
        biometricOnly: false, persistAcrossBackgrounding: true);
      if (!authorized) throw const WalletException('Payment authorization was cancelled. No funds deducted.');
      final tx = await DBHelper.instance.send(widget.user.id, receiver, cents);
      if (mounted) setState(() => _transfer = tx);
    } on LocalAuthException catch (e) {
      if (mounted) message(context, 'Device authentication failed (${e.code.name}). Check screen-lock / biometric settings.');
    } catch (e) { if (mounted) message(context, errorMessage(e)); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !_busy, child: Scaffold(
    appBar: AppBar(title: const Text('Send offline')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      if (_transfer == null) ...[
        Text('A payment, without the internet.', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12), const Text('The receiver must use the mobile number entered below. '
          'Funds are deducted once you authorize. The receiver credits them by scanning your QR.'),
        const SizedBox(height: 24), TextField(controller: _receiver, enabled: !_busy,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
          decoration: const InputDecoration(labelText: 'Receiver mobile number', hintText: '09172222222')),
        const SizedBox(height: 16), TextField(controller: _amount, enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount', prefixText: 'PHP ')),
        const SizedBox(height: 24), FilledButton.icon(onPressed: _busy ? null : _send,
          icon: const Icon(Icons.fingerprint), label: Text(_busy ? 'Authorizing…' : 'Authorize & create payment')),
      ] else ...[
        TransferCard(transfer: _transfer!),
        SwitchListTile(value: _mock, title: const Text('Simulate NFC tap'),
          subtitle: const Text('Mock transport; no NFC hardware is used.'),
          onChanged: (value) => setState(() => _mock = value)),
        if (_mock) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text(
          'Same device: switch to the receiver account → Receive offline → Mock NFC → select this payment.\n\n'
          'Two devices: copy the payload, transfer it manually, then paste into Mock NFC on the receiver. '
          'Use QR for direct offline device-to-device transfer.'))),
      ],
    ])));
}
