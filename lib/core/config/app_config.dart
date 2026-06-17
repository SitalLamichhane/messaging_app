// lib/core/config/app_config.dart

class AppConfig {
  static const bool useEmulator = false;

  static const String host = '2.25.198.109';

  static String get serverUrl => 'http://$host';
  static String get apiBaseUrl => '$serverUrl/api';

  // Explicit :80 avoids bad :0 URL parsing in old builds.
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
