class UserModel {
  final int id;
  final String fullName, mobileNumber, pinHash, publicKeyToken;
  final double balance;
  const UserModel({required this.id, required this.fullName,
    required this.mobileNumber, required this.pinHash, required this.balance,
    required this.publicKeyToken});
  factory UserModel.fromMap(Map<String, Object?> m) => UserModel(
    id: m['id'] as int, fullName: m['full_name'] as String,
    mobileNumber: m['mobile_number'] as String, pinHash: m['pin_hash'] as String,
    balance: (m['balance'] as num).toDouble(), publicKeyToken: m['public_key_token'] as String);
}
