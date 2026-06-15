// lib/incoming_call_screen.dart

import 'package:flutter/material.dart';

import 'package:messaging_app/call_screen.dart';
import 'package:messaging_app/call_waiting.dart';
import 'package:messaging_app/chat_data.dart';
import 'package:messaging_app/chat_models.dart';
import 'package:messaging_app/core/api_client.dart';
import 'package:messaging_app/core/call/call_socket_service.dart';
import 'package:messaging_app/core/call/call_notification.dart';
import 'package:messaging_app/core/call/global_call_handler.dart';
import 'package:messaging_app/core/config/app_config.dart';

class IncomingCallScreen extends StatefulWidget {
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;

  final String callerId;
  final String callerName;
  final String callerAvatar;

  final bool isVideoCall;
  final bool isGroupCall;

  /*
    IMPORTANT:
    offer is nullable because FCM/global incoming_call may not contain
    real WebRTC SDP. It may only contain call_id, conversation_id, caller_id.
  */
  final Map<String, dynamic>? offer;

  final ChatItem? chat;
  final String? conversationId;
  final String? callId;

  const IncomingCallScreen({
    super.key,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserAvatar,
    required this.callerId,
    required this.callerName,
    required this.callerAvatar,
    required this.isVideoCall,
    this.isGroupCall = false,
    required this.offer,
    this.chat,
    this.conversationId,
    this.callId,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  bool _accepting = false;
  bool _rejecting = false;
  bool _connectingSocket = false;

  String _resolvedCurrentUserId = '';
  String _resolvedCurrentUserName = '';
  String _resolvedCurrentUserAvatar = '';

  String get _effectiveConversationId {
    final value =
        widget.conversationId?.toString() ??
        widget.chat?.id.toString() ??
        widget.offer?['conversation_id']?.toString() ??
        widget.offer?['conversationId']?.toString() ??
        '';

    return value.trim();
  }

  String get _callId {
    final value =
        widget.callId ??
        widget.offer?['call_id']?.toString() ??
        widget.offer?['callId']?.toString() ??
        widget.offer?['id']?.toString() ??
        '';

    return value.trim();
  }

  String get _callKitId {
    if (_callId.isNotEmpty) {
      return _callId;
    }

    return _effectiveConversationId;
  }


  bool get _isGroupCall {
    return widget.isGroupCall == true ||
        widget.offer?['is_group_call'] == true ||
        widget.offer?['isGroupCall'] == true ||
        widget.offer?['is_group_call']?.toString() == 'true' ||
        widget.offer?['isGroupCall']?.toString() == 'true';
  }

  ChatItem? _freshChat() {
    final id = _effectiveConversationId;

    if (id.isNotEmpty) {
      try {
        return AppChatData.chats.firstWhere(
          (item) => item.id.toString() == id,
        );
      } catch (_) {
        return widget.chat;
      }
    }

    return widget.chat;
  }

  ChatUser? _callerMember(ChatItem? freshChat) {
    if (freshChat == null) return null;

    final cleanCallerId = widget.callerId.trim();

    if (cleanCallerId.isEmpty) return null;

    for (final member in freshChat.members) {
      if (member.id.toString().trim() == cleanCallerId) {
        return member;
      }
    }

    return null;
  }

  String _displayCallerName() {
    final freshChat = _freshChat();

    if (freshChat != null) {
      final cleanCallerId = widget.callerId.trim();

      if (cleanCallerId.isNotEmpty) {
        final nickname = freshChat.memberNicknames[cleanCallerId]?.trim() ?? '';

        if (nickname.isNotEmpty) {
          return nickname;
        }
      }

      final callerMember = _callerMember(freshChat);

      if (callerMember != null && callerMember.name.trim().isNotEmpty) {
        return callerMember.name.trim();
      }
    }

    final socketName = widget.callerName.trim();

    if (socketName.isNotEmpty) {
      return socketName;
    }

    return 'Unknown';
  }

  String _displayCallerAvatar() {
    final freshChat = _freshChat();
    final callerMember = _callerMember(freshChat);

    if (callerMember != null && callerMember.avatarUrl.trim().isNotEmpty) {
      return callerMember.avatarUrl.trim();
    }

    if (widget.callerAvatar.trim().isNotEmpty) {
      return widget.callerAvatar.trim();
    }

    return '';
  }

  bool _isValidWebRtcOffer(Map<String, dynamic>? value) {
    if (value == null) return false;

    final type = value['type']?.toString() ?? '';
    final sdp = value['sdp']?.toString() ?? '';

    return type.trim().isNotEmpty && sdp.trim().isNotEmpty;
  }

  Future<bool> _ensureCallSocketConnected() async {
    if (_connectingSocket) {
      return SocketService.instance.isConnected;
    }

    final convId = _effectiveConversationId;

    if (convId.isEmpty) {
      debugPrint('INCOMING CALL SOCKET ERROR: conversationId empty');
      return false;
    }

    final parsedConversationId = int.tryParse(convId);

    if (parsedConversationId == null) {
      debugPrint(
        'INCOMING CALL SOCKET ERROR: conversationId is not number: $convId',
      );
      return false;
    }

    _connectingSocket = true;

    try {
      String? accessToken = await ApiClient.storage.read(key: 'access');

      if (accessToken == null || accessToken.trim().isEmpty) {
        debugPrint('INCOMING CALL SOCKET: access empty, trying refresh');
        accessToken = await ApiClient.refreshAccessToken();
      }

      if (accessToken == null || accessToken.trim().isEmpty) {
        debugPrint('INCOMING CALL SOCKET ERROR: access token empty');
        return false;
      }

      final storedUserId =
          (await ApiClient.storage.read(key: 'user_id'))?.trim() ?? '';

      final storedUserName =
          (await ApiClient.storage.read(key: 'full_name'))?.trim() ?? '';

      final storedUserAvatar =
          (await ApiClient.storage.read(key: 'avatar_url'))?.trim() ??
              (await ApiClient.storage.read(key: 'image_url'))?.trim() ??
              '';

      _resolvedCurrentUserId = widget.currentUserId.trim().isNotEmpty
          ? widget.currentUserId.trim()
          : storedUserId;

      _resolvedCurrentUserName = widget.currentUserName.trim().isNotEmpty
          ? widget.currentUserName.trim()
          : storedUserName;

      _resolvedCurrentUserAvatar = widget.currentUserAvatar.trim().isNotEmpty
          ? widget.currentUserAvatar.trim()
          : storedUserAvatar;

      if (_resolvedCurrentUserId.isEmpty) {
        debugPrint('INCOMING CALL SOCKET ERROR: current user id empty');
        return false;
      }

      final url = AppConfig.callSocketUrl(
        conversationId: parsedConversationId,
        token: accessToken.trim(),
      );

      debugPrint('========== INCOMING CALL SOCKET DEBUG ==========');
      debugPrint('conversationId: $convId');
      debugPrint('currentUserId: $_resolvedCurrentUserId');
      debugPrint('callerId: ${widget.callerId}');
      debugPrint('AppConfig.wsBaseUrl: ${AppConfig.wsBaseUrl}');
      debugPrint('INCOMING CALL SOCKET URL: $url');
      debugPrint('================================================');

      /*
        Important:
        Do NOT use GlobalCallHandler.connectCallSocket() here.

        IncomingCallScreen is already opened by GlobalCallHandler.
        Calling GlobalCallHandler.connectCallSocket() again can register
        global handlers again and can open another IncomingCallScreen.

        So this screen connects the socket directly.
      */
      await SocketService.instance.connect(url: url);

      await Future.delayed(const Duration(milliseconds: 300));

      if (!SocketService.instance.isConnected) {
        debugPrint('INCOMING CALL SOCKET ERROR: SocketService.isConnected false');
        return false;
      }

      debugPrint('INCOMING CALL SOCKET CONNECTED');
      return true;
    } catch (e, stack) {
      debugPrint('INCOMING CALL SOCKET CONNECT ERROR: $e');
      debugPrint(stack.toString());
      return false;
    } finally {
      _connectingSocket = false;
    }
  }

  Future<void> _reject(BuildContext context) async {
    if (_rejecting) return;
    _rejecting = true;

    final callKitId = _callKitId;
    final convId = _effectiveConversationId;

    try {
      final connected = await _ensureCallSocketConnected();

      if (!connected) {
        debugPrint('INCOMING CALL REJECT WARNING: socket not connected');
      }

      final currentUserId = _resolvedCurrentUserId.isNotEmpty
          ? _resolvedCurrentUserId
          : widget.currentUserId.trim();

      if (currentUserId.isNotEmpty && widget.callerId.trim().isNotEmpty) {
        SocketService.instance.emit(
          CallSocketEvents.callReject,
          {
            'from': currentUserId,
            'from_user': currentUserId,
            'reason': 'rejected',
            if (_callId.isNotEmpty) 'call_id': _callId,
            if (_callId.isNotEmpty) 'callId': _callId,
            if (convId.isNotEmpty) 'conversation_id': convId,
            if (convId.isNotEmpty) 'conversationId': convId,
            'is_group_call': _isGroupCall,
            'isGroupCall': _isGroupCall,
            if (_isGroupCall && _callId.isNotEmpty) 'group_call_id': _callId,
            if (_isGroupCall && _callId.isNotEmpty) 'groupCallId': _callId,
          },
          targetUser: widget.callerId.trim(),
          conversationId: convId.isNotEmpty ? convId : null,
          queueIfDisconnected: false,
        );

        // Wait shortly so call_reject reaches caller before closing socket.
        await Future.delayed(const Duration(milliseconds: 180));
      }

      if (widget.chat != null) {
        AppChatData.addCallLog(
          chat: widget.chat!,
          type: widget.isVideoCall ? CallEntryType.video : CallEntryType.voice,
          status: CallEntryStatus.missed,
        );
      }

      if (callKitId.trim().isNotEmpty) {
        await NotificationService.endCall(callKitId);
      }

      GlobalCallHandler.instance.clearPendingOffer();
      GlobalCallHandler.instance.markCallScreenClosed();

      try {
        if (SocketService.instance.isConnected) {
          debugPrint('INCOMING CALL REJECT: disconnecting conversation socket');
          await SocketService.instance.disconnect();
          debugPrint('INCOMING CALL REJECT: conversation socket disconnected');
        }
      } catch (e, st) {
        debugPrint('INCOMING CALL REJECT SOCKET DISCONNECT ERROR: $e');
        debugPrint(st.toString());
      }

      if (context.mounted) {
        Navigator.of(context).maybePop();
      }
    } catch (e, st) {
      debugPrint('INCOMING CALL REJECT ERROR: $e');
      debugPrint(st.toString());

      if (callKitId.trim().isNotEmpty) {
        await NotificationService.endCall(callKitId);
      }

      try {
        if (SocketService.instance.isConnected) {
          await SocketService.instance.disconnect();
        }
      } catch (_) {}

      if (context.mounted) {
        Navigator.of(context).maybePop();
      }
    } finally {
      _rejecting = false;
    }
  }

  Future<void> _accept(BuildContext context) async {
    if (_accepting) return;
    _accepting = true;

    final displayName = _displayCallerName();
    final displayAvatar = _displayCallerAvatar();
    final callKitId = _callKitId;
    final convId = _effectiveConversationId;

    if (convId.isEmpty) {
      debugPrint('INCOMING CALL ACCEPT ERROR: conversationId empty');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Call error: conversation missing')),
        );
      }

      _accepting = false;
      return;
    }

    final connected = await _ensureCallSocketConnected();

    if (!connected) {
      debugPrint('INCOMING CALL ACCEPT ERROR: socket connect failed');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not connect call socket')),
        );
      }

      _accepting = false;
      return;
    }

    /*
      Do NOT send call_ready here.

      Why:
      - If valid SDP offer already exists, we open CallScreen directly.
      - If SDP missing, CallWaitingScreen will send call_ready itself.
      - Sending call_ready here and again in CallWaitingScreen causes duplicate
        call_offer resend and duplicate navigation race.
    */

    final pendingOffer =
        GlobalCallHandler.instance.takePendingOffer(
      callerId: widget.callerId,
      conversationId: convId,
      callId: _callId.isNotEmpty ? _callId : null,
    );

    final finalOffer =
        _isValidWebRtcOffer(widget.offer) ? widget.offer : pendingOffer;

    final hasValidFinalOffer = _isValidWebRtcOffer(finalOffer);

    if (callKitId.trim().isNotEmpty) {
      await NotificationService.endCall(callKitId);
    }

    if (!context.mounted) return;

    /*
      No valid WebRTC offer yet.
      Open CallWaitingScreen and let it:
      - connect socket
      - send call_ready
      - wait for call_offer
      - open CallScreen
    */
    if (!hasValidFinalOffer && !_isGroupCall) {
      debugPrint('INCOMING CALL ACCEPT: SDP missing.');
      debugPrint('INCOMING CALL ACCEPT: opening CallWaitingScreen.');
      debugPrint('INCOMING CALL OFFER DATA: ${widget.offer}');
      debugPrint('INCOMING CALL PENDING OFFER DATA: $pendingOffer');

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CallWaitingScreen(
            currentUserId: _resolvedCurrentUserId.isNotEmpty
                ? _resolvedCurrentUserId
                : widget.currentUserId,
            currentUserName: _resolvedCurrentUserName.isNotEmpty
                ? _resolvedCurrentUserName
                : widget.currentUserName,
            currentUserAvatar: _resolvedCurrentUserAvatar.isNotEmpty
                ? _resolvedCurrentUserAvatar
                : widget.currentUserAvatar,
            callerId: widget.callerId,
            callerName: displayName,
            callerAvatar: displayAvatar,
            isVideoCall: widget.isVideoCall,
            conversationId: convId,
            callId: _callId.isNotEmpty ? _callId : null,
            chat: widget.chat,
            emitAcceptOnOpen: false,
          ),
        ),
      );

      return;
    }

    /*
      Real WebRTC offer exists.
      Open CallScreen as receiver.
      CallScreen should send call_answer after setting remote offer.
    */
    debugPrint('INCOMING CALL ACCEPT: valid SDP found.');
    debugPrint('INCOMING CALL ACCEPT: opening CallScreen.');

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          name: displayName,
          avatarUrl: displayAvatar,
          isVideoCall: widget.isVideoCall,
          chat: widget.chat,
          currentUserId: _resolvedCurrentUserId.isNotEmpty
              ? _resolvedCurrentUserId
              : widget.currentUserId,
          currentUserName: _resolvedCurrentUserName.isNotEmpty
              ? _resolvedCurrentUserName
              : widget.currentUserName,
          currentUserAvatar: _resolvedCurrentUserAvatar.isNotEmpty
              ? _resolvedCurrentUserAvatar
              : widget.currentUserAvatar,
          receiverId: widget.callerId,
          isCaller: false,
          incomingOffer: hasValidFinalOffer ? finalOffer : null,
          conversationId: convId,
          callId: _callId.isNotEmpty ? _callId : null,
          isGroupCall: _isGroupCall,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _displayCallerName();
    final displayAvatar = _displayCallerAvatar();
    final hasAvatar = displayAvatar.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF111827),
              Color(0xFF0F172A),
              Color(0xFF030712),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              CircleAvatar(
                radius: 62,
                backgroundColor: const Color(0xFF1F2937),
                backgroundImage: hasAvatar ? NetworkImage(displayAvatar) : null,
                onBackgroundImageError: hasAvatar
                    ? (Object error, StackTrace? stackTrace) {
                        debugPrint('INCOMING CALL AVATAR ERROR: $error');
                      }
                    : null,
                child: !hasAvatar
                    ? Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 24),
              Text(
                displayName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.isVideoCall
                    ? '$displayName is video calling'
                    : '$displayName is calling',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 46),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _IncomingButton(
                      icon: Icons.call_end_rounded,
                      label: 'Decline',
                      color: const Color(0xFFFF3B30),
                      onTap: () => _reject(context),
                    ),
                    _IncomingButton(
                      icon: widget.isVideoCall
                          ? Icons.videocam_rounded
                          : Icons.call_rounded,
                      label: 'Accept',
                      color: const Color(0xFF22C55E),
                      onTap: () => _accept(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IncomingButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _IncomingButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 34),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}