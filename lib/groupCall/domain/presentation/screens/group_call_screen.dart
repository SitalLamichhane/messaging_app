import 'package:flutter/material.dart';

import '../../application/group_call_controller.dart';
import '../widgets/call_controls.dart';
import '../widgets/participant_grid.dart';

class GroupCallScreen extends StatefulWidget {
  final GroupCallController controller;

  const GroupCallScreen({
    super.key,
    required this.controller,
  });

  @override
  State<GroupCallScreen> createState() =>
      _GroupCallScreenState();
}

class _GroupCallScreenState
    extends State<GroupCallScreen> {
  bool _leaving = false;

  Future<void> _leave() async {
    if (_leaving) return;

    setState(() => _leaving = true);

    try {
      await widget.controller.leave();
    } catch (_) {
      // Local call still closes; backend webhook should reconcile if needed.
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B141A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF111B21),
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          title: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final call = widget.controller.call;
              final count =
                  widget.controller.liveKit.participants.length;

              return Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    call?.conversationName.isNotEmpty ==
                            true
                        ? call!.conversationName
                        : 'Group call',
                  ),
                  Text(
                    widget.controller.connected
                        ? '$count in call'
                        : _phaseText(
                            widget.controller.phase,
                          ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        body: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final controller = widget.controller;

            if (controller.phase ==
                    GroupCallPhase.joining ||
                controller.phase ==
                    GroupCallPhase.starting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (controller.phase ==
                GroupCallPhase.error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    controller.error ??
                        'Unable to join call',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                    ),
                  ),
                ),
              );
            }

            return Column(
              children: [
                Expanded(
                  child: ParticipantGrid(
                    liveKit: controller.liveKit,
                  ),
                ),
                CallControls(
                  microphoneEnabled: controller
                      .liveKit.microphoneEnabled,
                  cameraEnabled:
                      controller.liveKit.cameraEnabled,
                  speakerEnabled:
                      controller.liveKit.speakerEnabled,
                  onMicrophone: () {
                    controller.toggleMicrophone();
                  },
                  onCamera: () {
                    controller.toggleCamera();
                  },
                  onSwitchCamera: () {
                    controller.switchCamera();
                  },
                  onSpeaker: () {
                    controller.toggleSpeaker();
                  },
                  onLeave: _leave,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _phaseText(GroupCallPhase phase) {
    switch (phase) {
      case GroupCallPhase.checking:
        return 'Checking call…';
      case GroupCallPhase.starting:
        return 'Starting…';
      case GroupCallPhase.joining:
        return 'Joining…';
      case GroupCallPhase.connected:
        return 'Connected';
      case GroupCallPhase.leaving:
        return 'Leaving…';
      case GroupCallPhase.ended:
        return 'Call ended';
      case GroupCallPhase.error:
        return 'Connection error';
      case GroupCallPhase.idle:
        return 'Group call';
    }
  }
}
