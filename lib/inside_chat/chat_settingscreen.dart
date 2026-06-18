import 'package:hiddenly/core/api_client.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:hiddenly/profile_data/block_page.dart';
import 'package:provider/provider.dart';
import 'package:hiddenly/call_screen.dart';
import 'package:hiddenly/chat_data.dart';
import 'package:hiddenly/chat_models.dart';
import 'package:hiddenly/core/config/app_config.dart';
import 'package:hiddenly/core/block/block_provider.dart';
import 'package:hiddenly/group/create_group_chat_screen.dart';
import 'package:hiddenly/profile_data/conversation_search_page.dart';
import 'package:hiddenly/profile_data/photos_media_page.dart';
// import 'package:hiddenly/profile_data/profile_data_page.dart';
import 'package:hiddenly/theme_controller.dart';

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
  bool _blockedMe = false;
  bool isMuted = false;

  final ImagePicker _imagePicker = ImagePicker();
  String _localGroupImagePath = '';
  String _updatedGroupImageUrl = '';

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

  Color get inputColor =>
      isDark ? const Color(0xFF0F172A) : const Color(0xFFF0F2F5);

  Map<String, dynamic> get _settings {
    return _chatSettingsStore.putIfAbsent(widget.chat.id, () {
      return {
        'isPinned': false,
        'isBlocked': false,
        'isMuted': false,
        'muteLabel': 'Off',
        'myNickname': 'You',
        'otherNickname': '',
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

  // Messenger-style display rule:
  // 1) If nickname exists for this conversation member, show nickname.
  // 2) If nickname is empty/removed, show the latest real profile name.
  // 3) Never save the real profile name as nickname automatically.
  String get _displayChatName {
    if (isGroupChat) return widget.chat.name;

    final targetUserId = _targetUserIdForBlock();

    return _displayNameForUser(
      userId: targetUserId,
      fallbackRealName: widget.chat.name,
    );
  }

  String get _mediaBaseUrl {
    return AppConfig.apiBaseUrl.replaceFirst('/api', '');
  }

  String _cleanImageUrl(String value) {
    final cleanValue = value.trim();

    if (cleanValue.isEmpty) return '';

    if (cleanValue.startsWith('http://') || cleanValue.startsWith('https://')) {
      return cleanValue.replaceFirst('/api/media/', '/media/');
    }

    if (cleanValue.startsWith('/media/')) {
      return '$_mediaBaseUrl$cleanValue';
    }

    if (cleanValue.startsWith('media/')) {
      return '$_mediaBaseUrl/$cleanValue';
    }

    return cleanValue;
  }

  String _resolvedChatAvatarUrl() {
    if (_localGroupImagePath.trim().isNotEmpty) {
      return _localGroupImagePath.trim();
    }

    final updatedGroupImage = _cleanImageUrl(_updatedGroupImageUrl);

    if (updatedGroupImage.isNotEmpty) {
      return updatedGroupImage;
    }

    final directAvatar = _cleanImageUrl(widget.chat.avatarUrl);

    if (directAvatar.isNotEmpty) {
      return directAvatar;
    }

    for (final member in widget.chat.members) {
      final memberAvatar = _cleanImageUrl(member.avatarUrl);

      if (memberAvatar.isEmpty) continue;

      if (member.name.trim().toLowerCase() ==
          widget.chat.name.trim().toLowerCase()) {
        return memberAvatar;
      }
    }

    for (final member in widget.chat.members) {
      final memberAvatar = _cleanImageUrl(member.avatarUrl);

      if (memberAvatar.isNotEmpty) {
        return memberAvatar;
      }
    }

    return '';
  }

  String _targetUserIdForBlock() {
    if (isGroupChat) return '';

    final currentUserId = widget.currentUserId.trim();

    for (final member in widget.chat.members) {
      final memberId = member.id.toString().trim();

      if (memberId.isEmpty) continue;

      if (currentUserId.isNotEmpty && memberId == currentUserId) {
        continue;
      }

      return memberId;
    }

    return '';
  }


  ChatUser? _memberByUserId(String userId) {
    final cleanUserId = userId.trim();

    if (cleanUserId.isEmpty) return null;

    for (final member in widget.chat.members) {
      if (member.id.toString().trim() == cleanUserId) {
        return member;
      }
    }

    return null;
  }

  String _realNameForUser({
    required String userId,
    required String fallbackRealName,
  }) {
    final cleanUserId = userId.trim();

    if (cleanUserId.isNotEmpty) {
      final member = _memberByUserId(cleanUserId);
      final memberName = member?.name.trim() ?? '';

      if (memberName.isNotEmpty && memberName.toLowerCase() != 'unknown') {
        return memberName;
      }
    }

    final cleanFallback = fallbackRealName.trim();
    if (cleanFallback.isNotEmpty && cleanFallback.toLowerCase() != 'unknown') {
      return cleanFallback;
    }

    return 'Unknown';
  }

  String _nicknameForUser(String userId) {
    final cleanUserId = userId.trim();

    if (cleanUserId.isEmpty) return '';

    final localNickname = widget.chat.memberNicknames[cleanUserId];

    if (localNickname != null && localNickname.trim().isNotEmpty) {
      return localNickname.trim();
    }

    return '';
  }

  String _displayNameForUser({
    required String userId,
    required String fallbackRealName,
  }) {
    final cleanUserId = userId.trim();
    final nickname = _nicknameForUser(cleanUserId);

    if (nickname.trim().isNotEmpty) {
      return nickname.trim();
    }

    return _realNameForUser(
      userId: cleanUserId,
      fallbackRealName: fallbackRealName,
    );
  }

  String _initialNicknameForEditor(String userId) {
    return _nicknameForUser(userId);
  }

  void _applyNicknameLocally({
    required String userId,
    required String nickname,
  }) {
    final cleanUserId = userId.trim();
    final cleanNickname = nickname.trim();

    if (cleanUserId.isEmpty) return;

    final updatedNicknames = Map<String, String>.from(
      widget.chat.memberNicknames,
    );

    if (cleanNickname.isEmpty) {
      updatedNicknames.remove(cleanUserId);
    } else {
      updatedNicknames[cleanUserId] = cleanNickname;
    }

    widget.chat.memberNicknames = updatedNicknames;

    final index = AppChatData.chats.indexWhere(
      (chat) => chat.id.toString() == widget.chat.id.toString(),
    );

    if (index != -1) {
      AppChatData.chats[index].memberNicknames = updatedNicknames;
    }

    AppChatData.notify();
  }

  Future<bool> _updateMemberNicknameApi({
    required String conversationId,
    required String userId,
    required String nickname,
  }) async {
    try {
      final response = await ApiClient.dio.patch(
        '/chat/conversations/$conversationId/members/$userId/nickname/',
        data: {
          'nickname': nickname.trim(),
        },
      );

      debugPrint('NICKNAME UPDATE STATUS: ${response.statusCode}');
      debugPrint('NICKNAME UPDATE DATA: ${response.data}');

      return response.statusCode == 200 || response.statusCode == 204;
    } on DioException catch (e) {
      debugPrint('NICKNAME UPDATE DIO STATUS: ${e.response?.statusCode}');
      debugPrint('NICKNAME UPDATE DIO DATA: ${e.response?.data}');
      debugPrint('NICKNAME UPDATE DIO MESSAGE: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('NICKNAME UPDATE ERROR: $e');
      return false;
    }
  }

  Future<ChatItem> _latestChatForSettings({
    required String currentUserId,
  }) async {
    ChatItem latestChat = widget.chat;

    try {
      latestChat = AppChatData.chats.firstWhere(
        (chat) => chat.id.toString() == widget.chat.id.toString(),
        orElse: () => widget.chat,
      );
    } catch (_) {
      latestChat = widget.chat;
    }

    try {
      debugPrint('SETTINGS BLOCK REFRESH: fetching /chat/conversations/');

      final response = await ApiClient.dio.get('/chat/conversations/');
      final data = response.data;

      if (data is! List) {
        debugPrint('SETTINGS BLOCK REFRESH SKIPPED: response is not List');
        return latestChat;
      }

      for (final item in data) {
        if (item is! Map) continue;

        final map = Map<String, dynamic>.from(item);
        final conversationId = map['id']?.toString() ?? '';

        if (conversationId != widget.chat.id.toString()) continue;

        final freshChat = ChatItem.fromJson(
          map,
          currentUserId: currentUserId,
        );

        final index = AppChatData.chats.indexWhere(
          (chat) => chat.id.toString() == freshChat.id.toString(),
        );

        if (index >= 0) {
          AppChatData.chats[index] = freshChat;
        } else {
          AppChatData.chats.add(freshChat);
        }

        AppChatData.notify();

        debugPrint('SETTINGS BLOCK REFRESH FOUND: ${freshChat.id}');
        return freshChat;
      }

      return latestChat;
    } catch (e) {
      debugPrint('SETTINGS BLOCK REFRESH ERROR: $e');
      return latestChat;
    }
  }

  Future<void> _loadBlockStatus() async {
    if (isGroupChat) return;

    final currentUserId = widget.currentUserId.trim();

    if (currentUserId.isEmpty) {
      debugPrint('SETTINGS BLOCK ERROR: currentUserId is empty');
      return;
    }

    final latestChat = await _latestChatForSettings(
      currentUserId: currentUserId,
    );

    ChatUser? myMember;
    ChatUser? targetMember;

    for (final member in latestChat.members) {
      final memberId = member.id.toString().trim();

      debugPrint(
        'SETTINGS BLOCK MEMBER CHECK => '
        'memberId=$memberId, '
        'name=${member.name}, '
        'isBlocked=${member.isBlocked}, '
        'blockedBy=${member.blockedBy}, '
        'blockedByName=${member.blockedByName}',
      );

      if (memberId == currentUserId) {
        myMember = member;
      } else if (targetMember == null) {
        targetMember = member;
      }
    }

    if (myMember == null || targetMember == null) {
      debugPrint('SETTINGS BLOCK ERROR: members not found');
      return;
    }

    final targetUserId = targetMember.id.toString().trim();

    final blockedByMe =
        targetMember.isBlocked == true &&
        targetMember.blockedBy?.toString() == currentUserId;

    final blockedMe =
        myMember.isBlocked == true &&
        myMember.blockedBy?.toString() == targetUserId;

    final blockProvider = context.read<BlockProvider>();

    blockProvider.setLocalBlocked(
      conversationId: latestChat.id,
      targetUserId: targetUserId,
      value: blockedByMe,
    );

    blockProvider.setLocalBlockedMe(
      conversationId: latestChat.id,
      targetUserId: targetUserId,
      value: blockedMe,
    );

    if (!mounted) return;

    setState(() {
      isBlocked = blockedByMe;
      _blockedMe = blockedMe;
    });

    _saveSettings();

    debugPrint('========== SETTINGS BLOCK FINAL ==========');
    debugPrint('currentUserId: $currentUserId');
    debugPrint('targetUserId: $targetUserId');
    debugPrint('SETTINGS FINAL isBlocked/blockByMe: $blockedByMe');
    debugPrint('SETTINGS FINAL blockedMe: $blockedMe');
    debugPrint('==========================================');
  }

  @override
  void initState() {
    super.initState();

    themeColor = widget.themeColor;
    _loadSettings();
    Future.microtask(_loadBlockStatus);

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
    isBlocked = false;
    _blockedMe = false;
    isMuted = s['isMuted'] as bool? ?? false;
    muteLabel = s['muteLabel'] as String? ?? 'Off';
    myNickname = s['myNickname'] as String? ?? 'You';
    otherNickname = s['otherNickname'] as String? ?? '';
    emoji = s['emoji'] as String? ?? '👍';
    selectedThemeName = s['selectedThemeName'] as String? ?? 'Blue';
    themeColor = s['themeColor'] as Color? ?? widget.themeColor;
    themeLightColor = s['themeLightColor'] as Color? ?? const Color(0xFFEAF2FF);
  }

  void _saveSettings() {
    _settings['isPinned'] = isPinned;
    _settings['isBlocked'] = false;
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

  Future<void> _changeGroupImage() async {
    if (!isGroupChat) {
      await _bounceHeader();
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: sheetColor,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Change group image',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: mainTextColor,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.photo_camera_rounded, color: themeColor),
                  title: Text(
                    'Take photo',
                    style: TextStyle(color: mainTextColor),
                  ),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.photo_library_rounded, color: themeColor),
                  title: Text(
                    'Choose from gallery',
                    style: TextStyle(color: mainTextColor),
                  ),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) return;

    final picked = await _imagePicker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1800,
    );

    if (picked == null) return;

    final conversationId = int.tryParse(widget.chat.id);

    if (conversationId == null) {
      _showSnackBar('Invalid group');
      return;
    }

    setState(() {
      _localGroupImagePath = picked.path;
    });

    final uploadedUrl = await _uploadGroupImage(
      conversationId: conversationId,
      imageFile: File(picked.path),
    );

    if (uploadedUrl == null) {
      setState(() {
        _localGroupImagePath = '';
      });
      _showSnackBar('Could not update group image');
      return;
    }

    if (uploadedUrl.trim().isNotEmpty) {
      final cleanUploadedUrl = _cleanImageUrl(uploadedUrl.trim());

      setState(() {
        _localGroupImagePath = '';
        _updatedGroupImageUrl = cleanUploadedUrl;
      });

      final updatedChat = widget.chat.copyWith(
        avatarUrl: cleanUploadedUrl,
      );

      final index = AppChatData.chats.indexWhere((c) => c.id == widget.chat.id);

      if (index != -1) {
        AppChatData.chats[index] = updatedChat;
      }
    }

    debugPrint('UPDATED GROUP IMAGE URL: $_updatedGroupImageUrl');

    _notifyDataChanged();
    _showSnackBar('Group image updated');
  }

  Future<String?> _uploadGroupImage({
    required int conversationId,
    required File imageFile,
  }) async {
    try {
      final formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(
          imageFile.path,
          filename: imageFile.path.split('/').last,
        ),
      });

      final response = await ApiClient.dio.patch(
        '/chat/groups/$conversationId/update/',
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
        ),
      );

      debugPrint('GROUP IMAGE UPDATE STATUS: ${response.statusCode}');
      debugPrint('GROUP IMAGE UPDATE DATA: ${response.data}');

      final data = response.data;

      if (data is Map) {
        final conversation = data['conversation'];

        if (conversation is Map) {
          final imageUrl = conversation['image'] ??
              conversation['group_image'] ??
              conversation['avatar'] ??
              conversation['avatar_url'];

          if (imageUrl != null && imageUrl.toString().trim().isNotEmpty) {
            return imageUrl.toString();
          }
        }

        final imageUrl = data['image'] ??
            data['group_image'] ??
            data['avatar'] ??
            data['avatar_url'];

        if (imageUrl != null && imageUrl.toString().trim().isNotEmpty) {
          return imageUrl.toString();
        }
      }

      return '';
    } on DioException catch (e) {
      debugPrint('UPDATE GROUP IMAGE DIO ERROR STATUS: ${e.response?.statusCode}');
      debugPrint('UPDATE GROUP IMAGE DIO ERROR DATA: ${e.response?.data}');
      debugPrint('UPDATE GROUP IMAGE DIO ERROR MESSAGE: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('UPDATE GROUP IMAGE ERROR: $e');
      return null;
    }
  }

  void _createGroupWithThisUser() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateGroupChatScreen(
          preSelectedUser: ChatUser(
            id: _targetUserIdForBlock(),
            name: widget.chat.name,
            avatarUrl: _resolvedChatAvatarUrl(),
            isOnline: widget.chat.isOnline,
          ),
        ),
      ),
    );
  }


  Future<void> _openAddGroupMemberSheet() async {
    if (!isGroupChat) return;

    final phoneController = TextEditingController();
    ChatUser? foundUser;
    bool searching = false;
    bool adding = false;
    String errorText = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: sheetColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> searchUser() async {
              final phone = phoneController.text.trim();

              if (phone.isEmpty) {
                setModalState(() {
                  errorText = 'Enter phone number';
                  foundUser = null;
                });
                return;
              }

              setModalState(() {
                searching = true;
                errorText = '';
                foundUser = null;
              });

              try {
                final response = await ApiClient.dio.get(
                  '/chat/search-user/',
                  queryParameters: {'phone': phone},
                );

                final data = response.data;

                if (data is! Map) {
                  setModalState(() {
                    errorText = 'User not found';
                    foundUser = null;
                  });
                  return;
                }

                final id = data['id']?.toString() ?? '';

                if (id.isEmpty) {
                  setModalState(() {
                    errorText = 'User not found';
                    foundUser = null;
                  });
                  return;
                }

                final alreadyMember = widget.chat.members.any(
                  (member) => member.id.toString().trim() == id.trim(),
                );

                if (alreadyMember) {
                  setModalState(() {
                    errorText = 'This user is already in the group';
                    foundUser = null;
                  });
                  return;
                }

                setModalState(() {
                  foundUser = ChatUser(
                    id: id,
                    name: data['name']?.toString() ??
                        data['full_name']?.toString() ??
                        'User',
                    phone: data['phone_number']?.toString() ??
                        data['phone']?.toString() ??
                        phone,
                    avatarUrl: _cleanImageUrl(
                      data['profile_picture']?.toString() ??
                          data['avatarUrl']?.toString() ??
                          data['avatar_url']?.toString() ??
                          '',
                    ),
                  );
                  errorText = '';
                });
              } on DioException catch (e) {
                setModalState(() {
                  errorText = e.response?.data is Map
                      ? ((e.response?.data as Map)['error']?.toString() ??
                          'User not found')
                      : 'User not found';
                  foundUser = null;
                });
              } catch (e) {
                setModalState(() {
                  errorText = 'Could not search user';
                  foundUser = null;
                });
              } finally {
                setModalState(() {
                  searching = false;
                });
              }
            }

            Future<void> addUser() async {
              final user = foundUser;
              if (user == null || adding) return;

              setModalState(() {
                adding = true;
                errorText = '';
              });

              try {
                final response = await ApiClient.dio.post(
                  '/chat/groups/${widget.chat.id}/add-member/',
                  data: {'user_id': user.id},
                );

                final ok = response.statusCode == 200 ||
                    response.statusCode == 201 ||
                    response.data is Map &&
                        (response.data['success'] == true ||
                            response.data['created'] != null);

                if (!ok) {
                  setModalState(() {
                    errorText = 'Could not add member';
                  });
                  return;
                }

                final alreadyMember = widget.chat.members.any(
                  (member) => member.id.toString().trim() == user.id.trim(),
                );

                if (!alreadyMember) {
                  widget.chat.members.add(user);
                }

                final index = AppChatData.chats.indexWhere(
                  (chat) => chat.id.toString() == widget.chat.id.toString(),
                );

                if (index >= 0) {
                  final existsInGlobal = AppChatData.chats[index].members.any(
                    (member) =>
                        member.id.toString().trim() == user.id.trim(),
                  );

                  if (!existsInGlobal) {
                    AppChatData.chats[index].members.add(user);
                  }
                }

                AppChatData.notify();

                if (mounted) {
                  setState(() {});
                }

                if (sheetContext.mounted) {
                  Navigator.pop(sheetContext);
                }

                _showSnackBar('${user.name} added to group');
              } on DioException catch (e) {
                setModalState(() {
                  errorText = e.response?.data is Map
                      ? ((e.response?.data as Map)['error']?.toString() ??
                          'Could not add member')
                      : 'Could not add member';
                });
              } catch (e) {
                setModalState(() {
                  errorText = 'Could not add member';
                });
              } finally {
                setModalState(() {
                  adding = false;
                });
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                14,
                20,
                MediaQuery.of(context).viewInsets.bottom + 22,
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Add group member',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: mainTextColor,
                            ),
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => Navigator.pop(sheetContext),
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
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.search,
                      style: TextStyle(color: mainTextColor),
                      decoration: InputDecoration(
                        hintText: 'Enter phone number',
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
                        suffixIcon: IconButton(
                          onPressed: searching ? null : searchUser,
                          icon: searching
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(Icons.search_rounded, color: themeColor),
                        ),
                      ),
                      onSubmitted: (_) => searchUser(),
                    ),
                    if (errorText.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          errorText,
                          style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    if (foundUser != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundImage: foundUser!.avatarUrl.isNotEmpty
                                  ? NetworkImage(foundUser!.avatarUrl)
                                  : null,
                              child: foundUser!.avatarUrl.isEmpty
                                  ? Text(
                                      foundUser!.name.isNotEmpty
                                          ? foundUser!.name[0].toUpperCase()
                                          : 'U',
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                foundUser!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: mainTextColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            ElevatedButton(
                              onPressed: adding ? null : addUser,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: themeColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: adding
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Add'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    phoneController.dispose();
  }


  void _startCall(bool isVideo) {
    final targetUserId = _targetUserIdForBlock();

    if (isBlocked || _blockedMe) {
      _showSnackBar(
        isBlocked
            ? 'You blocked this user. Unblock to send messages.'
            : 'This user is unavailable.',
      );
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
          avatarUrl: _resolvedChatAvatarUrl(),
          isVideoCall: isVideo,
          chat: widget.chat,
          currentUserId: widget.currentUserId,
          currentUserName: widget.currentUserName,
          currentUserAvatar: widget.currentUserAvatar,
          receiverId: targetUserId,
          isCaller: true,
          conversationId: widget.chat.id,
        ),
      ),
    ).then((_) {
      if (mounted) _notifyDataChanged();
    });
  }

  // void _viewProfile() {
  //   Navigator.push(
  //     context,
  //     MaterialPageRoute(
  //       builder: (_) => const ProfileDataPage(),
  //     ),
  //   );
  // }

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

              if (!isGroupChat) ...[
                const SizedBox(height: 22),
                _buildSectionTitle('More actions'),
                _buildSettingsCard(
                  children: [
                    _SettingsTile(
                      icon: Icons.group_add_rounded,
                      iconColor: const Color(0xFF1877F2),
                      title: 'Create group with ${widget.chat.name}',
                      subtitle: 'Add more people to this chat',
                      showDivider: false,
                      onTap: _createGroupWithThisUser,
                    ),
                  ],
                ),
              ],

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
                    Consumer<BlockProvider>(
                      builder: (context, blockProvider, _) {
                        if (_blockedMe) {
                          return const SizedBox.shrink();
                        }

                        return _DangerTile(
                          icon: Icons.block_rounded,
                          title: blockProvider.isLoading
                              ? 'Please wait...'
                              : isBlocked
                                  ? 'Unblock'
                                  : 'Block',
                          showDivider: false,
                          onTap: blockProvider.isLoading ? () {} : _openBlockOptions,
                        );
                      },
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
              if (value == 'mute') {
                _openMuteSheet();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'mute',
                child: Text(
                  'Mute notifications',
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
    debugPrint('SETTINGS CHAT AVATAR: ${_resolvedChatAvatarUrl()}');

    return ScaleTransition(
      scale: _headerScaleAnimation,
      child: Column(
        children: [
          Center(
            child: GestureDetector(
              onTap: isGroupChat ? _changeGroupImage : _bounceHeader,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 59,
                    backgroundColor:
                        isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB),
                    backgroundImage: _resolvedChatAvatarUrl().isNotEmpty
                        ? (_resolvedChatAvatarUrl().startsWith('http://') ||
                                _resolvedChatAvatarUrl().startsWith('https://')
                            ? NetworkImage(_resolvedChatAvatarUrl())
                            : FileImage(File(_resolvedChatAvatarUrl()))
                                as ImageProvider)
                        : null,
                    onBackgroundImageError: _resolvedChatAvatarUrl().isNotEmpty
                        ? (Object error, StackTrace? stackTrace) {
                            debugPrint(
                              'SETTINGS PROFILE AVATAR ERROR: $error',
                            );
                          }
                        : null,
                    child: _resolvedChatAvatarUrl().isEmpty
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
                  if (isGroupChat)
                    Positioned(
                      right: -2,
                      bottom: 6,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: themeColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: bgColor, width: 3),
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    )
                  else if (widget.chat.isOnline)
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
            _blockedMe
                ? 'Unavailable'
                : isBlocked
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
  final actions = <Widget>[
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
  ];

  if (isGroupChat) {
    actions.add(
      _CircleActionButton(
        icon: Icons.person_add_alt_1_rounded,
        iconColor: themeColor,
        label: 'Add member',
        onTap: _openAddGroupMemberSheet,
      ),
    );
  }

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: actions,
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
                    trailing: isSelected
                        ? Icon(Icons.check_rounded, color: themeColor)
                        : null,
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
              final targetUserId = _targetUserIdForBlock();

              final latestOtherName = _realNameForUser(
                userId: targetUserId,
                fallbackRealName: widget.chat.name,
              );

              final latestMyName = _realNameForUser(
                userId: widget.currentUserId,
                fallbackRealName: widget.currentUserName.isNotEmpty
                    ? widget.currentUserName
                    : 'You',
              );

              final displayOtherNickname = _displayNameForUser(
                userId: targetUserId,
                fallbackRealName: latestOtherName,
              );

              final displayMyNickname = _displayNameForUser(
                userId: widget.currentUserId,
                fallbackRealName: latestMyName,
              );

              final actualOtherNickname = _initialNicknameForEditor(targetUserId);
              final actualMyNickname = _initialNicknameForEditor(widget.currentUserId);

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
                              final memberId = member.id.toString();
                              final nickname = _displayNameForUser(
                                userId: memberId,
                                fallbackRealName: member.name,
                              );
                              final actualNickname =
                                  _initialNicknameForEditor(memberId);

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
                                    initialValue: actualNickname,
                                  );

                                  if (value == null) return;

                                  final cleanedValue = value.trim();

                                  final success = await _updateMemberNicknameApi(
                                    conversationId: widget.chat.id.toString(),
                                    userId: memberId,
                                    nickname: cleanedValue,
                                  );

                                  if (!success) {
                                    _showSnackBar('Could not update nickname');
                                    return;
                                  }

                                  setState(() {
                                    _applyNicknameLocally(
                                      userId: memberId,
                                      nickname: cleanedValue,
                                    );
                                  });

                                  setModalState(() {});
                                  _notifyDataChanged();
                                  _showSnackBar(
                                    cleanedValue.isEmpty
                                        ? 'Nickname removed'
                                        : 'Nickname updated',
                                  );
                                },
                              );
                            }).toList(),
                          ),
                        )
                    else ...[
                      _NicknameRowTile(
                        avatarUrl: _resolvedChatAvatarUrl(),
                        fallbackLetter: latestOtherName.isNotEmpty
                            ? latestOtherName[0].toUpperCase()
                            : 'U',
                        nickname: displayOtherNickname,
                        realName: latestOtherName,
                        onEdit: () async {
                          final value = await _showNicknameEditSheet(
                            title: latestOtherName,
                            initialValue: actualOtherNickname,
                          );

                          if (value == null) return;

                          final targetUserId = _targetUserIdForBlock();

                          if (targetUserId.isEmpty) {
                            _showSnackBar('Could not find user');
                            return;
                          }

                          final cleanedValue = value.trim();

                          final success = await _updateMemberNicknameApi(
                            conversationId: widget.chat.id.toString(),
                            userId: targetUserId,
                            nickname: cleanedValue,
                          );

                          if (!success) {
                            _showSnackBar('Could not update nickname');
                            return;
                          }

                          setState(() {
                            otherNickname = '';

                            _applyNicknameLocally(
                              userId: targetUserId,
                              nickname: cleanedValue,
                            );
                          });

                          setModalState(() {});
                          _notifyDataChanged();
                          _showSnackBar(
                            cleanedValue.isEmpty
                                ? 'Nickname removed'
                                : 'Nickname updated',
                          );
                        },
                      ),
                      _NicknameRowTile(
                        avatarUrl: widget.currentUserAvatar,
                        fallbackLetter: latestMyName.isNotEmpty
                            ? latestMyName[0].toUpperCase()
                            : 'Y',
                        nickname: displayMyNickname,
                        realName: latestMyName,
                        avatarBackgroundColor: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE4E6EB),
                        onEdit: () async {
                          final value = await _showNicknameEditSheet(
                            title: 'You',
                            initialValue: actualMyNickname,
                          );

                          if (value == null) return;

                          final currentUserId = widget.currentUserId.trim();

                          if (currentUserId.isEmpty) {
                            _showSnackBar('Current user not found');
                            return;
                          }

                          final cleanedValue = value.trim();

                          final success = await _updateMemberNicknameApi(
                            conversationId: widget.chat.id.toString(),
                            userId: currentUserId,
                            nickname: cleanedValue,
                          );

                          if (!success) {
                            _showSnackBar('Could not update nickname');
                            return;
                          }

                          setState(() {
                            myNickname = 'You';

                            _applyNicknameLocally(
                              userId: currentUserId,
                              nickname: cleanedValue,
                            );
                          });

                          setModalState(() {});
                          _notifyDataChanged();
                          _showSnackBar(
                            cleanedValue.isEmpty
                                ? 'Nickname removed'
                                : 'Nickname updated',
                          );
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

    if (_blockedMe) {
      _showSnackBar('This user is unavailable.');
      return;
    }

    final targetUserId = _targetUserIdForBlock();

    if (targetUserId.isEmpty) {
      _showSnackBar('Could not find user to block');
      return;
    }

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MessengerBlockPage(
          name: widget.chat.name,
          isBlocked: isBlocked,
        ),
      ),
    );

    if (result == null) return;

    final blockProvider = context.read<BlockProvider>();

    final success = await blockProvider.setBlockStatus(
      conversationId: widget.chat.id,
      targetUserId: targetUserId,
      blocked: result,
      isGroupChat: false,
    );

    if (!mounted) return;

    if (!success) {
      _showSnackBar(
        blockProvider.error.isNotEmpty
            ? blockProvider.error
            : result
                ? 'Could not block ${widget.chat.name}'
                : 'Could not unblock ${widget.chat.name}',
      );
      return;
    }

    blockProvider.setLocalBlocked(
      conversationId: widget.chat.id,
      targetUserId: targetUserId,
      value: result,
    );

    blockProvider.setLocalBlockedMe(
      conversationId: widget.chat.id,
      targetUserId: targetUserId,
      value: false,
    );

    setState(() {
      isBlocked = result;
      _blockedMe = false;
    });

    _notifyDataChanged();

    _showSnackBar(
      isBlocked
          ? '${widget.chat.name} blocked'
          : '${widget.chat.name} unblocked',
    );

    Navigator.pop(context, true);
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

  String _cleanNicknameAvatarUrl(String value) {
    final cleanValue = value.trim();

    if (cleanValue.isEmpty) return '';

    final mediaBaseUrl = AppConfig.apiBaseUrl.replaceFirst('/api', '');

    if (cleanValue.startsWith('http://') || cleanValue.startsWith('https://')) {
      return cleanValue.replaceFirst('/api/media/', '/media/');
    }

    if (cleanValue.startsWith('/media/')) {
      return '$mediaBaseUrl$cleanValue';
    }

    if (cleanValue.startsWith('media/')) {
      return '$mediaBaseUrl/$cleanValue';
    }

    return cleanValue;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? const Color(0xFFCBD5E1) : Colors.black87;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Builder(
            builder: (_) {
              final cleanAvatarUrl = _cleanNicknameAvatarUrl(avatarUrl);

              return CircleAvatar(
                radius: 28,
                backgroundColor: avatarBackgroundColor ??
                    (isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE4E6EB)),
                backgroundImage:
                    cleanAvatarUrl.isNotEmpty ? NetworkImage(cleanAvatarUrl) : null,
                onBackgroundImageError: cleanAvatarUrl.isNotEmpty
                    ? (Object error, StackTrace? stackTrace) {
                        debugPrint('NICKNAME AVATAR ERROR: $error');
                      }
                    : null,
                child: cleanAvatarUrl.isEmpty
                    ? Text(
                        fallbackLetter,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      )
                    : null,
              );
            },
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
