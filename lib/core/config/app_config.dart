class AppConfig {
  static const bool useEmulator = false;

  static const String host = '147.93.40.65';

  static String get serverUrl => 'http://$host';
  static String get apiBaseUrl => '$serverUrl/api';

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