import 'dart:async';

import 'package:flutter/material.dart';
import 'package:messaging_app/calls.dart';
import 'package:messaging_app/chat_detail.dart';
import 'package:messaging_app/chat_models.dart';
import 'package:messaging_app/core/chat/chat_provider.dart';
import 'package:messaging_app/pages.dart';
import 'package:messaging_app/profile_page.dart';
import 'package:provider/provider.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  Timer? _debounce;

  int _selectedBottomIndex = 0;

  final TextEditingController _searchController =
      TextEditingController();

  String _search = '';

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadConversations();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<ChatItem> _filteredChats(List<ChatItem> chats) {
    if (_search.trim().isEmpty) {
      return chats;
    }

    final q = _search.toLowerCase().trim();

    return chats.where((chat) {
      final preview = _buildPreview(chat).toLowerCase();

      return chat.name.toLowerCase().contains(q) ||
          preview.contains(q);
    }).toList();
  }

  void _openChat(ChatItem chat) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(chat: chat),
      ),
    );
  }

  void _handleBottomTap(int index) {
    if (index == _selectedBottomIndex) return;

    Widget? page;

    if (index == 1) {
      page = const CallHistoryScreen();
    } else if (index == 2) {
      page = const PagesScreen();
    } else if (index == 3) {
      page = const ProfileScreen(
        chatId: '',
        chatName: '',
      );
    }

    if (page != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => page!),
      );
      return;
    }

    setState(() {
      _selectedBottomIndex = index;
    });
  }

  String _listTime(ChatItem chat) {
    return chat.time;
  }

  String _buildPreview(ChatItem chat) {
    if (chat.messages.isEmpty) {
      return chat.message;
    }

    final latest = chat.messages.last;

    switch (latest.type) {
      case MessageType.text:
        return latest.text.isEmpty
            ? 'Message'
            : latest.text;

      case MessageType.image:
        return '📷 Photo';

      case MessageType.video:
        return '🎥 Video';

      case MessageType.file:
        return '📎 ${latest.fileName ?? "File"}';

      case MessageType.call:
        return latest.callType == CallEntryType.video
            ? '📹 Video call'
            : '📞 Voice call';

      case MessageType.audio:
        return '🎤 Voice message';
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();

    final isSearching = _search.trim().isNotEmpty;

    final searchedUsers = provider.searchedUsers;

    final chats = _filteredChats(provider.conversations);

    final isDark =
        Theme.of(context).brightness == Brightness.dark;

    final bg = isDark
        ? const Color(0xFF0F172A)
        : const Color(0xFFF5F7FB);

    final borderColor = isDark
        ? const Color(0xFF243041)
        : const Color(0xFFE5E7EB);

    final secondaryText = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF6B7280);

    final cardColor =
        isDark ? const Color(0xFF1E293B) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1877F2),
                      borderRadius: BorderRadius.circular(23),
                    ),
                    child: const Icon(
                      Icons.chat_bubble_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Chats',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      provider.loadConversations();
                    },
                    icon: const Icon(
                      Icons.refresh_rounded,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: borderColor),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _search = value;
                    });

                    _debounce?.cancel();

                    _debounce = Timer(
                      const Duration(milliseconds: 500),
                      () {
                        final phone = value.trim();

                        if (phone.length >= 10) {
                          provider.searchUsers(phone);
                        } else {
                          provider.searchedUsers.clear();
                          provider.notifyListeners();
                        }
                      },
                    );
                  },
                  decoration: const InputDecoration(
                    hintText: 'Search user by phone',
                    prefixIcon: Icon(Icons.search_rounded),
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            Expanded(
              child: isSearching
                  ? _buildSearchResults(
                      provider,
                      searchedUsers,
                    )
                  : _buildConversationList(
                      provider,
                      chats,
                      secondaryText,
                    ),
            ),

            _buildBottomNavigation(
              bgColor: bg,
              dividerColor: borderColor,
              accent: const Color(0xFF1877F2),
              secondaryText: secondaryText,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(
    ChatProvider provider,
    List<dynamic> searchedUsers,
  ) {
    if (searchedUsers.isEmpty) {
      return const Center(
        child: Text('No user found'),
      );
    }

    return ListView.builder(
      itemCount: searchedUsers.length,
      itemBuilder: (context, index) {
        final user = searchedUsers[index];

        return ListTile(
          leading: CircleAvatar(
            child: Text(
              (user['name'] ?? 'U')[0].toUpperCase(),
            ),
          ),
          title: Text(
            user['name'] ?? 'Unknown',
          ),
          subtitle: Text(
            user['phone_number'] ?? '',
          ),
          onTap: () async {
            if (provider.isSending) return;

            final chat = await provider.startPrivateChat(
              user['id'],
            );

            if (!context.mounted) return;

            if (chat != null) {
              _searchController.clear();

              setState(() {
                _search = '';
              });

              provider.searchedUsers.clear();

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ChatDetailScreen(chat: chat),
                ),
              );
            }
          },
        );
      },
    );
  }

  Widget _buildConversationList(
    ChatProvider provider,
    List<ChatItem> chats,
    Color secondaryText,
  ) {
    if (provider.isLoading && chats.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (provider.error != null && chats.isEmpty) {
      return Center(
        child: Text(
          provider.error!,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: secondaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (chats.isEmpty) {
      return Center(
        child: Text(
          'No chats found',
          style:
              Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: secondaryText,
                    fontWeight: FontWeight.w600,
                  ),
        ),
      );
    }

    return ListView.builder(
      itemCount: chats.length,
      itemBuilder: (context, index) {
        final chat = chats[index];

        return InkWell(
          onTap: () => _openChat(chat),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            child: Row(
              children: [
                _Avatar(
                  name: chat.name,
                  avatarUrl: chat.avatarUrl,
                  isOnline: chat.isOnline,
                  isGroup: chat.isGroup,
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        chat.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        _buildPreview(chat),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                              color: secondaryText,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.end,
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  children: [
                    Text(
                      _listTime(chat),
                      style: TextStyle(
                        color: secondaryText,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    if (chat.unreadCount > 0) ...[
                      const SizedBox(height: 8),

                      Container(
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFF1877F2),
                          borderRadius:
                              BorderRadius.all(
                            Radius.circular(999),
                          ),
                        ),
                        child: Text(
                          '${chat.unreadCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomNavigation({
    required Color bgColor,
    required Color dividerColor,
    required Color accent,
    required Color secondaryText,
  }) {
    final textTheme = Theme.of(context).textTheme;

    final items = [
      _BottomNavItemData(
        Icons.chat_bubble_outline,
        'Chats',
      ),
      _BottomNavItemData(
        Icons.call_outlined,
        'Calls',
      ),
      _BottomNavItemData(
        Icons.description_outlined,
        'Pages',
      ),
      _BottomNavItemData(
        Icons.person_outline,
        'Profile',
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(
            color: dividerColor,
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.only(
        top: 6,
        bottom: 10,
      ),
      child: Row(
        children: List.generate(
          items.length,
          (index) {
            final isSelected =
                _selectedBottomIndex == index;

            return Expanded(
              child: InkWell(
                onTap: () => _handleBottomTap(index),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration:
                          const Duration(milliseconds: 180),
                      width: 72,
                      height: 3,
                      margin:
                          const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? accent
                            : Colors.transparent,
                        borderRadius:
                            BorderRadius.circular(20),
                      ),
                    ),

                    Icon(
                      items[index].icon,
                      size: 24,
                      color: isSelected
                          ? accent
                          : secondaryText,
                    ),

                    const SizedBox(height: 6),

                    Text(
                      items[index].label,
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected
                            ? accent
                            : secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BottomNavItemData {
  final IconData icon;
  final String label;

  _BottomNavItemData(
    this.icon,
    this.label,
  );
}

class _Avatar extends StatelessWidget {
  final String name;
  final String avatarUrl;
  final bool isOnline;
  final bool isGroup;
  final double radius;

  const _Avatar({
    required this.name,
    required this.avatarUrl,
    required this.isOnline,
    required this.isGroup,
    this.radius = 28,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: isGroup
              ? const Color(0xFFEFF4FF)
              : const Color(0xFFE5E7EB),
          backgroundImage:
              avatarUrl.trim().isNotEmpty
                  ? NetworkImage(avatarUrl)
                  : null,
          child: avatarUrl.trim().isEmpty
              ? Text(
                  (
                    name.isNotEmpty
                        ? name[0]
                        : 'U'
                  ).toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: radius * 0.65,
                  ),
                )
              : null,
        ),
        if (isOnline)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: radius * 0.55,
              height: radius * 0.55,
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
    );
  }
}