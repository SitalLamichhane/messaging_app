// lib/core/config/app_config.dart

class AppConfig {
  // true = emulator
  // false = real mobile
  static const bool useEmulator = true;

  static String get host {
    // Real mobile / same Wi-Fi testing
    return '2.25.198.109';

  }

  static String get serverUrl => 'http://$host';
  static String get apiBaseUrl => '$serverUrl/api';
  static String get wsBaseUrl => 'ws://$host';

  static String chatSocketUrl({
    required int conversationId,
    required String token,
  }) {
    final cleanToken = Uri.encodeComponent(token.trim());
    return '$wsBaseUrl/ws/chat/$conversationId/?token=$cleanToken';
  }

  /*
    Conversation call socket.

    Use this only after user accepts call:
      /ws/call/<conversation_id>/

    This socket handles:
      call_ready
      call_offer
      call_answer
      ice_candidate
      call_end
      call_reject
      call_busy
  */
  static String callSocketUrl({
    required int conversationId,
    required String token,
  }) {
    final cleanToken = Uri.encodeComponent(token.trim());
    return '$wsBaseUrl/ws/call/$conversationId/?token=$cleanToken';
  }

  /*
    Global incoming call socket.

    Connect this once after login:
      /ws/global-call/

    This socket handles:
      incoming_call
      call_cancelled

    Keep this connected even inside CallScreen.
  */
  static String globalCallSocketUrl({
    required String token,
  }) {
    final cleanToken = Uri.encodeComponent(token.trim());
    return '$wsBaseUrl/ws/global-call/?token=$cleanToken';
  }
}