// lib/core/config/app_config.dart

class AppConfig {
  /*
    Real mobile/server mode.

    IMPORTANT:
    useEmulator must be false for VPS/IP testing.
    If emulator mode exists somewhere else in old code, it can create bad URLs.
  */
  static const bool useEmulator = false;

  static const String host = '2.25.198.109';

  static String get serverUrl => 'http://$host';
  static String get apiBaseUrl => '$serverUrl/api';

  /*
    Use explicit :80.
    Your log showed actual connect as:
    http://2.25.198.109:0/ws/global-call/
    This avoids bad implicit port parsing.
  */
  static String get wsBaseUrl => 'ws://$host:80';

  static String chatSocketUrl({
    required int conversationId,
    required String token,
  }) {
    final cleanToken = Uri.encodeComponent(token.trim());
    return '$wsBaseUrl/ws/chat/$conversationId/?token=$cleanToken';
  }

  static String callSocketUrl({
    required int conversationId,
    required String token,
  }) {
    final cleanToken = Uri.encodeComponent(token.trim());
    return '$wsBaseUrl/ws/call/$conversationId/?token=$cleanToken';
  }

  static String globalCallSocketUrl({
    required String token,
  }) {
    final cleanToken = Uri.encodeComponent(token.trim());
    return '$wsBaseUrl/ws/global-call/?token=$cleanToken';
  }
}