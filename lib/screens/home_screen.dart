import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../models/user_model.dart';
import '../models/transaction_model.dart';
import '../services/crypto_service.dart';
import 'send_offline_screen.dart';
import 'receive_offline_screen.dart';
import 'transfer_card.dart';
import 'ui_helpers.dart';

class HomeScreen extends StatefulWidget {
  final int userId;
  const HomeScreen({super.key, required this.userId});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  UserModel? _user;
  List<TransactionModel> _history = [];
  bool _busy = false;
  String? _error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final user = await DBHelper.instance.user(widget.userId);
      final history = await DBHelper.instance.history(user.mobileNumber);
      if (mounted) setState(() { _user = user; _history = history; _error = null; });
    } catch (e) { if (mounted) setState(() => _error = errorMessage(e)); }
  }
  Future<void> _cashIn() async {
    setState(() => _busy = true);
    try {
      final text = await requestValue(context, title: 'Add mock funds', label: 'Amount in PHP');
      if (text == null) return;
      await DBHelper.instance.cashIn(widget.userId, CryptoService.parseAmount(text));
      await _load();
      if (mounted) message(context, 'Mock funds added.');
    } catch (e) { if (mounted) message(context, errorMessage(e)); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _sync() async {
    setState(() => _busy = true);
    try {
      final result = await DBHelper.instance.sync();
      await _load();
      if (mounted) message(context, '${result.synced} verified and synced; ${result.invalid} invalid left pending. No network used.');
    } catch (e) { if (mounted) message(context, errorMessage(e)); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _open(Widget screen) async {
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) await _load();
  }
  @override
  Widget build(BuildContext context) {
    final user = _user;
    return PopScope(canPop: !_busy, child: Scaffold(
      appBar: AppBar(title: const Text('TapCPeso'), automaticallyImplyLeading: false,
        actions: [TextButton.icon(onPressed: _busy ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.switch_account_outlined), label: const Text('Switch account'))]),
      body: user == null ? Center(child: _error == null ? const CircularProgressIndicator() :
        Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!), TextButton(onPressed: _load, child: const Text('Retry'))])) :
      RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Hello, ${user.fullName}', style: Theme.of(context).textTheme.headlineSmall),
        Text(user.mobileNumber), const SizedBox(height: 20),
        Card(color: Theme.of(context).colorScheme.primaryContainer, child: Padding(
          padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('AVAILABLE DEMO BALANCE'), const SizedBox(height: 8),
            Text(money(user.balance), style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8), const Text('Stored on this device · SQLite'),
          ]))),
        const SizedBox(height: 16), Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(onPressed: _busy ? null : _cashIn,
            icon: const Icon(Icons.add), label: const Text('Add money')),
          FilledButton.icon(onPressed: _busy ? null : () => _open(SendOfflineScreen(user: user)),
            icon: const Icon(Icons.north_east), label: const Text('Send offline')),
          FilledButton.tonalIcon(onPressed: _busy ? null : () => _open(ReceiveOfflineScreen(user: user)),
            icon: const Icon(Icons.qr_code_scanner), label: const Text('Receive offline')),
        ]), const SizedBox(height: 16),
        OutlinedButton.icon(onPressed: _busy ? null : _sync,
          icon: const Icon(Icons.sync), label: Text(_busy ? 'Working…' : 'Simulate reconnect & sync')),
        const Text('Sync verifies local signatures only. It does not contact a bank or another device.'),
        const SizedBox(height: 24), Text('Transaction history', style: Theme.of(context).textTheme.titleLarge),
        if (_error != null) Text(_error!),
        if (_history.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 32),
          child: Text('Your first offline payment starts here.')),
        ..._history.map((tx) {
          final sent = tx.senderMobile == user.mobileNumber;
          return Card(child: ListTile(isThreeLine: true,
            leading: Icon(sent ? Icons.north_east : Icons.south_west),
            title: Text('${sent ? '−' : '+'}${money(tx.amount)}'),
            subtitle: Text('${sent ? 'To ${tx.receiverMobile}' : 'From ${tx.senderMobile}'}\n'
              '${DateTime.parse(tx.timestamp).toLocal()}\n${tx.status}'),
            trailing: sent ? const Icon(Icons.qr_code) : null,
            onTap: sent ? () => showDialog<void>(context: context, builder: (ctx) => Dialog(
              child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min,
                children: [TransferCard(transfer: tx), TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))])))) : null));
        }),
      ]))));
  }
}
