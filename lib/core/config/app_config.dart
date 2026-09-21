class AppConfig {
  static const bool useEmulator = false;

  static const String host = 'hiddenly.org';

  // REST API
  static String get serverUrl => 'https://$host';
  static String get apiBaseUrl => '$serverUrl/api';

  // WebSocket
  static String get wsBaseUrl => 'wss://$host';

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