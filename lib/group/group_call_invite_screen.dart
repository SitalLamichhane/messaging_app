import 'package:flutter/material.dart';
import 'package:hiddenly/group/group_api_service.dart';
import 'package:hiddenly/group/group_call_screen.dart';
import 'package:hiddenly/group/group_models.dart';

class GroupCallInviteScreen extends StatefulWidget {
  final GroupCallSessionInfo call;
  final String groupName;

  const GroupCallInviteScreen({
    super.key,
    required this.call,
    required this.groupName,
  });

  @override
  State<GroupCallInviteScreen> createState() => _GroupCallInviteScreenState();
}

class _GroupCallInviteScreenState extends State<GroupCallInviteScreen> {
  bool _busy = false;

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await GroupApiService.declineCall(widget.call.callId);
    } finally {
      if (mounted) Navigator.maybePop(context);
    }
  }

  Future<void> _join() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final creds = await GroupApiService.joinCall(widget.call.callId);
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => GroupCallScreen(
            callId: creds.call.callId,
            conversationId: creds.call.conversationId,
            groupName: widget.groupName,
            serverUrl: creds.url,
            token: creds.token,
            roomName: creds.call.roomName,
            startWithVideo: creds.call.isVideo,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not join call: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111B21),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              const CircleAvatar(
                radius: 58,
                backgroundColor: Color(0xFF202C33),
                child: Icon(Icons.groups_rounded, color: Colors.white, size: 58),
              ),
              const SizedBox(height: 24),
              Text(
                widget.groupName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.call.startedByName} started a ${widget.call.isVideo ? 'video' : 'voice'} call',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              if (widget.call.joinedMembers.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  '${widget.call.joinedMembers.length} already in call',
                  style: const TextStyle(color: Color(0xFF00A884)),
                ),
              ],
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _InviteButton(
                    icon: Icons.call_end,
                    label: 'Decline',
                    color: Colors.red,
                    onTap: _busy ? null : _decline,
                  ),
                  _InviteButton(
                    icon: widget.call.isVideo ? Icons.videocam : Icons.call,
                    label: 'Join',
                    color: const Color(0xFF00A884),
                    onTap: _busy ? null : _join,
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _InviteButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _InviteButton({
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
          borderRadius: BorderRadius.circular(40),
          child: CircleAvatar(
            radius: 32,
            backgroundColor: color,
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    );
  }
}
