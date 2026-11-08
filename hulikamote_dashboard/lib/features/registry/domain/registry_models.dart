/// A motorist with the e-mail and plates on file (backend: routers/registry.py).
class Motorist {
  const Motorist({required this.id, required this.name, required this.licenseNo, this.email = '', this.plates = const []});

  final String id;
  final String name;
  final String licenseNo;

  /// Empty means "do not e-mail this motorist".
  final String email;
  final List<String> plates;

  factory Motorist.fromJson(Map<String, dynamic> json) => Motorist(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        licenseNo: json['license_no'] as String? ?? '',
        email: json['email'] as String? ?? '',
        plates: [for (final p in json['plates'] as List? ?? const []) p as String],
      );
}

/// One notice the system wrote to a motorist (e-mailed, or left in the laptop's mailbox).
class NoticeRecord {
  const NoticeRecord({required this.id, required this.userName, required this.toEmail, required this.subject, required this.status, this.detail = '', this.createdAt});

  final String id;
  final String userName;
  final String toEmail;
  final String subject;

  /// `sent` (e-mailed), `local` (waiting in the mailbox) or `failed` ([detail] says why).
  final String status;
  final String detail;
  final DateTime? createdAt;

  factory NoticeRecord.fromJson(Map<String, dynamic> json) => NoticeRecord(
        id: json['id'] as String? ?? '',
        userName: json['user_name'] as String? ?? '',
        toEmail: json['to_email'] as String? ?? '',
        subject: json['subject'] as String? ?? '',
        status: json['status'] as String? ?? '',
        detail: json['detail'] as String? ?? '',
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal(),
      );
}

/// How motorists are notified now (backend: routers/notify.py). The app password is never sent to the dashboard.
class NoticeSettings {
  const NoticeSettings({
    required this.mode,
    this.gmail = '',
    this.passwordSet = false,
    this.cloudUrl = '',
    this.cloudKeySet = false,
    this.mailboxUrls = const [],
    this.notices = const [],
  });

  /// `online` (Gmail) or `offline` (a phone on the same Wi-Fi opens the mailbox page).
  final String mode;
  final String gmail;
  final bool passwordSet;

  /// The Supabase project the phone app reads from, and whether its secret key is saved (the key itself never comes here).
  final String cloudUrl;
  final bool cloudKeySet;

  /// Where a phone on the same network opens the mailbox, e.g. `http://192.168.68.112:8000/mailbox`.
  final List<String> mailboxUrls;
  final List<NoticeRecord> notices;

  bool get online => mode == 'online';

  factory NoticeSettings.fromJson(Map<String, dynamic> json) => NoticeSettings(
        mode: json['mode'] as String? ?? 'offline',
        gmail: json['gmail'] as String? ?? '',
        passwordSet: json['password_set'] as bool? ?? false,
        cloudUrl: json['cloud_url'] as String? ?? '',
        cloudKeySet: json['cloud_key_set'] as bool? ?? false,
        mailboxUrls: [for (final u in json['mailbox_urls'] as List? ?? const []) u as String],
        notices: [for (final n in json['notices'] as List? ?? const []) NoticeRecord.fromJson(Map<String, dynamic>.from(n as Map))],
      );
}

/// The answer to "Send test e-mail".
class TestEmailResult {
  const TestEmailResult({required this.status, this.detail = '', this.to = ''});

  final String status;
  final String detail;
  final String to;

  bool get sent => status == 'sent';

  factory TestEmailResult.fromJson(Map<String, dynamic> json) =>
      TestEmailResult(status: json['status'] as String? ?? '', detail: json['detail'] as String? ?? '', to: json['to'] as String? ?? '');
}

/// The answer to "Test cloud".
class CloudTestResult {
  const CloudTestResult({required this.ok, this.detail = ''});

  final bool ok;
  final String detail;

  factory CloudTestResult.fromJson(Map<String, dynamic> json) =>
      CloudTestResult(ok: json['ok'] as bool? ?? false, detail: json['detail'] as String? ?? '');
}

/// One demo account that "Create demo accounts" tried to make in the cloud.
class CloudAccountResult {
  const CloudAccountResult({required this.plate, required this.status, this.detail = ''});

  final String plate;

  /// `created`, `exists` or `failed` ([detail] says why).
  final String status;
  final String detail;

  factory CloudAccountResult.fromJson(Map<String, dynamic> json) => CloudAccountResult(
      plate: json['plate'] as String? ?? '', status: json['status'] as String? ?? '', detail: json['detail'] as String? ?? '');
}

/// Is push set up on the laptop, and (after a test) how many phones got it.
class PushResult {
  const PushResult({required this.ready, this.detail = '', this.phones = 0, this.sent = 0, this.failed = 0});

  final bool ready;
  final String detail;
  final int phones;
  final int sent;
  final int failed;

  factory PushResult.fromJson(Map<String, dynamic> json) => PushResult(
        ready: json['ready'] as bool? ?? false,
        detail: json['detail'] as String? ?? '',
        phones: (json['phones'] as num?)?.toInt() ?? 0,
        sent: (json['sent'] as num?)?.toInt() ?? 0,
        failed: (json['failed'] as num?)?.toInt() ?? 0,
      );
}
