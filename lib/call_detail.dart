// lib/call_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:hiddenly/call_screen.dart';
import 'package:hiddenly/chat_models.dart';

/// Compatibility wrapper for old routes.
/// New code can open [CallScreen] directly.
class CallDetailScreen extends StatelessWidget {
  final String name;
  final String avatarUrl;
  final bool isVideoCall;
  final ChatItem? chat;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;
  final String receiverId;
  final bool isCaller;
  final Map<String, dynamic>? incomingOffer;
  final String? conversationId;
  final String? callId;

  const CallDetailScreen({
    super.key,
    required this.name,
    required this.avatarUrl,
    this.isVideoCall = false,
    this.chat,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserAvatar,
    required this.receiverId,
    required this.isCaller,
    this.incomingOffer,
    this.conversationId,
    this.callId,
  });

  @override
  Widget build(BuildContext context) {
    return CallScreen(
      name: name,
      avatarUrl: avatarUrl,
      isVideoCall: isVideoCall,
      chat: chat,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      currentUserAvatar: currentUserAvatar,
      receiverId: receiverId,
      isCaller: isCaller,
      incomingOffer: incomingOffer,
      conversationId: conversationId ?? chat?.id,
      callId: callId,
    );
  }
}
