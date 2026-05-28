// lib/call_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' hide MessageType;

import 'package:messaging_app/chat_data.dart';
import 'package:messaging_app/chat_models.dart';
import 'package:messaging_app/core/call/call_provider.dart';
import 'package:messaging_app/core/call/call_state.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String name;
  final String avatarUrl;
  final bool isVideoCall;
  final ChatItem? chat;

  final String currentUserId;
  final String receiverId;
  final bool isCaller;
  final Map? incomingOffer;

  const CallScreen({
    super.key,
    required this.name,
    required this.avatarUrl,
    required this.isVideoCall,
    this.chat,
    required this.currentUserId,
    required this.receiverId,
    required this.isCaller,
    this.incomingOffer,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  bool _didSaveCallResult = false;
  bool _didPop = false;

  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      ref.read(callProvider.notifier).startCall(
            currentUserId: widget.currentUserId,
            receiverId: widget.receiverId,
            name: widget.name,
            avatarUrl: widget.avatarUrl,
            isVideoCall: widget.isVideoCall,
            isCaller: widget.isCaller,
            incomingOffer: widget.incomingOffer,
          );
    });
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }

    return '$minutes:$seconds';
  }

  String _callStatusText(CallState callState) {
    if (callState.status == CallStatus.ended) return 'Call ended';
    if (callState.status == CallStatus.connected) {
      return _formatDuration(callState.duration);
    }
    if (callState.status == CallStatus.failed) return 'Call failed';

    return widget.isVideoCall ? 'Ringing...' : 'Calling...';
  }

  void _saveCallResultIfNeeded(CallState callState) {
    if (_didSaveCallResult) return;
    if (widget.chat == null) return;

    _didSaveCallResult = true;

    AppChatData.addMessage(
      widget.chat!,
      ChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        type: MessageType.call,
        text: widget.isVideoCall ? 'Video call ended' : 'Voice call ended',
        isMe: true,
        sentAt: DateTime.now(),
        isSeen: true,
        callType: widget.isVideoCall ? CallEntryType.video : CallEntryType.voice,
        callDuration: callState.duration,
        callAnswered: callState.status == CallStatus.connected,
      ),
    );
  }

  Future<void> _endCall() async {
    if (_didPop) return;

    final callState = ref.read(callProvider);

    _saveCallResultIfNeeded(callState);

    await ref.read(callProvider.notifier).endCall();

    _didPop = true;

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    ref.read(callProvider.notifier).disposeCall();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callProvider);
    final callNotifier = ref.read(callProvider.notifier);
    final hasAvatar = widget.avatarUrl.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: widget.isVideoCall
                ? _buildRemoteVideoBackground(callState, hasAvatar)
                : _buildVoiceCallBackground(hasAvatar),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.18),
                    Colors.black.withOpacity(0.40),
                    Colors.black.withOpacity(0.68),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      _TopCircleButton(
                        icon: Icons.arrow_back,
                        onTap: _endCall,
                      ),
                      const Spacer(),
                      if (widget.isVideoCall)
                        _TopCircleButton(
                          icon: Icons.flip_camera_ios_outlined,
                          onTap: callNotifier.switchCamera,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (!widget.isVideoCall || callState.isCameraOff) ...[
                  CircleAvatar(
                    radius: 52,
                    backgroundColor: const Color(0xFF1F2937),
                    backgroundImage:
                        hasAvatar ? NetworkImage(widget.avatarUrl) : null,
                    child: !hasAvatar
                        ? Text(
                            widget.name.isNotEmpty
                                ? widget.name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 18),
                ],
                Text(
                  widget.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _callStatusText(callState),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.86),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (widget.isVideoCall)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      margin: const EdgeInsets.only(right: 16, bottom: 18),
                      width: 110,
                      height: 170,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.22),
                          width: 1,
                        ),
                      ),
                      child: _buildLocalPreview(callState),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _MessengerCallButton(
                        icon: callState.isMicOff
                            ? Icons.mic_off_rounded
                            : Icons.mic_none_rounded,
                        bgColor: const Color(0x33FFFFFF),
                        onTap: callNotifier.toggleMic,
                      ),
                      _MessengerCallButton(
                        icon: callState.isSpeakerOn
                            ? Icons.volume_up_rounded
                            : Icons.volume_down_rounded,
                        bgColor: const Color(0x33FFFFFF),
                        onTap: callNotifier.toggleSpeaker,
                      ),
                      _MessengerCallButton(
                        icon: Icons.call_end_rounded,
                        bgColor: const Color(0xFFFF3B30),
                        size: 64,
                        iconSize: 30,
                        onTap: _endCall,
                      ),
                      _MessengerCallButton(
                        icon: widget.isVideoCall
                            ? (callState.isCameraOff
                                ? Icons.videocam_off_rounded
                                : Icons.videocam_rounded)
                            : Icons.videocam_rounded,
                        bgColor: const Color(0x33FFFFFF),
                        onTap: callNotifier.toggleCamera,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoteVideoBackground(CallState callState, bool hasAvatar) {
    final isConnected = callState.status == CallStatus.connected;
    final remoteRenderer = callState.remoteRenderer;

    if (isConnected && remoteRenderer != null) {
      return RTCVideoView(
        remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }

    if (hasAvatar) {
      return Image.network(
        widget.avatarUrl,
        fit: BoxFit.cover,
      );
    }

    return Container(
      color: const Color(0xFF111827),
      child: const Center(
        child: Icon(
          Icons.person,
          color: Colors.white54,
          size: 90,
        ),
      ),
    );
  }

  Widget _buildVoiceCallBackground(bool hasAvatar) {
    return Container(
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
      child: hasAvatar
          ? Center(
              child: Opacity(
                opacity: 0.12,
                child: Image.network(
                  widget.avatarUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildLocalPreview(CallState callState) {
    final localRenderer = callState.localRenderer;

    if (callState.isCameraOff) {
      return const Center(
        child: Icon(
          Icons.videocam_off_rounded,
          color: Colors.white70,
          size: 34,
        ),
      );
    }

    if (localRenderer == null) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 2.4,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: RTCVideoView(
        localRenderer,
        mirror: true,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      ),
    );
  }
}

class _MessengerCallButton extends StatelessWidget {
  final IconData icon;
  final Color bgColor;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  const _MessengerCallButton({
    required this.icon,
    required this.bgColor,
    required this.onTap,
    this.size = 56,
    this.iconSize = 26,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: iconSize,
        ),
      ),
    );
  }
}

class _TopCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopCircleButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.28),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}