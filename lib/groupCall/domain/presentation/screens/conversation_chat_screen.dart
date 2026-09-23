import 'package:flutter/material.dart';

import 'package:hiddenly/groupCall/domain/application/chat_room_controller.dart';
import 'package:hiddenly/groupCall/domain/application/group_call_controller.dart';
import 'package:hiddenly/groupCall/domain/data/chat_api_service.dart';
import 'package:hiddenly/groupCall/domain/infrastructure/call_api_service.dart';

import 'package:hiddenly/groupCall/domain/presentation/screens/groupWidgets/message_bubble.dart';
import 'package:hiddenly/groupCall/domain/presentation/screens/groupWidgets/message_composer.dart';

import 'package:hiddenly/groupCall/domain/presentation/screens/group_call_screen.dart';

import 'package:hiddenly/realtime/realtime_service.dart';

import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

typedef ChatSettingsBuilder = Widget Function(
  BuildContext context,
  GroupCallController? controller,
);

class ConversationChatScreen extends StatefulWidget {
  final int conversationId;

  final bool isGroup;

  final String title;

  final String members;

  final int currentUserId;

  final ConversationSocketUriBuilder socketUriBuilder;

  final Future<void> Function(bool video)? onPrivateCall;

  final ChatSettingsBuilder? settingsBuilder;

  const ConversationChatScreen({
    super.key,
    required this.conversationId,
    required this.isGroup,
    required this.title,
    required this.members,
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
  late final ChatRoomController chatController;

  GroupCallController? callController;

  late final ConversationRealtimeService realtime;

  final ScrollController scrollController =
      ScrollController();

  bool _initialScrollCompleted = false;

  int _previousMessageCount = 0;

  double _previousKeyboardHeight = 0;

  bool _disposed = false;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    realtime = ConversationRealtimeService(
      uriBuilder: widget.socketUriBuilder,
    );

    chatController = ChatRoomController(
      conversationId: widget.conversationId,
      currentUserId: widget.currentUserId,
      api: ChatApiService(),
      realtime: realtime,
    );

    if (widget.isGroup) {
      callController = GroupCallController(
        conversationId: widget.conversationId,
        api: CallApiService(),
        realtime: realtime,
      );
    }

    chatController.addListener(
      _onChatControllerChanged,
    );

    /*
     * initialize() connects realtime and loads
     * existing messages.
     */
    chatController.initialize();
  }

  // ============================================================
  // CHAT CONTROLLER LISTENER
  // ============================================================

  void _onChatControllerChanged() {
    if (!mounted || _disposed) {
      return;
    }

    final currentCount =
        chatController.messages.length;

    final messageCountChanged =
        currentCount != _previousMessageCount;

    /*
     * First successful history load:
     *
     * automatically show the most recent message.
     */
    if (!_initialScrollCompleted &&
        !chatController.loading &&
        currentCount > 0) {
      _initialScrollCompleted = true;
      _previousMessageCount = currentCount;

      setState(() {});

      _scrollToBottom(
        animated: false,
      );

      return;
    }

    /*
     * New message arrived while the chat is open.
     *
     * If user is already close to the latest
     * messages, keep following the conversation.
     *
     * If user scrolled far upward to read old
     * messages, don't suddenly force them down.
     */
    final shouldFollow =
        _isNearBottom();

    _previousMessageCount =
        currentCount;

    setState(() {});

    if (messageCountChanged &&
        shouldFollow) {
      _scrollToBottom();
    }
  }

  // ============================================================
  // KEYBOARD
  // ============================================================

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();

    if (!mounted || _disposed) {
      return;
    }

    final view =
        WidgetsBinding.instance.platformDispatcher.views.first;

    final keyboardHeight =
        view.viewInsets.bottom /
        view.devicePixelRatio;

    /*
     * Keyboard changed from closed -> open.
     */
    if (keyboardHeight > 0 &&
        _previousKeyboardHeight <= 0) {
      _scrollToBottom(
        delay: const Duration(
          milliseconds: 120,
        ),
      );
    }

    _previousKeyboardHeight =
        keyboardHeight;
  }

  // ============================================================
  // SCROLL HELPERS
  // ============================================================

  bool _isNearBottom() {
    if (!scrollController.hasClients) {
      return true;
    }

    final position =
        scrollController.position;

    final distanceFromBottom =
        position.maxScrollExtent -
        position.pixels;

    return distanceFromBottom < 180;
  }

  void _scrollToBottom({
    bool animated = true,
    Duration delay = Duration.zero,
  }) {
    Future<void>.delayed(
      delay,
      () {
        if (!mounted || _disposed) {
          return;
        }

        WidgetsBinding.instance
            .addPostFrameCallback(
          (_) {
            if (!mounted ||
                _disposed ||
                !scrollController.hasClients) {
              return;
            }

            final position =
                scrollController.position;

            final target =
                position.maxScrollExtent;

            if (animated) {
              scrollController.animateTo(
                target,
                duration: const Duration(
                  milliseconds: 250,
                ),
                curve: Curves.easeOut,
              );
            } else {
              scrollController.jumpTo(
                target,
              );
            }
          },
        );
      },
    );
  }

  // ============================================================
  // SETTINGS
  // ============================================================

  void openSettings() {
    final page =
        widget.settingsBuilder?.call(
      context,
      callController,
    );

    if (page == null) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          if (callController != null) {
            return ChangeNotifierProvider.value(
              value: callController!,
              child: page,
            );
          }

          return page;
        },
      ),
    );
  }

  // ============================================================
  // CALL
  // ============================================================

  Future<void> startCall(
    bool video,
  ) async {
    if (!widget.isGroup) {
      await widget.onPrivateCall?.call(
        video,
      );

      return;
    }

    if (callController == null) {
      return;
    }

    try {
      final active =
          await callController!
              .checkActiveCall(
        widget.conversationId,
      );

      if (active != null &&
          active.isActive) {
        await callController!
            .joinExistingCall(
          active,
        );
      } else {
        await callController!
            .startGroupCall(
          conversationId:
              widget.conversationId,
          video: video,
        );
      }

      if (!mounted) {
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              GroupCallScreen(
            controller:
                callController!,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            error.toString(),
          ),
        ),
      );
    }
  }

  // ============================================================
  // SEND TEXT
  // ============================================================

  Future<void> _sendText(
    String text,
  ) async {
    final value =
        text.trim();

    if (value.isEmpty) {
      return;
    }

    try {
      await chatController.sendText(
        value,
      );

      /*
       * Own message should always become the
       * most recent visible message.
       */
      _scrollToBottom(
        delay: const Duration(
          milliseconds: 80,
        ),
      );
    } catch (error) {
      _showError(error);
    }
  }

  // ============================================================
  // SEND MEDIA
  // ============================================================

  Future<void> _sendMedia(
    List<XFile> files,
    String caption,
    String type,
  ) async {
    if (files.isEmpty) {
      return;
    }

    try {
      await chatController.sendMedia(
        files,
        text: caption,
        type: type,
      );

      _scrollToBottom(
        delay: const Duration(
          milliseconds: 100,
        ),
      );
    } catch (error) {
      _showError(error);
    }
  }

  // ============================================================
  // DELETE
  // ============================================================

  Future<void> _deleteMessage(
    int messageId,
  ) async {
    try {
      await chatController.deleteMessage(
        messageId,
      );
    } catch (error) {
      _showError(error);
    }
  }

  // ============================================================
  // ERROR
  // ============================================================

  void _showError(
    Object error,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          error.toString(),
        ),
      ),
    );
  }

  // ============================================================
  // APP BAR
  // ============================================================

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor:
          const Color(
        0xff202c33,
      ),
      foregroundColor:
          Colors.white,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back,
        ),
        onPressed: () {
          Navigator.pop(context);
        },
      ),
      titleSpacing: 0,
      title: GestureDetector(
        behavior:
            HitTestBehavior.opaque,
        onTap: openSettings,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(
            vertical: 6,
          ),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style:
                    const TextStyle(
                  fontSize: 17,
                  fontWeight:
                      FontWeight.w600,
                  color: Colors.white,
                ),
              ),

              if (widget.isGroup &&
                  widget.members
                      .trim()
                      .isNotEmpty)
                Text(
                  widget.members,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style:
                      const TextStyle(
                    fontSize: 12,
                    color:
                        Colors.white70,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Video call',
          onPressed: () {
            startCall(true);
          },
          icon: const Icon(
            Icons.videocam_rounded,
          ),
        ),
        IconButton(
          tooltip: 'Audio call',
          onPressed: () {
            startCall(false);
          },
          icon: const Icon(
            Icons.call_rounded,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // MESSAGES
  // ============================================================

  Widget _buildMessages() {
    if (chatController.loading &&
        chatController.messages.isEmpty) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    if (chatController.messages.isEmpty) {
      return const Center(
        child: Text(
          'No messages yet',
          style: TextStyle(
            color: Colors.black54,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,

      /*
       * Normal order:
       *
       * old message
       * old message
       * latest message
       *
       * Then we scroll to maxScrollExtent.
       */
      reverse: false,

      keyboardDismissBehavior:
          ScrollViewKeyboardDismissBehavior
              .onDrag,

      padding:
          const EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: 8,
      ),

      itemCount:
          chatController.messages.length,

      itemBuilder:
          (context, index) {
        final message =
            chatController.messages[
                index];

        final isMine =
            message.senderId ==
            widget.currentUserId;

        return MessageBubble(
          message: message,
          isMine: isMine,

          /*
           * Only expose delete action for
           * the current user's messages.
           */
          onDelete: isMine
              ? () {
                  _deleteMessage(
                    message.id,
                  );
                }
              : null,
        );
      },
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    /*
     * This is intentionally true.
     *
     * Flutter will resize the body when
     * the keyboard opens, causing both the
     * composer and messages to move upward.
     */
    return Scaffold(
      resizeToAvoidBottomInset: true,

      backgroundColor:
          const Color(
        0xffefeae2,
      ),

      appBar: _buildAppBar(),

      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child:
                  _buildMessages(),
            ),

            MessageComposer(
              sending:
                  chatController.sending,

              onSendText:
                  _sendText,

              onSendMedia:
                  _sendMedia,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _disposed = true;

    WidgetsBinding.instance
        .removeObserver(this);

    chatController.removeListener(
      _onChatControllerChanged,
    );

    chatController.dispose();

    callController?.dispose();

    /*
     * ConversationChatScreen owns the
     * realtime service.
     */
    realtime.dispose();

    scrollController.dispose();

    super.dispose();
  }
}