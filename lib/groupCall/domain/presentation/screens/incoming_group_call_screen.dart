import 'package:flutter/material.dart';

import '../../application/group_call_controller.dart';
import 'group_call_screen.dart';

class IncomingGroupCallScreen extends StatefulWidget {
  final IncomingCallPayload payload;
  final GroupCallController controller;

  const IncomingGroupCallScreen({
    super.key,
    required this.payload,
    required this.controller,
  });

  @override
  State<IncomingGroupCallScreen> createState() =>
      _IncomingGroupCallScreenState();
}

class _IncomingGroupCallScreenState
    extends State<IncomingGroupCallScreen> {
  bool _busy = false;

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      // No separate action=accept call.
      // LiveKitTokenView marks JOINED in your backend.
      await widget.controller.joinExistingCall(
        widget.payload.call,
      );

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GroupCallScreen(
            controller: widget.controller,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not join: $e'),
        ),
      );
    }
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await widget.controller.declineIncoming(
        widget.payload.call,
      );
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.payload.call;

    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Spacer(),
              CircleAvatar(
                radius: 56,
                backgroundImage:
                    call.callerAvatar.isNotEmpty
                        ? NetworkImage(
                            call.callerAvatar,
                          )
                        : null,
                child: call.callerAvatar.isEmpty
                    ? const Icon(
                        Icons.groups,
                        size: 48,
                      )
                    : null,
              ),
              const SizedBox(height: 24),
              Text(
                call.conversationName.isNotEmpty
                    ? call.conversationName
                    : 'Group call',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${call.callerName.isEmpty ? 'Someone' : call.callerName} started a ${call.isVideo ? 'video' : 'voice'} call',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              if (_busy)
                const CircularProgressIndicator()
              else
                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceEvenly,
                  children: [
                    _RoundAction(
                      icon: Icons.call_end,
                      label: 'Decline',
                      color: Colors.red,
                      onTap: _decline,
                    ),
                    _RoundAction(
                      icon: call.isVideo
                          ? Icons.videocam
                          : Icons.call,
                      label: 'Join',
                      color: Colors.green,
                      onTap: _accept,
                    ),
                  ],
                ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _RoundAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Icon(
                icon,
                color: Colors.white,
                size: 30,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
