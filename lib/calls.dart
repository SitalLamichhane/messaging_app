import 'package:flutter/material.dart';
import 'package:messaging_app/call_screen.dart';
import 'package:messaging_app/chat_detail.dart';
import 'package:messaging_app/chat_models.dart';
import 'package:messaging_app/core/chat/chat_provider.dart';
import 'package:messaging_app/dashboard.dart';
// import 'package:messaging_app/pages.dart'; // PagesScreen temporarily commented
import 'package:messaging_app/profile_page.dart';
import 'package:provider/provider.dart';

class CallHistoryScreen extends StatefulWidget {
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;

  const CallHistoryScreen({
    super.key,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserAvatar,
  });

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  int _selectedBottomIndex = 1;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ChatProvider>().loadConversations();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ChatItem> _filteredChats(List<ChatItem> chats) {
    final q = _searchQuery.toLowerCase().trim();
    if (q.isEmpty) return chats;

    return chats.where((chat) {
      return chat.name.toLowerCase().contains(q) ||
          chat.phone.toLowerCase().contains(q) ||
          chat.message.toLowerCase().contains(q) ||
          chat.groupSubtitle.toLowerCase().contains(q);
    }).toList();
  }

  void _handleVoiceCall(ChatItem chat) {
    _openCall(chat: chat, isVideoCall: false);
  }

  void _handleVideoCall(ChatItem chat) {
    _openCall(chat: chat, isVideoCall: true);
  }

  void _openCall({
    required ChatItem chat,
    required bool isVideoCall,
  }) {
    if (chat.id.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conversation is not ready'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          name: chat.name,
          avatarUrl: chat.avatarUrl,
          isVideoCall: isVideoCall,
          chat: chat,
          currentUserId: widget.currentUserId,
          currentUserName: widget.currentUserName,
          currentUserAvatar: widget.currentUserAvatar,
          receiverId: _receiverIdFromChat(chat),
          isCaller: true,
          conversationId: chat.id,
        ),
      ),
    );
  }

  String _receiverIdFromChat(ChatItem chat) {
    if (chat.isGroup) return chat.id;

    for (final member in chat.members) {
      final memberId = member.id.trim();
      if (memberId.isNotEmpty && memberId != widget.currentUserId) {
        return memberId;
      }
    }

    return chat.id;
  }

  void _openChat(ChatItem chat) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(chat: chat),
      ),
    );
  }

  void _handleBottomNavTap(int index) {
    if (index == _selectedBottomIndex) return;

    Widget? page;

    if (index == 0) {
      page = ChatListScreen(
        currentUserId: widget.currentUserId,
        currentUserName: widget.currentUserName,
        currentUserAvatar: widget.currentUserAvatar,
      );
    }

    // PagesScreen temporarily commented
    // else if (index == 2) {
    //   page = const PagesScreen();
    // }

    else if (index == 2) {
      page = ProfileScreen(
        chatId: '',
        chatName: '',
        currentUserId: widget.currentUserId,
        currentUserName: widget.currentUserName,
        currentUserAvatar: widget.currentUserAvatar,
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

  IconData _callTypeIcon(ChatItem chat) {
    final latestCall =
        chat.messages.where((m) => m.type == MessageType.call).toList();

    if (latestCall.isNotEmpty &&
        latestCall.last.callType == CallEntryType.video) {
      return Icons.videocam_outlined;
    }

    return Icons.call_outlined;
  }

  String _subtitle(ChatItem chat) {
    final latestCall =
        chat.messages.where((m) => m.type == MessageType.call).toList();

    if (latestCall.isNotEmpty) {
      final call = latestCall.last;
      final type =
          call.callType == CallEntryType.video ? 'Video call' : 'Voice call';
      return '$type • ${chat.time}';
    }

    if (chat.isGroup) return chat.groupSubtitle;
    if (chat.phone.trim().isNotEmpty) return chat.phone.trim();
    return chat.isOnline ? 'Active now' : 'Offline';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final chats = _filteredChats(provider.conversations);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF7F8FC);
    final borderColor =
        isDark ? const Color(0xFF243041) : const Color(0xFFE5E7EB);
    final searchBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final hintColor =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => provider.loadConversations(),
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Calls',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ),
                                IconButton(
                                  onPressed: provider.isLoading
                                      ? null
                                      : () => provider.loadConversations(),
                                  icon: const Icon(Icons.refresh_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Container(
                              height: 40,
                              decoration: BoxDecoration(
                                color: searchBg,
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(color: borderColor),
                              ),
                              child: TextField(
                                controller: _searchController,
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w500,
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _searchQuery = value;
                                  });
                                },
                                decoration: InputDecoration(
                                  hintText: 'Search conversations',
                                  hintStyle: TextStyle(color: hintColor),
                                  prefixIcon: Icon(
                                    Icons.search_rounded,
                                    color: hintColor,
                                  ),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'People and groups',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (provider.isLoading && chats.isEmpty)
                      const SliverFillRemaining(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (chats.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _searchQuery.trim().isEmpty
                                  ? 'No conversations found'
                                  : 'No matching conversations',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: hintColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
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
                                    CircleAvatar(
                                      radius: 28,
                                      backgroundImage:
                                          chat.avatarUrl.trim().isNotEmpty
                                              ? NetworkImage(chat.avatarUrl)
                                              : null,
                                      child: chat.avatarUrl.trim().isEmpty
                                          ? Text(
                                              chat.isGroup
                                                  ? (chat.groupInitials.isEmpty
                                                      ? '?'
                                                      : chat.groupInitials)
                                                  : chat.name.trim().isNotEmpty
                                                      ? chat.name
                                                          .trim()[0]
                                                          .toUpperCase()
                                                      : '?',
                                            )
                                          : null,
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
                                          Row(
                                            children: [
                                              Icon(
                                                _callTypeIcon(chat),
                                                size: 15,
                                                color: hintColor,
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  _subtitle(chat),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        color: hintColor,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    IconButton(
                                      onPressed: () => _handleVoiceCall(chat),
                                      icon: const Icon(Icons.call_outlined),
                                    ),
                                    IconButton(
                                      onPressed: () => _handleVideoCall(chat),
                                      icon: const Icon(Icons.videocam_outlined),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          childCount: chats.length,
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  ],
                ),
              ),
            ),
            _buildBottomNavigation(
              bgColor: bgColor,
              dividerColor: borderColor,
              accent: const Color(0xFF1877F2),
              secondaryText: hintColor,
            ),
          ],
        ),
      ),
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
      _BottomNavItemData(Icons.chat_bubble_outline, 'Chats'),
      _BottomNavItemData(Icons.call_outlined, 'Calls'),

      // PagesScreen temporarily commented
      // _BottomNavItemData(Icons.description_outlined, 'Pages'),

      _BottomNavItemData(Icons.person_outline, 'Profile'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(color: dividerColor, width: 1),
        ),
      ),
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Row(
        children: List.generate(items.length, (index) {
          final isSelected = _selectedBottomIndex == index;

          return Expanded(
            child: InkWell(
              onTap: () => _handleBottomNavTap(index),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 72,
                    height: 3,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  Icon(
                    items[index].icon,
                    size: 24,
                    color: isSelected ? accent : secondaryText,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    items[index].label,
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? accent : secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _BottomNavItemData {
  final IconData icon;
  final String label;

  const _BottomNavItemData(this.icon, this.label);
}
