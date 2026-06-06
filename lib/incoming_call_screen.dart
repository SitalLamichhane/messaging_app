import 'package:flutter/material.dart';
import 'package:messaging_app/call_screen.dart';
import 'package:messaging_app/chat_data.dart';
import 'package:messaging_app/chat_models.dart';
import 'package:messaging_app/core/call/call_socket_service.dart';

class IncomingCallScreen extends StatelessWidget {
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;

  final String callerId;
  final String callerName;
  final String callerAvatar;

  final bool isVideoCall;
  final Map<String, dynamic> offer;
  final ChatItem? chat;
  final String? conversationId;

  const IncomingCallScreen({
    super.key,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserAvatar,
    required this.callerId,
    required this.callerName,
    required this.callerAvatar,
    required this.isVideoCall,
    required this.offer,
    this.chat,
    this.conversationId,
  });

  void _reject(BuildContext context) {
    SocketService.instance.emit(
      'call_reject',
      {
        'from': currentUserId,
        'to': callerId,
        'conversation_id': conversationId ?? chat?.id,
      },
      targetUser: callerId,
    );

    if (chat != null) {
      AppChatData.addCallLog(
        chat: chat!,
        type: isVideoCall ? CallEntryType.video : CallEntryType.voice,
        status: CallEntryStatus.missed,
      );
    }

    Navigator.of(context).maybePop();
  }

  void _accept(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          name: callerName,
          avatarUrl: callerAvatar,
          isVideoCall: isVideoCall,
          chat: chat,

          currentUserId: currentUserId,
          currentUserName: currentUserName,
          currentUserAvatar: currentUserAvatar,

          receiverId: callerId,
          isCaller: false,
          incomingOffer: offer,
          conversationId: conversationId ?? chat?.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAvatar = callerAvatar.trim().isNotEmpty;
    final displayName = callerName.trim().isNotEmpty ? callerName : 'Unknown';

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
                backgroundImage: hasAvatar ? NetworkImage(callerAvatar) : null,
                child: !hasAvatar
                    ? Text(
                        displayName[0].toUpperCase(),
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
                isVideoCall ? 'Incoming video call' : 'Incoming audio call',
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
                      icon: isVideoCall
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