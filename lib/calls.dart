import 'package:flutter/material.dart';
import 'package:messaging_app/call_screen.dart';
import 'package:messaging_app/chat_data.dart';
import 'package:messaging_app/chat_detail.dart';
import 'package:messaging_app/chat_models.dart';
import 'package:messaging_app/dashboard.dart';
import 'package:messaging_app/pages.dart';
import 'package:messaging_app/profile_page.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({
    super.key,
  });

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  int _selectedBottomIndex = 1;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final List<QuickDialContact> _quickDialContacts = [
    QuickDialContact(
      id: 'q1',
      name: 'Sarah Johnson',
      avatarUrl:
          'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=300&q=80',
      isOnline: true,
    ),
    QuickDialContact(
      id: 'q2',
      name: 'Michael Chen',
      avatarUrl:
          'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=300&q=80',
      isOnline: true,
    ),
    QuickDialContact(
      id: 'q3',
      name: 'Emily',
      avatarUrl:
          'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=300&q=80',
      isOnline: true,
    ),
    QuickDialContact(
      id: 'q4',
      name: 'James',
      avatarUrl:
          'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=300&q=80',
      isOnline: true,
    ),
    QuickDialContact(
      id: 'q5',
      name: 'Lisa Anderson',
      avatarUrl:
          'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=300&q=80',
      isOnline: true,
    ),
  ];

  List<CallEntry> get _recentCalls => AppChatData.allCalls;

  List<CallEntry> get _filteredRecentCalls {
    if (_searchQuery.trim().isEmpty) return _recentCalls;

    final q = _searchQuery.toLowerCase().trim();

    return _recentCalls.where((call) {
      return call.name.toLowerCase().contains(q) ||
          call.relativeTime.toLowerCase().contains(q) ||
          call.type.name.toLowerCase().contains(q);
    }).toList();
  }

  List<QuickDialContact> get _filteredQuickDial {
    if (_searchQuery.trim().isEmpty) return _quickDialContacts;

    final q = _searchQuery.toLowerCase().trim();

    return _quickDialContacts
        .where((contact) => contact.name.toLowerCase().contains(q))
        .toList();
  }

  void _handleVoiceCall(
    String name,
    String avatarUrl, {
    bool isGroup = false,
  }) {
    final chat = AppChatData.getOrCreateChat(
      name: name,
      avatarUrl: avatarUrl,
      isGroup: isGroup,
    );

    AppChatData.addCallLog(
      chat: chat,
      type: CallEntryType.voice,
      status: CallEntryStatus.outgoing,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
  name: name,
  avatarUrl: avatarUrl,
  isVideoCall: false,
  chat: chat,
  currentUserId: '1',
  receiverId: chat.id,
  isCaller: true,
),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _handleVideoCall(
    String name,
    String avatarUrl, {
    bool isGroup = false,
  }) {
    final chat = AppChatData.getOrCreateChat(
      name: name,
      avatarUrl: avatarUrl,
      isGroup: isGroup,
    );

    AppChatData.addCallLog(
      chat: chat,
      type: CallEntryType.video,
      status: CallEntryStatus.outgoing,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
            builder: (_) => CallScreen(
  name: name,
  avatarUrl: avatarUrl,
  isVideoCall: true,
  chat: chat,
  currentUserId: '1',
  receiverId: chat.id,
  isCaller: true,
),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _openChat(
    String name,
    String avatarUrl, {
    bool isGroup = false,
  }) {
    final chat = AppChatData.getOrCreateChat(
      name: name,
      avatarUrl: avatarUrl,
      isGroup: isGroup,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(chat: chat),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _handleBottomNavTap(int index) {
    if (index == _selectedBottomIndex) return;

    Widget? page;

    if (index == 0) {
      page = const ChatListScreen();
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

  void _handleQuickDialTap(QuickDialContact contact) {
    _openChat(contact.name, contact.avatarUrl);
  }

  IconData _callTypeIcon(CallEntryType type) {
    return type == CallEntryType.video
        ? Icons.videocam_outlined
        : Icons.call_outlined;
  }

  String _callSubtitle(CallEntry call) {
    final type = call.type == CallEntryType.video ? 'Video' : 'Voice';

    switch (call.status) {
      case CallEntryStatus.outgoing:
        return '$type • Outgoing • ${call.relativeTime}';
      case CallEntryStatus.incoming:
        return '$type • Incoming • ${call.relativeTime}';
      case CallEntryStatus.missed:
        return '$type • Missed • ${call.relativeTime}';
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              child: ValueListenableBuilder<int>(
                valueListenable: AppChatData.refresh,
                builder: (_, __, ___) {
                  return CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Calls',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
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
                                    hintText: 'Search calls',
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
                                'Quick dial',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 96,
                                child: _filteredQuickDial.isEmpty
                                    ? Center(
                                        child: Text(
                                          'No contacts found',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(color: hintColor),
                                        ),
                                      )
                                    : ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: _filteredQuickDial.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(width: 14),
                                        itemBuilder: (context, index) {
                                          final contact =
                                              _filteredQuickDial[index];

                                          return InkWell(
                                            onTap: () =>
                                                _handleQuickDialTap(contact),
                                            borderRadius:
                                                BorderRadius.circular(18),
                                            child: SizedBox(
                                              width: 72,
                                              child: Column(
                                                children: [
                                                  Stack(
                                                    clipBehavior: Clip.none,
                                                    children: [
                                                      CircleAvatar(
                                                        radius: 28,
                                                        backgroundImage:
                                                            contact.avatarUrl
                                                                    .trim()
                                                                    .isNotEmpty
                                                                ? NetworkImage(
                                                                    contact
                                                                        .avatarUrl,
                                                                  )
                                                                : null,
                                                        child: contact.avatarUrl
                                                                .trim()
                                                                .isEmpty
                                                            ? Text(
                                                                contact.name
                                                                        .isNotEmpty
                                                                    ? contact
                                                                        .name[0]
                                                                        .toUpperCase()
                                                                    : 'U',
                                                              )
                                                            : null,
                                                      ),
                                                      if (contact.isOnline)
                                                        Positioned(
                                                          right: -1,
                                                          bottom: -1,
                                                          child: Container(
                                                            width: 14,
                                                            height: 14,
                                                            decoration:
                                                                BoxDecoration(
                                                              color: const Color(
                                                                0xFF22C55E,
                                                              ),
                                                              shape: BoxShape
                                                                  .circle,
                                                              border: Border.all(
                                                                color: Colors
                                                                    .white,
                                                                width: 2,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    contact.name,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    textAlign: TextAlign.center,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Recent',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_filteredRecentCalls.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 30,
                            ),
                            child: Center(
                              child: Text(
                                'No recent calls',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
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
                              final call = _filteredRecentCalls[index];
                              final subtitleColor = call.status ==
                                      CallEntryStatus.missed
                                  ? const Color(0xFFEF4444)
                                  : hintColor;

                              return InkWell(
                                onTap: () => _openChat(
                                  call.name,
                                  call.avatarUrl,
                                  isGroup: call.isGroup,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 28,
                                        backgroundImage: call.avatarUrl
                                                .trim()
                                                .isNotEmpty
                                            ? NetworkImage(call.avatarUrl)
                                            : null,
                                        child: call.avatarUrl.trim().isEmpty
                                            ? Text(
                                                call.name.isNotEmpty
                                                    ? call.name[0].toUpperCase()
                                                    : 'U',
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
                                              call.name,
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
                                                  _callTypeIcon(call.type),
                                                  size: 15,
                                                  color: subtitleColor,
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    _callSubtitle(call),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.copyWith(
                                                          color: subtitleColor,
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
                                        onPressed: () => _handleVoiceCall(
                                          call.name,
                                          call.avatarUrl,
                                          isGroup: call.isGroup,
                                        ),
                                        icon: const Icon(Icons.call_outlined),
                                      ),
                                      IconButton(
                                        onPressed: () => _handleVideoCall(
                                          call.name,
                                          call.avatarUrl,
                                          isGroup: call.isGroup,
                                        ),
                                        icon:
                                            const Icon(Icons.videocam_outlined),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            childCount: _filteredRecentCalls.length,
                          ),
                        ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 12),
                      ),
                    ],
                  );
                },
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
      _BottomNavItemData(Icons.description_outlined, 'Pages'),
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

  _BottomNavItemData(this.icon, this.label);
}