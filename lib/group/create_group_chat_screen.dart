import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hiddenly/chat_detail.dart';
import 'package:hiddenly/chat_models.dart';
import 'package:hiddenly/core/chat/chat_provider.dart';
import 'package:hiddenly/core/config/app_config.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class CreateGroupChatScreen extends StatefulWidget {
  final ChatUser? preSelectedUser;

  const CreateGroupChatScreen({
    super.key,
    this.preSelectedUser,
  });

  @override
  State<CreateGroupChatScreen> createState() =>
      _CreateGroupChatScreenState();
}

class _CreateGroupChatScreenState extends State<CreateGroupChatScreen> {
  final TextEditingController _groupNameController =
      TextEditingController();

  final TextEditingController _phoneSearchController =
      TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();

  // Only OTHER users are stored here.
  // The current logged-in creator is not included.
  //
  // Therefore:
  // 0 selected = creator only
  // 1 selected = creator + 1 person = NOT a group
  // 2 selected = creator + 2 people = valid group of 3
  final Set<String> _selectedUserIds = {};

  File? _groupImage;

  bool _isCreating = false;

  String _phoneQuery = '';

  // ===============================================================
  // GROUP VALIDATION
  // ===============================================================

  bool get _hasValidGroupName =>
      _groupNameController.text.trim().isNotEmpty;

  bool get _hasMinimumMembers =>
      _selectedUserIds.length >= 2;

  bool get _canCreateGroup =>
      !_isCreating &&
      _hasValidGroupName &&
      _hasMinimumMembers;

  int get _totalGroupMembers {
    // +1 = currently logged-in creator.
    return _selectedUserIds.length + 1;
  }

  // ===============================================================
  // INIT
  // ===============================================================

  @override
  void initState() {
    super.initState();

    // If this page was opened from:
    // "Create group with <person>"
    //
    // that person is already selected.
    if (widget.preSelectedUser != null) {
      _selectedUserIds.add(
        widget.preSelectedUser!.id,
      );
    }

    // Update Create button when group name changes.
    _groupNameController.addListener(
      _onGroupNameChanged,
    );

    // Update phone filtering.
    _phoneSearchController.addListener(
      _onPhoneSearchChanged,
    );

    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        if (!mounted) return;

        context
            .read<ChatProvider>()
            .loadConversations();
      },
    );
  }

  void _onGroupNameChanged() {
    if (!mounted) return;

    setState(() {});
  }

  void _onPhoneSearchChanged() {
    if (!mounted) return;

    setState(() {
      _phoneQuery =
          _phoneSearchController.text.trim();
    });
  }

  @override
  void dispose() {
    _groupNameController.removeListener(
      _onGroupNameChanged,
    );

    _phoneSearchController.removeListener(
      _onPhoneSearchChanged,
    );

    _groupNameController.dispose();
    _phoneSearchController.dispose();

    super.dispose();
  }

  // ===============================================================
  // HELPERS
  // ===============================================================

  String _digitsOnly(String value) {
    return value.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
  }

  String _cleanImageUrl(String value) {
    final cleanValue = value.trim();

    if (cleanValue.isEmpty) {
      return '';
    }

    if (cleanValue.startsWith('http://') ||
        cleanValue.startsWith('https://')) {
      return cleanValue;
    }

    if (cleanValue.startsWith('/media/')) {
      return '${AppConfig.apiBaseUrl}$cleanValue';
    }

    if (cleanValue.startsWith('media/')) {
      return '${AppConfig.apiBaseUrl}/$cleanValue';
    }

    return cleanValue;
  }

  // ===============================================================
  // GROUP IMAGE
  // ===============================================================

  Future<void> _pickGroupImage() async {
    if (_isCreating) {
      return;
    }

    final source =
        await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (context) {
        final isDark =
            Theme.of(context).brightness ==
                Brightness.dark;

        final textColor =
            isDark
                ? Colors.white
                : Colors.black87;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              20,
              8,
              20,
              22,
            ),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                Align(
                  alignment:
                      Alignment.centerLeft,
                  child: Text(
                    'Group image',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 20,
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                ListTile(
                  contentPadding:
                      EdgeInsets.zero,
                  leading: const Icon(
                    Icons.photo_camera_rounded,
                    color: Color(
                      0xFF1877F2,
                    ),
                  ),
                  title: Text(
                    'Take photo',
                    style: TextStyle(
                      color: textColor,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(
                      context,
                      ImageSource.camera,
                    );
                  },
                ),

                ListTile(
                  contentPadding:
                      EdgeInsets.zero,
                  leading: const Icon(
                    Icons.photo_library_rounded,
                    color: Color(
                      0xFF1877F2,
                    ),
                  ),
                  title: Text(
                    'Choose from gallery',
                    style: TextStyle(
                      color: textColor,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(
                      context,
                      ImageSource.gallery,
                    );
                  },
                ),

                if (_groupImage != null)
                  ListTile(
                    contentPadding:
                        EdgeInsets.zero,
                    leading: const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(
                        0xFFEF4444,
                      ),
                    ),
                    title: const Text(
                      'Remove image',
                      style: TextStyle(
                        color: Color(
                          0xFFEF4444,
                        ),
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        _groupImage = null;
                      });

                      Navigator.pop(
                        context,
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) {
      return;
    }

    final picked =
        await _imagePicker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1800,
    );

    if (picked == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _groupImage =
          File(picked.path);
    });
  }

  // ===============================================================
  // CREATE GROUP
  // ===============================================================

  Future<void> _createGroup() async {
    if (_isCreating) {
      return;
    }

    final name =
        _groupNameController.text.trim();

    // -------------------------------------------------------------
    // GROUP NAME VALIDATION
    // -------------------------------------------------------------

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a group name.',
          ),
          behavior:
              SnackBarBehavior.floating,
        ),
      );

      return;
    }

    // -------------------------------------------------------------
    // MEMBER VALIDATION
    //
    // Creator is already member #1.
    // User must select minimum 2 OTHER people.
    //
    // Creator + Person A = 2 people -> private chat
    //
    // Creator + Person A + Person B
    // = 3 people -> valid group
    // -------------------------------------------------------------

    if (_selectedUserIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A group needs at least 3 people. '
            'Select at least 2 other people.',
          ),
          behavior:
              SnackBarBehavior.floating,
        ),
      );

      return;
    }

    // Convert IDs safely and remove duplicates.
    final memberIds =
        _selectedUserIds
            .map(
              (id) =>
                  int.tryParse(id),
            )
            .whereType<int>()
            .toSet()
            .toList();

    // Validate again AFTER conversion.
    if (memberIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A group needs at least 2 valid additional members.',
          ),
          behavior:
              SnackBarBehavior.floating,
        ),
      );

      return;
    }

    setState(() {
      _isCreating = true;
    });

    final provider =
        context.read<ChatProvider>();

    try {
      final group =
          await provider.createGroup(
        name: name,
        memberIds: memberIds,
        groupImage: _groupImage,
      );

      if (!mounted) {
        return;
      }

      if (group == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              provider.error ??
                  'Failed to create group',
            ),
            behavior:
                SnackBarBehavior.floating,
          ),
        );

        return;
      }

      // Group successfully created.
      //
      // Open actual group chat immediately.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ChatDetailScreen(
            chat: group,
          ),
        ),
      );
    } catch (e) {
      debugPrint(
        'CREATE GROUP ERROR: $e',
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            provider.error ??
                'Failed to create group',
          ),
          behavior:
              SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  // ===============================================================
  // USER SELECTION
  // ===============================================================

  void _toggleUser(
    String userId,
  ) {
    if (_isCreating) {
      return;
    }

    setState(() {
      if (_selectedUserIds.contains(
        userId,
      )) {
        _selectedUserIds.remove(
          userId,
        );
      } else {
        _selectedUserIds.add(
          userId,
        );
      }
    });
  }

  // ===============================================================
  // BUILD
  // ===============================================================

  @override
  Widget build(BuildContext context) {
    final provider =
        context.watch<ChatProvider>();

    // Existing private conversations are being used
    // as available people, preserving your current logic.
    final allUsers =
        provider.conversations
            .where(
              (chat) =>
                  chat.isGroup != true,
            )
            .toList();

    final searchDigits =
        _digitsOnly(
      _phoneQuery,
    );

    final users =
        searchDigits.isEmpty
            ? allUsers
            : allUsers.where(
                (user) {
                  final phone =
                      _digitsOnly(
                    ((user as dynamic)
                                .phone ??
                            '')
                        .toString(),
                  );

                  return phone.contains(
                    searchDigits,
                  );
                },
              ).toList();

    final isDark =
        Theme.of(context).brightness ==
            Brightness.dark;

    final bg = isDark
        ? const Color(
            0xFF0B1220,
          )
        : Colors.white;

    final card = isDark
        ? const Color(
            0xFF1E293B,
          )
        : const Color(
            0xFFF1F2F6,
          );

    final text =
        isDark
            ? Colors.white
            : Colors.black87;

    final subText =
        isDark
            ? const Color(
                0xFF94A3B8,
              )
            : const Color(
                0xFF6B7280,
              );

    return Scaffold(
      backgroundColor: bg,

      // =============================================================
      // APP BAR
      // =============================================================

      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,

        leading: IconButton(
          icon: Icon(
            Icons.close_rounded,
            color: text,
          ),
          onPressed:
              _isCreating
                  ? null
                  : () {
                      Navigator.pop(
                        context,
                      );
                    },
        ),

        title: Text(
          'New group',
          style: TextStyle(
            color: text,
            fontWeight:
                FontWeight.w800,
          ),
        ),

        actions: [
          TextButton(
            // Button is enabled ONLY when:
            //
            // 1. group name exists
            // 2. at least 2 other people are selected
            // 3. group isn't already being created
            onPressed:
                _canCreateGroup
                    ? _createGroup
                    : null,

            child:
                _isCreating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Create',
                        style: TextStyle(
                          color:
                              _canCreateGroup
                                  ? const Color(
                                      0xFF1877F2,
                                    )
                                  : subText,
                          fontWeight:
                              FontWeight.w800,
                        ),
                      ),
          ),
        ],
      ),

      // =============================================================
      // BODY
      // =============================================================

      body: Column(
        children: [
          // =========================================================
          // GROUP NAME + GROUP IMAGE
          // =========================================================

          Container(
            margin:
                const EdgeInsets.all(
              16,
            ),
            padding:
                const EdgeInsets.all(
              14,
            ),
            decoration:
                BoxDecoration(
              color: card,
              borderRadius:
                  BorderRadius.circular(
                20,
              ),
            ),
            child: Row(
              children: [
                // ---------------------------------------------------
                // GROUP IMAGE
                // ---------------------------------------------------

                GestureDetector(
                  onTap:
                      _isCreating
                          ? null
                          : _pickGroupImage,
                  child: Stack(
                    clipBehavior:
                        Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor:
                            const Color(
                          0xFF1877F2,
                        ),
                        backgroundImage:
                            _groupImage != null
                                ? FileImage(
                                    _groupImage!,
                                  )
                                : null,
                        child:
                            _groupImage == null
                                ? const Icon(
                                    Icons
                                        .groups_rounded,
                                    color:
                                        Colors.white,
                                  )
                                : null,
                      ),

                      Positioned(
                        right: -3,
                        bottom: -3,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration:
                              BoxDecoration(
                            color:
                                const Color(
                              0xFF1877F2,
                            ),
                            shape:
                                BoxShape.circle,
                            border:
                                Border.all(
                              color: bg,
                              width: 2,
                            ),
                          ),
                          child:
                              const Icon(
                            Icons
                                .camera_alt_rounded,
                            color:
                                Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(
                  width: 12,
                ),

                // ---------------------------------------------------
                // GROUP NAME
                // ---------------------------------------------------

                Expanded(
                  child: TextField(
                    controller:
                        _groupNameController,
                    enabled:
                        !_isCreating,
                    style:
                        TextStyle(
                      color: text,
                    ),
                    textCapitalization:
                        TextCapitalization
                            .words,
                    decoration:
                        InputDecoration(
                      hintText:
                          'Group name',
                      hintStyle:
                          TextStyle(
                        color:
                            subText,
                      ),
                      border:
                          InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // =========================================================
          // MEMBER COUNTER
          // =========================================================

          Padding(
            padding:
                const EdgeInsets.fromLTRB(
              18,
              0,
              18,
              5,
            ),
            child: Row(
              children: [
                Text(
                  'Select people',
                  style: TextStyle(
                    color: text,
                    fontSize: 16,
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),

                const Spacer(),

                Text(
                  '${_selectedUserIds.length} selected',
                  style: TextStyle(
                    color: _hasMinimumMembers
                        ? const Color(
                            0xFF1877F2,
                          )
                        : subText,
                    fontSize: 13,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // =========================================================
          // TOTAL MEMBER INFORMATION
          // =========================================================

          Padding(
            padding:
                const EdgeInsets.fromLTRB(
              18,
              0,
              18,
              12,
            ),
            child: Align(
              alignment:
                  Alignment.centerLeft,
              child: Text(
                _hasMinimumMembers
                    ? '$_totalGroupMembers total members'
                    : 'Select at least 2 people. '
                        'You are automatically included.',
                style: TextStyle(
                  color:
                      _hasMinimumMembers
                          ? const Color(
                              0xFF22C55E,
                            )
                          : subText,
                  fontSize: 12,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ),
          ),

          // =========================================================
          // PHONE SEARCH
          // =========================================================

          Padding(
            padding:
                const EdgeInsets.fromLTRB(
              16,
              0,
              16,
              12,
            ),
            child: TextField(
              controller:
                  _phoneSearchController,
              enabled:
                  !_isCreating,
              keyboardType:
                  TextInputType.phone,
              style:
                  TextStyle(
                color: text,
              ),
              decoration:
                  InputDecoration(
                hintText:
                    'Search by phone number',
                hintStyle:
                    TextStyle(
                  color: subText,
                ),
                prefixIcon:
                    const Icon(
                  Icons.phone_rounded,
                  color:
                      Color(
                    0xFF1877F2,
                  ),
                ),
                suffixIcon:
                    _phoneQuery
                            .isNotEmpty
                        ? IconButton(
                            icon:
                                Icon(
                              Icons
                                  .close_rounded,
                              color:
                                  subText,
                            ),
                            onPressed:
                                () {
                              _phoneSearchController
                                  .clear();
                            },
                          )
                        : null,
                filled: true,
                fillColor: card,
                border:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(
                    18,
                  ),
                  borderSide:
                      BorderSide.none,
                ),
              ),
            ),
          ),

          // =========================================================
          // LOADING
          // =========================================================

          if (provider.isLoading &&
              allUsers.isEmpty)
            const Expanded(
              child: Center(
                child:
                    CircularProgressIndicator(),
              ),
            )

          // =========================================================
          // EMPTY
          // =========================================================

          else if (users.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding:
                      const EdgeInsets.all(
                    24,
                  ),
                  child: Text(
                    searchDigits.isEmpty
                        ? 'No users found.'
                        : 'No user found with this phone number.',
                    textAlign:
                        TextAlign.center,
                    style:
                        TextStyle(
                      color: subText,
                      fontWeight:
                          FontWeight.w600,
                    ),
                  ),
                ),
              ),
            )

          // =========================================================
          // PEOPLE LIST
          // =========================================================

          else
            Expanded(
              child:
                  ListView.builder(
                itemCount:
                    users.length,
                itemBuilder:
                    (
                  context,
                  index,
                ) {
                  final user =
                      users[index];

                  final selected =
                      _selectedUserIds
                          .contains(
                    user.id,
                  );

                  return ListTile(
                    enabled:
                        !_isCreating,

                    onTap: () {
                      _toggleUser(
                        user.id,
                      );
                    },

                    // ------------------------------------------------
                    // AVATAR
                    // ------------------------------------------------

                    leading:
                        Builder(
                      builder: (_) {
                        final avatarUrl =
                            _cleanImageUrl(
                          user.avatarUrl,
                        );

                        return CircleAvatar(
                          backgroundImage:
                              avatarUrl
                                      .isNotEmpty
                                  ? NetworkImage(
                                      avatarUrl,
                                    )
                                  : null,
                          onBackgroundImageError:
                              avatarUrl
                                      .isNotEmpty
                                  ? (
                                      Object
                                          error,
                                      StackTrace?
                                          stackTrace,
                                    ) {
                                      debugPrint(
                                        'CREATE GROUP USER AVATAR ERROR: $error',
                                      );
                                    }
                                  : null,
                          child:
                              avatarUrl
                                      .isEmpty
                                  ? Text(
                                      user.name
                                              .isNotEmpty
                                          ? user
                                              .name[0]
                                              .toUpperCase()
                                          : 'U',
                                    )
                                  : null,
                        );
                      },
                    ),

                    // ------------------------------------------------
                    // NAME
                    // ------------------------------------------------

                    title: Text(
                      user.name,
                      style: TextStyle(
                        color: text,
                        fontWeight:
                            FontWeight
                                .w700,
                      ),
                    ),

                    // ------------------------------------------------
                    // PHONE
                    // ------------------------------------------------

                    subtitle: Text(
                      (() {
                        final phone =
                            ((user as dynamic)
                                        .phone ??
                                    '')
                                .toString();

                        return phone
                                .isNotEmpty
                            ? phone
                            : 'No phone number';
                      })(),
                      style:
                          TextStyle(
                        color:
                            subText,
                      ),
                    ),

                    // ------------------------------------------------
                    // SELECTED INDICATOR
                    // ------------------------------------------------

                    trailing:
                        CircleAvatar(
                      radius: 13,
                      backgroundColor:
                          selected
                              ? const Color(
                                  0xFF1877F2,
                                )
                              : Colors
                                  .transparent,
                      child:
                          selected
                              ? const Icon(
                                  Icons.check,
                                  color:
                                      Colors.white,
                                  size:
                                      18,
                                )
                              : Icon(
                                  Icons
                                      .circle_outlined,
                                  color:
                                      subText,
                                  size: 26,
                                ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}