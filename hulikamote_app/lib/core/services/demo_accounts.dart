import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/plate.dart';

/// A sign-in shortcut for a demo motorist on the sign-in page. The list lives on the phone and can be edited in
/// developer mode; the accounts themselves live on the laptop (and in the cloud).
class DemoAccount {
  const DemoAccount(this.name, this.plate, this.password);

  final String name;
  final String plate;
  final String password;

  Map<String, String> toJson() => {'name': name, 'plate': plate, 'password': password};

  factory DemoAccount.fromJson(Map<String, dynamic> json) =>
      DemoAccount('${json['name']}', '${json['plate']}', '${json['password']}');
}

class DemoAccounts {
  DemoAccounts._();

  static const _key = 'demo_accounts';

  /// The three motorists the laptop starts with (see store.DEMO_PLATES on the laptop).
  static const defaults = [
    DemoAccount('Juan', 'ABC 1234', 'password123'),
    DemoAccount('Maria', 'DEF 5678', 'password123'),
    DemoAccount('Pedro', 'GHI 9012', 'password123'),
  ];

  static Future<List<DemoAccount>> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return defaults;
      return [for (final item in jsonDecode(raw) as List) DemoAccount.fromJson(Map<String, dynamic>.from(item as Map))];
    } catch (_) {
      return defaults;
    }
  }

  static Future<void> save(List<DemoAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode([for (final a in accounts) a.toJson()]));
  }

  /// Add or replace the shortcut for this plate (however it is typed).
  static Future<void> upsert(DemoAccount account) async {
    final key = normalizePlate(account.plate);
    final all = await load();
    final index = all.indexWhere((a) => normalizePlate(a.plate) == key);
    await save([...all]..replaceRange(index < 0 ? all.length : index, index < 0 ? all.length : index + 1, [account]));
  }

  static Future<void> remove(String plate) async {
    final key = normalizePlate(plate);
    await save([for (final a in await load()) if (normalizePlate(a.plate) != key) a]);
  }

  static Future<void> reset() async => (await SharedPreferences.getInstance()).remove(_key);
}
