// lib/core/call/mini_call_overlay.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' hide MessageType;

import 'package:hiddenly/call_screen.dart';
import 'package:hiddenly/core/call/call_overlay_controller.dart';
import 'package:hiddenly/core/call/call_provider.dart';
import 'package:hiddenly/core/call/call_state.dart';
import 'package:hiddenly/core/call/global_call_handler.dart';

class MiniCallOverlay extends ConsumerStatefulWidget {
  const MiniCallOverlay({super.key});

  @override
  ConsumerState<MiniCallOverlay> createState() => _MiniCallOverlayState();
}

class _MiniCallOverlayState extends ConsumerState<MiniCallOverlay> {
  Offset _position = const Offset(16, 120);
  bool _opening = false;

  bool _isFinalStatus(CallStatus status) {
    return status == CallStatus.ended ||
        status == CallStatus.failed ||
        status == CallStatus.rejected ||
        status == CallStatus.busy ||
        status == CallStatus.timeout ||
        status == CallStatus.missed;
  }

  bool _hasActiveCall(CallState state) {
    final hasUsers = state.currentUserId?.trim().isNotEmpty == true &&
        state.receiverId?.trim().isNotEmpty == true;

    return hasUsers && !_isFinalStatus(state.status);
  }

  String _displayName(CallState state) {
    final name = state.name?.trim() ?? '';
    return name.isEmpty ? 'Call' : name;
  }

  Future<void> _restoreSameCallScreen() async {
    if (_opening) return;

    final callState = ref.read(callProvider);
    if (!_hasActiveCall(callState)) return;

    if (ref.read(callScreenVisibleProvider)) {
      debugPrint('MINI CALL RESTORE IGNORED: CallScreen already visible');
      return;
    }

    if (!lockCallScreenOpening(ref)) {
      debugPrint('MINI CALL RESTORE IGNORED: CallScreen already opening');
      return;
    }

    _opening = true;

    try {
      final navigator = GlobalCallHandler.navigatorKey.currentState;
      if (navigator == null || !navigator.mounted) {
        debugPrint('MINI CALL RESTORE ERROR: navigator not ready');
        restoreInAppOverlayFromPip(ref);
        return;
      }

      // IMPORTANT:
      // Back from CallScreen pops the CallScreen route.
      // So mini overlay must open exactly ONE resumeExistingCall route.
      // Do NOT use pushAndRemoveUntil here; it can reset routes and cause
      // black screen / duplicate screen issues.
      await navigator.push(
        MaterialPageRoute(
          fullscreenDialog: false,
          builder: (_) => CallScreen(
            name: callState.name?.trim().isNotEmpty == true
                ? callState.name!.trim()
                : 'Unknown',
            avatarUrl: callState.avatarUrl?.trim() ?? '',
            isVideoCall: callState.isVideoCall,
            currentUserId: callState.currentUserId?.trim() ?? '',
            currentUserName: '',
            currentUserAvatar: '',
            receiverId: callState.receiverId?.trim() ?? '',
            isCaller: callState.isCaller,
            incomingOffer: null,
            conversationId: null,
            callId: null,
            resumeExistingCall: true,
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('MINI CALL RESTORE ERROR: $e');
      debugPrint(st.toString());
      restoreInAppOverlayFromPip(ref);
    } finally {
      if (mounted) {
        _opening = false;
      }
      unlockCallScreenOpening(ref);
    }
  }

  Future<void> _endCallFromMini() async {
    final state = ref.read(callProvider);
    if (!_hasActiveCall(state)) return;

    clearCallOverlayFlags(ref);
    await ref.read(callProvider.notifier).endCall();
  }

  @override
  Widget build(BuildContext context) {
    final isMinimized = ref.watch(callScreenMinimizedProvider);
    final callState = ref.watch(callProvider);

    if (!isMinimized || !_hasActiveCall(callState)) {
      return const SizedBox.shrink();
    }

    final media = MediaQuery.of(context);
    final screenSize = media.size;
    final padding = media.padding;

    const width = 166.0;
    final height = callState.isVideoCall ? 222.0 : 78.0;
    const margin = 12.0;

    final minX = margin;
    final maxX = screenSize.width - width - margin;
    final minY = padding.top + margin;
    final maxY = screenSize.height - height - padding.bottom - margin;

    final safePosition = Offset(
      _position.dx.clamp(minX, maxX).toDouble(),
      _position.dy.clamp(minY, maxY).toDouble(),
    );

    return Positioned(
      left: safePosition.dx,
      top: safePosition.dy,
      width: width,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _restoreSameCallScreen,
          onPanUpdate: (details) {
            setState(() {
              _position = Offset(
                (_position.dx + details.delta.dx).clamp(minX, maxX).toDouble(),
                (_position.dy + details.delta.dy).clamp(minY, maxY).toDouble(),
              );
            });
          },
          onPanEnd: (_) {
            final snapLeft =
                _position.dx + (width / 2) < screenSize.width / 2;

            setState(() {
              _position = Offset(
                snapLeft ? minX : maxX,
                _position.dy.clamp(minY, maxY).toDouble(),
              );
            });
          },
          child: callState.isVideoCall
              ? _MiniVideoCallCard(
                  callState: callState,
                  displayName: _displayName(callState),
                  onExpand: _restoreSameCallScreen,
                  onEnd: _endCallFromMini,
                )
              : _MiniAudioCallCard(
                  callState: callState,
                  displayName: _displayName(callState),
                  onExpand: _restoreSameCallScreen,
                  onEnd: _endCallFromMini,
                ),
        ),
      ),
    );
  }
}

class _MiniVideoCallCard extends StatelessWidget {
  final CallState callState;
  final String displayName;
  final VoidCallback onExpand;
  final VoidCallback onEnd;

  const _MiniVideoCallCard({
    required this.callState,
    required this.displayName,
    required this.onExpand,
    required this.onEnd,
  });

  bool _isFinalStatus(CallStatus status) {
    return status == CallStatus.ended ||
        status == CallStatus.failed ||
        status == CallStatus.rejected ||
        status == CallStatus.busy ||
        status == CallStatus.timeout ||
        status == CallStatus.missed;
  }

  @override
  Widget build(BuildContext context) {
    final remoteRenderer = callState.remoteRenderer;
    final localRenderer = callState.localRenderer;

    final hasRemoteVideo = !_isFinalStatus(callState.status) &&
        !callState.isRemoteCameraOff &&
        remoteRenderer != null &&
        remoteRenderer.srcObject != null;

    final hasLocalVideo = !_isFinalStatus(callState.status) &&
        !callState.isCameraOff &&
        localRenderer != null &&
        localRenderer.srcObject != null;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.22),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.34),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasRemoteVideo)
            RTCVideoView(
              remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else if (hasLocalVideo)
            RTCVideoView(
              localRenderer,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            _VideoFallback(
              name: displayName,
              avatarUrl: callState.avatarUrl?.trim() ?? '',
            ),
          if (hasRemoteVideo && hasLocalVideo)
            Positioned(
              top: 8,
              right: 8,
              width: 42,
              height: 58,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.25),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: RTCVideoView(
                    localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ),
          Positioned(
            left: 8,
            right: 8,
            top: 8,
            child: Row(
              children: [
                _MiniCircleButton(
                  icon: Icons.open_in_full_rounded,
                  onPressed: onExpand,
                ),
                const Spacer(),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.76),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniAudioCallCard extends StatelessWidget {
  final CallState callState;
  final String displayName;
  final VoidCallback onExpand;
  final VoidCallback onEnd;

  const _MiniAudioCallCard({
    required this.callState,
    required this.displayName,
    required this.onExpand,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = callState.avatarUrl?.trim() ?? '';
    final hasAvatar = avatar.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withOpacity(0.16),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFF1877F2),
            backgroundImage: hasAvatar ? NetworkImage(avatar) : null,
            child: !hasAvatar
                ? const Icon(
                    Icons.call_rounded,
                    color: Colors.white,
                    size: 24,
                  )
                : null,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _MiniCircleButton(
            icon: Icons.open_in_full_rounded,
            onPressed: onExpand,
          ),
        ],
      ),
    );
  }
}

class _MiniCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color backgroundColor;

  const _MiniCircleButton({
    required this.icon,
    required this.onPressed,
    this.backgroundColor = const Color(0xAA000000),
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withOpacity(0.18),
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 16,
        ),
      ),
    );
  }
}

class _VideoFallback extends StatelessWidget {
  final String name;
  final String avatarUrl;

  const _VideoFallback({
    required this.name,
    required this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl.trim().isNotEmpty;

    return Container(
      color: const Color(0xFF111827),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasAvatar)
            Opacity(
              opacity: 0.22,
              child: Image.network(
                avatarUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Center(
            child: CircleAvatar(
              radius: 34,
              backgroundColor: const Color(0xFF1877F2),
              backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
              child: !hasAvatar
                  ? Text(
                      name.isEmpty ? 'C' : name[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.none,
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}