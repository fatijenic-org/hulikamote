import '../config/app_config.dart';
import 'session.dart';

/// Where a ticket's photo comes from. On the same Wi-Fi: the laptop's evidence folder. Online: the private cloud
/// bucket, which only opens with the motorist's sign-in token (so only their own photos load).
class PhotoSource {
  PhotoSource._();

  /// [name] is a file name on the laptop, or (online) a path `<user>/<ticket>/<file>` in the cloud bucket.
  static String url(String name) => AppConfig.isOnline
      ? '${AppConfig.cloudUrl}/storage/v1/object/authenticated/evidence/${name.split('/').map(Uri.encodeComponent).join('/')}'
      : '${AppConfig.baseUrl}/snapshots/evidence/${Uri.encodeComponent(name)}';

  /// What the request needs besides the address (nothing on the laptop).
  static Map<String, String>? get headers =>
      AppConfig.isOnline ? {'apikey': AppConfig.cloudKey, 'Authorization': 'Bearer ${Session.accessToken ?? AppConfig.cloudKey}'} : null;
}
