import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../database/db_helper.dart';
import 'home_screen.dart';
import 'ui_helpers.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}
class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController(), _mobile = TextEditingController(), _pin = TextEditingController();
  bool _register = false, _busy = false;
  @override
  void dispose() { _name.dispose(); _mobile.dispose(); _pin.dispose(); super.dispose(); }
  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      if (_register) await DBHelper.instance.register(_name.text, _mobile.text.trim(), _pin.text);
      final user = await DBHelper.instance.login(_mobile.text.trim(), _pin.text);
      if (!mounted) return;
      _pin.clear();
      await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => HomeScreen(userId: user.id)));
    } catch (e) { if (mounted) message(context, errorMessage(e)); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _demo() async {
    setState(() => _busy = true);
    try {
      await DBHelper.instance.demo();
      if (!mounted) return;
      setState(() { _register = false; _mobile.text = '09171111111'; _pin.text = '1234'; });
      message(context, 'Demo ready. Each NEW account starts with PHP 1,000. PIN: 1234.');
    } catch (e) { if (mounted) message(context, errorMessage(e)); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(
    padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Icon(Icons.account_balance_wallet_rounded, size: 64, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16), Text('TapCPeso', textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
        const Text('Your offline wallet playground', textAlign: TextAlign.center),
        const SizedBox(height: 12), const Chip(label: Text('LOCAL DEMO · NO REAL MONEY')),
        const SizedBox(height: 24),
        SegmentedButton<bool>(segments: const [ButtonSegment(value: false, label: Text('Log in')),
          ButtonSegment(value: true, label: Text('Register'))], selected: {_register},
          onSelectionChanged: _busy ? null : (s) => setState(() => _register = s.first)),
        const SizedBox(height: 24),
        if (_register) ...[TextField(controller: _name, enabled: !_busy, textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Full name')), const SizedBox(height: 16)],
        TextField(controller: _mobile, enabled: !_busy, keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
          decoration: const InputDecoration(labelText: 'Mobile number', hintText: '09XXXXXXXXX')),
        const SizedBox(height: 16), TextField(controller: _pin, enabled: !_busy, obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          decoration: const InputDecoration(labelText: '4-digit wallet PIN'),
          onSubmitted: _busy ? null : (_) => _submit()),
        const SizedBox(height: 20), FilledButton(onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Please wait…' : _register ? 'Create account' : 'Open wallet')),
        const SizedBox(height: 12), OutlinedButton.icon(onPressed: _busy ? null : _demo,
          icon: const Icon(Icons.science_outlined), label: const Text('Quick Demo Setup')),
        const SizedBox(height: 16), const Text('Person 1: 09171111111\nPerson 2: 09172222222\nBoth demo PINs: 1234',
          textAlign: TextAlign.center),
        const SizedBox(height: 12), const Text('Accounts and balances exist only on this installation. '
          'Set up the demo on both phones for a two-device QR test.', textAlign: TextAlign.center),
      ]))))));
}
