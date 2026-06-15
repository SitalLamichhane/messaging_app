
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' hide MessageType;

import 'package:messaging_app/chat_models.dart';
import 'package:messaging_app/core/call/call_socket_service.dart';

class GroupCallView extends StatefulWidget {
  final ChatItem chat;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;
  final bool isVideoCall;
  final bool isCaller;
  final String callerId;
  final Map<String, dynamic>? incomingOffer;
  final String? callId;

  const GroupCallView({
    super.key,
    required this.chat,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserAvatar,
    required this.isVideoCall,
    required this.isCaller,
    required this.callerId,
    this.incomingOffer,
    this.callId,
  });

  @override
  State<GroupCallView> createState() => _GroupCallViewState();
}

class _GroupCallViewState extends State<GroupCallView> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  final Map<String, RTCPeerConnection> _peers = {};
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, List<RTCIceCandidate>> _pendingIce = {};

  MediaStream? _localStream;

  bool _micOff = false;
  bool _cameraOff = false;
  bool _speakerOn = true;
  bool _ending = false;
  bool _cleaned = false;

  late final String _groupCallId;

  List<ChatUser> get _otherMembers {
    return widget.chat.members.where((member) {
      final id = member.id.toString().trim();
      return id.isNotEmpty && id != widget.currentUserId.trim();
    }).toList();
  }

  Map<String, dynamic> get _rtcConfig {
    return {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
    };
  }

  @override
  void initState() {
    super.initState();

    _groupCallId = widget.callId?.trim().isNotEmpty == true
        ? widget.callId!.trim()
        : 'group_${widget.chat.id}_${DateTime.now().millisecondsSinceEpoch}';

    _init();
  }

  Future<void> _init() async {
    try {
      await _localRenderer.initialize();

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.isVideoCall,
      });

      _localRenderer.srcObject = _localStream;

      await Helper.setSpeakerphoneOn(widget.isVideoCall || _speakerOn);

      _listenSocketEvents();

      if (widget.isCaller) {
        for (final member in _otherMembers) {
          await _createOfferFor(member.id.toString());
        }
      } else {
        final callerId = widget.callerId.trim();

        if (callerId.isNotEmpty && _validOffer(widget.incomingOffer)) {
          await _answerOfferFrom(
            fromUserId: callerId,
            offerMap: widget.incomingOffer!,
          );
        } else {
          _sendCallReadyToCaller();
        }
      }

      if (mounted) setState(() {});
    } catch (e, st) {
      debugPrint('GROUP CALL INIT ERROR: $e');
      debugPrint(st.toString());

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start group call')),
      );

      Navigator.maybePop(context);
    }
  }

  bool _validOffer(Map<String, dynamic>? value) {
    if (value == null) return false;

    final type = value['type']?.toString() ?? '';
    final sdp = value['sdp']?.toString() ?? '';

    return type.trim().isNotEmpty && sdp.trim().isNotEmpty;
  }

  void _listenSocketEvents() {
    SocketService.instance.on(CallSocketEvents.callOffer, _onOffer);
    SocketService.instance.on(CallSocketEvents.callAnswer, _onAnswer);
    SocketService.instance.on(CallSocketEvents.iceCandidate, _onIce);
    SocketService.instance.on(CallSocketEvents.callReady, _onCallReady);
    SocketService.instance.on(CallSocketEvents.callEnd, _onLeaveOrEnd);
    SocketService.instance.on(CallSocketEvents.callReject, _onLeaveOrEnd);
    SocketService.instance.on(CallSocketEvents.callTimeout, _onLeaveOrEnd);
  }

  void _removeSocketEvents() {
    SocketService.instance.off(CallSocketEvents.callOffer, _onOffer);
    SocketService.instance.off(CallSocketEvents.callAnswer, _onAnswer);
    SocketService.instance.off(CallSocketEvents.iceCandidate, _onIce);
    SocketService.instance.off(CallSocketEvents.callReady, _onCallReady);
    SocketService.instance.off(CallSocketEvents.callEnd, _onLeaveOrEnd);
    SocketService.instance.off(CallSocketEvents.callReject, _onLeaveOrEnd);
    SocketService.instance.off(CallSocketEvents.callTimeout, _onLeaveOrEnd);
  }

  Map<String, dynamic> _payload(Map<String, dynamic> data) {
    final raw = data['payload'];
    if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return Map<String, dynamic>.from(data);
  }

  String _fromUser(Map<String, dynamic> data) {
    final payload = _payload(data);

    return payload['from']?.toString() ??
        payload['from_user']?.toString() ??
        payload['caller_id']?.toString() ??
        payload['callerId']?.toString() ??
        data['from_user']?.toString() ??
        data['from']?.toString() ??
        '';
  }

  bool _isGroupPayload(Map<String, dynamic> data) {
    final payload = _payload(data);

    final convId = payload['conversation_id']?.toString() ??
        payload['conversationId']?.toString() ??
        data['conversation_id']?.toString() ??
        data['conversationId']?.toString() ??
        '';

    final isGroup =
        payload['is_group_call'] == true ||
        payload['isGroupCall'] == true ||
        payload['is_group_call']?.toString() == 'true' ||
        payload['isGroupCall']?.toString() == 'true' ||
        payload['group_call_id']?.toString() == _groupCallId ||
        payload['groupCallId']?.toString() == _groupCallId;

    return isGroup && convId == widget.chat.id.toString();
  }

  Future<RTCPeerConnection> _getPeer(String remoteUserId) async {
    final existing = _peers[remoteUserId];
    if (existing != null) return existing;

    final pc = await createPeerConnection(_rtcConfig);

    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }
    }

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;

      SocketService.instance.emit(
        CallSocketEvents.iceCandidate,
        {
          'from': widget.currentUserId,
          'from_user': widget.currentUserId,
          'candidate': candidate.toMap(),
          'conversation_id': widget.chat.id,
          'conversationId': widget.chat.id,
          'call_id': _groupCallId,
          'callId': _groupCallId,
          'is_group_call': true,
          'isGroupCall': true,
          'group_call_id': _groupCallId,
          'groupCallId': _groupCallId,
        },
        targetUser: remoteUserId,
        conversationId: widget.chat.id,
        queueIfDisconnected: true,
      );
    };

    pc.onTrack = (event) async {
      if (event.streams.isEmpty) return;

      final renderer = _remoteRenderers[remoteUserId] ?? RTCVideoRenderer();

      if (!_remoteRenderers.containsKey(remoteUserId)) {
        await renderer.initialize();
        _remoteRenderers[remoteUserId] = renderer;
      }

      renderer.srcObject = event.streams.first;

      if (mounted) setState(() {});
    };

    _peers[remoteUserId] = pc;
    return pc;
  }

  Future<void> _createOfferFor(String targetUserId) async {
    if (targetUserId.trim().isEmpty) return;

    final pc = await _getPeer(targetUserId);

    final offer = await pc.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': widget.isVideoCall ? 1 : 0,
    });

    await pc.setLocalDescription(offer);

    SocketService.instance.emit(
      CallSocketEvents.callOffer,
      {
        'from': widget.currentUserId,
        'from_user': widget.currentUserId,
        'callerName': widget.currentUserName,
        'caller_name': widget.currentUserName,
        'callerAvatar': widget.currentUserAvatar,
        'caller_avatar': widget.currentUserAvatar,
        'isVideoCall': widget.isVideoCall,
        'is_video_call': widget.isVideoCall,
        'conversation_id': widget.chat.id,
        'conversationId': widget.chat.id,
        'call_id': _groupCallId,
        'callId': _groupCallId,
        'is_group_call': true,
        'isGroupCall': true,
        'group_call_id': _groupCallId,
        'groupCallId': _groupCallId,
        'offer': offer.toMap(),
      },
      targetUser: targetUserId,
      conversationId: widget.chat.id,
      queueIfDisconnected: true,
    );
  }

  Future<void> _answerOfferFrom({
    required String fromUserId,
    required Map<String, dynamic> offerMap,
  }) async {
    if (fromUserId.trim().isEmpty) return;

    final pc = await _getPeer(fromUserId);

    await pc.setRemoteDescription(
      RTCSessionDescription(
        offerMap['sdp']?.toString(),
        offerMap['type']?.toString(),
      ),
    );

    await _flushPendingIce(fromUserId);

    final answer = await pc.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': widget.isVideoCall ? 1 : 0,
    });

    await pc.setLocalDescription(answer);

    SocketService.instance.emit(
      CallSocketEvents.callAnswer,
      {
        'from': widget.currentUserId,
        'from_user': widget.currentUserId,
        'answer': answer.toMap(),
        'conversation_id': widget.chat.id,
        'conversationId': widget.chat.id,
        'call_id': _groupCallId,
        'callId': _groupCallId,
        'is_group_call': true,
        'isGroupCall': true,
        'group_call_id': _groupCallId,
        'groupCallId': _groupCallId,
      },
      targetUser: fromUserId,
      conversationId: widget.chat.id,
      queueIfDisconnected: true,
    );
  }

  Future<void> _onOffer(Map<String, dynamic> data) async {
    if (!_isGroupPayload(data)) return;

    final payload = _payload(data);
    final from = _fromUser(data);

    if (from.isEmpty || from == widget.currentUserId) return;

    final rawOffer = payload['offer'];
    if (rawOffer is! Map) return;

    await _answerOfferFrom(
      fromUserId: from,
      offerMap: Map<String, dynamic>.from(rawOffer),
    );
  }

  Future<void> _onAnswer(Map<String, dynamic> data) async {
    if (!_isGroupPayload(data)) return;

    final payload = _payload(data);
    final from = _fromUser(data);

    if (from.isEmpty || from == widget.currentUserId) return;

    final rawAnswer = payload['answer'];
    if (rawAnswer is! Map) return;

    final pc = _peers[from];
    if (pc == null) return;

    await pc.setRemoteDescription(
      RTCSessionDescription(
        rawAnswer['sdp']?.toString(),
        rawAnswer['type']?.toString(),
      ),
    );

    await _flushPendingIce(from);
  }

  Future<void> _onIce(Map<String, dynamic> data) async {
    if (!_isGroupPayload(data)) return;

    final payload = _payload(data);
    final from = _fromUser(data);

    if (from.isEmpty || from == widget.currentUserId) return;

    final raw = payload['candidate'];
    if (raw is! Map) return;

    final candidate = RTCIceCandidate(
      raw['candidate']?.toString(),
      raw['sdpMid']?.toString(),
      raw['sdpMLineIndex'] is int
          ? raw['sdpMLineIndex']
          : int.tryParse(raw['sdpMLineIndex']?.toString() ?? '0'),
    );

    final pc = _peers[from];

    if (pc == null) {
      _pendingIce.putIfAbsent(from, () => []).add(candidate);
      return;
    }

    try {
      await pc.addCandidate(candidate);
    } catch (_) {
      _pendingIce.putIfAbsent(from, () => []).add(candidate);
    }
  }

  Future<void> _flushPendingIce(String userId) async {
    final pc = _peers[userId];
    final list = _pendingIce.remove(userId) ?? [];

    if (pc == null || list.isEmpty) return;

    for (final candidate in list) {
      try {
        await pc.addCandidate(candidate);
      } catch (e) {
        debugPrint('GROUP CALL ADD PENDING ICE ERROR: $e');
      }
    }
  }

  Future<void> _onCallReady(Map<String, dynamic> data) async {
    if (!_isGroupPayload(data)) return;
    if (!widget.isCaller) return;

    final from = _fromUser(data);

    if (from.isEmpty || from == widget.currentUserId) return;

    await _createOfferFor(from);
  }

  void _sendCallReadyToCaller() {
    if (widget.isCaller) return;
    if (widget.callerId.trim().isEmpty) return;

    SocketService.instance.emit(
      CallSocketEvents.callReady,
      {
        'from': widget.currentUserId,
        'from_user': widget.currentUserId,
        'conversation_id': widget.chat.id,
        'conversationId': widget.chat.id,
        'call_id': _groupCallId,
        'callId': _groupCallId,
        'is_group_call': true,
        'isGroupCall': true,
        'group_call_id': _groupCallId,
        'groupCallId': _groupCallId,
      },
      targetUser: widget.callerId.trim(),
      conversationId: widget.chat.id,
      queueIfDisconnected: true,
    );
  }

  Future<void> _onLeaveOrEnd(Map<String, dynamic> data) async {
    if (!_isGroupPayload(data)) return;

    final from = _fromUser(data);
    if (from.isEmpty) return;

    final pc = _peers.remove(from);
    await pc?.close();

    final renderer = _remoteRenderers.remove(from);
    renderer?.srcObject = null;
    await renderer?.dispose();

    if (mounted) setState(() {});
  }

  Future<void> _toggleMic() async {
    _micOff = !_micOff;

    for (final track in _localStream?.getAudioTracks() ?? []) {
      track.enabled = !_micOff;
    }

    if (mounted) setState(() {});
  }

  Future<void> _toggleCamera() async {
    _cameraOff = !_cameraOff;

    for (final track in _localStream?.getVideoTracks() ?? []) {
      track.enabled = !_cameraOff;
    }

    if (mounted) setState(() {});
  }

  Future<void> _toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    await Helper.setSpeakerphoneOn(_speakerOn);

    if (mounted) setState(() {});
  }

  Future<void> _endCall() async {
    if (_ending) return;
    _ending = true;

    for (final member in _otherMembers) {
      SocketService.instance.emit(
        CallSocketEvents.callEnd,
        {
          'from': widget.currentUserId,
          'from_user': widget.currentUserId,
          'conversation_id': widget.chat.id,
          'conversationId': widget.chat.id,
          'call_id': _groupCallId,
          'callId': _groupCallId,
          'is_group_call': true,
          'isGroupCall': true,
          'group_call_id': _groupCallId,
          'groupCallId': _groupCallId,
        },
        targetUser: member.id.toString(),
        conversationId: widget.chat.id,
        queueIfDisconnected: true,
      );
    }

    await _clean();

    if (mounted) Navigator.maybePop(context);
  }

  Future<void> _clean() async {
    if (_cleaned) return;
    _cleaned = true;

    _removeSocketEvents();

    for (final pc in _peers.values) {
      try {
        await pc.close();
      } catch (_) {}
    }
    _peers.clear();

    for (final renderer in _remoteRenderers.values) {
      try {
        renderer.srcObject = null;
        await renderer.dispose();
      } catch (_) {}
    }
    _remoteRenderers.clear();

    for (final track in _localStream?.getTracks() ?? []) {
      try {
        await track.stop();
      } catch (_) {}
    }

    try {
      _localRenderer.srcObject = null;
      await _localRenderer.dispose();
    } catch (_) {}
  }

  @override
  void dispose() {
    _clean();
    super.dispose();
  }

  Widget _videoGrid() {
    final items = <Widget>[
      _videoTile(
        title: 'You',
        renderer: _localRenderer,
        mirror: true,
      ),
    ];

    for (final entry in _remoteRenderers.entries) {
      final users = _otherMembers
          .where((m) => m.id.toString().trim() == entry.key)
          .toList();

      items.add(
        _videoTile(
          title: users.isEmpty ? 'User' : users.first.name,
          renderer: entry.value,
        ),
      );
    }

    return GridView.count(
      padding: const EdgeInsets.all(12),
      crossAxisCount: items.length <= 2 ? 1 : 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: items,
    );
  }

  Widget _audioGrid() {
    final items = <Widget>[
      _audioTile(title: 'You', connected: true),
      ..._otherMembers.map((member) {
        final connected = _peers.containsKey(member.id.toString());
        return _audioTile(
          title: connected ? member.name : '${member.name} ringing...',
          connected: connected,
        );
      }),
    ];

    return GridView.count(
      padding: const EdgeInsets.all(12),
      crossAxisCount: items.length <= 2 ? 1 : 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: items,
    );
  }

  Widget _videoTile({
    required String title,
    required RTCVideoRenderer renderer,
    bool mirror = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: RTCVideoView(
              renderer,
              mirror: mirror,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
          Positioned(
            left: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(title, style: const TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _audioTile({
    required String title,
    required bool connected,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor:
                  connected ? const Color(0xFF1877F2) : const Color(0xFF64748B),
              child: const Icon(Icons.person, color: Colors.white, size: 34),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required FutureOr<void> Function() onTap,
    Color color = const Color(0xFF334155),
  }) {
    return InkWell(
      onTap: () => onTap(),
      borderRadius: BorderRadius.circular(999),
      child: CircleAvatar(
        radius: 28,
        backgroundColor: color,
        child: Icon(icon, color: Colors.white),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.chat.name.trim().isEmpty ? 'Group call' : widget.chat.name.trim();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _endCall();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF020617),
        appBar: AppBar(
          backgroundColor: const Color(0xFF020617),
          foregroundColor: Colors.white,
          title: Text(title),
        ),
        body: Column(
          children: [
            Expanded(
              child: widget.isVideoCall ? _videoGrid() : _audioGrid(),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _controlButton(
                      icon: _micOff ? Icons.mic_off : Icons.mic,
                      onTap: _toggleMic,
                    ),
                    if (widget.isVideoCall)
                      _controlButton(
                        icon: _cameraOff ? Icons.videocam_off : Icons.videocam,
                        onTap: _toggleCamera,
                      ),
                    _controlButton(
                      icon: _speakerOn ? Icons.volume_up : Icons.hearing,
                      onTap: _toggleSpeaker,
                    ),
                    _controlButton(
                      icon: Icons.call_end,
                      color: Colors.red,
                      onTap: _endCall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
