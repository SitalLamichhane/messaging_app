import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:messaging_app/call_screen.dart';
import 'package:messaging_app/chat_data.dart';
import 'package:messaging_app/chat_models.dart';
import 'package:messaging_app/group/create_group_chat_screen.dart';
import 'package:messaging_app/profile_data/conversation_search_page.dart';
import 'package:messaging_app/profile_data/photos_media_page.dart';
import 'package:messaging_app/profile_data/profile_data_page.dart';
import 'package:messaging_app/theme_controller.dart';

class ChatSettingsScreen extends StatefulWidget {
  final ChatItem chat;
  final Color themeColor;

  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;

  const ChatSettingsScreen({
    super.key,
    required this.chat,
    required this.themeColor,
    this.currentUserId = '',
    this.currentUserName = 'You',
    this.currentUserAvatar = '',
  });

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen>
    with TickerProviderStateMixin {
  bool isPinned = false;
  bool isBlocked = false;
  bool isMuted = false;

  bool get isGroupChat => widget.chat.isGroup == true;

  String muteLabel = 'Off';
  String myNickname = 'You';
  String otherNickname = '';
  String emoji = '👍';
  String selectedThemeName = 'Blue';

  late Color themeColor;
  Color themeLightColor = const Color(0xFFEAF2FF);

  late final AnimationController _headerScaleController;
  late final Animation<double> _headerScaleAnimation;

  static final Map<String, Map<String, dynamic>> _chatSettingsStore = {};

  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  Color get bgColor => isDark ? const Color(0xFF0F172A) : const Color(0xFFF4F5F7);

  Color get cardColor => isDark ? const Color(0xFF1E293B) : Colors.white;

  Color get borderColor =>
      isDark ? const Color(0xFF243041) : const Color(0xFFE5E7EB);

  Color get mainTextColor => isDark ? Colors.white : Colors.black;

  Color get secondaryTextColor =>
      isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);

  Color get sheetColor => isDark ? const Color(0xFF1E293B) : Colors.white;

  Color get inputColor => isDark ? const Color(0xFF0F172A) : const Color(0xFFF0F2F5);

  Map<String, dynamic> get _settings {
    return _chatSettingsStore.putIfAbsent(widget.chat.id, () {
      return {
        'isPinned': false,
        'isBlocked': false,
        'isMuted': false,
        'muteLabel': 'Off',
        'myNickname': 'You',
        'otherNickname': widget.chat.name,
        'emoji': '👍',
        'selectedThemeName': 'Blue',
        'themeColor': widget.themeColor,
        'themeLightColor': const Color(0xFFEAF2FF),
      };
    });
  }

  List<ChatMessage> get _mediaMessages {
    return widget.chat.messages
        .where((m) => m.type == MessageType.image || m.type == MessageType.video)
        .toList();
  }

  String get _displayChatName =>
      otherNickname.trim().isEmpty ? widget.chat.name : otherNickname.trim();

  @override
  void initState() {
    super.initState();

    themeColor = widget.themeColor;
    _loadSettings();

    _headerScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    _headerScaleAnimation = Tween<double>(begin: 1, end: 1.04).animate(
      CurvedAnimation(
        parent: _headerScaleController,
        curve: Curves.easeOutBack,
      ),
    );
  }

  @override
  void dispose() {
    _headerScaleController.dispose();
    super.dispose();
  }

  void _loadSettings() {
    final s = _settings;

    isPinned = s['isPinned'] as bool? ?? false;
    isBlocked = s['isBlocked'] as bool? ?? false;
    isMuted = s['isMuted'] as bool? ?? false;
    muteLabel = s['muteLabel'] as String? ?? 'Off';
    myNickname = s['myNickname'] as String? ?? 'You';
    otherNickname =
        s['otherNickname'] as String? ?? (isGroupChat ? 'Group' : widget.chat.name);
    emoji = s['emoji'] as String? ?? '👍';
    selectedThemeName = s['selectedThemeName'] as String? ?? 'Blue';
    themeColor = s['themeColor'] as Color? ?? widget.themeColor;
    themeLightColor = s['themeLightColor'] as Color? ?? const Color(0xFFEAF2FF);
  }

  void _saveSettings() {
    _settings['isPinned'] = isPinned;
    _settings['isBlocked'] = isBlocked;
    _settings['isMuted'] = isMuted;
    _settings['muteLabel'] = muteLabel;
    _settings['myNickname'] = myNickname;
    _settings['otherNickname'] = otherNickname;
    _settings['emoji'] = emoji;
    _settings['selectedThemeName'] = selectedThemeName;
    _settings['themeColor'] = themeColor;
    _settings['themeLightColor'] = themeLightColor;
  }

  void _notifyDataChanged() {
    _saveSettings();
    AppChatData.notify();
    if (mounted) setState(() {});
  }

  void _showSnackBar(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _bounceHeader() async {
    await _headerScaleController.forward();
    await _headerScaleController.reverse();
  }

  void _createGroupWithThisUser() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateGroupChatScreen(
          preSelectedUser: ChatUser(
            id: widget.chat.id,
            name: widget.chat.name,
            avatarUrl: widget.chat.avatarUrl,
            isOnline: widget.chat.isOnline,
          ),
        ),
      ),
    );
  }

  void _moveChatForPin() {
    final index = AppChatData.chats.indexWhere((c) => c.id == widget.chat.id);
    if (index == -1) return;

    final chat = AppChatData.chats.removeAt(index);

    if (isPinned) {
      AppChatData.chats.insert(0, chat);
    } else {
      AppChatData.chats.add(chat);
    }
  }

  void _startCall(bool isVideo) {
    if (isBlocked) {
      _showSnackBar('You blocked this chat');
      return;
    }

    AppChatData.addCallLog(
      chat: widget.chat,
      type: isVideo ? CallEntryType.video : CallEntryType.voice,
      status: CallEntryStatus.outgoing,
      duration: const Duration(seconds: 0),
      answered: true,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          name: _displayChatName,
          avatarUrl: widget.chat.avatarUrl,
          isVideoCall: isVideo,
          chat: widget.chat,
          currentUserId: widget.currentUserId,
          currentUserName: widget.currentUserName,
          currentUserAvatar: widget.currentUserAvatar,
          receiverId: widget.chat.id,
          isCaller: true,
          conversationId: widget.chat.id,
        ),
      ),
    ).then((_) {
      if (mounted) _notifyDataChanged();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopBar(),
              const SizedBox(height: 10),
              _buildProfileHeader(),
              const SizedBox(height: 26),
              _buildQuickCallActions(),
              const SizedBox(height: 24),

              _buildSectionTitle('Customization'),
              _buildSettingsCard(
                children: [
                  _SettingsTile(
                    icon: Icons.color_lens_outlined,
                    iconColor: const Color(0xFF5B5CE6),
                    title: 'Theme',
                    subtitle: selectedThemeName,
                    showDivider: true,
                    onTap: _openThemePicker,
                  ),
                  _SettingsSwitchTile(
                    icon: Icons.dark_mode_rounded,
                    iconColor: isDark
                        ? const Color(0xFF93C5FD)
                        : const Color(0xFF111827),
                    title: 'Dark mode',
                    value: isAppDarkMode,
                    showDivider: true,
                    onChanged: (value) {
                      setAppDarkMode(value);
                      setState(() {});
                    },
                  ),
                  _SettingsTile(
                    icon: Icons.thumb_up_alt_outlined,
                    iconColor: const Color(0xFF7C3AED),
                    title: 'Emoji',
                    subtitle: emoji,
                    showDivider: true,
                    onTap: _openReactionPicker,
                  ),
                  _SettingsTile(
                    icon: Icons.text_fields_rounded,
                    iconColor: const Color(0xFF06B6D4),
                    title: isGroupChat ? 'Group nicknames' : 'Nicknames',
                    subtitle: _displayChatName,
                    showDivider: false,
                    onTap: _openNicknameEditor,
                  ),
                ],
              ),

              const SizedBox(height: 22),
              _buildSectionTitle('Privacy & support'),
              _buildSettingsCard(
                children: [
                  _SettingsTile(
                    icon: Icons.search_rounded,
                    iconColor: mainTextColor,
                    title: 'Search conversation',
                    showDivider: false,
                    onTap: _openConversationSearch,
                  ),
                ],
              ),

              const SizedBox(height: 22),
              _buildSectionTitle('Shared media & files'),
              _buildSettingsCard(
                children: [
                  _SettingsTile(
                    icon: Icons.image_outlined,
                    iconColor: const Color(0xFF0EA5E9),
                    title: 'Photos & videos',
                    subtitle: '${_mediaMessages.length} items',
                    showDivider: false,
                    onTap: _openMediaPage,
                  ),
                ],
              ),

              const SizedBox(height: 22),
              _buildSectionTitle('More actions'),
              _buildSettingsCard(
                children: [
                  if (!isGroupChat)
                    _SettingsTile(
                      icon: Icons.group_add_rounded,
                      iconColor: const Color(0xFF1877F2),
                      title: 'Create group with ${widget.chat.name}',
                      subtitle: 'Add more people to this chat',
                      showDivider: true,
                      onTap: _createGroupWithThisUser,
                    ),
                  _SettingsTile(
                    icon: Icons.delete_outline_rounded,
                    iconColor: const Color(0xFF22C55E),
                    title: 'Clear chat',
                    showDivider: true,
                    onTap: _clearChat,
                  ),
                  _SettingsSwitchTile(
                    icon: Icons.push_pin_outlined,
                    iconColor: const Color(0xFFF97316),
                    title: 'Pin chat',
                    value: isPinned,
                    showDivider: false,
                    onChanged: (value) {
                      isPinned = value;
                      _moveChatForPin();
                      _notifyDataChanged();
                      _showSnackBar(value ? 'Chat pinned' : 'Chat unpinned');
                    },
                  ),
                ],
              ),

              const SizedBox(height: 18),
              _buildDangerCard(
                children: [
                  _DangerTile(
                    icon: Icons.delete_outline_rounded,
                    title: 'Delete chat',
                    showDivider: !isGroupChat,
                    onTap: _deleteChat,
                  ),
                  if (!isGroupChat)
                    _DangerTile(
                      icon: Icons.block_rounded,
                      title: isBlocked ? 'Unblock' : 'Block',
                      showDivider: false,
                      onTap: _openBlockOptions,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context, true),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: mainTextColor,
              size: 30,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Chat settings',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: mainTextColor,
              ),
            ),
          ),
          PopupMenuButton<String>(
            color: sheetColor,
            icon: Icon(
              Icons.more_vert_rounded,
              color: mainTextColor,
              size: 28,
            ),
            onSelected: (value) {
              if (value == 'profile' && !isGroupChat) {
                _viewProfile();
              } else if (value == 'mute') {
                _openMuteSheet();
              } else if (value == 'block' && !isGroupChat) {
                _openBlockOptions();
              }
            },
            itemBuilder: (context) => [
              if (!isGroupChat)
                PopupMenuItem(
                  value: 'profile',
                  child: Text(
                    'View profile',
                    style: TextStyle(color: mainTextColor),
                  ),
                ),
              PopupMenuItem(
                value: 'mute',
                child: Text(
                  'Mute notifications',
                  style: TextStyle(color: mainTextColor),
                ),
              ),
              if (!isGroupChat)
                PopupMenuItem(
                  value: 'block',
                  child: Text(
                    'Block',
                    style: TextStyle(color: mainTextColor),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    return ScaleTransition(
      scale: _headerScaleAnimation,
      child: Column(
        children: [
          Center(
            child: GestureDetector(
              onTap: _bounceHeader,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 59,
                    backgroundColor:
                        isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB),
                    backgroundImage: widget.chat.avatarUrl.trim().isNotEmpty
                        ? NetworkImage(widget.chat.avatarUrl)
                        : null,
                    child: widget.chat.avatarUrl.trim().isEmpty
                        ? Text(
                            widget.chat.name.isNotEmpty
                                ? widget.chat.name[0].toUpperCase()
                                : 'U',
                            style: TextStyle(
                              fontSize: 26,
                              color: mainTextColor,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                  if (widget.chat.isOnline)
                    Positioned(
                      right: 2,
                      bottom: 8,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: const Color(0xFF40C057),
                          shape: BoxShape.circle,
                          border: Border.all(color: bgColor, width: 3),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              _displayChatName,
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                color: mainTextColor,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isBlocked
                ? 'Blocked'
                : widget.chat.isOnline
                    ? 'Active now'
                    : 'Offline',
            style: TextStyle(
              fontSize: 14,
              color: secondaryTextColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickCallActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CircleActionButton(
            icon: Icons.call_rounded,
            iconColor: themeColor,
            label: 'Audio call',
            onTap: () => _startCall(false),
          ),
          _CircleActionButton(
            icon: Icons.videocam_rounded,
            iconColor: themeColor,
            label: 'Video call',
            onTap: () => _startCall(true),
          ),
          if (!isGroupChat)
            _CircleActionButton(
              icon: Icons.person_rounded,
              iconColor: themeColor,
              label: 'View profile',
              onTap: _viewProfile,
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: secondaryTextColor,
        ),
      ),
    );
  }

  Widget _buildSettingsCard({required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor),
        ),
        child: Column(children: children),
      ),
    );
  }

  Widget _buildDangerCard({required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor),
        ),
        child: Column(children: children),
      ),
    );
  }

  Future<void> _openMuteSheet() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: sheetColor,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        final options = [
          '15 minutes',
          '1 hour',
          '24 hours',
          'Until turned off',
          'Turn off mute',
        ];

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Mute notifications',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: mainTextColor,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Choose how long you want to mute this chat.',
                    style: TextStyle(
                      fontSize: 14,
                      color: secondaryTextColor,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                ...options.map(
                  (e) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(e, style: TextStyle(color: mainTextColor)),
                    onTap: () => Navigator.pop(context, e),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == null) return;

    if (result == 'Turn off mute') {
      isMuted = false;
      muteLabel = 'Off';
      _showSnackBar('Notifications unmuted');
    } else {
      isMuted = true;
      muteLabel = result;
      _showSnackBar('Notifications muted for $result');
    }

    _notifyDataChanged();
  }

  Future<void> _openThemePicker() async {
    final themes = [
      {
        'name': 'Blue',
        'primary': const Color(0xFF1877F2),
        'light': const Color(0xFFEAF2FF),
      },
      {
        'name': 'Purple',
        'primary': const Color(0xFF7C3AED),
        'light': const Color(0xFFF3E8FF),
      },
      {
        'name': 'Green',
        'primary': const Color(0xFF10B981),
        'light': const Color(0xFFDCFCE7),
      },
      {
        'name': 'Red',
        'primary': const Color(0xFFEF4444),
        'light': const Color(0xFFFEE2E2),
      },
      {
        'name': 'Orange',
        'primary': const Color(0xFFF97316),
        'light': const Color(0xFFFFEDD5),
      },
    ];

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: sheetColor,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Choose theme',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: mainTextColor,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ...themes.map((theme) {
                  final isSelected = selectedThemeName == theme['name'];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: theme['primary'] as Color,
                      radius: 14,
                    ),
                    title: Text(
                      theme['name'] as String,
                      style: TextStyle(color: mainTextColor),
                    ),
                    trailing:
                        isSelected ? Icon(Icons.check_rounded, color: themeColor) : null,
                    onTap: () => Navigator.pop(context, theme),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );

    if (result == null) return;

    selectedThemeName = result['name'] as String;
    themeColor = result['primary'] as Color;
    themeLightColor = result['light'] as Color;

    _notifyDataChanged();
    _showSnackBar('Theme changed to $selectedThemeName');
  }

  Future<void> _openReactionPicker() async {
    final controller = TextEditingController(text: emoji);

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: sheetColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.78,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Row(
                  children: [
                    const SizedBox(width: 52),
                    Expanded(
                      child: Center(
                        child: Text(
                          'Emoji',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: mainTextColor,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: InkWell(
                        onTap: () => Navigator.pop(sheetContext),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE4E6EB),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 34,
                            color: secondaryTextColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Divider(height: 1, thickness: 1, color: borderColor),
                Expanded(
                  child: EmojiPicker(
                    textEditingController: controller,
                    onEmojiSelected: (category, selectedEmoji) {
                      Navigator.pop(sheetContext, selectedEmoji.emoji);
                    },
                    onBackspacePressed: () {},
                    config: Config(
                      height: MediaQuery.of(context).size.height * 0.65,
                      checkPlatformCompatibility: true,
                      emojiViewConfig: EmojiViewConfig(
                        columns: 8,
                        emojiSizeMax: 34,
                        backgroundColor: sheetColor,
                      ),
                      categoryViewConfig: CategoryViewConfig(
                        backgroundColor: sheetColor,
                        iconColor: secondaryTextColor,
                        iconColorSelected: themeColor,
                        indicatorColor: themeColor,
                      ),
                      bottomActionBarConfig: BottomActionBarConfig(
                        enabled: false,
                        backgroundColor: sheetColor,
                      ),
                      searchViewConfig: SearchViewConfig(
                        backgroundColor: sheetColor,
                        buttonIconColor: secondaryTextColor,
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

    if (result == null || result.trim().isEmpty) return;

    emoji = result;
    _notifyDataChanged();
    _showSnackBar('Emoji changed');
  }

  Future<void> _openNicknameEditor() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: sheetColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (context, setModalState) {
              final displayOtherNickname =
                  otherNickname.trim().isEmpty ? widget.chat.name : otherNickname;
              final displayMyNickname =
                  myNickname.trim().isEmpty ? 'You' : myNickname;

              return Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              isGroupChat ? widget.chat.name : 'Nicknames',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: mainTextColor,
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF334155)
                                      : const Color(0xFFE4E6EB),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.close_rounded,
                                  color: secondaryTextColor,
                                  size: 28,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, thickness: 1, color: borderColor),
                    const SizedBox(height: 16),

                    if (isGroupChat)
                      if (widget.chat.members.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                          child: Text(
                            'No group members found.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: secondaryTextColor,
                            ),
                          ),
                        )
                      else
                        Flexible(
                          child: ListView(
                            shrinkWrap: true,
                            children: widget.chat.members.map((member) {
                              final nickname =
                                  widget.chat.memberNicknames[member.id] ??
                                      member.name;

                              return _NicknameRowTile(
                                avatarUrl: member.avatarUrl,
                                fallbackLetter: member.name.isNotEmpty
                                    ? member.name[0].toUpperCase()
                                    : 'U',
                                nickname: nickname,
                                realName: member.name,
                                onEdit: () async {
                                  final value = await _showNicknameEditSheet(
                                    title: member.name,
                                    initialValue:
                                        nickname == member.name ? '' : nickname,
                                  );

                                  if (value == null) return;

                                  setState(() {
                                    widget.chat.memberNicknames =
                                        Map<String, String>.from(
                                      widget.chat.memberNicknames,
                                    );

                                    final cleanedValue = value.trim();

                                    if (cleanedValue.isEmpty) {
                                      widget.chat.memberNicknames.remove(member.id);
                                    } else {
                                      widget.chat.memberNicknames[member.id] =
                                          cleanedValue;
                                    }
                                  });

                                  setModalState(() {});
                                  _notifyDataChanged();
                                  _showSnackBar('Nickname updated');
                                },
                              );
                            }).toList(),
                          ),
                        )
                    else ...[
                      _NicknameRowTile(
                        avatarUrl: widget.chat.avatarUrl,
                        fallbackLetter: widget.chat.name.isNotEmpty
                            ? widget.chat.name[0].toUpperCase()
                            : 'U',
                        nickname: displayOtherNickname,
                        realName: widget.chat.name,
                        onEdit: () async {
                          final value = await _showNicknameEditSheet(
                            title: widget.chat.name,
                            initialValue: displayOtherNickname == widget.chat.name
                                ? ''
                                : displayOtherNickname,
                          );

                          if (value == null) return;

                          setState(() {
                            otherNickname = value.trim().isEmpty
                                ? widget.chat.name
                                : value.trim();
                          });

                          setModalState(() {});
                          _notifyDataChanged();
                        },
                      ),
                      _NicknameRowTile(
                        avatarUrl: widget.currentUserAvatar,
                        fallbackLetter: widget.currentUserName.isNotEmpty
                            ? widget.currentUserName[0].toUpperCase()
                            : 'Y',
                        nickname: displayMyNickname,
                        realName: widget.currentUserName.isNotEmpty
                            ? widget.currentUserName
                            : 'You',
                        avatarBackgroundColor: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE4E6EB),
                        onEdit: () async {
                          final value = await _showNicknameEditSheet(
                            title: 'You',
                            initialValue:
                                displayMyNickname == 'You' ? '' : displayMyNickname,
                          );

                          if (value == null) return;

                          setState(() {
                            myNickname =
                                value.trim().isEmpty ? 'You' : value.trim();
                          });

                          setModalState(() {});
                          _notifyDataChanged();
                        },
                      ),
                    ],
                    const SizedBox(height: 10),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<String?> _showNicknameEditSheet({
    required String title,
    required String initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue);

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: sheetColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            14,
            20,
            MediaQuery.of(context).viewInsets.bottom + 22,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Edit nickname',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: mainTextColor,
                      ),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE4E6EB),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 24,
                        color: secondaryTextColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: secondaryTextColor,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                style: TextStyle(color: mainTextColor),
                decoration: InputDecoration(
                  hintText: 'Enter nickname',
                  hintStyle: TextStyle(color: secondaryTextColor),
                  filled: true,
                  fillColor: inputColor,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => Navigator.pop(context, controller.text),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, controller.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openBlockOptions() async {
    if (isGroupChat) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: sheetColor,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isBlocked ? 'Manage block' : 'Block ${widget.chat.name}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: mainTextColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose what you want to block.',
                  style: TextStyle(
                    fontSize: 14,
                    color: secondaryTextColor,
                  ),
                ),
                const SizedBox(height: 18),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.message_outlined, color: mainTextColor),
                  title: Text(
                    isBlocked ? 'Unblock messages' : 'Block messages',
                    style: TextStyle(color: mainTextColor),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmBlockAction('messages');
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.call_outlined, color: mainTextColor),
                  title: Text(
                    isBlocked ? 'Unblock calls' : 'Block calls',
                    style: TextStyle(color: mainTextColor),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmBlockAction('calls');
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.block_rounded,
                    color: Color(0xFFEF4444),
                  ),
                  title: Text(
                    isBlocked ? 'Unblock everything' : 'Block everything',
                    style: const TextStyle(color: Color(0xFFEF4444)),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmBlockAction('everything');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmBlockAction(String type) async {
    final enabling = !isBlocked;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: sheetColor,
          title: Text(
            enabling ? 'Confirm block' : 'Confirm unblock',
            style: TextStyle(color: mainTextColor),
          ),
          content: Text(
            enabling
                ? 'Are you sure you want to block $type for ${widget.chat.name}?'
                : 'Do you want to remove the block for $type?',
            style: TextStyle(color: secondaryTextColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(enabling ? 'Block' : 'Unblock'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    isBlocked = enabling;
    _notifyDataChanged();
    _showSnackBar(
      enabling ? '${widget.chat.name} blocked' : '${widget.chat.name} unblocked',
    );
  }

  Future<void> _openConversationSearch() async {
    final selectedMessageId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationSearchPage(
          chatName: widget.chat.name,
          messages: widget.chat.messages,
        ),
      ),
    );

    if (!mounted) return;

    if (selectedMessageId != null && selectedMessageId.isNotEmpty) {
      Navigator.pop(context, selectedMessageId);
    }
  }

  void _openMediaPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhotosMediaPage(
          chatId: widget.chat.id,
          chatName: _displayChatName,
        ),
      ),
    );
  }

  void _viewProfile() {
    if (isGroupChat) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileDataPage(chat: widget.chat),
      ),
    );
  }

  Future<void> _clearChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: sheetColor,
          title: Text('Clear chat', style: TextStyle(color: mainTextColor)),
          content: Text(
            'This will remove all messages in this chat from the local app view.',
            style: TextStyle(color: secondaryTextColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    widget.chat.messages.clear();
    _notifyDataChanged();
    _showSnackBar('Chat cleared');
  }

  Future<void> _deleteChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: sheetColor,
          title: Text('Delete chat', style: TextStyle(color: mainTextColor)),
          content: Text(
            'Delete chat with ${widget.chat.name}?',
            style: TextStyle(color: secondaryTextColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    AppChatData.chats.removeWhere((c) => c.id == widget.chat.id);
    AppChatData.notify();

    if (!mounted) return;
    Navigator.pop(context, true);
  }
}

class _CircleActionButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  const _CircleActionButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;

    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: onTap,
      child: SizedBox(
        width: 92,
        child: Column(
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: cardColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool showDivider;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.showDivider = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);
    final dividerColor =
        isDark ? const Color(0xFF243041) : const Color(0xFFF1F5F9);

    return Column(
      children: [
        ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          subtitle: subtitle == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: subTextColor,
                    ),
                  ),
                ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: subTextColor,
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Divider(height: 1, thickness: 1, color: dividerColor),
          ),
      ],
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final bool value;
  final bool showDivider;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    this.showDivider = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final dividerColor =
        isDark ? const Color(0xFF243041) : const Color(0xFFF1F5F9);

    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          trailing: Switch(
            value: value,
            activeColor: const Color(0xFF1877F2),
            onChanged: onChanged,
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Divider(height: 1, thickness: 1, color: dividerColor),
          ),
      ],
    );
  }
}

class _DangerTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool showDivider;
  final VoidCallback onTap;

  const _DangerTile({
    required this.icon,
    required this.title,
    this.showDivider = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dividerColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF243041)
        : const Color(0xFFF1F5F9);

    return Column(
      children: [
        ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: const Color(0xFFEF4444),
              size: 22,
            ),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFFEF4444),
            ),
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Divider(height: 1, thickness: 1, color: dividerColor),
          ),
      ],
    );
  }
}

class _NicknameRowTile extends StatelessWidget {
  final String avatarUrl;
  final String fallbackLetter;
  final String nickname;
  final String realName;
  final VoidCallback onEdit;
  final Color? avatarBackgroundColor;

  const _NicknameRowTile({
    required this.avatarUrl,
    required this.fallbackLetter,
    required this.nickname,
    required this.realName,
    required this.onEdit,
    this.avatarBackgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? const Color(0xFFCBD5E1) : Colors.black87;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: avatarBackgroundColor ??
                (isDark ? const Color(0xFF334155) : const Color(0xFFE4E6EB)),
            backgroundImage:
                avatarUrl.trim().isNotEmpty ? NetworkImage(avatarUrl) : null,
            child: avatarUrl.trim().isEmpty
                ? Text(
                    fallbackLetter,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  realName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: subTextColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: onEdit,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.edit,
                size: 25,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}