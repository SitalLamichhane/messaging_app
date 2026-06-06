import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:messaging_app/core/api_client.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:messaging_app/call_screen.dart';
import 'package:messaging_app/chat_data.dart';
import 'package:messaging_app/chat_models.dart';
import 'package:messaging_app/inside_chat/chat_settingScreen.dart';
import 'package:messaging_app/core/chat/chat_provider.dart';
import 'package:messaging_app/core/call/global_call_handler.dart';
import 'package:messaging_app/widgets/dynamic_message_media.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

class ChatDetailScreen extends StatefulWidget {
  final ChatItem chat;

  const ChatDetailScreen({
    super.key,
    required this.chat,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();

  late List<ChatMessage> _messages;
  late ChatProvider _chatProvider;

  bool _showEmoji = false;
  bool _isRecording = false;
  bool _isSendingText = false;
  bool _isSendingLike = false;

  final Map<String, String> _messageReactions = {};
  final Set<String> _pinnedMessageIds = {};

  final Set<String> _deletingMessageIds = {};
  final Set<String> _hiddenMessageIds = {};

  Timer? _recordTicker;
  Duration _recordDuration = Duration.zero;
  String? _currentRecordPath;
  int _lastRenderedMessageCount = 0;

  ChatMessage? _replyingTo;

  final List<String> _messengerReactions = const [
    '❤️',
    '👍',
    '👎',
    '🔥',
    '🥰',
    '👏',
    '😁',
  ];

  List<ChatMessage> _sortedProviderMessages(ChatProvider provider) {
    return List<ChatMessage>.from(
      provider.getMessagesForChat(widget.chat.id),
    )..sort((a, b) => a.sentAt.compareTo(b.sentAt));
  }


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatProvider = context.read<ChatProvider>();
  }

  @override
  void initState() {
    super.initState();

    _messages = List<ChatMessage>.from(widget.chat.messages)
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));

    Future.microtask(() async {
      final conversationId = int.tryParse(widget.chat.id);
      if (conversationId == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpBottom());
        return;
      }

      if (!mounted) return;

      final provider = _chatProvider;
      await provider.loadMessages(conversationId);

      if (!mounted) return;

      await provider.connectSocket(
        conversationId: conversationId,
        // myUserId: 1, // TODO: replace with real logged-in user id
      );

      final accessToken = await ApiClient.storage.read(key: 'access');
      final currentUserId = await ApiClient.storage.read(key: 'user_id');

      if (accessToken != null &&
          accessToken.trim().isNotEmpty &&
          currentUserId != null &&
          currentUserId.trim().isNotEmpty) {
        GlobalCallHandler.connectCallSocket(
          url:
              'ws://192.168.1.97:8000/ws/call/$conversationId/?token=${Uri.encodeComponent(accessToken.trim())}',
          currentUserId: currentUserId,
        );
      } else {
        debugPrint('CALL SOCKET ERROR: token/user missing in ChatDetailScreen');
      }

      if (!mounted) return;

      setState(() {
        _messages = _sortedProviderMessages(provider)
        .where((m) => !_hiddenMessageIds.contains(m.id))
        .where((m) => m.type != MessageType.text || m.text.trim().isNotEmpty)
        .toList();
      });

      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpBottom());
    });
  }

  @override
  void dispose() {
    _recordTicker?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _recorder.dispose();

    super.dispose();
  }

  bool _isOnlyEmoji(String text) {
    final value = text.trim();
    if (value.isEmpty) return false;

    final withoutSpaces = value.replaceAll(' ', '');

    final emojiOnly = RegExp(
      r'^[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2300}-\u{23FF}\u{2B00}-\u{2BFF}\u{2190}-\u{21FF}\u{2934}-\u{2935}\u{3030}\u{303D}\u{3297}\u{3299}\u{FE0F}\u{200D}]+$',
      unicode: true,
    );

    return withoutSpaces.characters.length <= 8 &&
        emojiOnly.hasMatch(withoutSpaces);
  }

  void _jumpBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  void _animateBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _smartScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _animateBottom();
    });

    Future.delayed(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      _animateBottom();
    });

    Future.delayed(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      _animateBottom();
    });
  }

  void _scrollToBottomAfterKeyboard() {
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _animateBottom();
    });

    Future.delayed(const Duration(milliseconds: 550), () {
      if (!mounted) return;
      _animateBottom();
    });
  }

  void _syncLocalMessages() {
    try {
      _messages = _sortedProviderMessages(_chatProvider)
          .where((m) => !_hiddenMessageIds.contains(m.id))
          .toList();
    } catch (_) {
      _messages = (List<ChatMessage>.from(widget.chat.messages)
          ..sort((a, b) => a.sentAt.compareTo(b.sentAt)))
          .where((m) => !_hiddenMessageIds.contains(m.id))
          .toList();
    }
  }

  void _append(ChatMessage message) {
    setState(() {
      _messages.add(message);
      _replyingTo = null;
      _showEmoji = false;
    });

    AppChatData.addMessage(widget.chat, message);
    _smartScrollToBottom();
  }

  String _previewForReply(ChatMessage msg) {
    switch (msg.type) {
      case MessageType.text:
        return msg.text;
      case MessageType.image:
        return '📷 Photo';
      case MessageType.mediaAlbum:
        return '📷 ${msg.mediaUrls?.length ?? 0} Photos';
      case MessageType.video:
        return '🎥 Video';
      case MessageType.file:
        return '📎 ${msg.fileName ?? "File"}';
      case MessageType.call:
        return msg.callType == CallEntryType.video
            ? '📹 Video call'
            : '📞 Voice call';
      case MessageType.audio:
        return '🎤 Voice message';
    }
  }

  ChatMessage _cloneForwardMessage(ChatMessage message) {
    return ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: message.type,
      text: message.text,
      isMe: true,
      sentAt: DateTime.now(),
      isSeen: true,
      filePath: message.filePath,
      fileName: message.fileName,
      fileSizeBytes: message.fileSizeBytes,
      mediaUrls: message.mediaUrls,
      audioPath: message.audioPath,
      audioDuration: message.audioDuration,
      callType: message.callType,
      callAnswered: message.callAnswered,
      callDuration: message.callDuration,
    );
  }

  void _replyTo(ChatMessage message) {
    setState(() {
      _replyingTo = message;
      _showEmoji = false;
    });
  }

  void _cancelReply() {
    setState(() {
      _replyingTo = null;
    });
  }

  Future<void> _sendText() async {
    if (_isSendingText) return;

    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isSendingText = true;
    });

    final conversationId = int.tryParse(widget.chat.id);
    if (conversationId == null) {
      _append(
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          type: MessageType.text,
          text: text,
          isMe: true,
          sentAt: DateTime.now(),
          isSeen: true,
          replyToMessageId: _replyingTo?.id,
          replyPreview:
              _replyingTo == null ? null : _previewForReply(_replyingTo!),
          replyToMe: _replyingTo?.isMe,
        ),
      );
      _messageController.clear();

      if (mounted) {
        setState(() {
          _isSendingText = false;
        });
      }
      return;
    }

    final provider = _chatProvider;
    _messageController.clear();

    // IMPORTANT:
    // Do not call sendSocketTyping() here until your backend consumer has
    // a separate typing handler. In your logs, typing socket events were being
    // broadcast back as blank "new_message" objects with text: "".

    try {
      if (_replyingTo != null) {
        await provider.sendReply(
          conversationId: conversationId,
          text: text,
          replyTo: int.tryParse(_replyingTo!.id) ?? 0,
          replyPreview: _previewForReply(_replyingTo!),
          replyToMe: _replyingTo!.isMe,
        );
      } else {
        await provider.sendText(
          conversationId: conversationId,
          text: text,
        );
      }

      if (!mounted) return;

      setState(() {
        _replyingTo = null;
        _showEmoji = false;
        _messages = _sortedProviderMessages(provider)
            .where((m) => m.type != MessageType.text || m.text.trim().isNotEmpty)
            .toList();
      });

      _smartScrollToBottom();
    } catch (e) {
      debugPrint('SEND TEXT ERROR: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSendingText = false;
        });
      }
    }
  }

  Future<void> _sendLike() async {
    if (_isSendingLike) return;

    setState(() {
      _isSendingLike = true;
    });

    final conversationId = int.tryParse(widget.chat.id);
    if (conversationId == null) {
      _append(
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          type: MessageType.text,
          text: '👍',
          isMe: true,
          sentAt: DateTime.now(),
          isSeen: true,
        ),
      );

      if (mounted) {
        setState(() {
          _isSendingLike = false;
        });
      }
      return;
    }

    final provider = _chatProvider;

    try {
      await provider.sendText(
        conversationId: conversationId,
        text: '👍',
      );

      if (!mounted) return;

      setState(() {
        _messages = _sortedProviderMessages(provider)
            .where((m) => m.type != MessageType.text || m.text.trim().isNotEmpty)
            .toList();
      });

      _smartScrollToBottom();
    } catch (e) {
      debugPrint('SEND LIKE ERROR: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSendingLike = false;
        });
      }
    }
  }

  void _showMessengerPop(
    String text, {
    IconData icon = Icons.check_circle_rounded,
  }) {
    if (!mounted) return;

    final overlay = Overlay.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) {
        return Positioned(
          bottom: 110,
          left: 20,
          right: 20,
          child: IgnorePointer(
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.92, end: 1),
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.scale(
                      scale: value,
                      child: child,
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1F1F1F) : Colors.black87,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);

    Future.delayed(
      const Duration(milliseconds: 950),
      () {
        if (entry.mounted) {
          entry.remove();
        }
      },
    );
  }

  Future<void> _copyMessage(ChatMessage message) async {
  String copyValue = '';

  if (message.type == MessageType.text) {
    copyValue = message.text.trim();
  } else if (message.type == MessageType.image) {
    copyValue = message.filePath ?? '';
  } else if (message.type == MessageType.mediaAlbum) {
    copyValue = (message.mediaUrls ?? []).join('\n');
  } else if (message.type == MessageType.video) {
    copyValue = message.filePath ?? '';
  } else if (message.type == MessageType.audio) {
    copyValue = message.audioPath ?? '';
  } else if (message.type == MessageType.file) {
    copyValue = message.filePath ?? '';
  } else if (message.type == MessageType.call) {
    copyValue = _previewForReply(message);
  }

  if (copyValue.trim().isEmpty) {
    _showMessengerPop('Nothing to copy');
    return;
  }

  await Clipboard.setData(ClipboardData(text: copyValue));

  if (!mounted) return;

  _showMessengerPop('Copied');
}

  bool _isNetworkPath(String value) {
    final lower = value.toLowerCase().trim();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  String _fileNameFromPath(String value, String fallback) {
    final cleanValue = value.split('?').first.split('#').first;
    final parts = cleanValue.replaceAll('\\', '/').split('/');
    final name = parts.isNotEmpty ? parts.last.trim() : '';
    return name.isEmpty ? fallback : name;
  }

  Future<String> _copyMessageFileToPhoneFolder({
    required String sourcePath,
    required String fallbackName,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final saveDir = Directory('${dir.path}/MessengerSaved');

    if (!await saveDir.exists()) {
      await saveDir.create(recursive: true);
    }

    final fileName = _fileNameFromPath(sourcePath, fallbackName);
    final targetPath = '${saveDir.path}/$fileName';

    if (_isNetworkPath(sourcePath)) {
      final uri = Uri.parse(sourcePath);
      final request = await HttpClient().getUrl(uri);
      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Download failed');
      }

      final bytes = await consolidateHttpClientResponseBytes(response);
      final savedFile = File(targetPath);
      await savedFile.writeAsBytes(bytes, flush: true);
      return savedFile.path;
    }

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('File not found');
    }

    final savedFile = await sourceFile.copy(targetPath);
    return savedFile.path;
  }

  Future<Uint8List> _readMessageFileBytes(String sourcePath) async {
    if (_isNetworkPath(sourcePath)) {
      final uri = Uri.parse(sourcePath);
      final request = await HttpClient().getUrl(uri);
      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Download failed');
      }

      return consolidateHttpClientResponseBytes(response);
    }

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('File not found');
    }

    return sourceFile.readAsBytes();
  }

  Future<String> _prepareLocalFileForSaving({
    required String sourcePath,
    required String fallbackName,
  }) async {
    final fileName = _fileNameFromPath(sourcePath, fallbackName);
    final dir = await getTemporaryDirectory();
    final targetPath = '${dir.path}/save_${DateTime.now().millisecondsSinceEpoch}_$fileName';

    if (_isNetworkPath(sourcePath)) {
      final uri = Uri.parse(sourcePath);
      final request = await HttpClient().getUrl(uri);
      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Download failed');
      }

      final bytes = await consolidateHttpClientResponseBytes(response);
      final savedFile = File(targetPath);
      await savedFile.writeAsBytes(bytes, flush: true);
      return savedFile.path;
    }

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('File not found');
    }

    final copiedFile = await sourceFile.copy(targetPath);
    return copiedFile.path;
  }

  Future<void> _saveMessage(ChatMessage message) async {
    try {
      if (message.type == MessageType.text) {
        final text = message.text.trim();
        if (text.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nothing to save'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        await Clipboard.setData(ClipboardData(text: text));

        if (!mounted) return;
        _showMessengerPop('Copied');
        return;
      }

      if (message.type == MessageType.mediaAlbum) {
        final urls = message.mediaUrls ?? [];
        if (urls.isEmpty) {
          _showMessengerPop(
            'File not found',
            icon: Icons.error_rounded,
          );
          return;
        }

        for (var i = 0; i < urls.length; i++) {
          final source = urls[i];
          final bytes = await _readMessageFileBytes(source);
          final fileName = _fileNameFromPath(
            source,
            'photo_${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
          );

          await SaverGallery.saveImage(
            bytes,
            quality: 100,
            fileName: fileName,
            androidRelativePath: 'Pictures/MessagingApp',
            skipIfExists: false,
          );
        }

        if (!mounted) return;
        _showMessengerPop(
          'Photos saved',
          icon: Icons.download_done_rounded,
        );
        return;
      }

      final path = (message.filePath != null && message.filePath!.trim().isNotEmpty)
          ? message.filePath!.trim()
          : (message.audioPath ?? '').trim();

      if (path.isEmpty) {
        _showMessengerPop(
          'File not found',
          icon: Icons.error_rounded,
        );
        return;
      }

      final fallbackName = message.fileName ??
          '${message.type.name}_${DateTime.now().millisecondsSinceEpoch}';
      final fileName = _fileNameFromPath(path, fallbackName);

      if (message.type == MessageType.image) {
        final bytes = await _readMessageFileBytes(path);

        final result = await SaverGallery.saveImage(
          bytes,
          quality: 100,
          fileName: fileName,
          androidRelativePath: 'Pictures/MessagingApp',
          skipIfExists: false,
        );

        debugPrint('SAVE IMAGE RESULT: $result');

        if (!mounted) return;
        _showMessengerPop(
          'Photo saved',
          icon: Icons.download_done_rounded,
        );
        return;
      }

      final localPath = await _prepareLocalFileForSaving(
        sourcePath: path,
        fallbackName: fallbackName,
      );

      final androidFolder = message.type == MessageType.video
          ? 'Movies/MessagingApp'
          : 'Download/MessagingApp';

      final result = await SaverGallery.saveFile(
        filePath: localPath,
        fileName: fileName,
        androidRelativePath: androidFolder,
        skipIfExists: false,
      );

      debugPrint('SAVE FILE RESULT: $result');

      if (!mounted) return;
      _showMessengerPop(
        message.type == MessageType.video
            ? 'Video saved'
            : 'File saved',
        icon: Icons.download_done_rounded,
      );
    } catch (e) {
      debugPrint('SAVE MESSAGE ERROR: $e');

      if (!mounted) return;
      _showMessengerPop(
        'Could not save',
        icon: Icons.error_rounded,
      );
    }
  }


  void _showReactionBurst(Offset center, String emoji) {
    if (!mounted) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: _ReactionBurstOverlay(
          center: center,
          emoji: emoji,
          onCompleted: () {
            if (entry.mounted) entry.remove();
          },
        ),
      ),
    );

    Overlay.of(context).insert(entry);
  }

  void _applyReaction(ChatMessage message, String emoji, Offset burstCenter) {
    HapticFeedback.heavyImpact();
    setState(() {
      if (_messageReactions[message.id] == emoji) {
        _messageReactions.remove(message.id);
      } else {
        _messageReactions[message.id] = emoji;
      }
    });
    _showReactionBurst(burstCenter, emoji);
  }

  void _openDeleteMessageDialog(ChatMessage message) {
    HapticFeedback.mediumImpact();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF242424)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = isDark ? Colors.white : Colors.black87;
        final subColor = isDark
            ? const Color(0xFF94A3B8)
            : const Color(0xFF6B7280);
        const dangerColor = Color(0xFFEF4444);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF475569)
                        : const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: dangerColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete_rounded,
                    color: dangerColor,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Delete message?',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message.isMe
                      ? 'Choose who you want to remove this message for.'
                      : 'This will remove the message only from your chat.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: subColor,
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 18),
                _DeleteChoiceTile(
                  icon: Icons.person_remove_alt_1_rounded,
                  title: 'Delete from me',
                  subtitle: 'Remove this message only from your phone.',
                  textColor: textColor,
                  subtitleColor: subColor,
                  iconColor: dangerColor,
                  onTap: () {
                    Navigator.pop(context);
                    _deleteFromMe(message);
                  },
                ),
                if (message.isMe) ...[
                  const SizedBox(height: 10),
                  _DeleteChoiceTile(
                    icon: Icons.group_remove_rounded,
                    title: 'Delete from everyone',
                    subtitle: 'Remove this message for everyone in this chat.',
                    textColor: textColor,
                    subtitleColor: subColor,
                    iconColor: dangerColor,
                    onTap: () {
                      Navigator.pop(context);
                      _deleteFromEverybody(message);
                    },
                  ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF1877F2),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _deleteFromMe(ChatMessage message) {
    HapticFeedback.mediumImpact();
    setState(() {
      _deletingMessageIds.add(message.id);
    });

    Future.delayed(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      setState(() {
        _hiddenMessageIds.add(message.id);
        _messages.removeWhere((m) => m.id == message.id);
        widget.chat.messages.removeWhere((m) => m.id == message.id);
        _messageReactions.remove(message.id);
        _pinnedMessageIds.remove(message.id);
        _deletingMessageIds.remove(message.id);
      });

      AppChatData.notify();

      _showMessengerPop(
        'Deleted from me',
        icon: Icons.delete_rounded,
      );
    });
  }

  void _deleteFromEverybody(ChatMessage message) {
    if (!message.isMe) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can only delete your own message for everyone'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    HapticFeedback.heavyImpact();
    setState(() {
      _deletingMessageIds.add(message.id);
    });

    Future.delayed(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      setState(() {
        _hiddenMessageIds.add(message.id);
        _messages.removeWhere((m) => m.id == message.id);
        widget.chat.messages.removeWhere((m) => m.id == message.id);
        _messageReactions.remove(message.id);
        _pinnedMessageIds.remove(message.id);
        _deletingMessageIds.remove(message.id);
      });

      AppChatData.notify();

      _showMessengerPop(
        'Deleted from everyone',
        icon: Icons.delete_rounded,
      );
    });
  }

  void _pinMessage(ChatMessage message) {
    final alreadyPinned = _pinnedMessageIds.contains(message.id);

    setState(() {
      if (alreadyPinned) {
        _pinnedMessageIds.remove(message.id);
      } else {
        _pinnedMessageIds.add(message.id);
      }
    });

    _showMessengerPop(
      alreadyPinned ? 'Message unpinned' : 'Message pinned',
      icon: Icons.push_pin_rounded,
    );
  }

  Future<void> _forwardMessage(ChatMessage message) async {
    final availableChats =
        AppChatData.chats.where((chat) => chat.id != widget.chat.id).toList();

    if (availableChats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No other chats available to forward'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final selectedChat = await showModalBottomSheet<ChatItem>(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF111827)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = isDark ? Colors.white : Colors.black87;
        final subColor =
            isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Forward to',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: availableChats.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: isDark
                          ? const Color(0xFF243041)
                          : const Color(0xFFE5E7EB),
                    ),
                    itemBuilder: (context, index) {
                      final chat = availableChats[index];

                      return ListTile(
                        onTap: () => Navigator.pop(context, chat),
                        leading: CircleAvatar(
                          backgroundImage: chat.avatarUrl.trim().isNotEmpty
                              ? NetworkImage(chat.avatarUrl)
                              : null,
                          child: chat.avatarUrl.trim().isEmpty
                              ? Text(
                                  chat.name.isNotEmpty
                                      ? chat.name[0].toUpperCase()
                                      : 'U',
                                )
                              : null,
                        ),
                        title: Text(
                          chat.name,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          _previewForReply(message),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: subColor),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selectedChat == null) return;

    final forwardedMessage = _cloneForwardMessage(message);
    AppChatData.addMessage(selectedChat, forwardedMessage);
    AppChatData.notify();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Forwarded to ${selectedChat.name}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

void _openReactionPicker(
  ChatMessage message,
  BuildContext bubbleContext,
) {
  HapticFeedback.mediumImpact();

  final renderObject = bubbleContext.findRenderObject();
  final overlayObject = Overlay.of(context).context.findRenderObject();

  if (renderObject is! RenderBox || overlayObject is! RenderBox) return;

  final position = renderObject.localToGlobal(
    Offset.zero,
    ancestor: overlayObject,
  );
  final size = renderObject.size;

  int? hoveredReactionIndex;

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Message actions',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 185),
    pageBuilder: (_, __, ___) {
      return StatefulBuilder(
        builder: (context, dialogSetState) {
          final screenSize = MediaQuery.of(context).size;
          final safeTop = MediaQuery.of(context).padding.top;
          final safeBottom = MediaQuery.of(context).padding.bottom;

          const edgePadding = 12.0;
          const reactionHeight = 44.0;
          const reactionGap = 4.0;
          const menuGap = 4.0;
          const reactionItemWidth = 34.0;
          const reactionHorizontalPadding = 8.0;
          const reactionMoreWidth = 34.0;
          const reactionMoreGap = 3.0;
          const menuWidth = 205.0;
          const menuHeight = 276.0;

          double safeClamp(double value, double min, double max) {
            if (max < min) return min;
            return value.clamp(min, max).toDouble();
          }

          final bubbleLeft = position.dx;
          final bubbleTop = position.dy;
          final bubbleRight = position.dx + size.width;

          final reactionWidth = reactionHorizontalPadding +
              (_messengerReactions.length * reactionItemWidth) +
              reactionMoreGap +
              reactionMoreWidth +
              reactionHorizontalPadding;

          final bottomLimit = screenSize.height - safeBottom - 8;
          final minCloneTop = safeTop + 8 + reactionHeight + reactionGap;
          final maxCloneTop = bottomLimit - menuHeight - menuGap - size.height;

          double cloneTop;
          if (maxCloneTop >= minCloneTop) {
            cloneTop = safeClamp(
              bubbleTop - 8,
              minCloneTop,
              maxCloneTop,
            );
          } else {
            cloneTop = safeClamp(
              bubbleTop - 8,
              minCloneTop,
              bottomLimit - size.height,
            );
          }

          final reactionTop = cloneTop - reactionHeight - reactionGap;
          double menuTop = cloneTop + size.height + menuGap;
          if (menuTop + menuHeight > bottomLimit) {
            menuTop = safeClamp(
              bottomLimit - menuHeight,
              reactionTop + reactionHeight + reactionGap + 2,
              bottomLimit - menuHeight,
            );
          }

          final popupAreaWidth = screenSize.width - (edgePadding * 2);
          final cloneLeft = edgePadding;
          final cloneRight = screenSize.width - edgePadding;

          final reactionLeft = safeClamp(
            message.isMe ? cloneRight - reactionWidth : cloneLeft,
            edgePadding,
            screenSize.width - reactionWidth - edgePadding,
          );

          final menuLeft = safeClamp(
            message.isMe ? cloneRight - menuWidth : cloneLeft,
            edgePadding,
            screenSize.width - menuWidth - edgePadding,
          );

          int? hitTestReaction(Offset globalPosition) {
            final localX = globalPosition.dx - reactionLeft - reactionHorizontalPadding;
            final localY = globalPosition.dy - reactionTop - 6;
            if (localY < -22 || localY > reactionHeight + 14) return null;

            final index = (localX / reactionItemWidth).floor();
            if (index < 0 || index >= _messengerReactions.length) return null;
            return index;
          }

          Offset reactionCenterFor(int index) {
            return Offset(
              reactionLeft + reactionHorizontalPadding + (index * reactionItemWidth) + (reactionItemWidth / 2),
              reactionTop + reactionHeight / 2,
            );
          }

          void updateHover(Offset globalPosition) {
            final next = hitTestReaction(globalPosition);
            if (next != hoveredReactionIndex) {
              HapticFeedback.selectionClick();
              dialogSetState(() => hoveredReactionIndex = next);
            }
          }

          void selectReactionIndex(int index) {
            final emoji = _messengerReactions[index];
            HapticFeedback.selectionClick();
            setState(() {
              if (_messageReactions[message.id] == emoji) {
                _messageReactions.remove(message.id);
              } else {
                _messageReactions[message.id] = emoji;
              }
            });
            _showReactionBurst(reactionCenterFor(index), emoji);
            Navigator.pop(context);
          }

          Widget menuTile({
            required IconData icon,
            required String title,
            required VoidCallback onTap,
            Color? color,
            bool topDivider = false,
          }) {
            final itemColor = color ?? Colors.white;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (topDivider)
                  Container(
                    height: 1,
                    margin: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                    color: Colors.white.withOpacity(0.13),
                  ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    splashColor: Colors.white.withOpacity(0.04),
                    highlightColor: Colors.white.withOpacity(0.03),
                    child: SizedBox(
                      height: 42,
                      child: Row(
                        children: [
                          const SizedBox(width: 22),
                          Icon(icon, color: itemColor, size: 21),
                          const SizedBox(width: 18),
                          Text(
                            title,
                            style: TextStyle(
                              color: itemColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.25,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          Widget reactionTray(double openValue) {
            return GestureDetector(
              onTap: () {},
              onPanStart: (details) => updateHover(details.globalPosition),
              onPanUpdate: (details) => updateHover(details.globalPosition),
              onPanEnd: (_) {
                final index = hoveredReactionIndex;
                if (index != null) selectReactionIndex(index);
              },
              child: Transform.translate(
                offset: Offset(0, (1 - openValue) * 8),
                child: Transform.scale(
                  scale: 0.92 + (0.08 * openValue),
                  child: Opacity(
                    opacity: openValue.clamp(0.0, 1.0).toDouble(),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          height: reactionHeight,
                          padding: const EdgeInsets.symmetric(
                            horizontal: reactionHorizontalPadding,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1F2026).withOpacity(0.97),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.06),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.26),
                                blurRadius: 16,
                                offset: const Offset(0, 7),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ..._messengerReactions.asMap().entries.map((entry) {
                                final index = entry.key;
                                final emoji = entry.value;
                                final selected = _messageReactions[message.id] == emoji;
                                final hovered = hoveredReactionIndex == index;

                                return GestureDetector(
                                  onTap: () => selectReactionIndex(index),
                                  onTapDown: (_) {
                                    HapticFeedback.selectionClick();
                                    dialogSetState(() => hoveredReactionIndex = index);
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 170),
                                    curve: Curves.easeOutBack,
                                    width: 34,
                                    height: 34,
                                    alignment: Alignment.center,
                                    transform: Matrix4.identity()
                                      ..translate(0.0, hovered ? -13.0 : 0.0)
                                      ..scale(
                                        hovered
                                            ? 1.26
                                            : selected
                                                ? 1.10
                                                : 1.0,
                                      ),
                                    child: AnimatedRotation(
                                      turns: hovered ? -0.018 : 0,
                                      duration: const Duration(milliseconds: 170),
                                      curve: Curves.easeOutBack,
                                      child: AnimatedScale(
                                        scale: hovered ? 1.04 : 1.0,
                                        duration: const Duration(milliseconds: 170),
                                        curve: Curves.easeOutBack,
                                        child: Text(
                                          emoji,
                                          style: const TextStyle(
                                            fontSize: 22,
                                            height: 1,
                                            decoration: TextDecoration.none,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                              const SizedBox(width: reactionMoreGap),
                              GestureDetector(
                                onTap: () {
                                  Navigator.pop(context);
                                  _openFullEmojiReactionPicker(message);
                                },
                                child: Container(
                                  width: reactionMoreWidth,
                                  height: reactionMoreWidth,
                                  alignment: Alignment.center,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF44454D),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: Colors.white,
                                    size: 26,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                        left: message.isMe ? null : 24,
                        right: message.isMe ? 24 : null,
                        bottom: -4,
                        child: Transform.rotate(
                         angle: math.pi / 4,
                          child: Container(
                        width: 10,
                       height: 10,
                       decoration: BoxDecoration(
                       color: const Color(0xFF1F2026).withOpacity(0.97),
                       borderRadius: BorderRadius.circular(2),
                       ),
                     ),
                   ),
                 ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(context),
            onPanStart: (details) => updateHover(details.globalPosition),
            onPanUpdate: (details) => updateHover(details.globalPosition),
            onPanEnd: (_) {
              final index = hoveredReactionIndex;
              if (index != null) selectReactionIndex(index);
            },
            child: Material(
              color: Colors.transparent,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 185),
                curve: Curves.easeOutBack,
                builder: (context, value, child) {
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(
                            sigmaX: 6 * value,
                            sigmaY: 6 * value,
                          ),
                          child: Container(
                            color: Colors.black.withOpacity(0.40 * value),
                          ),
                        ),
                      ),
                      Opacity(
                        opacity: value.clamp(0.0, 1.0).toDouble(),
                        child: Transform.translate(
                          offset: Offset(0, 8 * (1 - value)),
                          child: Transform.scale(
                            scale: 0.985 + (0.015 * value),
                            alignment: message.isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: child,
                          ),
                        ),
                      ),
                    ],
                  );
                },
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 185),
                  curve: Curves.easeOutBack,
                  builder: (context, openValue, _) {
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: cloneLeft,
                          top: cloneTop,
                          width: popupAreaWidth,
                          child: IgnorePointer(
                            child: Material(
                              color: Colors.transparent,
                              child: Transform.translate(
                                offset: Offset(0, (1 - openValue) * 10),
                                child: Transform.scale(
                                  scale: 0.985 + (0.015 * openValue),
                                  alignment: message.isMe
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Align(
                                    alignment: message.isMe
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: popupAreaWidth * 0.78,
                                      ),
                                      child: _MessageBubble(
                                        message: message,
                                        isDark: true,
                                        isOnlyEmoji: _isOnlyEmoji(message.text),
                                        compact: true,
                                        onCallAction: () => _startCall(
                                          message.callType == CallEntryType.video,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        Positioned(
                          left: menuLeft,
                          top: menuTop,
                          child: GestureDetector(
                            onTap: () {},
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: BackdropFilter(
                                filter: ui.ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                                child: Transform.translate(
                                  offset: Offset(0, (1 - openValue) * 12),
                                  child: Transform.scale(
                                    scale: 0.96 + (0.04 * openValue),
                                    alignment: Alignment.topCenter,
                                    child: Container(
                                      width: menuWidth,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF151820).withOpacity(0.95),
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.08),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.25),
                                            blurRadius: 22,
                                            offset: const Offset(0, 10),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          menuTile(
                                            icon: Icons.reply_rounded,
                                            title: 'Reply',
                                            onTap: () {
                                              Navigator.pop(context);
                                              _replyTo(message);
                                            },
                                          ),
                                          menuTile(
                                          icon: message.type == MessageType.text
                                           ? Icons.copy_rounded
                                          : Icons.download_rounded,
                                              title: message.type == MessageType.text
                                                       ? 'Copy'
                                                        : 'Save',
                                                       onTap: () {
                                               Navigator.pop(context);
                                              if (message.type == MessageType.text) {
                                             _copyMessage(message);
                                                } else {
                                               _saveMessage(message);
                                               }
                                               },
                                              ),
                                          menuTile(
                                            icon: Icons.push_pin_outlined,
                                            title: _pinnedMessageIds.contains(message.id)
                                                ? 'Unpin'
                                                : 'Pin',
                                            onTap: () {
                                              Navigator.pop(context);
                                              _pinMessage(message);
                                            },
                                          ),
                                          menuTile(
                                            icon: Icons.redo_rounded,
                                            title: 'Forward',
                                            onTap: () {
                                              Navigator.pop(context);
                                              _forwardMessage(message);
                                            },
                                          ),
                                          menuTile(
                                            icon: Icons.delete_outline_rounded,
                                            title: 'Delete',
                                            color: const Color(0xFFFF4D4D),
                                            onTap: () {
                                              Navigator.pop(context);
                                              _openDeleteMessageDialog(message);
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Reaction tray is intentionally last so it always stays
                        // above the chat bubble and above the action menu.
                        Positioned(
                          left: reactionLeft,
                          top: reactionTop,
                          child: reactionTray(openValue),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
    },
    transitionBuilder: (_, animation, __, child) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
        child: child,
      );
    },
  );
}


  void _openMoreMessageActions(ChatMessage message) {
    HapticFeedback.mediumImpact();

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'More actions',
      barrierColor: Colors.black.withOpacity(0.55),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final menuColor = isDark ? const Color(0xFF242424) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black87;
        const dangerColor = Color(0xFFEF4444);
        final isPinned = _pinnedMessageIds.contains(message.id);

        return GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Material(
            color: Colors.transparent,
            child: SafeArea(
              child: Center(
                child: GestureDetector(
                  onTap: () {},
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: message.isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Container(
                        constraints: const BoxConstraints(maxWidth: 270),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF303030)
                              : const Color(0xFFEFEFF4),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Text(
                          _previewForReply(message),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: 270,
                        decoration: BoxDecoration(
                          color: menuColor,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          children: [
                            _ReactionActionTile(
                              title: message.type == MessageType.text ? 'Copy text' : 'Save to phone',
                              icon: message.type == MessageType.text
                                  ? Icons.copy_rounded
                                  : Icons.download_rounded,
                              textColor: textColor,
                              onTap: () {
                                Navigator.pop(context);
                                _saveMessage(message);
                              },
                            ),
                            _ReactionActionTile(
                              title: 'Forward',
                              icon: Icons.forward_rounded,
                              textColor: textColor,
                              onTap: () {
                                Navigator.pop(context);
                                _forwardMessage(message);
                              },
                            ),
                            _ReactionActionTile(
                              title: isPinned ? 'Unpin' : 'Pin',
                              icon: Icons.push_pin_rounded,
                              textColor: textColor,
                              onTap: () {
                                Navigator.pop(context);
                                _pinMessage(message);
                              },
                            ),
                            _ReactionActionTile(
                              title: 'Delete',
                              icon: Icons.delete_rounded,
                              textColor: dangerColor,
                              onTap: () {
                                Navigator.pop(context);
                                _openDeleteMessageDialog(message);
                              },
                            ),
                            Divider(
                              height: 1,
                              thickness: 6,
                              color: isDark
                                  ? const Color(0xFF6B7280)
                                  : const Color(0xFFD1D5DB),
                            ),
                            _ReactionActionTile(
                              title: 'More',
                              icon: Icons.arrow_back_rounded,
                              textColor: textColor,
                              showDivider: false,
                              onTap: () {
                                Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutBack,
            ),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _openFullEmojiReactionPicker(ChatMessage message) async {
    final controller = TextEditingController();

    final selectedEmoji = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF111827)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.62,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Choose reaction',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: EmojiPicker(
                    textEditingController: controller,
                    onEmojiSelected: (category, emoji) {
                      Navigator.pop(context, emoji.emoji);
                    },
                    config: Config(
                      height: 300,
                      checkPlatformCompatibility: true,
                      emojiViewConfig: EmojiViewConfig(
                        columns: 8,
                        emojiSizeMax: 30,
                        backgroundColor:
                            isDark ? const Color(0xFF111827) : Colors.white,
                      ),
                      categoryViewConfig: CategoryViewConfig(
                        backgroundColor:
                            isDark ? const Color(0xFF111827) : Colors.white,
                        iconColor: const Color(0xFF94A3B8),
                        iconColorSelected: const Color(0xFF1877F2),
                        indicatorColor: const Color(0xFF1877F2),
                      ),
                      bottomActionBarConfig: BottomActionBarConfig(
                        enabled: false,
                        backgroundColor:
                            isDark ? const Color(0xFF111827) : Colors.white,
                      ),
                      searchViewConfig: SearchViewConfig(
                        backgroundColor:
                            isDark ? const Color(0xFF111827) : Colors.white,
                        buttonIconColor: const Color(0xFF1877F2),
                        hintText: 'Search emoji',
                      ),
                      skinToneConfig: const SkinToneConfig(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    controller.dispose();

    if (selectedEmoji == null || selectedEmoji.trim().isEmpty) return;

    HapticFeedback.selectionClick();

    setState(() {
      _messageReactions[message.id] = selectedEmoji;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1800,
    );

    if (file == null) return;

    final conversationId = int.tryParse(widget.chat.id);
    if (conversationId == null) {
      _append(
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          type: MessageType.image,
          text: '',
          isMe: true,
          sentAt: DateTime.now(),
          isSeen: true,
          filePath: file.path,
          fileName: file.name,
          replyToMessageId: _replyingTo?.id,
          replyPreview:
              _replyingTo == null ? null : _previewForReply(_replyingTo!),
          replyToMe: _replyingTo?.isMe,
        ),
      );
      return;
    }

    final provider = _chatProvider;

    await provider.sendImage(
      conversationId: conversationId,
      image: File(file.path),
    );

    if (!mounted) return;

    setState(() {
      _replyingTo = null;
      _messages = _sortedProviderMessages(provider)
          .where((m) => !_hiddenMessageIds.contains(m.id))
          .where((m) => m.type != MessageType.text || m.text.trim().isNotEmpty)
          .toList();
    });

    _smartScrollToBottom();
  }

  Future<void> _pickMultipleImages() async {
    final files = await _picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 1800,
    );

    if (files.isEmpty) return;

    final conversationId = int.tryParse(widget.chat.id);

    if (conversationId == null) {
      final message = ChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        type: MessageType.mediaAlbum,
        text: '',
        isMe: true,
        sentAt: DateTime.now(),
        isSeen: true,
        mediaUrls: files.map((file) => file.path).toList(),
        replyToMessageId: _replyingTo?.id,
        replyPreview:
            _replyingTo == null ? null : _previewForReply(_replyingTo!),
        replyToMe: _replyingTo?.isMe,
      );

      setState(() {
        _messages.add(message);
        _replyingTo = null;
        _showEmoji = false;
      });

      AppChatData.addMessage(widget.chat, message);

      AppChatData.notify();
      _smartScrollToBottom();
      return;
    }

    final provider = _chatProvider;

    try {
      await provider.sendImages(
        conversationId: conversationId,
        images: files.map((file) => File(file.path)).toList(),
      );

      if (!mounted) return;

      setState(() {
        _replyingTo = null;
        _showEmoji = false;
        _messages = _sortedProviderMessages(provider)
            .where((m) => !_hiddenMessageIds.contains(m.id))
            .where((m) => m.type != MessageType.text || m.text.trim().isNotEmpty)
            .toList();
      });

      _smartScrollToBottom();
    } catch (e) {
      debugPrint('PICK MULTIPLE IMAGES ERROR: $e');

      if (!mounted) return;
      _showMessengerPop(
        'Could not send photos',
        icon: Icons.error_rounded,
      );
    }
  }

  Future<void> _pickMultipleFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
    );

    if (result == null || result.files.isEmpty) return;

    final selectedFiles = result.files
        .where((file) => file.path != null && file.path!.trim().isNotEmpty)
        .toList();

    if (selectedFiles.isEmpty) {
      _showMessengerPop(
        'No file selected',
        icon: Icons.error_rounded,
      );
      return;
    }

    final conversationId = int.tryParse(widget.chat.id);

    if (conversationId == null) {
      setState(() {
        for (final pickedFile in selectedFiles) {
          final path = pickedFile.path!;
          final message = ChatMessage(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            type: MessageType.file,
            text: '',
            isMe: true,
            sentAt: DateTime.now(),
            isSeen: true,
            filePath: path,
            fileName: pickedFile.name,
            fileSizeBytes: pickedFile.size,
            replyToMessageId: _replyingTo?.id,
            replyPreview:
                _replyingTo == null ? null : _previewForReply(_replyingTo!),
            replyToMe: _replyingTo?.isMe,
          );

          _messages.add(message);
          AppChatData.addMessage(widget.chat, message);
        }

        _replyingTo = null;
        _showEmoji = false;
      });

      AppChatData.notify();
      _smartScrollToBottom();
      return;
    }

    final provider = _chatProvider;

    try {
      await provider.sendFiles(
        conversationId: conversationId,
        files: selectedFiles.map((file) => File(file.path!)).toList(),
      );

      if (!mounted) return;

      setState(() {
        _replyingTo = null;
        _showEmoji = false;
        _messages = _sortedProviderMessages(provider)
            .where((m) => !_hiddenMessageIds.contains(m.id))
            .where((m) => m.type != MessageType.text || m.text.trim().isNotEmpty)
            .toList();
      });

      _smartScrollToBottom();
    } catch (e) {
      debugPrint('PICK MULTIPLE FILES ERROR: $e');

      if (!mounted) return;
      _showMessengerPop(
        'Could not send files',
        icon: Icons.error_rounded,
      );
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording) return;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return;

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(const RecordConfig(), path: path);

    _recordTicker?.cancel();

    setState(() {
      _isRecording = true;
      _recordDuration = Duration.zero;
      _currentRecordPath = path;
      _showEmoji = false;
    });

    _recordTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() {
        _recordDuration += const Duration(milliseconds: 200);
      });
    });
  }

  Future<void> _stopAndSendRecording() async {
    _recordTicker?.cancel();

    if (!_isRecording) return;

    final duration = _recordDuration.inMilliseconds <= 0
        ? const Duration(seconds: 1)
        : _recordDuration;

    final path = await _recorder.stop();

    if (!mounted) return;

    setState(() {
      _isRecording = false;
    });

    if (path == null || path.trim().isEmpty) {
      setState(() {
        _recordDuration = Duration.zero;
        _currentRecordPath = null;
      });
      return;
    }

    final conversationId = int.tryParse(widget.chat.id);
    if (conversationId == null) {
      _append(
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          type: MessageType.audio,
          text: 'Voice message',
          isMe: true,
          sentAt: DateTime.now(),
          isSeen: true,
          audioPath: path,
          audioDuration: duration,
          replyToMessageId: _replyingTo?.id,
          replyPreview:
              _replyingTo == null ? null : _previewForReply(_replyingTo!),
          replyToMe: _replyingTo?.isMe,
        ),
      );
      setState(() {
        _recordDuration = Duration.zero;
        _currentRecordPath = null;
      });
      return;
    }

    final provider = _chatProvider;

    await provider.sendAudio(
      conversationId: conversationId,
      audio: File(path),
      duration: duration.inMilliseconds / 1000,
    );

    if (!mounted) return;

    setState(() {
      _recordDuration = Duration.zero;
      _currentRecordPath = null;
      _replyingTo = null;
      _messages = _sortedProviderMessages(provider)
        .where((m) => !_hiddenMessageIds.contains(m.id))
        .where((m) => m.type != MessageType.text || m.text.trim().isNotEmpty)
        .toList();
    });

    _smartScrollToBottom();
  }

  Future<void> _cancelRecording() async {
    _recordTicker?.cancel();

    if (_isRecording) {
      await _recorder.stop();
    }

    if (!mounted) return;

    setState(() {
      _isRecording = false;
      _recordDuration = Duration.zero;
      _currentRecordPath = null;
    });
  }

Future<void> _startCall(bool isVideo) async {
  final currentUserId = await ApiClient.storage.read(key: 'user_id');
  final accessToken = await ApiClient.storage.read(key: 'access');
  final currentUserName =
      (await ApiClient.storage.read(key: 'user_name'))?.trim().isNotEmpty == true
          ? (await ApiClient.storage.read(key: 'user_name'))!.trim()
          : 'You';
  final currentUserAvatar =
      (await ApiClient.storage.read(key: 'user_avatar'))?.trim() ?? '';

  if (currentUserId == null || currentUserId.trim().isEmpty) {
    debugPrint('CALL ERROR: currentUserId missing');
    return;
  }

  if (accessToken == null || accessToken.trim().isEmpty) {
    debugPrint('CALL ERROR: accessToken missing');
    return;
  }

  final conversationId = int.tryParse(widget.chat.id);

  if (conversationId == null) {
    debugPrint('CALL ERROR: invalid conversation id ${widget.chat.id}');
    return;
  }

  String? receiverId;

  for (final member in widget.chat.members) {
    final memberId = member.id.toString();
    if (memberId != currentUserId.toString()) {
      receiverId = memberId;
      break;
    }
  }

  debugPrint('======================');
  debugPrint('CURRENT USER: $currentUserId');
  debugPrint('RECEIVER: $receiverId');
  debugPrint('CONVERSATION: $conversationId');
  debugPrint('CHAT MEMBERS: ${widget.chat.members.length}');
  debugPrint('======================');

  if (receiverId == null || receiverId.trim().isEmpty) {
    debugPrint('CALL ERROR: receiver id not found');
    return;
  }

  GlobalCallHandler.connectCallSocket(
    url:
        'ws://192.168.1.97:8000/ws/call/$conversationId/?token=${Uri.encodeComponent(accessToken.trim())}',
    currentUserId: currentUserId.trim(),
  );

  AppChatData.addCallLog(
    chat: widget.chat,
    type: isVideo ? CallEntryType.video : CallEntryType.voice,
    status: CallEntryStatus.outgoing,
  );

  if (!mounted) return;

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => CallScreen(
        name: widget.chat.name,
        avatarUrl: widget.chat.avatarUrl,
        isVideoCall: isVideo,
        chat: widget.chat,
        currentUserId: currentUserId.trim(),
        currentUserName: currentUserName,
        currentUserAvatar: currentUserAvatar,
        receiverId: receiverId!,
        isCaller: true,
        conversationId: widget.chat.id,
      ),
    ),
  );
}

  Future<void> _openProfile() async {
    final currentUserId = (await ApiClient.storage.read(key: 'user_id')) ?? '';
    final storedName = (await ApiClient.storage.read(key: 'user_name')) ?? '';
    final currentUserName = storedName.trim().isEmpty ? 'You' : storedName.trim();
    final currentUserAvatar =
        ((await ApiClient.storage.read(key: 'user_avatar')) ?? '').trim();

    if (!mounted) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatSettingsScreen(
          chat: widget.chat,
          themeColor: const Color(0xFF1877F2),
        ),
      ),
    );

    if (!mounted) return;

    if (result is String && result.isNotEmpty) {
      final index = _messages.indexWhere((m) => m.id == result);
      if (index != -1 && _scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollController.animateTo(
            index * 110.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        });
      }
    }

    setState(() {
      _syncLocalMessages();
    });
  }

  String _time(DateTime dt) => DateFormat('h:mm a').format(dt);

  String _recordText(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _dateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final value = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(value).inDays;

    if (diff == 0) return 'TODAY';
    if (diff == 1) return 'YESTERDAY';
    return DateFormat('EEE AT h:mm a').format(dt).toUpperCase();
  }

  bool _showDateHeader(int index) {
    if (index == 0) return true;

    final current = _messages[index].sentAt;
    final previous = _messages[index - 1].sentAt;

    return current.year != previous.year ||
        current.month != previous.month ||
        current.day != previous.day;
  }

  Widget _buildPinnedMessagesBar(bool isDark) {
    if (_pinnedMessageIds.isEmpty) return const SizedBox.shrink();

    final pinnedMessages = _messages
        .where((message) => _pinnedMessageIds.contains(message.id))
        .toList();

    if (pinnedMessages.isEmpty) return const SizedBox.shrink();

    final pinned = pinnedMessages.last;

    return InkWell(
      onTap: () {
        final index = _messages.indexWhere((m) => m.id == pinned.id);
        if (index != -1 && _scrollController.hasClients) {
          _scrollController.animateTo(
            index * 110.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111827) : Colors.white,
          border: Border(
            bottom: BorderSide(
              color: isDark ? const Color(0xFF243041) : const Color(0xFFE5E7EB),
            ),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.push_pin_rounded,
              color: Color(0xFF1877F2),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _previewForReply(pinned),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${pinnedMessages.length}',
              style: const TextStyle(
                color: Color(0xFF1877F2),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomAppBar(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF0B1220) : Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: Color(0xFF1877F2),
                size: 28,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _openProfile,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 21,
                            backgroundImage:
                                widget.chat.avatarUrl.trim().isNotEmpty
                                    ? NetworkImage(widget.chat.avatarUrl)
                                    : null,
                            child: widget.chat.avatarUrl.trim().isEmpty
                                ? Text(
                                    widget.chat.name.isNotEmpty
                                        ? widget.chat.name[0].toUpperCase()
                                        : 'U',
                                  )
                                : null,
                          ),
                          if (widget.chat.isOnline)
                            Positioned(
                              right: -1,
                              bottom: -1,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF22C55E),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.chat.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            Text(
                              widget.chat.isOnline ? 'Active now' : 'Offline',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
IconButton(
  onPressed: () => _startCall(false),
  icon: const Icon(
    Icons.call_rounded,
    color: Color(0xFF1877F2),
  ),
),

IconButton(
  onPressed: () => _startCall(true),
  icon: const Icon(
    Icons.videocam_rounded,
    color: Color(0xFF1877F2),
  ),
),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer(bool isDark) {
    final hasText = _messageController.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.only(left: 4, right: 4, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0B1220) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF243041) : const Color(0xFFE5E7EB),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyingTo != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF1F2F6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 34,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1877F2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _replyingTo!.isMe
                                ? 'Replying to yourself'
                                : 'Replying to ${widget.chat.name}',
                            style: const TextStyle(
                              color: Color(0xFF1877F2),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _previewForReply(_replyingTo!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _cancelReply,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            if (_isRecording)
  _MessengerRecordingComposer(
    durationText: _recordText(_recordDuration),
    onCancel: _cancelRecording,
    onSend: () {
      HapticFeedback.mediumImpact();
      _stopAndSendRecording();
    },
  )

            else
              Row(
                children: [
                  _MessengerCameraButton(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _pickImage(ImageSource.camera);
                    },
                  ),
                  _MessengerPlainIcon(
                    icon: Icons.photo_library_rounded,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _pickMultipleImages();
                    },
                  ),
                  _MessengerPlainIcon(
                    icon: Icons.attach_file_rounded,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _pickMultipleFiles();
                    },
                  ),
                  _MessengerPlainIcon(
                    icon: Icons.mic_rounded,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _startRecording();
                    },
                  ),
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF1F2F6),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              onSubmitted: null,
                              onChanged: (_) {
                                setState(() {});

                                // Disabled for now: your backend is treating typing
                                // socket events as blank messages. Re-enable only
                                // after the backend consumer handles typing separately.
                                // _chatProvider.sendSocketTyping(
                                //   typing: _messageController.text.trim().isNotEmpty,
                                // );
                              },
                              onTap: () {
                                if (_showEmoji) {
                                  setState(() => _showEmoji = false);
                                }
                                _scrollToBottomAfterKeyboard();
                              },
                              minLines: 1,
                              maxLines: 5,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Aa',
                                isDense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 9),
                                hintStyle: TextStyle(
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF6B7280),
                                ),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () {
                              HapticFeedback.lightImpact();
                              FocusScope.of(context).unfocus();

                              setState(() {
                                _showEmoji = !_showEmoji;
                              });

                              Future.delayed(
                                const Duration(milliseconds: 280),
                                () {
                                  if (!mounted) return;
                                  _animateBottom();
                                },
                              );
                            },
                            child: SizedBox(
                              width: 32,
                              height: 32,
                              child: Icon(
                                _showEmoji
                                    ? Icons.keyboard_alt_outlined
                                    : Icons.emoji_emotions_outlined,
                                color: const Color(0xFF1877F2),
                                size: 24,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _MessengerSendLikeButton(
                    hasText: hasText,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      hasText ? _sendText() : _sendLike();
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmojiPicker(bool isDark) {
    return SizedBox(
      height: 320,
      child: EmojiPicker(
        textEditingController: _messageController,
        onEmojiSelected: (category, emoji) {
          setState(() {});
          Future.delayed(const Duration(milliseconds: 80), () {
            if (!mounted) return;
            _animateBottom();
          });
        },
        onBackspacePressed: () {
          final text = _messageController.text;
          if (text.isEmpty) return;

          _messageController.text = text.characters.skipLast(1).toString();
          _messageController.selection = TextSelection.fromPosition(
            TextPosition(offset: _messageController.text.length),
          );

          setState(() {});
        },
        config: Config(
          height: 320,
          checkPlatformCompatibility: true,
          emojiViewConfig: EmojiViewConfig(
            columns: 8,
            emojiSizeMax: 28 *
                (foundation.defaultTargetPlatform == TargetPlatform.iOS
                    ? 1.20
                    : 1.0),
            backgroundColor: isDark ? const Color(0xFF111827) : Colors.white,
          ),
          categoryViewConfig: CategoryViewConfig(
            backgroundColor: isDark ? const Color(0xFF111827) : Colors.white,
            iconColor: const Color(0xFF94A3B8),
            iconColorSelected: const Color(0xFF1877F2),
            indicatorColor: const Color(0xFF1877F2),
          ),
          bottomActionBarConfig: BottomActionBarConfig(
            backgroundColor: isDark ? const Color(0xFF111827) : Colors.white,
            buttonColor: const Color(0xFF1877F2),
            buttonIconColor: Colors.white,
          ),
          skinToneConfig: const SkinToneConfig(),
          searchViewConfig: SearchViewConfig(
            backgroundColor: isDark ? const Color(0xFF111827) : Colors.white,
            buttonIconColor: const Color(0xFF1877F2),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageItem({
    required ChatMessage message,
    required int index,
    required bool isDark,
  }) {
    final showAvatar = !message.isMe &&
        (index == _messages.length - 1 ||
            _messages[index + 1].isMe ||
            _messages[index + 1].sentAt.day != message.sentAt.day);

    final reaction = _messageReactions[message.id];
    final isDeleting = _deletingMessageIds.contains(message.id);

    final messageRow = Column(
      children: [
        if (_showDateHeader(index))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _dateLabel(message.sentAt),
              style: TextStyle(
                fontSize: 12,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Builder(
          builder: (bubbleContext) {
            return _SwipeToReply(
              isMe: message.isMe,
              enabled: true,
              onReply: () {
                HapticFeedback.lightImpact();
                _replyTo(message);
              },
              onTapMessage: null,
              onLongPress: () {
                _openReactionPicker(message, bubbleContext);
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: message.isMe
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                children: [
                  if (!message.isMe)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: showAvatar
                          ? Stack(
                              clipBehavior: Clip.none,
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundImage: widget.chat.avatarUrl.trim().isNotEmpty
                                      ? NetworkImage(widget.chat.avatarUrl)
                                      : null,
                                  child: widget.chat.avatarUrl.trim().isEmpty
                                      ? Text(
                                          widget.chat.name.isNotEmpty
                                              ? widget.chat.name[0].toUpperCase()
                                              : 'U',
                                          style: const TextStyle(fontSize: 12),
                                        )
                                      : null,
                                ),
                                if (widget.chat.isOnline)
                                  Positioned(
                                    right: -1,
                                    bottom: -1,
                                    child: Container(
                                      width: 9,
                                      height: 9,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF22C55E),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 1.5),
                                      ),
                                    ),
                                  ),
                              ],
                            )
                          : const SizedBox(width: 28),
                    ),
                  Flexible(
                    child: AnimatedScale(
                      scale: 1,
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOutBack,
                      child: Column(
                        crossAxisAlignment: message.isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(22),
                                  boxShadow: null,
                                ),
                                child: _MessageBubble(
                                  message: message,
                                  isDark: isDark,
                                  isOnlyEmoji: _isOnlyEmoji(message.text),
                                  onCallAction: () => _startCall(
                                    message.callType == CallEntryType.video,
                                  ),
                                ),
                              ),
                              if (reaction != null)
                                Positioned(
                                  right: message.isMe ? 4 : null,
                                  left: message.isMe ? null : 4,
                                  bottom: -17,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB),
                                      ),
                                      boxShadow: [
                                        BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 8),
                                      ],
                                    ),
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween(begin: 0.35, end: 1),
                                      duration: const Duration(milliseconds: 440),
                                      curve: Curves.elasticOut,
                                      builder: (context, value, child) {
                                        return Transform.scale(scale: value, child: child);
                                      },
                                      child: Text(reaction, style: const TextStyle(fontSize: 16)),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          SizedBox(height: reaction == null ? 4 : 18),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              _time(message.sentAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
      ],
    );

    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        opacity: isDeleting ? 0 : 1,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInBack,
          scale: isDeleting ? 0.82 : 1,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInCubic,
            offset: isDeleting ? Offset(message.isMe ? 0.18 : -0.18, 0) : Offset.zero,
            child: isDeleting ? const SizedBox.shrink() : messageRow,
          ),
        ),
      ),
    );
  }
   
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();

    _messages = _sortedProviderMessages(provider)
        .where((m) => !_hiddenMessageIds.contains(m.id))
        .where((m) => m.type != MessageType.text || m.text.trim().isNotEmpty)
        .toList();

    if (_messages.length != _lastRenderedMessageCount) {
      _lastRenderedMessageCount = _messages.length;
      _smartScrollToBottom();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
  final bg = isDark ? const Color(0xFF0B1220) : const Color(0xFFF5F5F5);
  final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          _buildCustomAppBar(isDark),
          _buildPinnedMessagesBar(isDark),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _buildMessageItem(
                  message: _messages[index],
                  index: index,
                  isDark: isDark,
                );
              },
            ),
          ),
          AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: keyboardHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildComposer(isDark),
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: (_showEmoji && keyboardHeight == 0)
                      ? AnimatedSlide(
                          offset: Offset.zero,
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          child: AnimatedOpacity(
                            opacity: 1,
                            duration: const Duration(milliseconds: 180),
                            child: _buildEmojiPicker(isDark),
                          ),
                        )
                      : const SizedBox(height: 0),
                ),
              ],
            ),
          ),
          
        ],
      ),
    );
  }
}

class _DeleteChoiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color textColor;
  final Color subtitleColor;
  final Color iconColor;
  final VoidCallback onTap;

  const _DeleteChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.textColor,
    required this.subtitleColor,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF303030) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: subtitleColor,
                      fontSize: 13,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessengerCameraButton extends StatelessWidget {
  final VoidCallback onTap;

  const _MessengerCameraButton({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: Color(0xFF1877F2),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.camera_alt_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
      ),
    );
  }
}

class _MessengerPlainIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  const _MessengerPlainIcon({
    required this.icon,
    required this.onTap,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(
          icon,
          color: const Color(0xFF1877F2),
          size: size,
        ),
      ),
    );
  }
}

class _MessengerSendLikeButton extends StatelessWidget {
  final bool hasText;
  final VoidCallback onTap;

  const _MessengerSendLikeButton({
    required this.hasText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      transitionBuilder: (child, animation) {
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
          ),
          child: child,
        );
      },
      child: InkWell(
        key: ValueKey(hasText),
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            hasText ? Icons.send_rounded : Icons.thumb_up_alt_rounded,
            color: const Color(0xFF1877F2),
            size: hasText ? 26 : 32,
          ),
        ),
      ),
    );
  }
}

class _MessengerRecordingComposer extends StatelessWidget {
  final String durationText;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  const _MessengerRecordingComposer({
    required this.durationText,
    required this.onCancel,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          InkWell(
            onTap: onCancel,
            borderRadius: BorderRadius.circular(999),
            child: const SizedBox(
              width: 42,
              height: 42,
              child: Icon(
                Icons.delete_rounded,
                color: Color(0xFFEF4444),
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF2F5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.mic_rounded,
                    color: Color(0xFFEF4444),
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    durationText,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: _MessengerRecordingWave(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: onSend,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFF1877F2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessengerRecordingWave extends StatefulWidget {
  const _MessengerRecordingWave();

  @override
  State<_MessengerRecordingWave> createState() =>
      _MessengerRecordingWaveState();
}

class _MessengerRecordingWaveState extends State<_MessengerRecordingWave> {
  Timer? _timer;
  final math.Random _random = math.Random();
  late List<double> _bars;

  @override
  void initState() {
    super.initState();
    _bars = List.generate(22, (_) => 0.25 + _random.nextDouble() * 0.75);

    _timer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted) return;
      setState(() {
        _bars = List.generate(22, (_) => 0.25 + _random.nextDouble() * 0.75);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _bars.map((value) {
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1.2),
            height: 5 + (22 * value),
            decoration: BoxDecoration(
              color: const Color(0xFF1877F2).withOpacity(0.85),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _MessengerMicButton extends StatefulWidget {
  final VoidCallback onStart;
  final VoidCallback onStopSend;
  final VoidCallback onCancel;

  const _MessengerMicButton({
    required this.onStart,
    required this.onStopSend,
    required this.onCancel,
  });

  @override
  State<_MessengerMicButton> createState() => _MessengerMicButtonState();
}

class _MessengerMicButtonState extends State<_MessengerMicButton> {
  double _dragX = 0;
  bool _holding = false;

  void _start(LongPressStartDetails details) {
    setState(() {
      _holding = true;
      _dragX = 0;
    });
    widget.onStart();
  }

  void _move(LongPressMoveUpdateDetails details) {
    setState(() {
      _dragX = details.offsetFromOrigin.dx.clamp(-90.0, 0.0).toDouble();
    });
  }

  void _end(LongPressEndDetails details) {
    final shouldCancel = _dragX <= -70;

    setState(() {
      _holding = false;
      _dragX = 0;
    });

    if (shouldCancel) {
      widget.onCancel();
    } else {
      widget.onStopSend();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: _start,
      onLongPressMoveUpdate: _move,
      onLongPressEnd: _end,
      child: AnimatedScale(
        scale: _holding ? 1.18 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutBack,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (_holding)
              Positioned(
                right: 34,
                child: Opacity(
                  opacity: 0.85,
                  child: Row(
                    children: const [
                      Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 13,
                        color: Color(0xFF6B7280),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Slide to cancel',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Transform.translate(
              offset: Offset(_dragX, 0),
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      _holding ? const Color(0xFF1877F2) : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.mic_rounded,
                  color: _holding ? Colors.white : const Color(0xFF1877F2),
                  size: _holding ? 24 : 25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveWaveform extends StatefulWidget {
  final bool isActive;
  final bool danger;

  const _LiveWaveform({
    required this.isActive,
    required this.danger,
  });

  @override
  State<_LiveWaveform> createState() => _LiveWaveformState();
}

class _LiveWaveformState extends State<_LiveWaveform> {
  Timer? _timer;
  final math.Random _random = math.Random();
  late List<double> _bars;

  @override
  void initState() {
    super.initState();
    _bars = List.generate(18, (_) => 0.3 + _random.nextDouble() * 0.7);
    _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted || !widget.isActive) return;
      setState(() {
        _bars = List.generate(18, (_) => 0.2 + _random.nextDouble() * 0.8);
      });
    });
  }

  @override
  void didUpdateWidget(covariant _LiveWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _start();
    } else if (!widget.isActive && oldWidget.isActive) {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.danger ? const Color(0xFFEF4444) : Colors.white;

    return SizedBox(
      height: 26,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: _bars
            .map(
              (v) => Expanded(
                child: Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: 3,
                    height: 8 + (18 * v),
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}


class _MediaAlbumGrid extends StatelessWidget {
  final List<String> images;
  final bool isMe;
  final void Function(int index)? onTap;

  const _MediaAlbumGrid({
    required this.images,
    required this.isMe,
    this.onTap,
  });

  static const double _gap = 2;
  static const double _width = 244;
  static const double _height = 196;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return Container(
        width: _width,
        height: 150,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.22),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.photo_library_outlined),
      );
    }

    final total = images.length;
    final visibleCount = total > 4 ? 4 : total;
    final visibleImages = images.take(visibleCount).toList();
    final extraCount = total - 4;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: total == 1 ? 228 : _width,
        height: total == 1 ? 228 : _height,
        child: _buildLayout(visibleImages, extraCount),
      ),
    );
  }

  Widget _buildLayout(List<String> visibleImages, int extraCount) {
    final total = images.length;

    if (total == 1) {
      return _imageTile(images[0], 0);
    }

    if (total == 2) {
      return Row(
        children: [
          Expanded(child: _imageTile(images[0], 0)),
          const SizedBox(width: _gap),
          Expanded(child: _imageTile(images[1], 1)),
        ],
      );
    }

    if (total == 3) {
      return Row(
        children: [
          Expanded(
            flex: 2,
            child: _imageTile(images[0], 0),
          ),
          const SizedBox(width: _gap),
          Expanded(
            child: Column(
              children: [
                Expanded(child: _imageTile(images[1], 1)),
                const SizedBox(height: _gap),
                Expanded(child: _imageTile(images[2], 2)),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _imageTile(images[0], 0)),
              const SizedBox(width: _gap),
              Expanded(child: _imageTile(images[1], 1)),
            ],
          ),
        ),
        const SizedBox(height: _gap),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _imageTile(images[2], 2)),
              const SizedBox(width: _gap),
              Expanded(
                child: _imageTile(
                  images[3],
                  3,
                  extraCount: extraCount,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _imageTile(
    String path,
    int index, {
    int extraCount = 0,
  }) {
    return GestureDetector(
      onTap: () => onTap?.call(index),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildImage(path),
          if (extraCount > 0)
            Container(
              color: Colors.black.withOpacity(0.52),
              alignment: Alignment.center,
              child: Text(
                '+$extraCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImage(String path) {
    final lower = path.toLowerCase().trim();
    final isNetwork = lower.startsWith('http://') || lower.startsWith('https://');

    if (isNetwork) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _brokenImage(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            color: Colors.grey.withOpacity(0.22),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      );
    }

    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _brokenImage(),
    );
  }

  Widget _brokenImage() {
    return Container(
      color: Colors.grey.withOpacity(0.25),
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image_rounded),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isDark;
  final bool isOnlyEmoji;
  final VoidCallback? onCallAction;
  final bool compact;

  const _MessageBubble({
    required this.message,
    required this.isDark,
    required this.isOnlyEmoji,
    this.onCallAction,
    this.compact = false,
  });

  String _sizeText(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final outgoingColor = const Color(0xFF1D4ED8);
    final incomingColor =
        isDark ? const Color(0xFF1E293B) : const Color(0xFFEFEFF4);

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(message.isMe ? 18 : 6),
      bottomRight: Radius.circular(message.isMe ? 6 : 18),
    );

    Widget? replyBlock;

    if (message.replyPreview != null &&
        message.replyPreview!.trim().isNotEmpty) {
      replyBlock = Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: message.isMe
              ? Colors.white.withOpacity(0.18)
              : (isDark ? const Color(0xFF111827) : Colors.white),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.replyToMe == true ? 'Replied to you' : 'Reply',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: message.isMe ? Colors.white : const Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              message.replyPreview!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: message.isMe
                    ? Colors.white
                    : (isDark ? Colors.white : Colors.black87),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    switch (message.type) {
      case MessageType.text:
        if (isOnlyEmoji && replyBlock == null) {
          return Padding(
            padding: EdgeInsets.only(
              left: compact ? 0 : (message.isMe ? 50 : 0),
              right: compact ? 0 : (message.isMe ? 0 : 50),
            ),
            child: Text(
              message.text,
              style: const TextStyle(fontSize: 42),
            ),
          );
        }

        return Container(
          margin: EdgeInsets.only(
            left: compact ? 0 : (message.isMe ? 50 : 0),
            right: compact ? 0 : (message.isMe ? 0 : 50),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: message.isMe ? outgoingColor : incomingColor,
            borderRadius: radius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (replyBlock != null) replyBlock,
              Text(
                message.text,
                style: TextStyle(
                  color: message.isMe
                      ? Colors.white
                      : (isDark ? Colors.white : Colors.black87),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );

      case MessageType.audio:
        return Container(
          margin: EdgeInsets.only(
            left: compact ? 0 : (message.isMe ? 50 : 0),
            right: compact ? 0 : (message.isMe ? 0 : 50),
          ),
          child: _AudioBubble(
            message: message,
            isDark: isDark,
            replyBlock: replyBlock,
          ),
        );

      case MessageType.mediaAlbum:
        return Container(
          margin: EdgeInsets.only(
            left: compact ? 0 : (message.isMe ? 50 : 0),
            right: compact ? 0 : (message.isMe ? 0 : 50),
          ),
          child: Column(
            crossAxisAlignment: message.isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (replyBlock != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: replyBlock,
                ),
              _MediaAlbumGrid(
                images: message.mediaUrls ?? const [],
                isMe: message.isMe,
                onTap: (index) {
                  // Add your fullscreen viewer here later.
                },
              ),
              if (message.text.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: message.isMe ? outgoingColor : incomingColor,
                      borderRadius: radius,
                    ),
                    child: Text(
                      message.text,
                      style: TextStyle(
                        color: message.isMe
                            ? Colors.white
                            : isDark
                                ? Colors.white
                                : Colors.black87,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );

      case MessageType.image:
      case MessageType.video:
      case MessageType.file:
        return Container(
          margin: EdgeInsets.only(
            left: compact ? 0 : (message.isMe ? 50 : 0),
            right: compact ? 0 : (message.isMe ? 0 : 50),
          ),
          child: Column(
            crossAxisAlignment: message.isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (replyBlock != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: replyBlock,
                ),

              DynamicMessageMedia(
                message: message,
                isDark: isDark,
              ),

              if (message.text.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: message.isMe
                          ? outgoingColor
                          : incomingColor,
                      borderRadius: radius,
                    ),
                    child: Text(
                      message.text,
                      style: TextStyle(
                        color: message.isMe
                            ? Colors.white
                            : isDark
                                ? Colors.white
                                : Colors.black87,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );

      case MessageType.call:
        final isMissed = message.callAnswered == false;
        final title = isMissed
            ? (message.callType == CallEntryType.video
                ? 'Missed video call'
                : 'Missed audio call')
            : (message.callType == CallEntryType.video
                ? 'Video call'
                : 'Audio call');

        final subtitle = message.callDuration != null
            ? '${message.callDuration!.inSeconds} sec'
            : DateFormat('h:mm a').format(message.sentAt);

        return Container(
          width: 260,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFEFF4),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            children: [
              if (replyBlock != null) replyBlock,
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: isMissed
                          ? const Color(0xFFEF4444)
                          : const Color(0xFFBDBDBD),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      message.callType == CallEntryType.video
                          ? Icons.videocam_rounded
                          : Icons.call_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: onCallAction,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  height: 46,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF111827) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    isMissed ? 'Call back' : 'Call again',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }
}

class _AudioBubble extends StatefulWidget {
  final ChatMessage message;
  final bool isDark;
  final Widget? replyBlock;

  const _AudioBubble({
    required this.message,
    required this.isDark,
    this.replyBlock,
  });

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  late final AudioPlayer _player;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  bool _playing = false;
  bool _loading = true;
  bool _dragging = false;
  double _dragProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();

    _positionSub = _player.positionStream.listen((position) {
      if (!mounted || _dragging) return;
      setState(() => _position = position);
    });

    _durationSub = _player.durationStream.listen((duration) {
      if (!mounted || duration == null) return;
      setState(() => _duration = duration);
    });

    _stateSub = _player.playerStateStream.listen((state) async {
      if (!mounted) return;

      if (state.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
        await _player.pause();
      }

      if (!mounted) return;
      setState(() {
        _playing =
            state.playing && state.processingState != ProcessingState.completed;
      });
    });

    _initAudio();
  }

  Future<void> _initAudio() async {
    final path = widget.message.audioPath?.trim();

    if (path == null || path.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      Duration? duration;

      if (path.startsWith('http://') || path.startsWith('https://')) {
        duration = await _player.setUrl(path);
      } else {
        duration = await _player.setFilePath(path);
      }

      if (!mounted) return;

      setState(() {
        _duration =
            duration ?? widget.message.audioDuration ?? const Duration(seconds: 1);
        _loading = false;
      });
    } catch (e) {
      debugPrint('AUDIO LOAD ERROR: $e');

      if (!mounted) return;

      setState(() {
        _duration = widget.message.audioDuration ?? const Duration(seconds: 1);
        _loading = false;
      });
    }
  }

  Future<void> _toggle() async {
    HapticFeedback.lightImpact();

    if (_loading) return;

    if (_playing) {
      await _player.pause();
      return;
    }

    if (_duration > Duration.zero && _position >= _duration) {
      await _player.seek(Duration.zero);
    }

    await _player.play();
  }

  Future<void> _seekTo(double progress) async {
    final safeProgress = progress.clamp(0.0, 1.0).toDouble();

    final target = Duration(
      milliseconds: (_duration.inMilliseconds * safeProgress).round(),
    );

    await _player.seek(target);

    if (!mounted) return;

    setState(() {
      _position = target;
      _dragProgress = safeProgress;
    });
  }

  String _format(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isMe = message.isMe;
    final isDark = widget.isDark;

    final total = _duration == Duration.zero
        ? message.audioDuration ?? const Duration(seconds: 1)
        : _duration;

    final progress = total.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0).toDouble();

    final visibleProgress = _dragging ? _dragProgress : progress;

    final Color bubbleColor = isMe
        ? const Color(0xFF7C3AED) // Messenger purple
        : isDark
            ? const Color(0xFF2D2D2F)
            : const Color(0xFFE5E5E7);

    final Color playCircleColor = Colors.white;

    final Color playIconColor = isMe
        ? const Color(0xFF7C3AED)
        : const Color(0xFF111111);

    final Color activeWaveColor = Colors.white;

    final Color inactiveWaveColor = isMe
        ? Colors.white.withOpacity(0.34)
        : isDark
            ? Colors.white.withOpacity(0.30)
            : Colors.black.withOpacity(0.25);

    final Color durationColor = isMe
        ? Colors.white
        : isDark
            ? Colors.white
            : Colors.black87;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: 280,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: _loading
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: playIconColor,
                      ),
                    )
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 140),
                      transitionBuilder: (child, animation) {
                        return ScaleTransition(scale: animation, child: child);
                      },
                      child: Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        key: ValueKey(_playing),
                        color: playIconColor,
                        size: 30,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _SmoothMessengerWaveform(
              progress: visibleProgress,
              isPlaying: _playing,
              activeColor: activeWaveColor,
              inactiveColor: inactiveWaveColor,
              thumbColor: Colors.white,
              onSeekStart: (value) {
                setState(() {
                  _dragging = true;
                  _dragProgress = value;
                });
              },
              onSeekUpdate: (value) {
                setState(() {
                  _dragProgress = value;
                });
              },
              onSeekEnd: (value) async {
                await _seekTo(value);
                if (!mounted) return;
                setState(() => _dragging = false);
              },
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _format(total),
            style: TextStyle(
              color: durationColor,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmoothMessengerWaveform extends StatefulWidget {
  final double progress;
  final bool isPlaying;
  final Color activeColor;
  final Color inactiveColor;
  final Color thumbColor;
  final ValueChanged<double> onSeekStart;
  final ValueChanged<double> onSeekUpdate;
  final ValueChanged<double> onSeekEnd;

  const _SmoothMessengerWaveform({
    required this.progress,
    required this.isPlaying,
    required this.activeColor,
    required this.inactiveColor,
    required this.thumbColor,
    required this.onSeekStart,
    required this.onSeekUpdate,
    required this.onSeekEnd,
  });

  @override
  State<_SmoothMessengerWaveform> createState() =>
      _SmoothMessengerWaveformState();
}

class _SmoothMessengerWaveformState extends State<_SmoothMessengerWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  double _lastDragValue = 0.0;

  static const List<double> _bars = [
    0.28, 0.48, 0.36, 0.70, 0.45, 0.86, 0.56, 0.34,
    0.76, 0.98, 0.62, 0.42, 0.88, 0.66, 0.40, 0.72,
    0.94, 0.52, 0.32, 0.68, 0.82, 0.58, 0.44, 0.78,
    0.92, 0.50, 0.36, 0.64, 0.84, 0.46,
  ];

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    if (widget.isPlaying) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _SmoothMessengerWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }

    if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
      _controller.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  double _progressFromDx(double dx, double width) {
    if (width <= 0) return 0.0;
    return (dx / width).clamp(0.0, 1.0).toDouble();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress.clamp(0.0, 1.0).toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final thumbX = width * progress;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final value = _progressFromDx(details.localPosition.dx, width);
            widget.onSeekEnd(value);
          },
          onHorizontalDragStart: (details) {
            final value = _progressFromDx(details.localPosition.dx, width);
            _lastDragValue = value;
            widget.onSeekStart(value);
          },
          onHorizontalDragUpdate: (details) {
            final value = _progressFromDx(details.localPosition.dx, width);
            _lastDragValue = value;
            widget.onSeekUpdate(value);
          },
          onHorizontalDragEnd: (_) {
            widget.onSeekEnd(_lastDragValue);
          },
          child: SizedBox(
            height: 36,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: List.generate(_bars.length, (index) {
                        final barProgress = (index + 0.5) / _bars.length;
                        final isActive = barProgress <= progress;

                        final pulse = widget.isPlaying
                            ? (math.sin(
                                      (_controller.value * math.pi * 2) +
                                          index * 0.55,
                                    ) *
                                    0.08)
                                .abs()
                            : 0.0;

                        final height = 7 + (24 * (_bars[index] + pulse));

                        return Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            curve: Curves.easeOut,
                            margin: const EdgeInsets.symmetric(horizontal: 1.15),
                            height: height.clamp(7.0, 31.0).toDouble(),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? widget.activeColor
                                  : widget.inactiveColor,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        );
                      }),
                    ),

                    if (progress > 0.01)
                      Positioned(
                        left: thumbX.clamp(0.0, width).toDouble() - 1.4,
                        top: 2,
                        bottom: 2,
                        child: Container(
                          width: 2.8,
                          decoration: BoxDecoration(
                            color: widget.thumbColor,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.18),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),

                    if (progress > 0.01)
                      Positioned(
                        left: thumbX.clamp(0.0, width).toDouble() - 5,
                        top: 0,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: widget.thumbColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _VideoBubble extends StatefulWidget {
  final String? path;
  final BorderRadius borderRadius;

  const _VideoBubble({
    required this.path,
    required this.borderRadius,
  });

  @override
  State<_VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<_VideoBubble> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.path == null || widget.path!.trim().isEmpty) return;

    final controller = VideoPlayerController.file(File(widget.path!));
    await controller.initialize();
    controller.setLooping(false);

    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _controller = controller;
      _ready = true;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _controller == null) {
      return ClipRRect(
        borderRadius: widget.borderRadius,
        child: Container(
          width: 230,
          height: 230,
          color: Colors.black12,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(),
        ),
      );
    }

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 230,
            height: 230,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            ),
          ),
          InkWell(
            onTap: () {
              setState(() {
                if (_controller!.value.isPlaying) {
                  _controller!.pause();
                } else {
                  _controller!.play();
                }
              });
            },
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 30,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeToReply extends StatefulWidget {
  final Widget child;
  final bool isMe;
  final bool enabled;
  final VoidCallback? onTapMessage;
  final VoidCallback onLongPress;
  final VoidCallback onReply;

  const _SwipeToReply({
    required this.child,
    required this.isMe,
    required this.onReply,
    this.enabled = true,
    this.onTapMessage,
    required this.onLongPress,
  });

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _returnAnimation;

  double _dragX = 0;
  bool _triggered = false;

  static const double _maxDrag = 88;
  static const double _triggerDistance = 64;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..addListener(() {
        setState(() {
          _dragX = _returnAnimation.value;
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;
    final dx = details.delta.dx;

    setState(() {
      if (widget.isMe) {
        _dragX = (_dragX + dx).clamp(-_maxDrag, 0.0).toDouble();
      } else {
        _dragX = (_dragX + dx).clamp(0.0, _maxDrag).toDouble();
      }

      final reached = widget.isMe
          ? _dragX <= -_triggerDistance
          : _dragX >= _triggerDistance;

      if (reached && !_triggered) {
        _triggered = true;
        HapticFeedback.mediumImpact();
      }
    });
  }

  void _springBack() {
    _returnAnimation = Tween<double>(begin: _dragX, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.elasticOut,
      ),
    );
    _controller
      ..reset()
      ..forward();
  }

  void _onDragEnd(DragEndDetails details) {
    if (!widget.enabled) return;

    final shouldReply = widget.isMe
        ? _dragX <= -_triggerDistance
        : _dragX >= _triggerDistance;

    if (shouldReply) {
      widget.onReply();
    }

    _triggered = false;
    _springBack();
  }

  @override
  Widget build(BuildContext context) {
    final showIcon = _dragX.abs() > 8;
    final progress = (_dragX.abs() / _triggerDistance).clamp(0.0, 1.25).toDouble();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.onTapMessage,
      onLongPress: widget.onLongPress,
      onHorizontalDragUpdate: widget.enabled ? _onDragUpdate : null,
      onHorizontalDragEnd: widget.enabled ? _onDragEnd : null,
      onHorizontalDragCancel: widget.enabled
          ? () {
              _triggered = false;
              _springBack();
            }
          : null,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: widget.isMe ? null : 18,
            right: widget.isMe ? 18 : null,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: showIcon ? 1 : 0,
              child: Transform.scale(
                scale: (0.72 + (progress * 0.34)).clamp(0.72, 1.12).toDouble(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _triggered
                        ? const Color(0xFF1877F2)
                        : const Color(0xFF1877F2).withOpacity(0.13),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.reply_rounded,
                    color: _triggered ? Colors.white : const Color(0xFF1877F2),
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_dragX, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

class _ReactionBurstOverlay extends StatefulWidget {
  final Offset center;
  final String emoji;
  final VoidCallback onCompleted;

  const _ReactionBurstOverlay({
    required this.center,
    required this.emoji,
    required this.onCompleted,
  });

  @override
  State<_ReactionBurstOverlay> createState() => _ReactionBurstOverlayState();
}

class _ReactionBurstOverlayState extends State<_ReactionBurstOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onCompleted();
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _ReactionBurstPainter(
              progress: _controller.value,
              center: widget.center,
              emoji: widget.emoji,
            ),
          );
        },
      ),
    );
  }
}

class _ReactionBurstPainter extends CustomPainter {
  final double progress;
  final Offset center;
  final String emoji;

  const _ReactionBurstPainter({
    required this.progress,
    required this.center,
    required this.emoji,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    final fade = (1 - progress).clamp(0.0, 1.0).toDouble();
    final eased = Curves.easeOutCubic.transform(progress);

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF1877F2).withOpacity(0.75 * fade);

    for (int i = 0; i < 10; i++) {
      final angle = (math.pi * 2 / 10) * i;
      final distance = 18 + (54 * eased) + ((i % 3) * 8);
      final point = center + Offset(math.cos(angle), math.sin(angle)) * distance;

      if (i.isEven) {
        textPainter.text = TextSpan(
          text: emoji,
          style: TextStyle(
            fontSize: 10 + (8 * fade),
            color: Colors.black.withOpacity(fade),
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          point - Offset(textPainter.width / 2, textPainter.height / 2),
        );
      } else {
        canvas.drawCircle(point, 3.5 + (2.5 * fade), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ReactionBurstPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.center != center ||
        oldDelegate.emoji != emoji;
  }
}

class _ReactionActionTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color textColor;
  final VoidCallback onTap;
  final bool showDivider;

  const _ReactionActionTile({
    required this.title,
    required this.icon,
    required this.textColor,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                  Icon(
                    icon,
                    color: textColor.withOpacity(0.95),
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),

        if (showDivider)
          Divider(
            height: 1,
            thickness: 0.6,
            color: Colors.white.withOpacity(0.08),
          ),
      ],
    );
  }
}
class _MessengerMenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final Color? dividerColor;
  final VoidCallback onTap;
  final bool showBorder;

  const _MessengerMenuTile({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
    this.dividerColor,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 15,
        ),
        decoration: BoxDecoration(
          border: showBorder
              ? Border(
                  bottom: BorderSide(
                    color: dividerColor ?? Colors.white.withOpacity(0.10),
                    width: 0.6,
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              icon,
              color: color,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
