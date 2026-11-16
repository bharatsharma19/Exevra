/// Plain REST calls to the local Supabase stack for the end-to-end test:
/// the mail catcher, and a second user driven from the test.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'e2e_env.dart';

/// Reads the sign-up code from the local mail catcher (Mailpit).
class MailCatcher {
  MailCatcher({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  static final RegExp _code = RegExp(r'(?<!\d)(\d{6})(?!\d)');

  /// Waits for the newest email to [email] and returns its 6-digit code.
  Future<String> waitForCode(
    String email, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final search = Uri.parse(
        '${E2eEnv.mailUrl}/api/v1/search',
      ).replace(queryParameters: {'query': 'to:"$email"'});
      final res = await _http.get(search);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final messages = (body['messages'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
        if (messages.isNotEmpty) {
          final id = messages.first['ID'] as String;
          final msg = await _http.get(
            Uri.parse('${E2eEnv.mailUrl}/api/v1/message/$id'),
          );
          final data = jsonDecode(msg.body) as Map<String, dynamic>;
          final text =
              '${data['Text'] ?? ''}\n'
              '${(data['HTML'] as String? ?? '').replaceAll(RegExp('<[^>]+>'), ' ')}';
          final match = _code.firstMatch(text);
          if (match != null) return match.group(1)!;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw StateError('No verification email for $email');
  }
}

/// A user driven over REST (the second member of the group).
class RestUser {
  RestUser._(this.email, this.password, this.id, this._token, this._http);

  final String email;
  final String password;
  final String id;
  final String _token;
  final http.Client _http;

  /// Creates a confirmed user with the admin API (local service key) and
  /// signs them in.
  static Future<RestUser> create({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final client = http.Client();
    final created = await client.post(
      Uri.parse('${E2eEnv.supabaseUrl}/auth/v1/admin/users'),
      headers: _serviceHeaders,
      body: jsonEncode({
        'email': email,
        'password': password,
        'email_confirm': true,
        'user_metadata': {'full_name': displayName},
      }),
    );
    _expectOk(created, 'admin create user');
    final signIn = await client.post(
      Uri.parse('${E2eEnv.supabaseUrl}/auth/v1/token?grant_type=password'),
      headers: {'apikey': E2eEnv.anonKey, 'content-type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    _expectOk(signIn, 'second user sign-in');
    final session = jsonDecode(signIn.body) as Map<String, dynamic>;
    final user = session['user'] as Map<String, dynamic>;
    return RestUser._(
      email,
      password,
      user['id'] as String,
      session['access_token'] as String,
      client,
    );
  }

  /// Calls the database function [fn] as this user.
  Future<Object?> rpc(String fn, Map<String, Object?> params) async {
    final res = await _http.post(
      Uri.parse('${E2eEnv.supabaseUrl}/rest/v1/rpc/$fn'),
      headers: {
        'apikey': E2eEnv.anonKey,
        'authorization': 'Bearer $_token',
        'content-type': 'application/json',
      },
      body: jsonEncode(params),
    );
    _expectOk(res, fn);
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  /// Accepts the invitation in [token]; returns the group id.
  Future<String> acceptInvitation(String token) async {
    final data = await rpc('accept_group_invitation', {'p_token': token});
    return (data! as Map<String, dynamic>)['group_id'] as String;
  }

  /// Records a payment of [amountMinor] to [toUser]; returns its id.
  Future<String> recordSettlement({
    required String groupId,
    required String toUser,
    required int amountMinor,
  }) async {
    final data = await rpc('record_settlement', {
      'p_group_id': groupId,
      'p_to_user': toUser,
      'p_amount_minor': amountMinor,
      'p_note': 'E2E settle up',
    });
    final row = data is List ? data.first : data;
    return (row! as Map<String, dynamic>)['id'] as String;
  }

  void close() => _http.close();
}

/// Admin calls for clean-up (local stack only).
abstract final class Admin {
  /// Whether a user with [email] still exists.
  static Future<bool> userExists(String email) async {
    final id = await _idOf(email);
    return id != null;
  }

  /// Deletes the user with [email] if there is one.
  static Future<void> deleteUser(String email) async {
    final id = await _idOf(email);
    if (id == null) return;
    final res = await http.delete(
      Uri.parse('${E2eEnv.supabaseUrl}/auth/v1/admin/users/$id'),
      headers: _serviceHeaders,
    );
    _expectOk(res, 'admin delete user');
  }

  static Future<String?> _idOf(String email) async {
    final res = await http.get(
      Uri.parse('${E2eEnv.supabaseUrl}/auth/v1/admin/users?per_page=1000'),
      headers: _serviceHeaders,
    );
    _expectOk(res, 'admin list users');
    final users =
        ((jsonDecode(res.body) as Map<String, dynamic>)['users']
                as List<dynamic>)
            .cast<Map<String, dynamic>>();
    for (final u in users) {
      if ((u['email'] as String?)?.toLowerCase() == email.toLowerCase()) {
        return u['id'] as String;
      }
    }
    return null;
  }
}

Map<String, String> get _serviceHeaders => {
  'apikey': E2eEnv.serviceKey,
  'authorization': 'Bearer ${E2eEnv.serviceKey}',
  'content-type': 'application/json',
};

void _expectOk(http.Response res, String what) {
  if (res.statusCode >= 200 && res.statusCode < 300) return;
  // The body is a server error message; it never carries a key.
  final body = res.body.length > 300 ? res.body.substring(0, 300) : res.body;
  throw StateError('$what failed (${res.statusCode}): $body');
}
