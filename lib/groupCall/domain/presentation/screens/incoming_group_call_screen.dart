import 'package:flutter/material.dart';

import 'package:hiddenly/groupCall/domain/call_models.dart';
import 'package:hiddenly/groupCall/domain/presentation/screens/group_call_screen.dart';

import '../../application/group_call_controller.dart';

class IncomingGroupCallScreen
    extends StatefulWidget {
  final IncomingCallPayload payload;
  final GroupCallController controller;

  const IncomingGroupCallScreen({
    super.key,
    required this.payload,
    required this.controller,
  });

  @override
  State<IncomingGroupCallScreen>
      createState() =>
          _IncomingGroupCallScreenState();
}

class _IncomingGroupCallScreenState
    extends State<IncomingGroupCallScreen> {
  bool _handling = false;
  bool _finished = false;

  String? _error;

  Future<CallSessionDto?>
      _findActiveCall() async {
    final active =
        await widget.controller
            .checkActiveCall(
      widget.payload.conversationId,
    );

    if (active == null) {
      return null;
    }

    /*
     * Ignore stale FCM notification.
     */
    if (widget.payload.callId > 0 &&
        active.callId > 0 &&
        active.callId !=
            widget.payload.callId) {
      debugPrint(
        '[INCOMING GROUP CALL] '
        'stale push ignored. '
        'push=${widget.payload.callId} '
        'active=${active.callId}',
      );

      return null;
    }

    return active;
  }

  Future<void> _accept() async {
    if (_handling || _finished) {
      return;
    }

    setState(() {
      _handling = true;
      _error = null;
    });

    try {
      final call =
          await _findActiveCall();

      if (!mounted) {
        return;
      }

      if (call == null ||
          !call.isActive) {
        setState(() {
          _handling = false;
          _error =
              'This group call is no longer active.';
        });

        return;
      }

      await widget.controller
          .joinExistingCall(call);

      if (!mounted) {
        return;
      }

      if (!widget.controller.connected) {
        setState(() {
          _handling = false;
          _error =
              widget.controller.error ??
              'Unable to join group call.';
        });

        return;
      }

      _finished = true;

      await Navigator.of(context)
          .pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              GroupCallScreen(
            controller:
                widget.controller,
          ),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint(
        '[INCOMING GROUP CALL] '
        'accept error: $e',
      );

      debugPrint(
        stackTrace.toString(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _handling = false;

        _error =
            widget.controller.error ??
            'Unable to join group call.';
      });
    }
  }

  Future<void> _decline() async {
    if (_handling || _finished) {
      return;
    }

    setState(() {
      _handling = true;
      _error = null;
    });

    try {
      final call =
          await _findActiveCall();

      if (call != null &&
          call.isActive) {
        await widget.controller
            .declineIncoming(call);
      }

      if (!mounted) {
        return;
      }

      _finished = true;

      Navigator.of(context).pop();
    } catch (e, stackTrace) {
      debugPrint(
        '[INCOMING GROUP CALL] '
        'decline error: $e',
      );

      debugPrint(
        stackTrace.toString(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _handling = false;

        _error =
            widget.controller.error ??
            'Unable to decline call.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final payload =
        widget.payload;

    final groupName =
        payload.conversationName.trim();

    final callerName =
        payload.callerName.trim();

    return PopScope(
      canPop: !_handling,
      child: Scaffold(
        backgroundColor:
            Colors.black,
        body: SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.all(
              24,
            ),
            child: Column(
              children: [
                const Spacer(),

                CircleAvatar(
                  radius: 54,
                  backgroundColor:
                      Colors.white
                          .withOpacity(
                    0.15,
                  ),
                  child: const Icon(
                    Icons.groups_rounded,
                    color: Colors.white,
                    size: 54,
                  ),
                ),

                const SizedBox(
                  height: 28,
                ),

                Text(
                  groupName.isNotEmpty
                      ? groupName
                      : 'Group call',
                  textAlign:
                      TextAlign.center,
                  style:
                      const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 10,
                ),

                Text(
                  payload.isVideo
                      ? 'Incoming group video call'
                      : 'Incoming group audio call',
                  style:
                      const TextStyle(
                    color:
                        Colors.white70,
                    fontSize: 16,
                  ),
                ),

                if (callerName
                    .isNotEmpty) ...[
                  const SizedBox(
                    height: 8,
                  ),
                  Text(
                    'From $callerName',
                    style:
                        const TextStyle(
                      color:
                          Colors.white60,
                      fontSize: 14,
                    ),
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(
                    height: 20,
                  ),
                  Text(
                    _error!,
                    textAlign:
                        TextAlign.center,
                    style:
                        const TextStyle(
                      color:
                          Colors.redAccent,
                    ),
                  ),
                ],

                const Spacer(),

                if (_handling)
                  const Padding(
                    padding:
                        EdgeInsets.only(
                      bottom: 30,
                    ),
                    child:
                        CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  )
                else
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment
                            .spaceEvenly,
                    children: [
                      _CallButton(
                        icon:
                            Icons.call_end,
                        label: 'Decline',
                        backgroundColor:
                            Colors.red,
                        onPressed:
                            _decline,
                      ),
                      _CallButton(
                        icon:
                            payload.isVideo
                                ? Icons
                                    .videocam
                                : Icons.call,
                        label: 'Accept',
                        backgroundColor:
                            Colors.green,
                        onPressed:
                            _accept,
                      ),
                    ],
                  ),

                const SizedBox(
                  height: 40,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final VoidCallback? onPressed;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: backgroundColor,
          shape:
              const CircleBorder(),
          child: InkWell(
            customBorder:
                const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 68,
              height: 68,
              child: Icon(
                icon,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ),
        const SizedBox(
          height: 10,
        ),
        Text(
          label,
          style:
              const TextStyle(
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}