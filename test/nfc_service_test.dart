import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapc_peso/services/nfc_service.dart';
import 'package:tapc_peso/services/crypto_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tapcpeso/nfc');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('native NFC receives the same signed payload that QR uses', () async {
    final tx = CryptoService.create('09171111111', '09172222222', 2500);
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'capabilities': return {'reader': true, 'sender': true, 'enabled': true};
        case 'read': return tx.payload;
        default: return null;
      }
    });
    expect((await NfcService.capabilities())['sender'], true);
    await NfcService.offer(tx.payload);
    expect(calls.last.arguments, tx.payload);
    final received = CryptoService.decode(await NfcService.read());
    expect(received.txId, tx.txId);
    expect(received.amountCents, 2500);
    await NfcService.stop();
    expect(calls.last.method, 'stop');
  });
  test('invalid offer never reaches native NFC', () async {
    var nativeCalls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async { nativeCalls++; return null; });
    await expectLater(NfcService.offer('{"amount":999}'), throwsA(isA<WalletException>()));
    expect(nativeCalls, 0);
  });
  test('unsupported platforms report no NFC and cancellation propagates', () async {
    expect((await NfcService.capabilities())['reader'], false);
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'NFC_CANCELLED');
    });
    await expectLater(NfcService.read(), throwsA(isA<PlatformException>()));
    await NfcService.stop();
  });
}
