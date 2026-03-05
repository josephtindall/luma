import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Stores previously-successful login email addresses in browser localStorage.
/// Used to show quick-select tiles on the login screen (Google-like UX).
class LoginEmailStore {
  static const _storageKey = 'luma_login_emails';

  /// Returns saved email addresses, most-recently-used first.
  List<String> getEmails() {
    try {
      final storage = globalContext['localStorage'] as JSObject?;
      if (storage == null) return [];
      final raw = (storage.callMethod<JSAny?>('getItem'.toJS, _storageKey.toJS)
              as JSString?)
          ?.toDart;
      if (raw == null || raw.isEmpty) return [];
      return raw.split(',').where((e) => e.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// Adds an email after a successful login. Moves it to the front if it
  /// already existed, and caps the list at 5 entries.
  void addEmail(String email) {
    try {
      final emails = getEmails()..remove(email);
      emails.insert(0, email);
      if (emails.length > 5) emails.removeRange(5, emails.length);
      _save(emails);
    } catch (_) {}
  }

  /// Removes a single email from history (the X button).
  void removeEmail(String email) {
    try {
      final emails = getEmails()..remove(email);
      _save(emails);
    } catch (_) {}
  }

  /// Replaces an old email with a new one in-place (e.g. after email change).
  void replaceEmail(String oldEmail, String newEmail) {
    try {
      final emails = getEmails();
      final idx = emails.indexOf(oldEmail);
      if (idx != -1) {
        emails[idx] = newEmail;
      }
      _save(emails);
    } catch (_) {}
  }

  void _save(List<String> emails) {
    final storage = globalContext['localStorage'] as JSObject?;
    if (storage == null) return;
    storage.callMethod<JSAny?>(
        'setItem'.toJS, _storageKey.toJS, emails.join(',').toJS);
  }
}
