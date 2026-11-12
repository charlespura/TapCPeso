import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tapc_peso/database/db_helper.dart';
import 'package:tapc_peso/services/crypto_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final wallet = DBHelper.instance;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('tapcpeso_test_');
    await databaseFactory.setDatabasesPath(directory.path);
  });
  setUp(() async {
    final db = await wallet.database;
    await db.delete('receipts');
    await db.delete('transactions');
    await db.delete('users');
    await wallet.demo();
  });
  tearDownAll(() async {
    await (await wallet.database).close();
    await directory.delete(recursive: true);
  });
  test('same-device transfer credits once and sync never changes balances', () async {
    final a = await wallet.login('09171111111', '1234');
    final b = await wallet.login('09172222222', '1234');
    final tx = await wallet.send(a.id, b.mobileNumber, 12345);
    expect((await wallet.user(a.id)).balance, 876.55);
    expect((await wallet.history(b.mobileNumber)), isEmpty);
    await wallet.receive(b.id, tx.payload);
    expect((await wallet.user(b.id)).balance, 1123.45);
    await expectLater(wallet.receive(b.id, tx.payload), throwsA(isA<WalletException>()));
    expect((await wallet.user(b.id)).balance, 1123.45);
    expect((await wallet.database).query('transactions').then((r) => r.length), completion(1));
    expect((await wallet.sync()).synced, 1);
    expect((await wallet.sync()).synced, 0);
    expect((await wallet.user(a.id)).balance + (await wallet.user(b.id)).balance, 2000);
  });
  test('insufficient balance and wrong recipient leave database unchanged', () async {
    final a = await wallet.login('09171111111', '1234');
    final b = await wallet.login('09172222222', '1234');
    await expectLater(wallet.send(a.id, b.mobileNumber, 100001), throwsA(isA<WalletException>()));
    expect(await wallet.history(a.mobileNumber), isEmpty);
    final foreign = CryptoService.create('09173333333', '09174444444', 100);
    await expectLater(wallet.receive(b.id, foreign.payload), throwsA(isA<WalletException>()));
    expect((await wallet.user(a.id)).balance, 1000);
    expect((await wallet.user(b.id)).balance, 1000);
  });
  test('cross-device receipt with absent sender account and concurrent replay', () async {
    final b = await wallet.login('09172222222', '1234');
    final tx = CryptoService.create('09173333333', b.mobileNumber, 101);
    var successes = 0, duplicates = 0;
    await Future.wait(List.generate(2, (_) async {
      try { await wallet.receive(b.id, tx.payload); successes++; }
      on WalletException { duplicates++; }
    }));
    expect(successes, 1); expect(duplicates, 1);
    expect((await wallet.user(b.id)).balance, 1001.01);
  });
  test('two isolated device databases transfer, persist and sync independently', () async {
    final phoneA = DBHelper.forDatabase(p.join(directory.path, 'phone_a.db'));
    final phoneB = DBHelper.forDatabase(p.join(directory.path, 'phone_b.db'));
    try {
      await phoneA.register('Person 1', '09171111111', '1234');
      await phoneB.register('Person 2', '09172222222', '1234');
      final a = await phoneA.login('09171111111', '1234');
      final b = await phoneB.login('09172222222', '1234');
      await phoneA.cashIn(a.id, 100000);
      final outgoing = await phoneA.send(a.id, b.mobileNumber, 2500);
      // Transport (QR or native NFC) passes precisely these UTF-8 JSON bytes.
      await phoneB.receive(b.id, outgoing.payload);
      expect((await phoneA.user(a.id)).balance, 975);
      expect((await phoneB.user(b.id)).balance, 25);
      await phoneA.sync();
      expect((await phoneB.history(b.mobileNumber)).single.status, 'OFFLINE_PENDING');
      await (await phoneB.database).close();
      final reopened = DBHelper.forDatabase(p.join(directory.path, 'phone_b.db'));
      try {
        expect((await reopened.login(b.mobileNumber, '1234')).balance, 25);
        await expectLater(reopened.receive(b.id, outgoing.payload), throwsA(isA<WalletException>()));
        expect((await reopened.sync()).synced, 1);
        expect((await reopened.user(b.id)).balance, 25);
      } finally { await (await reopened.database).close(); }
    } finally {
      await (await phoneA.database).close();
      final db = await phoneB.database;
      if (db.isOpen) await db.close();
    }
  });
  test('tampered records remain pending during sync', () async {
    final a = await wallet.login('09171111111', '1234');
    final tx = await wallet.send(a.id, '09172222222', 100);
    await (await wallet.database).update('transactions', {'amount': 999.0}, where: 'tx_id = ?', whereArgs: [tx.txId]);
    final sync = await wallet.sync();
    expect(sync.invalid, 1); expect(sync.synced, 0);
    expect((await wallet.history(a.mobileNumber)).single.status, 'OFFLINE_PENDING');
    expect((await wallet.user(a.id)).balance, 999);
  });
  test('demo setup is idempotent and PINs / duplicate accounts are checked', () async {
    final a = await wallet.login('09171111111', '1234');
    await wallet.cashIn(a.id, 25);
    await wallet.demo();
    expect((await wallet.user(a.id)).balance, 1000.25);
    await expectLater(wallet.login(a.mobileNumber, '0000'), throwsA(isA<WalletException>()));
    await expectLater(wallet.register('Other', a.mobileNumber, '1234'), throwsA(isA<WalletException>()));
  });
}
