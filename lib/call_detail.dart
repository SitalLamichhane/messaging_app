import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CallDetailScreen extends StatefulWidget {
  final String name;
  final String imageUrl;
  final bool isVideoCall;

  const CallDetailScreen({
    super.key,
    required this.name,
    required this.imageUrl,
    this.isVideoCall = false,
  });

  @override
  State<CallDetailScreen> createState() => _CallDetailScreenState();
}

class _CallDetailScreenState extends State<CallDetailScreen> {
  bool isMicOn = true;
  bool isSpeakerOn = false;
  bool isCameraOn = false;
  bool isChatOpen = false;
  bool isCallEnded = false;
  bool isConnected = false;
  bool isFrontCamera = true;

  Timer? _ringingTimer;
  Timer? _callTimer;
  Duration _callDuration = Duration.zero;

  final TextEditingController _chatController = TextEditingController();
  final List<_CallChatMessage> _messages = [];

  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _cameraReady = false;

  @override
  void initState() {
    super.initState();
    isCameraOn = widget.isVideoCall;
    _startCallFlow();

    if (widget.isVideoCall) {
      _initCamera();
    }
  }

  void _startCallFlow() {
    _ringingTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || isCallEnded) return;

      setState(() {
        isConnected = true;
        _callDuration = Duration.zero;
      });

      _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || isCallEnded) return;
        setState(() {
          _callDuration += const Duration(seconds: 1);
        });
      });
    });
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      final camera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (!mounted) return;
      setState(() {
        _cameraReady = true;
      });
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;

    try {
      isFrontCamera = !isFrontCamera;

      final nextCamera = _cameras.firstWhere(
        (c) =>
            c.lensDirection ==
            (isFrontCamera
                ? CameraLensDirection.front
                : CameraLensDirection.back),
        orElse: () => _cameras.first,
      );

      await _cameraController?.dispose();

      _cameraController = CameraController(
        nextCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (!mounted) return;
      setState(() {
        _cameraReady = true;
      });
    } catch (e) {
      debugPrint('Camera switch error: $e');
    }
  }

  String get _statusText {
    if (isCallEnded) return "Call ended";
    if (!isConnected) {
      return widget.isVideoCall ? "Ringing video call..." : "Audio calling...";
    }
    return _formatDuration(_callDuration);
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

  void _endCall() {
    setState(() {
      isCallEnded = true;
      isConnected = false;
    });

    _ringingTimer?.cancel();
    _callTimer?.cancel();

    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) Navigator.pop(context);
    });
  }

  void _sendChatMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(
        _CallChatMessage(
          text: text,
          isMe: true,
          time: TimeOfDay.now().format(context),
        ),
      );
      _chatController.clear();
    });
  }

  @override
  void dispose() {
    _ringingTimer?.cancel();
    _callTimer?.cancel();
    _chatController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _buildBackground()),

            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.20),
                      Colors.black.withOpacity(0.32),
                      Colors.black.withOpacity(0.70),
                    ],
                  ),
                ),
              ),
            ),

            Column(
              children: [
                _buildTopBar(),
                const Spacer(),
                _buildProfileSection(),
                const Spacer(),
                if (widget.isVideoCall && isCameraOn) _buildLocalPreviewCard(),
                const SizedBox(height: 18),
                _buildBottomControls(),
                const SizedBox(height: 24),
              ],
            ),

            AnimatedPositioned(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut,
              right: isChatOpen ? 0 : -340,
              top: 0,
              bottom: 0,
              child: _buildChatPanel(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    if (widget.isVideoCall && !isCameraOn) {
      if (widget.imageUrl.trim().isNotEmpty) {
        return Image.network(
          widget.imageUrl,
          fit: BoxFit.cover,
        );
      }
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF15233F),
            Color(0xFF0C1731),
            Color(0xFF091127),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: widget.imageUrl.trim().isNotEmpty
          ? Opacity(
              opacity: 0.10,
              child: Image.network(
                widget.imageUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            )
          : null,
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _topCircleButton(
            icon: Icons.arrow_back,
            onTap: _endCall,
          ),
          const Spacer(),
          if (widget.isVideoCall)
            _topCircleButton(
              icon: Icons.flip_camera_ios_outlined,
              onTap: isCallEnded ? () {} : _switchCamera,
            ),
          const SizedBox(width: 10),
          _topCircleButton(
            icon: Icons.person_add_alt_1_rounded,
            onTap: isCallEnded ? () {} : _addMemberToCall,
          ),
          const SizedBox(width: 10),
          _topCircleButton(
            icon: Icons.more_horiz_rounded,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("More options clicked")),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSection() {
    return Column(
      children: [
        if (!widget.isVideoCall || !isCameraOn) ...[
          CircleAvatar(
            radius: 70,
            backgroundColor: const Color(0xFF223150),
            backgroundImage: widget.imageUrl.trim().isNotEmpty
                ? NetworkImage(widget.imageUrl)
                : null,
            child: widget.imageUrl.trim().isEmpty
                ? Text(
                    widget.name.isNotEmpty ? widget.name[0].toUpperCase() : "?",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 22),
        ],
        Text(
          widget.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _statusText,
          style: TextStyle(
            color: Colors.white.withOpacity(0.82),
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildLocalPreviewCard() {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(right: 18),
        width: 118,
        height: 175,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF182746),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.22)),
        ),
        child: _buildLocalPreview(),
      ),
    );
  }

  Widget _buildLocalPreview() {
    if (!isCameraOn) {
      return const Center(
        child: Icon(
          Icons.videocam_off_rounded,
          color: Colors.white70,
          size: 34,
        ),
      );
    }

    if (_cameraController != null &&
        _cameraReady &&
        _cameraController!.value.isInitialized) {
      return CameraPreview(_cameraController!);
    }

    return const Center(
      child: CircularProgressIndicator(
        color: Colors.white,
        strokeWidth: 2.4,
      ),
    );
  }

  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _circleControlButton(
            icon: isMicOn ? Icons.mic_none_rounded : Icons.mic_off_rounded,
            bgColor: const Color(0x33FFFFFF),
            onTap: isCallEnded
                ? null
                : () {
                    setState(() {
                      isMicOn = !isMicOn;
                    });
                  },
          ),
          _circleControlButton(
            icon: isSpeakerOn
                ? Icons.volume_up_rounded
                : Icons.volume_down_rounded,
            bgColor: const Color(0x33FFFFFF),
            onTap: isCallEnded
                ? null
                : () {
                    setState(() {
                      isSpeakerOn = !isSpeakerOn;
                    });
                  },
          ),
          _circleControlButton(
            icon: Icons.call_end_rounded,
            bgColor: const Color(0xFFE85B52),
            size: 66,
            iconSize: 32,
            onTap: _endCall,
          ),
          _circleControlButton(
            icon: isCameraOn
                ? Icons.videocam_rounded
                : Icons.videocam_off_rounded,
            bgColor: const Color(0x33FFFFFF),
            onTap: isCallEnded
                ? null
                : () {
                    setState(() {
                      isCameraOn = !isCameraOn;
                    });
                  },
          ),
          _circleControlButton(
            icon: Icons.chat_bubble_outline_rounded,
            bgColor: isChatOpen
                ? const Color(0xFF1877F2)
                : const Color(0x33FFFFFF),
            onTap: isCallEnded
                ? null
                : () {
                    setState(() {
                      isChatOpen = !isChatOpen;
                    });
                  },
          ),
        ],
      ),
    );
  }

  Widget _circleControlButton({
    required IconData icon,
    required Color bgColor,
    required VoidCallback? onTap,
    double size = 58,
    double iconSize = 28,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
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

  Widget _topCircleButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
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

  Widget _buildChatPanel() {
    return Container(
      width: 340,
      color: const Color(0xFF121E38),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
            decoration: BoxDecoration(
              color: const Color(0xFF182746),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    "Call Chat",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      isChatOpen = false;
                    });
                  },
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      "No messages yet",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(14),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return Align(
                        alignment: msg.isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          constraints: const BoxConstraints(maxWidth: 240),
                          decoration: BoxDecoration(
                            color: msg.isMe
                                ? const Color(0xFF1877F2)
                                : const Color(0xFF223150),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: msg.isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg.text,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                msg.time,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Type a message...",
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.60),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF223150),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _sendChatMessage(),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _sendChatMessage,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1877F2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addMemberToCall() {
    final members = [
      "Emma Watson",
      "John Carter",
      "Sophia Turner",
      "David Miller",
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF182746),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Add member to call",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              ...members.map(
                (member) => ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF31415F),
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  title: Text(
                    member,
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(content: Text("$member added to the call")),
                      );
                    },
                    child: const Text("Add"),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _CallChatMessage {
  final String text;
  final bool isMe;
  final String time;

  _CallChatMessage({
    required this.text,
    required this.isMe,
    required this.time,
  });
}