import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:messaging_app/call_screen.dart';
import 'package:messaging_app/core/call/call_overlay_controller.dart';
import 'package:messaging_app/core/call/call_provider.dart';
import 'package:messaging_app/core/call/call_state.dart';

class MiniCallOverlay extends ConsumerWidget {
  const MiniCallOverlay({super.key});

  bool _isFinalStatus(CallStatus status) {
    return status == CallStatus.ended ||
        status == CallStatus.failed ||
        status == CallStatus.rejected ||
        status == CallStatus.busy ||
        status == CallStatus.timeout ||
        status == CallStatus.missed;
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    if (duration.inHours > 0) {
      return '${duration.inHours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }

    return '$minutes:$seconds';
  }

  String _statusText(CallState state) {
    if (state.status == CallStatus.connected) {
      return _formatDuration(state.duration);
    }

    if (state.status == CallStatus.calling) {
      return 'Calling...';
    }

    if (state.status == CallStatus.ringing) {
      return 'Ringing...';
    }

    return state.isVideoCall ? 'Video call' : 'Voice call';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minimized = ref.watch(callScreenMinimizedProvider);
    final callState = ref.watch(callProvider);

    if (!minimized) {
      return const SizedBox.shrink();
    }

    if (_isFinalStatus(callState.status)) {
      return const SizedBox.shrink();
    }

    final currentUserId = callState.currentUserId;
    final receiverId = callState.receiverId;

    if (currentUserId == null || receiverId == null) {
      return const SizedBox.shrink();
    }

    final name = callState.name?.trim().isNotEmpty == true
        ? callState.name!.trim()
        : 'Call';

    final avatarUrl = callState.avatarUrl?.trim() ?? '';
    final hasAvatar = avatarUrl.isNotEmpty;

    return Positioned(
      left: 14,
      right: 14,
      bottom: 22,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: () {
            ref.read(callScreenMinimizedProvider.notifier).state = false;

            Navigator.of(context).push(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => CallScreen(
                  name: name,
                  avatarUrl: avatarUrl,
                  isVideoCall: callState.isVideoCall,
                  currentUserId: currentUserId,
                  currentUserName: '',
                  currentUserAvatar: '',
                  receiverId: receiverId,
                  isCaller: callState.isCaller,
                  incomingOffer: callState.incomingOffer,
                  conversationId: null,
                  callId: null,
                  resumeExistingCall: true,
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFF374151),
                  backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
                  child: !hasAvatar
                      ? Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            callState.isVideoCall
                                ? Icons.videocam_rounded
                                : Icons.call_rounded,
                            color: Colors.greenAccent,
                            size: 15,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _statusText(callState),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(
                  Icons.open_in_full_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}