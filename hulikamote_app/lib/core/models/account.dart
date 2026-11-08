/// A motorist's account as the backend sends it after logging in or signing up (never contains the password).
class Account {
  const Account({
    required this.userId,
    required this.name,
    required this.plate,
    this.email = '',
    this.licenseNo = '',
    this.licenseType = '',
    this.restrictions = '',
    this.expiry = '',
    this.address = '',
  });

  final String userId;
  final String name;
  final String plate;
  final String email;
  final String licenseNo;
  final String licenseType;
  final String restrictions;
  final String expiry;
  final String address;

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        userId: json['user_id'] as String,
        name: json['name'] as String? ?? '',
        plate: json['plate'] as String? ?? '',
        email: json['email'] as String? ?? '',
        licenseNo: json['license_no'] as String? ?? '',
        licenseType: json['license_type'] as String? ?? '',
        restrictions: json['restrictions'] as String? ?? '',
        expiry: json['expiry'] as String? ?? '',
        address: json['address'] as String? ?? '',
      );

  /// Accounts made in the app have no licence on file (the backend fills in placeholders).
  bool get hasLicense => licenseType.isNotEmpty && licenseType != 'Not provided';
}
