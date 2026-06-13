// lib/core/call/mini_call_overlay.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:messaging_app/call_screen.dart';
import 'package:messaging_app/core/call/call_overlay_controller.dart';
import 'package:messaging_app/core/call/call_provider.dart';
import 'package:messaging_app/core/call/call_state.dart';
import 'package:messaging_app/core/call/global_call_handler.dart';

class MiniCallOverlay extends ConsumerStatefulWidget {
  const MiniCallOverlay({super.key});

  @override
  ConsumerState<MiniCallOverlay> createState() => _MiniCallOverlayState();
}

class _MiniCallOverlayState extends ConsumerState<MiniCallOverlay> {
  static const double _videoWidth = 126;
  static const double _videoHeight = 188;
  static const double _voiceHeight = 76;
  static const double _edgeMargin = 14;

  Offset? _position;
  bool _dragging = false;

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

  Offset _defaultPosition({
    required Size screenSize,
    required EdgeInsets safePadding,
    required Size overlaySize,
  }) {
    return Offset(
      screenSize.width - overlaySize.width - _edgeMargin,
      safePadding.top + 16,
    );
  }

  Offset _clampPosition({
    required Offset position,
    required Size screenSize,
    required EdgeInsets safePadding,
    required Size overlaySize,
  }) {
    final minX = _edgeMargin;
    final maxX = math.max(
      minX,
      screenSize.width - overlaySize.width - _edgeMargin,
    );

    final minY = safePadding.top + 10;
    final maxY = math.max(
      minY,
      screenSize.height - overlaySize.height - safePadding.bottom - 24,
    );

    return Offset(
      position.dx.clamp(minX, maxX),
      position.dy.clamp(minY, maxY),
    );
  }

  void _onDragUpdate({
    required DragUpdateDetails details,
    required Size screenSize,
    required EdgeInsets safePadding,
    required Size overlaySize,
  }) {
    final current = _position ??
        _defaultPosition(
          screenSize: screenSize,
          safePadding: safePadding,
          overlaySize: overlaySize,
        );

    setState(() {
      _position = _clampPosition(
        position: current + details.delta,
        screenSize: screenSize,
        safePadding: safePadding,
        overlaySize: overlaySize,
      );
    });
  }

  void _onDragEnd({
    required Size screenSize,
    required EdgeInsets safePadding,
    required Size overlaySize,
  }) {
    final current = _position;
    if (current == null) return;

    final leftX = _edgeMargin;
    final rightX = screenSize.width - overlaySize.width - _edgeMargin;

    final shouldSnapLeft = current.dx + (overlaySize.width / 2) < screenSize.width / 2;

    final snapped = Offset(
      shouldSnapLeft ? leftX : rightX,
      current.dy,
    );

    setState(() {
      _dragging = false;
      _position = _clampPosition(
        position: snapped,
        screenSize: screenSize,
        safePadding: safePadding,
        overlaySize: overlaySize,
      );
    });
  }

  void _restoreCall(CallState callState) {
    if (_isFinalStatus(callState.status)) {
      ref.read(callScreenMinimizedProvider.notifier).state = false;
      return;
    }

    final currentUserId = callState.currentUserId?.trim() ?? '';
    final receiverId = callState.receiverId?.trim() ?? '';

    if (currentUserId.isEmpty || receiverId.isEmpty) {
      return;
    }

    final name = callState.name?.trim().isNotEmpty == true
        ? callState.name!.trim()
        : 'Call';

    final avatarUrl = callState.avatarUrl?.trim() ?? '';

    ref.read(callScreenMinimizedProvider.notifier).state = false;

    final navigator = GlobalCallHandler.navigatorKey.currentState;

    if (navigator == null) {
      return;
    }

    navigator.push(
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
  }

  @override
  Widget build(BuildContext context) {
    final minimized = ref.watch(callScreenMinimizedProvider);
    final callState = ref.watch(callProvider);

    if (!minimized) {
      return const SizedBox.shrink();
    }

    if (_isFinalStatus(callState.status)) {
      return const SizedBox.shrink();
    }

    final currentUserId = callState.currentUserId?.trim() ?? '';
    final receiverId = callState.receiverId?.trim() ?? '';

    if (currentUserId.isEmpty || receiverId.isEmpty) {
      return const SizedBox.shrink();
    }

    final media = MediaQuery.of(context);
    final screenSize = media.size;
    final safePadding = media.padding;

    final overlayWidth = callState.isVideoCall
        ? _videoWidth
        : math.min(screenSize.width - (_edgeMargin * 2), 310.0);

    final overlayHeight = callState.isVideoCall ? _videoHeight : _voiceHeight;
    final overlaySize = Size(overlayWidth, overlayHeight);

    final rawPosition = _position ??
        _defaultPosition(
          screenSize: screenSize,
          safePadding: safePadding,
          overlaySize: overlaySize,
        );

    final position = _clampPosition(
      position: rawPosition,
      screenSize: screenSize,
      safePadding: safePadding,
      overlaySize: overlaySize,
    );

    final name = callState.name?.trim().isNotEmpty == true
        ? callState.name!.trim()
        : 'Call';

    final avatarUrl = callState.avatarUrl?.trim() ?? '';
    final hasAvatar = avatarUrl.isNotEmpty;

    return AnimatedPositioned(
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      left: position.dx,
      top: position.dy,
      width: overlaySize.width,
      height: overlaySize.height,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _restoreCall(callState),
          onPanStart: (_) {
            setState(() {
              _dragging = true;
            });
          },
          onPanUpdate: (details) {
            _onDragUpdate(
              details: details,
              screenSize: screenSize,
              safePadding: safePadding,
              overlaySize: overlaySize,
            );
          },
          onPanEnd: (_) {
            _onDragEnd(
              screenSize: screenSize,
              safePadding: safePadding,
              overlaySize: overlaySize,
            );
          },
          onPanCancel: () {
            setState(() {
              _dragging = false;
            });
          },
          child: callState.isVideoCall
              ? _VideoMiniWindow(
                  callState: callState,
                  name: name,
                  avatarUrl: avatarUrl,
                  hasAvatar: hasAvatar,
                  statusText: _statusText(callState),
                  isFinalStatus: _isFinalStatus,
                )
              : _VoiceMiniWindow(
                  callState: callState,
                  name: name,
                  avatarUrl: avatarUrl,
                  hasAvatar: hasAvatar,
                  statusText: _statusText(callState),
                ),
        ),
      ),
    );
  }
}

class _VideoMiniWindow extends StatelessWidget {
  final CallState callState;
  final String name;
  final String avatarUrl;
  final bool hasAvatar;
  final String statusText;
  final bool Function(CallStatus status) isFinalStatus;

  const _VideoMiniWindow({
    required this.callState,
    required this.name,
    required this.avatarUrl,
    required this.hasAvatar,
    required this.statusText,
    required this.isFinalStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withOpacity(0.18),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.34),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildRemoteLayer(),

          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.22),
                    Colors.transparent,
                    Colors.black.withOpacity(0.55),
                  ],
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.42),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.videocam_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.open_in_full_rounded,
                  color: Colors.white,
                  size: 17,
                ),
              ],
            ),
          ),

          Positioned(
            left: 9,
            right: 9,
            bottom: 9,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                shadows: [
                  Shadow(
                    color: Colors.black,
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),

          if (callState.isVideoCall)
            Positioned(
              right: 8,
              bottom: 32,
              width: 42,
              height: 58,
              child: _LocalPreview(callState: callState),
            ),
        ],
      ),
    );
  }

  Widget _buildRemoteLayer() {
    final remoteRenderer = callState.remoteRenderer;

    final canShowRemoteVideo =
        callState.isVideoCall &&
        !callState.isRemoteCameraOff &&
        !isFinalStatus(callState.status) &&
        remoteRenderer != null &&
        remoteRenderer.srcObject != null;

    if (canShowRemoteVideo) {
      return RTCVideoView(
        remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }

    return _AvatarFallback(
      name: name,
      avatarUrl: avatarUrl,
      hasAvatar: hasAvatar,
      subtitle: callState.isRemoteCameraOff ? 'Camera off' : 'Connecting...',
    );
  }
}

class _VoiceMiniWindow extends StatelessWidget {
  final CallState callState;
  final String name;
  final String avatarUrl;
  final bool hasAvatar;
  final String statusText;

  const _VoiceMiniWindow({
    required this.callState,
    required this.name,
    required this.avatarUrl,
    required this.hasAvatar,
    required this.statusText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          _SmallAvatar(
            name: name,
            avatarUrl: avatarUrl,
            hasAvatar: hasAvatar,
            radius: 24,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(
                      Icons.call_rounded,
                      color: Colors.greenAccent,
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      statusText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.open_in_full_rounded,
            color: Colors.white,
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _LocalPreview extends StatelessWidget {
  final CallState callState;

  const _LocalPreview({
    required this.callState,
  });

  @override
  Widget build(BuildContext context) {
    final localRenderer = callState.localRenderer;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF020617),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.24),
          width: 1,
        ),
      ),
      child: _buildContent(localRenderer),
    );
  }

  Widget _buildContent(RTCVideoRenderer? localRenderer) {
    if (callState.isCameraOff) {
      return const Center(
        child: Icon(
          Icons.videocam_off_rounded,
          color: Colors.white70,
          size: 20,
        ),
      );
    }

    if (localRenderer == null || localRenderer.srcObject == null) {
      return const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2,
          ),
        ),
      );
    }

    return RTCVideoView(
      localRenderer,
      mirror: true,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  final String name;
  final String avatarUrl;
  final bool hasAvatar;
  final String subtitle;

  const _AvatarFallback({
    required this.name,
    required this.avatarUrl,
    required this.hasAvatar,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111827),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasAvatar)
            Opacity(
              opacity: 0.20,
              child: Image.network(
                avatarUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SmallAvatar(
                  name: name,
                  avatarUrl: avatarUrl,
                  hasAvatar: hasAvatar,
                  radius: 30,
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallAvatar extends StatelessWidget {
  final String name;
  final String avatarUrl;
  final bool hasAvatar;
  final double radius;

  const _SmallAvatar({
    required this.name,
    required this.avatarUrl,
    required this.hasAvatar,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF374151),
      backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
      onBackgroundImageError: hasAvatar
          ? (Object error, StackTrace? stackTrace) {
              debugPrint('MINI CALL AVATAR ERROR: $error');
            }
          : null,
      child: !hasAvatar
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                color: Colors.white,
                fontSize: radius * 0.72,
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
    );
  }
}