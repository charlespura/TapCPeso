import 'package:flutter/material.dart';
import '../services/crypto_service.dart';

String money(num value) => 'PHP ${value.toStringAsFixed(2)}';
void message(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
String errorMessage(Object error) => error is WalletException ? error.message :
  'Could not complete the operation. Check device setup and try again.';

Future<String?> requestValue(BuildContext context, {required String title,
  required String label, bool secret = false}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
    title: Text(title), content: TextField(controller: controller, autofocus: true,
      obscureText: secret, maxLength: secret ? 4 : null,
      keyboardType: secret ? TextInputType.number : const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      onSubmitted: (value) => Navigator.pop(ctx, value)),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Continue'))]));
  // Wait for the dialog route's exit animation before disposing its controller.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
  return result;
}
