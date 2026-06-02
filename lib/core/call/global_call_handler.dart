import 'package:flutter/material.dart';

import 'package:messaging_app/call_screen.dart';
import 'package:messaging_app/core/call/call_socket_service.dart';

class GlobalCallHandler {
  static final GlobalCallHandler instance = GlobalCallHandler._internal();
  GlobalCallHandler._internal();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  bool _registered = false;
  bool _callScreenOpen = false;

  String? _currentUserId;
  String? _currentUserName;
  String? _currentUserAvatar;

  /// Use this from ChatDetailScreen after you have token, userId and conversationId.
  ///
  /// Example:
  /// GlobalCallHandler.connectCallSocket(
  ///   url: 'ws://192.168.1.97:8000/ws/call/$conversationId/?token=$token',
  ///   currentUserId: currentUserId,
  /// );
  static void connectCallSocket({
    required String url,
    required String currentUserId,
    String currentUserName = '',
    String currentUserAvatar = '',
  }) {
    SocketService.instance.connect(url: url);

    GlobalCallHandler.instance.init(
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      currentUserAvatar: currentUserAvatar,
      forceRegister: true,
    );
  }

  void init({
    required String currentUserId,
    required String currentUserName,
    required String currentUserAvatar,
    bool forceRegister = false,
  }) {
    _currentUserId = currentUserId;
    _currentUserName = currentUserName;
    _currentUserAvatar = currentUserAvatar;

    if (_registered && !forceRegister) return;

    // Important:
    // CallProvider removes call_answer / ice_candidate etc. after each call,
    // but global incoming call listener must stay alive for next calls.
    SocketService.instance.off('call_offer');

    _registered = true;

    SocketService.instance.on('call_offer', (data) async {
      final currentId = _currentUserId;
      if (currentId == null || currentId.trim().isEmpty) return;

      final payload = data['payload'];
      if (payload is! Map) return;

      final callerId = payload['from']?.toString();
      final offer = payload['offer'];

      if (callerId == null || callerId.trim().isEmpty || offer is! Map) {
        return;
      }

      // Prefer payload conversationId, fallback to top-level conversation_id if backend sends it.
      final conversationId =
          payload['conversationId']?.toString() ??
          payload['conversation_id']?.toString() ??
          data['conversationId']?.toString() ??
          data['conversation_id']?.toString();

      if (_callScreenOpen) {
        SocketService.instance.emit(
          'call_busy',
          {
            'from': currentId,
            'reason': 'busy',
            if (conversationId != null) 'conversationId': conversationId,
          },
          targetUser: callerId,
          conversationId: conversationId,
        );
        return;
      }

      final context = navigatorKey.currentContext;
      if (context == null) {
        debugPrint('GLOBAL CALL HANDLER ERROR: navigator context null');
        return;
      }

      final isVideoCall = payload['isVideoCall'] == true;
      final callerName = payload['callerName']?.toString() ?? 'Unknown';
      final callerAvatar = payload['callerAvatar']?.toString() ?? '';

      final accept = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(
              isVideoCall ? 'Incoming video call' : 'Incoming voice call',
            ),
            content: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage: callerAvatar.trim().isNotEmpty
                      ? NetworkImage(callerAvatar)
                      : null,
                  child: callerAvatar.trim().isEmpty
                      ? Text(
                          callerName.isNotEmpty
                              ? callerName[0].toUpperCase()
                              : '?',
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    callerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext, false);
                },
                child: const Text('Reject'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Accept'),
              ),
            ],
          );
        },
      );

      if (accept != true) {
        SocketService.instance.emit(
          'call_reject',
          {
            'from': currentId,
            'reason': 'rejected',
            if (conversationId != null) 'conversationId': conversationId,
          },
          targetUser: callerId,
          conversationId: conversationId,
        );
        return;
      }

      _callScreenOpen = true;

      try {
        await navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => CallScreen(
              name: callerName,
              avatarUrl: callerAvatar,
              isVideoCall: isVideoCall,
              currentUserId: currentId,
              receiverId: callerId,
              isCaller: false,
              incomingOffer: Map<String, dynamic>.from(offer),
              conversationId: conversationId,
            ),
          ),
        );
      } finally {
        _callScreenOpen = false;
      }
    });
  }

  void markCallScreenClosed() {
    _callScreenOpen = false;
  }

  void dispose() {
    _registered = false;
    _callScreenOpen = false;
    _currentUserId = null;
    _currentUserName = null;
    _currentUserAvatar = null;

    SocketService.instance.off('call_offer');
  }
}
