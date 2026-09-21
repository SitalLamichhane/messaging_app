import 'package:flutter/material.dart';
import 'package:hiddenly/groupCall/domain/application/chat_room_controller.dart';
import 'package:hiddenly/groupCall/domain/application/group_call_controller.dart';
import 'package:hiddenly/groupCall/domain/data/chat_api_service.dart';
import 'package:hiddenly/groupCall/domain/infrastructure/call_api_service.dart';
import 'package:hiddenly/groupCall/domain/presentation/screens/groupWidgets/message_bubble.dart';
import 'package:hiddenly/groupCall/domain/presentation/screens/groupWidgets/message_composer.dart';
import 'package:hiddenly/groupCall/domain/presentation/screens/groupWidgets/ongoing_call_banner.dart';
import 'package:hiddenly/groupCall/domain/presentation/screens/group_call_screen.dart';
import 'package:hiddenly/realtime/realtime_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

typedef ChatSettingsBuilder = Widget Function(
  BuildContext context,
  GroupCallController? groupCallController,
);

class ConversationChatScreen extends StatefulWidget {
  final int conversationId;
  final bool isGroup;
  final String title;
  final String avatarUrl;
  final int currentUserId;

  /// IMPORTANT:
  /// Build the exact websocket URI/auth format that already works in your app.
  ///
  /// Example:
  ///   return Uri.parse(
  ///     'wss://api.hiddenly.org/ws/chat/$conversationId/?token=$token',
  ///   );
  final ConversationSocketUriBuilder socketUriBuilder;

  /// Existing private one-to-one call hooks.
  /// Group calls use the new LiveKit controller below.
  final Future<void> Function(bool isVideo)?
      onPrivateCall;

  final ChatSettingsBuilder? settingsBuilder;

  const ConversationChatScreen({
    super.key,
    required this.conversationId,
    required this.isGroup,
    required this.title,
    required this.avatarUrl,
    required this.currentUserId,
    required this.socketUriBuilder,
    this.onPrivateCall,
    this.settingsBuilder,
  });

  @override
  State<ConversationChatScreen> createState() =>
      _ConversationChatScreenState();
}

class _ConversationChatScreenState
    extends State<ConversationChatScreen>
    with WidgetsBindingObserver {
  late final ConversationRealtimeService
      _realtime;

  late final ChatRoomController
      _chatController;

  GroupCallController? _groupCallController;

  final ScrollController _scrollController =
      ScrollController();

  bool _initialized = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _realtime = ConversationRealtimeService(
      uriBuilder: widget.socketUriBuilder,
    );

   _chatController = ChatRoomController(
   conversationId: widget.conversationId,
   currentUserId: widget.currentUserId,
   api: ChatApiService(),
   realtime: _realtime,
    );

    if (widget.isGroup) {
      _groupCallController =
          GroupCallController(
        conversationId:
            widget.conversationId,
        api: CallApiService(),
        realtime: _realtime,
      );
    }

    _chatController.addListener(
      _chatChanged,
    );

    _initialize();
  }

  Future<void> _initialize() async {
    await _chatController.initialize();

    if (widget.isGroup) {
      await _groupCallController
          ?.checkActiveCall(
        widget.conversationId,
      );
    }

    if (mounted) {
      setState(() {
        _initialized = true;
      });
    }

    _scrollToBottom();
  }

  void _chatChanged() {
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      if (!mounted ||
          !_scrollController.hasClients) {
        return;
      }

      _scrollController.animateTo(
        _scrollController
            .position
            .maxScrollExtent,
        duration:
            const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    if (state ==
            AppLifecycleState.resumed &&
        widget.isGroup) {
      _groupCallController
          ?.checkActiveCall(
        widget.conversationId,
      );
    }
  }

  Future<void> _startCall(
    bool isVideo,
  ) async {
    if (!widget.isGroup) {
      await widget.onPrivateCall
          ?.call(isVideo);
      return;
    }

    final controller =
        _groupCallController;

    if (controller == null) return;

    try {
      final active =
          await controller.checkActiveCall(
        widget.conversationId,
      );

      if (active != null &&
          active.isActive) {
        await controller
            .joinExistingCall(active);
      } else {
        await controller.startGroupCall(
          conversationId:
              widget.conversationId,
          video: isVideo,
        );
      }

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              GroupCallScreen(
            controller: controller,
          ),
        ),
      );

      await controller.checkActiveCall(
        widget.conversationId,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            controller.error ??
                'Could not start call: $e',
          ),
        ),
      );
    }
  }

  Future<void> _joinOngoingCall() async {
    final controller =
        _groupCallController;

    final active =
        controller?.activeDiscoveredCall;

    if (controller == null ||
        active == null) {
      return;
    }

    try {
      await controller
          .joinExistingCall(active);

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              GroupCallScreen(
            controller: controller,
          ),
        ),
      );

      await controller.checkActiveCall(
        widget.conversationId,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            controller.error ??
                'Could not join call: $e',
          ),
        ),
      );
    }
  }

  void _openSettings() {
    final builder =
        widget.settingsBuilder;

    if (builder == null) return;

    final page = builder(
      context,
      _groupCallController,
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) {
          // This makes context.read<GroupCallController>()
          // work inside your existing ChatSettingsScreen.
          if (_groupCallController != null) {
            return ChangeNotifierProvider<
                GroupCallController>.value(
              value:
                  _groupCallController!,
              child: page,
            );
          }

          return page;
        },
      ),
    ).then((_) {
      if (widget.isGroup) {
        _groupCallController
            ?.checkActiveCall(
          widget.conversationId,
        );
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance
        .removeObserver(this);

    _chatController.removeListener(
      _chatChanged,
    );

    _scrollController.dispose();

    _groupCallController?.dispose();
    _chatController.dispose();

    _realtime.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callController =
        _groupCallController;

    return Scaffold(
      backgroundColor:
          Theme.of(context).brightness ==
                  Brightness.dark
              ? const Color(0xFF0B141A)
              : const Color(0xFFEFEAE2),
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage:
                  widget.avatarUrl
                          .trim()
                          .isNotEmpty
                      ? NetworkImage(
                          widget.avatarUrl,
                        )
                      : null,
              child: widget.avatarUrl
                      .trim()
                      .isEmpty
                  ? Text(
                      widget.title
                              .trim()
                              .isEmpty
                          ? '?'
                          : widget.title
                              .trim()
                              .substring(
                                0,
                                1,
                              )
                              .toUpperCase(),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () =>
                _startCall(true),
            icon: const Icon(
              Icons.videocam_rounded,
            ),
          ),
          IconButton(
            onPressed: () =>
                _startCall(false),
            icon: const Icon(
              Icons.call_rounded,
            ),
          ),
          if (widget.settingsBuilder !=
              null)
            IconButton(
              onPressed: _openSettings,
              icon: const Icon(
                Icons.more_vert_rounded,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (callController != null)
            OngoingCallBanner(
              controller:
                  callController,
              onJoin:
                  _joinOngoingCall,
            ),
          Expanded(
            child: AnimatedBuilder(
              animation:
                  _chatController,
              builder: (context, _) {
                if (!_initialized &&
                    _chatController.loading) {
                  return const Center(
                    child:
                        CircularProgressIndicator(),
                  );
                }

                if (_chatController
                        .messages
                        .isEmpty &&
                    _chatController.error !=
                        null) {
                  return Center(
                    child: Padding(
                      padding:
                          const EdgeInsets.all(
                        24,
                      ),
                      child: Text(
                        _chatController
                            .error!,
                        textAlign:
                            TextAlign.center,
                      ),
                    ),
                  );
                }

                final messages =
                    _chatController.messages;

                return ListView.builder(
                  controller:
                      _scrollController,
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 8,
                  ),
                  itemCount:
                      messages.length,
                  itemBuilder:
                      (context, index) {
                    final message =
                        messages[index];

                    return MessageBubble(
                      message: message,
                      isMine:
                          message.senderId ==
                              widget
                                  .currentUserId,
                    );
                  },
                );
              },
            ),
          ),
          AnimatedBuilder(
            animation: _chatController,
            builder: (context, _) {
              return MessageComposer(
                sending:
                    _chatController.sending,
                onSendText:
                    _chatController
                        .sendText,
                onSendImages:
                    (
                  List<XFile> files,
                  String caption,
                ) async {
                  await _chatController
                      .sendImages(
                    files,
                    text: caption,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
