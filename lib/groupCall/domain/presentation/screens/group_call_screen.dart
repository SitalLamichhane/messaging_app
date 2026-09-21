import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hiddenly/groupCall/domain/application/group_call_controller.dart';
import 'package:hiddenly/groupCall/domain/presentation/screens/groupWidgets/call_controls.dart';
import 'package:hiddenly/groupCall/domain/presentation/screens/groupWidgets/participant_tile.dart';

class GroupCallScreen
    extends StatefulWidget {
  final GroupCallController controller;

  const GroupCallScreen({
    super.key,
    required this.controller,
  });

  @override
  State<GroupCallScreen> createState() {
    return _GroupCallScreenState();
  }
}

class _GroupCallScreenState
    extends State<GroupCallScreen> {
  bool _leaving = false;
  bool _popping = false;

  @override
  void initState() {
    super.initState();

    widget.controller.addListener(
      _controllerChanged,
    );
  }

  void _controllerChanged() {
    if (!mounted || _popping) {
      return;
    }

    if (widget.controller.phase ==
        GroupCallPhase.ended) {
      _schedulePop();
    }
  }

  void _schedulePop() {
    if (_popping) return;

    _popping = true;

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      if (!mounted) return;

      final navigator =
          Navigator.of(context);

      if (navigator.canPop()) {
        navigator.pop();
      }
    });
  }

  Future<void> _leave() async {
    if (_leaving || _popping) {
      return;
    }

    setState(() {
      _leaving = true;
    });

    try {
      await widget.controller.leave();
    } catch (e) {
      debugPrint(
        'GROUP CALL LEAVE ERROR => $e',
      );
    }

    if (!mounted || _popping) {
      return;
    }

    _schedulePop();
  }

  void _runMediaAction(
    Future<void> Function() action,
  ) {
    unawaited(
      action().catchError(
        (Object error) {
          debugPrint(
            'GROUP CALL MEDIA ERROR => $error',
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(
      _controllerChanged,
    );

    /*
     * IMPORTANT:
     *
     * Do NOT dispose controller here.
     *
     * ConversationChatScreen owns the
     * GroupCallController.
     */

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _leave();

        // _leave() performs navigation itself.
        return false;
      },
      child: Scaffold(
        backgroundColor:
            const Color(0xFF0B141A),
        appBar: AppBar(
          automaticallyImplyLeading:
              false,
          backgroundColor:
              const Color(0xFF111B21),
          foregroundColor:
              Colors.white,
          title: AnimatedBuilder(
            animation:
                widget.controller,
            builder: (context, _) {
              final controller =
                  widget.controller;

              final call =
                  controller.call;

              final count =
                  controller
                      .liveKit
                      .participants
                      .length;

              final conversationName =
                  call
                      ?.conversationName
                      .trim();

              return Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Text(
                    conversationName !=
                                null &&
                            conversationName
                                .isNotEmpty
                        ? conversationName
                        : 'Group call',
                  ),
                  Text(
                    controller.connected
                        ? '$count in call'
                        : _phaseLabel(
                            controller
                                .phase,
                          ),
                    style:
                        const TextStyle(
                      fontSize: 12,
                      color:
                          Colors.white70,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        body: AnimatedBuilder(
          animation:
              widget.controller,
          builder: (context, _) {
            final controller =
                widget.controller;

            if (controller.phase ==
                    GroupCallPhase
                        .starting ||
                controller.phase ==
                    GroupCallPhase
                        .joining) {
              return const Center(
                child:
                    CircularProgressIndicator(),
              );
            }

            if (controller.phase ==
                GroupCallPhase.error) {
              return Center(
                child: Padding(
                  padding:
                      const EdgeInsets
                          .all(24),
                  child: Text(
                    controller.error ??
                        'Unable to connect to call',
                    textAlign:
                        TextAlign.center,
                    style:
                        const TextStyle(
                      color:
                          Colors.white,
                    ),
                  ),
                ),
              );
            }

            final media =
                controller.liveKit;

            final room =
                media.room;

            final participants =
                media.participants;

            return Column(
              children: [
                Expanded(
                  child: room == null
                      ? const Center(
                          child:
                              CircularProgressIndicator(),
                        )
                      : participants
                              .isEmpty
                          ? const Center(
                              child: Text(
                                'Waiting for participants…',
                                style:
                                    TextStyle(
                                  color:
                                      Colors.white70,
                                ),
                              ),
                            )
                          : GridView
                              .builder(
                              padding:
                                  const EdgeInsets
                                      .all(
                                6,
                              ),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount:
                                    _columnCount(
                                  participants
                                      .length,
                                ),
                                crossAxisSpacing:
                                    2,
                                mainAxisSpacing:
                                    2,
                                childAspectRatio:
                                    participants.length <=
                                            2
                                        ? 0.78
                                        : 0.9,
                              ),
                              itemCount:
                                  participants
                                      .length,
                              itemBuilder:
                                  (
                                context,
                                index,
                              ) {
                                final participant =
                                    participants[
                                        index];

                                return ParticipantTile(
                                  participant:
                                      participant,
                                  liveKit:
                                      media,
                                  isLocal:
                                      participant
                                              .identity ==
                                          room
                                              .localParticipant
                                              ?.identity,
                                );
                              },
                            ),
                ),
                CallControls(
                  microphoneEnabled:
                      media
                          .microphoneEnabled,
                  cameraEnabled:
                      media.cameraEnabled,
                  speakerEnabled:
                      media.speakerEnabled,
                  onMicrophone: () {
                    _runMediaAction(
                      controller
                          .toggleMicrophone,
                    );
                  },
                  onCamera: () {
                    _runMediaAction(
                      controller
                          .toggleCamera,
                    );
                  },
                  onSwitchCamera: () {
                    _runMediaAction(
                      controller
                          .switchCamera,
                    );
                  },
                  onSpeaker: () {
                    _runMediaAction(
                      controller
                          .toggleSpeaker,
                    );
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

  int _columnCount(
    int participantCount,
  ) {
    if (participantCount <= 1) {
      return 1;
    }

    if (participantCount <= 4) {
      return 2;
    }

    return 3;
  }

  String _phaseLabel(
    GroupCallPhase phase,
  ) {
    switch (phase) {
      case GroupCallPhase.idle:
        return 'Ready';

      case GroupCallPhase.checking:
        return 'Checking…';

      case GroupCallPhase.starting:
        return 'Starting…';

      case GroupCallPhase.joining:
        return 'Joining…';

      case GroupCallPhase.connected:
        return 'Connected';

      case GroupCallPhase.leaving:
        return 'Leaving…';

      case GroupCallPhase.ended:
        return 'Ended';

      case GroupCallPhase.error:
        return 'Connection error';
    }
  }
}