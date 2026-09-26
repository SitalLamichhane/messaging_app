import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:characters/characters.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:hiddenly/chat_models.dart';
import 'package:hiddenly/core/api_client.dart';
import 'package:hiddenly/core/chat/chat_provider.dart';

class CreateGroupChatScreen extends StatefulWidget {

  final String currentUserId;
  final ChatUser? preSelectedUser;

  const CreateGroupChatScreen({
    super.key,
    this.currentUserId = '',
    this.preSelectedUser,
  });

  @override
  State<CreateGroupChatScreen> createState() =>
      _CreateGroupChatScreenState();
}

class _CreateGroupChatScreenState
    extends State<CreateGroupChatScreen> {
  final TextEditingController _groupNameController =
      TextEditingController();

  final TextEditingController _searchController =
      TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();

  final Map<int, Map<String, dynamic>> _selectedUsers = {};

  Timer? _searchDebounce;

  File? _groupImage;

  bool _creatingGroup = false;

  String _currentUserId = '';

  // =============================================================
  // INIT
  // =============================================================

  @override
  void initState() {
    super.initState();

    _currentUserId = widget.currentUserId.trim();

    // Auto select the user when creating group from private chat settings
    if (widget.preSelectedUser != null) {
      final user = widget.preSelectedUser!;

      final id = int.tryParse(user.id.toString());

      if (id != null) {
        _selectedUsers[id] = {
          "id": id,
          "name": user.name,
          "phone_number": user.phone,
          "avatar_url": user.avatarUrl,
        };
      }
    }

    WidgetsBinding.instance.addPostFrameCallback(
      (_) async {
        await _loadCurrentUser();
      },
    );
  }

  Future<void> _loadCurrentUser() async {

    if (_currentUserId.trim().isNotEmpty) {
      return;
    }

    final id =
        (await ApiClient.storage.read(key: 'user_id'))?.trim() ?? '';

    if (!mounted) return;

    setState(() {
      _currentUserId = id;
    });
  }

  // =============================================================
  // DISPOSE
  // =============================================================

  @override
  void dispose() {
    _searchDebounce?.cancel();

    _groupNameController.dispose();
    _searchController.dispose();

    super.dispose();
  }

  // =============================================================
  // USER HELPERS
  // =============================================================

  int? _userId(dynamic user) {
    if (user is! Map) {
      return null;
    }

    final value = user['id'] ??
        user['user_id'] ??
        user['pk'];

    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    return int.tryParse(
      value.toString(),
    );
  }

  String _userName(dynamic user) {
    if (user is! Map) {
      return 'Unknown';
    }

    final value = user['name'] ??
        user['full_name'] ??
        user['profile_name'] ??
        user['username'] ??
        user['phone_number'] ??
        user['phone'];

    final name =
        value?.toString().trim() ?? '';

    if (name.isEmpty ||
        name == 'null') {
      return 'Unknown';
    }

    return name;
  }

  String _userPhone(dynamic user) {
    if (user is! Map) {
      return '';
    }

    final value = user['phone_number'] ??
        user['phone'] ??
        '';

    return value.toString().trim();
  }

  String _userAvatar(dynamic user) {
    if (user is! Map) {
      return '';
    }

    final value = user['profile_picture'] ??
        user['profilePicture'] ??
        user['avatar'] ??
        user['avatar_url'] ??
        user['profile_image'] ??
        user['image'] ??
        user['photo'] ??
        '';

    return value.toString().trim();
  }

  bool _isCurrentUser(dynamic user) {
    final id = _userId(user);

    if (id == null) {
      return false;
    }

    if (_currentUserId.trim().isEmpty) {
      return false;
    }

    return id.toString() ==
        _currentUserId.trim();
  }

  // =============================================================
  // SEARCH
  // =============================================================

  void _onSearchChanged(
    String value,
  ) {
    _searchDebounce?.cancel();

    final query = value.trim();

    if (query.isEmpty) {
      final provider =
          context.read<ChatProvider>();

      provider.searchedUsers.clear();
      provider.notifyListeners();

      return;
    }

    _searchDebounce = Timer(
      const Duration(
        milliseconds: 450,
      ),
      () async {
        if (!mounted) return;

        // Your current ChatProvider search is phone based.
        if (query.length < 3) {
          return;
        }

        await context
            .read<ChatProvider>()
            .searchUsers(query);
      },
    );
  }

  // =============================================================
  // SELECT USER
  // =============================================================

  void _toggleUser(
    dynamic rawUser,
  ) {
    if (rawUser is! Map) {
      return;
    }

    final user =
        Map<String, dynamic>.from(
      rawUser,
    );

    final id = _userId(user);

    if (id == null) {
      _showMessage(
        'Unable to select this user.',
      );

      return;
    }

    if (_isCurrentUser(user)) {
      _showMessage(
        'You are automatically included in the group.',
      );

      return;
    }

    setState(() {
      if (_selectedUsers.containsKey(id)) {
        _selectedUsers.remove(id);
      } else {
        _selectedUsers[id] = user;
      }
    });
  }

  bool _isSelected(
    dynamic user,
  ) {
    final id = _userId(user);

    if (id == null) {
      return false;
    }

    return _selectedUsers.containsKey(id);
  }

  // =============================================================
  // REMOVE SELECTED USER
  // =============================================================

  void _removeSelectedUser(
    int userId,
  ) {
    setState(() {
      _selectedUsers.remove(userId);
    });
  }

  // =============================================================
  // IMAGE PICKER
  // =============================================================

  Future<void> _pickGroupImage() async {
    try {
      final image =
          await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (image == null) {
        return;
      }

      if (!mounted) return;

      setState(() {
        _groupImage =
            File(image.path);
      });
    } catch (e) {
      debugPrint(
        'GROUP IMAGE PICK ERROR: $e',
      );

      if (!mounted) return;

      _showMessage(
        'Unable to select image.',
      );
    }
  }

  void _removeGroupImage() {
    setState(() {
      _groupImage = null;
    });
  }

  // =============================================================
  // CREATE GROUP
  // =============================================================

  Future<void> _createGroup() async {
    if (_creatingGroup) {
      return;
    }

    final name =
        _groupNameController.text.trim();

    // -------------------------------------------------------------
    // VALIDATION
    // -------------------------------------------------------------

    if (name.isEmpty) {
      _showMessage(
        'Please enter a group name.',
      );

      return;
    }

    if (_selectedUsers.isEmpty) {
      _showMessage(
        'Please select at least one member.',
      );

      return;
    }

    final memberIds =
        _selectedUsers.keys.toList();

    debugPrint(
      '======================================',
    );

    debugPrint(
      'CREATING GROUP',
    );

    debugPrint(
      'NAME: $name',
    );

    debugPrint(
      'MEMBERS: $memberIds',
    );

    debugPrint(
      'IMAGE: ${_groupImage?.path}',
    );

    debugPrint(
      '======================================',
    );

    setState(() {
      _creatingGroup = true;
    });

    try {
      final provider =
          context.read<ChatProvider>();

      // -----------------------------------------------------------
      // IMPORTANT
      //
      // ChatProvider.createGroup() already:
      //
      // 1. Calls backend
      // 2. Maps response to ChatItem
      // 3. Calls _upsertConversation(chat)
      // 4. notifyListeners()
      // 5. Returns ChatItem
      // -----------------------------------------------------------

      final ChatItem? chat =
          await provider.createGroup(
        name: name,
        memberIds: memberIds,
        groupImage: _groupImage,
      );

      if (!mounted) {
        return;
      }

      // -----------------------------------------------------------
      // FAILED
      // -----------------------------------------------------------

      if (chat == null) {
        debugPrint(
          'GROUP CREATION FAILED',
        );

        debugPrint(
          'Provider error: ${provider.error}',
        );

        _showMessage(
          provider.error ??
              'Failed to create group.',
        );

        return;
      }

      // -----------------------------------------------------------
      // SUCCESS
      // -----------------------------------------------------------

      debugPrint(
        '======================================',
      );

      debugPrint(
        'GROUP CREATED SUCCESSFULLY',
      );

      debugPrint(
        'ID: ${chat.id}',
      );

      debugPrint(
        'NAME: ${chat.name}',
      );

      debugPrint(
        'IS GROUP: ${chat.isGroup}',
      );

      debugPrint(
        'MEMBERS: ${chat.members.length}',
      );

      debugPrint(
        '======================================',
      );

      // -----------------------------------------------------------
      // IMPORTANT
      //
      // Return ChatItem.
      //
      // DO NOT:
      //
      // Navigator.pop(context, true);
      //
      // ChatListScreen needs the ChatItem.
      // -----------------------------------------------------------

      Navigator.pop(
        context,
        chat,
      );
    } catch (
      error,
      stackTrace
    ) {
      debugPrint(
        'CREATE GROUP EXCEPTION: $error',
      );

      debugPrint(
        '$stackTrace',
      );

      if (!mounted) return;

      _showMessage(
        'Unable to create group.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _creatingGroup = false;
        });
      }
    }
  }

  // =============================================================
  // MESSAGE
  // =============================================================

  void _showMessage(
    String message,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .hideCurrentSnackBar();

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          message,
        ),
        behavior:
            SnackBarBehavior.floating,
      ),
    );
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final provider =
        context.watch<ChatProvider>();

    final isDark =
        Theme.of(context).brightness ==
            Brightness.dark;

    final backgroundColor = isDark
        ? const Color(0xFF0F172A)
        : const Color(0xFFF5F7FB);

    final cardColor = isDark
        ? const Color(0xFF1E293B)
        : Colors.white;

    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE5E7EB);

    final secondaryTextColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF6B7280);

    final users = provider.searchedUsers
        .where(
          (user) => !_isCurrentUser(user),
        )
        .toList();

    return Scaffold(
      backgroundColor:
          backgroundColor,

      appBar: AppBar(
        elevation: 0,
        backgroundColor:
            backgroundColor,
        surfaceTintColor:
            Colors.transparent,

        leading: IconButton(
          onPressed:
              _creatingGroup
                  ? null
                  : () {
                      Navigator.pop(
                        context,
                      );
                    },
          icon: const Icon(
            Icons.arrow_back_rounded,
          ),
        ),

        title: const Text(
          'New group',
          style: TextStyle(
            fontWeight:
                FontWeight.w800,
          ),
        ),

        actions: [
          Padding(
            padding:
                const EdgeInsets.only(
              right: 10,
            ),
            child: TextButton(
              onPressed:
                  _creatingGroup
                      ? null
                      : _createGroup,
              child:
                  _creatingGroup
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child:
                              CircularProgressIndicator(
                            strokeWidth:
                                2.4,
                          ),
                        )
                      : const Text(
                          'Create',
                          style:
                              TextStyle(
                            fontSize:
                                16,
                            fontWeight:
                                FontWeight
                                    .w800,
                          ),
                        ),
            ),
          ),
        ],
      ),

      body: SafeArea(
        child: Column(
          children: [
            // =====================================================
            // GROUP INFO
            // =====================================================

            Container(
              width:
                  double.infinity,
              color:
                  backgroundColor,
              padding:
                  const EdgeInsets
                      .fromLTRB(
                20,
                14,
                20,
                18,
              ),
              child: Column(
                children: [
                  // -------------------------------------------------
                  // GROUP IMAGE
                  // -------------------------------------------------

                  GestureDetector(
                    onTap:
                        _creatingGroup
                            ? null
                            : _pickGroupImage,
                    child: Stack(
                      clipBehavior:
                          Clip.none,
                      children: [
                        Container(
                          width: 104,
                          height: 104,
                          decoration:
                              BoxDecoration(
                            shape:
                                BoxShape
                                    .circle,
                            color:
                                cardColor,
                            border:
                                Border.all(
                              color:
                                  borderColor,
                              width:
                                  2,
                            ),
                          ),
                          clipBehavior:
                              Clip.antiAlias,
                          child:
                              _groupImage !=
                                      null
                                  ? Image.file(
                                      _groupImage!,
                                      width:
                                          104,
                                      height:
                                          104,
                                      fit:
                                          BoxFit
                                              .cover,
                                    )
                                  : const Icon(
                                      Icons
                                          .groups_rounded,
                                      size:
                                          48,
                                      color:
                                          Color(
                                        0xFF1877F2,
                                      ),
                                    ),
                        ),

                        Positioned(
                          right: 0,
                          bottom: 0,
                          child:
                              Container(
                            width: 34,
                            height: 34,
                            decoration:
                                BoxDecoration(
                              color:
                                  const Color(
                                0xFF1877F2,
                              ),
                              shape:
                                  BoxShape
                                      .circle,
                              border:
                                  Border.all(
                                color:
                                    backgroundColor,
                                width:
                                    3,
                              ),
                            ),
                            child:
                                const Icon(
                              Icons
                                  .camera_alt_rounded,
                              color:
                                  Colors.white,
                              size:
                                  17,
                            ),
                          ),
                        ),

                        if (_groupImage !=
                            null)
                          Positioned(
                            left: -2,
                            top: -2,
                            child:
                                GestureDetector(
                              onTap:
                                  _creatingGroup
                                      ? null
                                      : _removeGroupImage,
                              child:
                                  Container(
                                width:
                                    30,
                                height:
                                    30,
                                decoration:
                                    BoxDecoration(
                                  color:
                                      Colors.red,
                                  shape:
                                      BoxShape
                                          .circle,
                                  border:
                                      Border.all(
                                    color:
                                        backgroundColor,
                                    width:
                                        2,
                                  ),
                                ),
                                child:
                                    const Icon(
                                  Icons
                                      .close_rounded,
                                  size:
                                      17,
                                  color:
                                      Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(
                    height: 18,
                  ),

                  // -------------------------------------------------
                  // GROUP NAME
                  // -------------------------------------------------

                  TextField(
                    controller:
                        _groupNameController,
                    enabled:
                        !_creatingGroup,
                    textInputAction:
                        TextInputAction
                            .done,
                    maxLength: 100,
                    decoration:
                        InputDecoration(
                      hintText:
                          'Group name',
                      counterText: '',
                      prefixIcon:
                          const Icon(
                        Icons
                            .group_outlined,
                      ),
                      filled: true,
                      fillColor:
                          cardColor,
                      border:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius
                                .circular(
                          16,
                        ),
                        borderSide:
                            BorderSide(
                          color:
                              borderColor,
                        ),
                      ),
                      enabledBorder:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius
                                .circular(
                          16,
                        ),
                        borderSide:
                            BorderSide(
                          color:
                              borderColor,
                        ),
                      ),
                      focusedBorder:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius
                                .circular(
                          16,
                        ),
                        borderSide:
                            const BorderSide(
                          color:
                              Color(
                            0xFF1877F2,
                          ),
                          width:
                              1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // =====================================================
            // SELECTED MEMBERS
            // =====================================================

            if (_selectedUsers
                .isNotEmpty)
              Container(
                width:
                    double.infinity,
                color:
                    backgroundColor,
                padding:
                    const EdgeInsets
                        .only(
                  bottom: 12,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Padding(
                      padding:
                          const EdgeInsets
                              .symmetric(
                        horizontal:
                            20,
                      ),
                      child: Text(
                        '${_selectedUsers.length} selected',
                        style:
                            TextStyle(
                          color:
                              secondaryTextColor,
                          fontSize:
                              13,
                          fontWeight:
                              FontWeight
                                  .w700,
                        ),
                      ),
                    ),

                    const SizedBox(
                      height: 10,
                    ),

                    SizedBox(
                      height: 86,
                      child:
                          ListView
                              .separated(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          horizontal:
                              16,
                        ),
                        scrollDirection:
                            Axis.horizontal,
                        itemCount:
                            _selectedUsers
                                .length,
                        separatorBuilder:
                            (
                          context,
                          index,
                        ) =>
                                const SizedBox(
                          width:
                              10,
                        ),
                        itemBuilder:
                            (
                          context,
                          index,
                        ) {
                          final entry =
                              _selectedUsers
                                  .entries
                                  .elementAt(
                            index,
                          );

                          return _SelectedUserItem(
                            name:
                                _userName(
                              entry.value,
                            ),
                            avatarUrl:
                                _userAvatar(
                              entry.value,
                            ),
                            onRemove:
                                () {
                              _removeSelectedUser(
                                entry.key,
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

            // =====================================================
            // SEARCH
            // =====================================================

            Padding(
              padding:
                  const EdgeInsets
                      .fromLTRB(
                16,
                8,
                16,
                10,
              ),
              child: Container(
                decoration:
                    BoxDecoration(
                  color:
                      cardColor,
                  borderRadius:
                      BorderRadius
                          .circular(
                    28,
                  ),
                  border:
                      Border.all(
                    color:
                        borderColor,
                  ),
                ),
                child: TextField(
                  controller:
                      _searchController,
                  enabled:
                      !_creatingGroup,
                  keyboardType:
                      TextInputType
                          .phone,
                  onChanged:
                      _onSearchChanged,
                  decoration:
                      const InputDecoration(
                    hintText:
                        'Search member by phone',
                    prefixIcon:
                        Icon(
                      Icons
                          .search_rounded,
                    ),
                    border:
                        InputBorder
                            .none,
                    contentPadding:
                        EdgeInsets
                            .symmetric(
                      vertical:
                          15,
                    ),
                  ),
                ),
              ),
            ),

            // =====================================================
            // MEMBERS TITLE
            // =====================================================

            Padding(
              padding:
                  const EdgeInsets
                      .fromLTRB(
                20,
                5,
                20,
                8,
              ),
              child: Row(
                children: [
                  const Text(
                    'Add members',
                    style:
                        TextStyle(
                      fontSize:
                          16,
                      fontWeight:
                          FontWeight
                              .w800,
                    ),
                  ),

                  const Spacer(),

                  if (_selectedUsers
                      .isNotEmpty)
                    Text(
                      '${_selectedUsers.length}',
                      style:
                          const TextStyle(
                        color:
                            Color(
                          0xFF1877F2,
                        ),
                        fontWeight:
                            FontWeight
                                .w800,
                      ),
                    ),
                ],
              ),
            ),

            // =====================================================
            // USER RESULTS
            // =====================================================

            Expanded(
              child:
                  _buildUserList(
                provider:
                    provider,
                users:
                    users,
                secondaryTextColor:
                    secondaryTextColor,
              ),
            ),
          ],
        ),
      ),

      // ===========================================================
      // CREATE BUTTON
      // ===========================================================

      bottomNavigationBar:
          SafeArea(
        top: false,
        child: Container(
          padding:
              const EdgeInsets
                  .fromLTRB(
            16,
            10,
            16,
            12,
          ),
          decoration:
              BoxDecoration(
            color:
                backgroundColor,
            border:
                Border(
              top:
                  BorderSide(
                color:
                    borderColor,
              ),
            ),
          ),
          child: SizedBox(
            height: 52,
            child:
                ElevatedButton(
              onPressed:
                  _creatingGroup
                      ? null
                      : _createGroup,
              style:
                  ElevatedButton
                      .styleFrom(
                backgroundColor:
                    const Color(
                  0xFF1877F2,
                ),
                foregroundColor:
                    Colors.white,
                disabledBackgroundColor:
                    const Color(
                  0xFF1877F2,
                ).withValues(
                  alpha:
                      0.5,
                ),
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius
                          .circular(
                    16,
                  ),
                ),
                elevation: 0,
              ),
              child:
                  _creatingGroup
                      ? const SizedBox(
                          width:
                              23,
                          height:
                              23,
                          child:
                              CircularProgressIndicator(
                            strokeWidth:
                                2.5,
                            color:
                                Colors.white,
                          ),
                        )
                      : Text(
                          _selectedUsers
                                  .isEmpty
                              ? 'Create group'
                              : 'Create group (${_selectedUsers.length})',
                          style:
                              const TextStyle(
                            fontSize:
                                16,
                            fontWeight:
                                FontWeight
                                    .w800,
                          ),
                        ),
            ),
          ),
        ),
      ),
    );
  }

  // =============================================================
  // USER LIST
  // =============================================================

  Widget _buildUserList({
    required ChatProvider provider,
    required List<dynamic> users,
    required Color secondaryTextColor,
  }) {
    final query = _searchController.text.trim();

    // =============================================================
    // EMPTY SEARCH STATE
    // =============================================================
    if (query.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          // On small screens / while the keyboard is open, the
          // remaining Expanded area can become extremely small.
          // Do not force the large empty-state UI into that space.
          if (constraints.maxHeight < 80) {
            return const SizedBox.shrink();
          }

          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight > 16
                    ? constraints.maxHeight - 16
                    : 0,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.person_search_rounded,
                      size: constraints.maxHeight < 130 ? 36 : 55,
                      color: secondaryTextColor.withValues(
                        alpha: 0.7,
                      ),
                    ),
                    SizedBox(
                      height: constraints.maxHeight < 130 ? 6 : 14,
                    ),
                    Text(
                      'Search for people by phone number',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: secondaryTextColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    // =============================================================
    // QUERY TOO SHORT
    // =============================================================
    if (query.length < 3) {
      return LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxHeight < 30) {
            return const SizedBox.shrink();
          }

          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            child: Center(
              child: Text(
                'Enter at least 3 digits',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: secondaryTextColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      );
    }

    // =============================================================
    // NO USERS FOUND
    // =============================================================
    if (users.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxHeight < 30) {
            return const SizedBox.shrink();
          }

          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            child: Center(
              child: Text(
                'No users found',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: secondaryTextColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      );
    }

    // =============================================================
    // SEARCH RESULTS
    // =============================================================
    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(
        bottom: 20,
      ),
      itemCount: users.length,
      separatorBuilder: (
        context,
        index,
      ) =>
          const Divider(
        height: 1,
        indent: 82,
      ),
      itemBuilder: (
        context,
        index,
      ) {
        final user = users[index];

        final id = _userId(user);
        final name = _userName(user);
        final phone = _userPhone(user);
        final avatarUrl = _userAvatar(user);
        final selected = _isSelected(user);

        return ListTile(
          enabled: !_creatingGroup,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 5,
          ),
          leading: _UserAvatar(
            name: name,
            avatarUrl: avatarUrl,
          ),
          title: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: phone.isEmpty
              ? null
              : Text(
                  phone,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: secondaryTextColor,
                  ),
                ),
          trailing: AnimatedContainer(
            duration: const Duration(
              milliseconds: 150,
            ),
            width: 27,
            height: 27,
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF1877F2)
                  : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? const Color(0xFF1877F2)
                    : secondaryTextColor,
                width: 1.8,
              ),
            ),
            child: selected
                ? const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 18,
                  )
                : null,
          ),
          onTap: id == null
              ? null
              : () {
                  _toggleUser(user);
                },
        );
      },
    );
  }
}

// =================================================================
// USER AVATAR
// =================================================================

class _AvatarFallback extends StatelessWidget {
  final String name;
  final String avatarUrl;

  const _AvatarFallback({
    required this.name,
    required this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();

    String initial = '?';

    if (trimmed.isNotEmpty) {
      initial = trimmed.characters.first.toUpperCase();
    }

    return Center(
      child: CircleAvatar(
        radius: 48,

        backgroundImage:
            avatarUrl.trim().isNotEmpty
                ? NetworkImage(
                    avatarUrl.trim(),
                  )
                : null,

        child: avatarUrl.trim().isEmpty
            ? Text(
                initial,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                ),
              )
            : null,
      ),
    );
  }
}

// =================================================================
// USER AVATAR - UTF-16 / EMOJI SAFE
// =================================================================

class _UserAvatar extends StatelessWidget {
  final String name;
  final String avatarUrl;
  final double radius;

  const _UserAvatar({
    required this.name,
    required this.avatarUrl,
    this.radius = 28,
  });

  @override
  Widget build(BuildContext context) {
    final trimmedName = name.trim();
    final imageUrl = avatarUrl.trim();

    final String initial = trimmedName.isEmpty
        ? '?'
        : trimmedName.characters.first.toUpperCase();

    return CircleAvatar(
      radius: radius,
      backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
      child: imageUrl.isEmpty
          ? Text(
              initial,
              style: TextStyle(
                fontSize: radius * 0.65,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}

// =================================================================
// SELECTED USER
// =================================================================

class _SelectedUserItem
    extends StatelessWidget {
  final String name;
  final String avatarUrl;
  final VoidCallback onRemove;

  const _SelectedUserItem({
    required this.name,
    required this.avatarUrl,
    required this.onRemove,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return SizedBox(
      width: 68,
      child: Column(
        children: [
          Stack(
            clipBehavior:
                Clip.none,
            children: [
              _UserAvatar(
                name: name,
                avatarUrl:
                    avatarUrl,
              ),

              Positioned(
                right: -4,
                top: -4,
                child:
                    GestureDetector(
                  onTap:
                      onRemove,
                  child:
                      Container(
                    width: 22,
                    height: 22,
                    decoration:
                        BoxDecoration(
                      color:
                          Colors.red,
                      shape:
                          BoxShape
                              .circle,
                      border:
                          Border.all(
                        color:
                            Theme.of(
                                      context,
                                    )
                                        .scaffoldBackgroundColor,
                        width:
                            2,
                      ),
                    ),
                    child:
                        const Icon(
                      Icons
                          .close_rounded,
                      color:
                          Colors.white,
                      size: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 5,
          ),

          Text(
            name,
            maxLines: 1,
            overflow:
                TextOverflow
                    .ellipsis,
            textAlign:
                TextAlign.center,
            style:
                const TextStyle(
              fontSize: 11,
              fontWeight:
                  FontWeight
                      .w600,
            ),
          ),
        ],
      ),
    );
  }
}