import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/user_model.dart';
import '../models/transaction_model.dart';
import '../services/crypto_service.dart';

class SyncResult {
  final int synced, invalid;
  const SyncResult(this.synced, this.invalid);
}

class DBHelper {
  DBHelper._() : _path = null;
  DBHelper.forDatabase(String path) : _path = path;
  final String? _path;
  static final instance = DBHelper._();
  Future<Database>? _database;
  Future<Database> get database => _database ??= _open();
  Future<Database> _open() async {
    try {
      return await openDatabase(_path ?? p.join(await getDatabasesPath(), 'tapc_peso.db'), version: 1,
        onConfigure: (db) async { await db.execute('PRAGMA foreign_keys = ON'); },
        onCreate: (db, _) async {
          await db.execute('''CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT, full_name TEXT NOT NULL,
            mobile_number TEXT NOT NULL UNIQUE, pin_hash TEXT NOT NULL,
            balance REAL NOT NULL DEFAULT 0 CHECK(balance >= 0), public_key_token TEXT NOT NULL)''');
          await db.execute('''CREATE TABLE transactions (
            tx_id TEXT PRIMARY KEY, sender_mobile TEXT NOT NULL, receiver_mobile TEXT NOT NULL,
            amount REAL NOT NULL CHECK(amount > 0), timestamp TEXT NOT NULL,
            signature_token TEXT NOT NULL, status TEXT NOT NULL
            CHECK(status IN ('OFFLINE_PENDING', 'SYNCED')))''');
          // Separate receipt is needed when both users share the sender's database.
          await db.execute('''CREATE TABLE receipts (
            tx_id TEXT PRIMARY KEY REFERENCES transactions(tx_id),
            receiver_mobile TEXT NOT NULL, received_at TEXT NOT NULL)''');
          await db.execute('CREATE INDEX tx_parties ON transactions(sender_mobile, receiver_mobile)');
        });
    } catch (_) { _database = null; rethrow; }
  }
  Future<UserModel> user(int id) async {
    final rows = await (await database).query('users', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) throw const WalletException('Account no longer exists.');
    return UserModel.fromMap(rows.first);
  }
  Future<void> register(String name, String mobile, String pin) async {
    if (name.trim().length < 2 || name.trim().length > 80 || !CryptoService.validMobile(mobile) ||
        !RegExp(r'^[0-9]{4}$').hasMatch(pin)) {
      throw const WalletException('Enter a name, an 11-digit 09 mobile number, and a 4-digit PIN.');
    }
    final token = CryptoService.randomToken();
    try {
      await (await database).insert('users', {'full_name': name.trim(), 'mobile_number': mobile,
        'pin_hash': CryptoService.pinHash(pin, token), 'balance': 0.0, 'public_key_token': token});
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) throw const WalletException('Mobile number is already registered on this device.');
      rethrow;
    }
  }
  Future<UserModel> login(String mobile, String pin) async {
    final rows = await (await database).query('users', where: 'mobile_number = ?', whereArgs: [mobile]);
    if (rows.isEmpty) throw const WalletException('Incorrect mobile number or PIN.');
    final account = UserModel.fromMap(rows.first);
    if (!CryptoService.equal(account.pinHash, CryptoService.pinHash(pin, account.publicKeyToken))) {
      throw const WalletException('Incorrect mobile number or PIN.');
    }
    return account;
  }
  Future<void> demo() async {
    await (await database).transaction((txn) async {
      for (var i = 1; i <= 2; i++) {
        final mobile = i == 1 ? '09171111111' : '09172222222';
        final rows = await txn.query('users', where: 'mobile_number = ?', whereArgs: [mobile]);
        if (rows.isNotEmpty) continue;
        final token = CryptoService.randomToken();
        await txn.insert('users', {'full_name': 'Person $i', 'mobile_number': mobile,
          'pin_hash': CryptoService.pinHash('1234', token), 'balance': 1000.0, 'public_key_token': token});
      }
    });
  }
  static void _checkCents(int cents) {
    if (cents <= 0 || cents > 100000000) throw const WalletException('Invalid amount.');
  }
  Future<void> cashIn(int id, int cents) async {
    _checkCents(cents);
    await (await database).transaction((txn) async {
      final rows = await txn.query('users', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) throw const WalletException('Account not found.');
      final next = ((rows.first['balance'] as num) * 100).round() + cents;
      if (next > 100000000) throw const WalletException('Demo wallet limit is PHP 1,000,000.');
      await txn.update('users', {'balance': next / 100}, where: 'id = ?', whereArgs: [id]);
    });
  }
  Future<TransactionModel> send(int id, String receiver, int cents) async {
    _checkCents(cents);
    if (!CryptoService.validMobile(receiver)) throw const WalletException('Enter the receiver’s 11-digit 09 mobile number.');
    return (await database).transaction((txn) async {
      final rows = await txn.query('users', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) throw const WalletException('Account not found.');
      final sender = UserModel.fromMap(rows.first);
      if (sender.mobileNumber == receiver) throw const WalletException('Choose a different receiver.');
      final balance = (sender.balance * 100).round();
      if (balance < cents) throw const WalletException('Insufficient balance. Add mock funds first.');
      final transfer = CryptoService.create(sender.mobileNumber, receiver, cents);
      await txn.update('users', {'balance': (balance - cents) / 100}, where: 'id = ?', whereArgs: [id]);
      await txn.insert('transactions', transfer.toMap());
      return transfer;
    });
  }
  Future<TransactionModel> receive(int id, String payload) async {
    final transfer = CryptoService.decode(payload);
    return (await database).transaction((txn) async {
      final rows = await txn.query('users', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) throw const WalletException('Account not found.');
      final receiver = UserModel.fromMap(rows.first);
      if (transfer.receiverMobile != receiver.mobileNumber) throw const WalletException('This transfer is addressed to another account.');
      final receipts = await txn.query('receipts', where: 'tx_id = ?', whereArgs: [transfer.txId]);
      if (receipts.isNotEmpty) throw const WalletException('Duplicate transfer: this payment has already been received.');
      final existing = await txn.query('transactions', where: 'tx_id = ?', whereArgs: [transfer.txId]);
      if (existing.isNotEmpty) {
        if (TransactionModel.fromMap(existing.first).payload != transfer.payload || existing.first['amount'] != transfer.amount) {
          throw const WalletException('Transaction ID conflicts with an existing transfer.');
        }
      } else {
        await txn.insert('transactions', transfer.toMap());
      }
      final next = (receiver.balance * 100).round() + transfer.amountCents;
      if (next > 100000000) throw const WalletException('Receiving would exceed the demo wallet limit.');
      await txn.insert('receipts', {'tx_id': transfer.txId, 'receiver_mobile': receiver.mobileNumber,
        'received_at': DateTime.now().toUtc().toIso8601String()});
      await txn.update('users', {'balance': next / 100}, where: 'id = ?', whereArgs: [id]);
      await txn.update('transactions', {'status': 'OFFLINE_PENDING'}, where: 'tx_id = ?', whereArgs: [transfer.txId]);
      return transfer;
    });
  }
  Future<List<TransactionModel>> history(String mobile) async => (await (await database).rawQuery(
    '''SELECT t.* FROM transactions t WHERE t.sender_mobile = ? OR
    (t.receiver_mobile = ? AND EXISTS (SELECT 1 FROM receipts r WHERE r.tx_id = t.tx_id))
    ORDER BY t.timestamp DESC''', [mobile, mobile])).map(TransactionModel.fromMap).toList();
  Future<List<TransactionModel>> mockInbox(String mobile) async => (await (await database).rawQuery(
    '''SELECT t.* FROM transactions t WHERE t.receiver_mobile = ? AND NOT EXISTS
    (SELECT 1 FROM receipts r WHERE r.tx_id = t.tx_id) ORDER BY t.timestamp DESC''',
    [mobile])).map(TransactionModel.fromMap).toList();
  Future<SyncResult> sync() async => (await database).transaction((txn) async {
    final pending = await txn.query('transactions', where: 'status = ?', whereArgs: ['OFFLINE_PENDING']);
    var valid = 0, invalid = 0;
    for (final row in pending) {
      try {
        final fields = Map<String, Object?>.from(row)..remove('status');
        final tx = CryptoService.decode(jsonEncode({'version': 1, ...fields}));
        await txn.update('transactions', {'status': 'SYNCED'}, where: 'tx_id = ?', whereArgs: [tx.txId]);
        valid++;
      } catch (_) { invalid++; }
    }
    return SyncResult(valid, invalid);
  });
}
