// import 'package:flutter/material.dart';
// import 'package:messaging_app/calls.dart';
// import 'package:messaging_app/chat_data.dart';
// import 'package:messaging_app/chat_detail.dart';
// import 'package:messaging_app/dashboard.dart';
// import 'package:messaging_app/profile_page.dart';

// class PagesScreen extends StatefulWidget {
//   final String currentUserId;
//   final String currentUserName;
//   final String currentUserAvatar;

//   const PagesScreen({
//     super.key,
//     this.currentUserId = '',
//     this.currentUserName = 'You',
//     this.currentUserAvatar = '',
//   });

//   @override
//   State<PagesScreen> createState() => _PagesScreenState();
// }

// class _PagesScreenState extends State<PagesScreen> {
//   int _selectedBottomIndex = 2;
//   String _searchQuery = '';

//   final List<PageItem> _allPages = [
//     PageItem(
//       id: '1',
//       name: 'ReplyHub Official',
//       category: 'Business Page',
//       membersOrFollowers: '12.5K followers',
//       avatar: 'R',
//       color: const Color(0xFF4F7CF5),
//       isVerified: true,
//     ),
//     PageItem(
//       id: '2',
//       name: 'Marketing Team',
//       category: 'Private Group',
//       membersOrFollowers: '248 members',
//       avatar: 'M',
//       color: const Color(0xFF10B981),
//     ),
//     PageItem(
//       id: '3',
//       name: 'Design Community',
//       category: 'Public Group',
//       membersOrFollowers: '3.1K members',
//       avatar: 'D',
//       color: const Color(0xFFF59E0B),
//     ),
//     PageItem(
//       id: '4',
//       name: 'Client Support',
//       category: 'Support Page',
//       membersOrFollowers: '1.8K followers',
//       avatar: 'C',
//       color: const Color(0xFFEF4444),
//     ),
//   ];

//   List<PageItem> get _filteredPages {
//     final q = _searchQuery.toLowerCase().trim();

//     if (q.isEmpty) return _allPages;

//     return _allPages.where((page) {
//       return page.name.toLowerCase().contains(q) ||
//           page.category.toLowerCase().contains(q) ||
//           page.membersOrFollowers.toLowerCase().contains(q);
//     }).toList();
//   }

//   void _handleBottomTap(int index) {
//     if (index == _selectedBottomIndex) return;

//     Widget? page;

//     if (index == 0) {
//       page = const ChatListScreen();
//     } else if (index == 1) {
//       page = CallHistoryScreen(
//         currentUserId: widget.currentUserId,
//         currentUserName: widget.currentUserName,
//         currentUserAvatar: widget.currentUserAvatar,
//       );
//     } else if (index == 3) {
//       page = const ProfileScreen(
//         chatId: '',
//         chatName: '',
//       );
//     }

//     if (page != null) {
//       Navigator.pushReplacement(
//         context,
//         MaterialPageRoute(builder: (_) => page!),
//       );
//       return;
//     }

//     setState(() {
//       _selectedBottomIndex = index;
//     });
//   }

//   void _openPage(PageItem page) {
//     final chat = AppChatData.getOrCreateChat(
//       name: page.name,
//       avatarUrl: '',
//       isGroup: true,
//     );

//     Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder: (_) => ChatDetailScreen(chat: chat),
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     final textTheme = Theme.of(context).textTheme;
//     final isDark = Theme.of(context).brightness == Brightness.dark;
//     final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF5F7FB);
//     final emptyTextColor =
//         isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

//     return Scaffold(
//       backgroundColor: bgColor,
//       body: SafeArea(
//         child: Column(
//           children: [
//             Expanded(
//               child: Column(
//                 children: [
//                   _buildHeader(),
//                   _buildSearchBar(),
//                   const SizedBox(height: 14),
//                   Expanded(
//                     child: _filteredPages.isEmpty
//                         ? Center(
//                             child: Text(
//                               'No pages or groups found',
//                               style: textTheme.bodyLarge?.copyWith(
//                                 color: emptyTextColor,
//                                 fontWeight: FontWeight.w500,
//                               ),
//                             ),
//                           )
//                         : ListView.separated(
//                             padding: const EdgeInsets.only(bottom: 20),
//                             itemCount: _filteredPages.length,
//                             separatorBuilder: (_, __) => _buildDivider(),
//                             itemBuilder: (context, index) {
//                               final page = _filteredPages[index];

//                               return _PageTile(
//                                 page: page,
//                                 onTap: () => _openPage(page),
//                               );
//                             },
//                           ),
//                   ),
//                 ],
//               ),
//             ),
//             _buildBottomNavigation(),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildHeader() {
//     final textTheme = Theme.of(context).textTheme;
//     final isDark = Theme.of(context).brightness == Brightness.dark;
//     final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);

//     return Padding(
//       padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
//       child: Row(
//         children: [
//           Expanded(
//             child: Text(
//               'Pages & Groups',
//               style: textTheme.displayLarge?.copyWith(
//                 color: titleColor,
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildSearchBar() {
//     final textTheme = Theme.of(context).textTheme;
//     final isDark = Theme.of(context).brightness == Brightness.dark;
//     final searchBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFEEF2F6);
//     final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
//     final hintColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF718096);

//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 16),
//       child: Container(
//         height: 56,
//         decoration: BoxDecoration(
//           color: searchBg,
//           borderRadius: BorderRadius.circular(18),
//         ),
//         child: TextField(
//           style: textTheme.bodyLarge?.copyWith(
//             color: textColor,
//           ),
//           onChanged: (value) {
//             setState(() {
//               _searchQuery = value;
//             });
//           },
//           decoration: InputDecoration(
//             hintText: 'Search pages or groups...',
//             hintStyle: textTheme.bodyLarge?.copyWith(
//               color: hintColor,
//             ),
//             prefixIcon: Icon(
//               Icons.search,
//               size: 24,
//               color: hintColor,
//             ),
//             border: InputBorder.none,
//             contentPadding: const EdgeInsets.symmetric(vertical: 16),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildDivider() {
//     final isDark = Theme.of(context).brightness == Brightness.dark;
//     final dividerColor =
//         isDark ? const Color(0xFF243041) : const Color(0xFFE2E8F0);

//     return Divider(
//       height: 1,
//       thickness: 1,
//       color: dividerColor,
//     );
//   }

//   Widget _buildBottomNavigation() {
//     final textTheme = Theme.of(context).textTheme;
//     final isDark = Theme.of(context).brightness == Brightness.dark;
//     final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF5F7FB);
//     final dividerColor =
//         isDark ? const Color(0xFF243041) : const Color(0xFFE2E8F0);
//     final inactiveColor =
//         isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

//     final items = [
//       _BottomNavItemData(Icons.chat_bubble_outline, 'Chats'),
//       _BottomNavItemData(Icons.call_outlined, 'Calls'),
//       _BottomNavItemData(Icons.description_outlined, 'Pages'),
//       _BottomNavItemData(Icons.person_outline, 'Profile'),
//     ];

//     return Container(
//       decoration: BoxDecoration(
//         color: bgColor,
//         border: Border(
//           top: BorderSide(
//             color: dividerColor,
//             width: 1,
//           ),
//         ),
//       ),
//       padding: const EdgeInsets.only(top: 6, bottom: 10),
//       child: Row(
//         children: List.generate(items.length, (index) {
//           final isSelected = _selectedBottomIndex == index;

//           return Expanded(
//             child: InkWell(
//               splashColor: Colors.transparent,
//               highlightColor: Colors.transparent,
//               hoverColor: Colors.transparent,
//               onTap: () => _handleBottomTap(index),
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   AnimatedContainer(
//                     duration: const Duration(milliseconds: 180),
//                     width: 72,
//                     height: 3,
//                     margin: const EdgeInsets.only(bottom: 10),
//                     decoration: BoxDecoration(
//                       color: isSelected
//                           ? const Color(0xFF4F7CF5)
//                           : Colors.transparent,
//                       borderRadius: BorderRadius.circular(20),
//                     ),
//                   ),
//                   Icon(
//                     items[index].icon,
//                     size: 24,
//                     color: isSelected
//                         ? const Color(0xFF4F7CF5)
//                         : inactiveColor,
//                   ),
//                   const SizedBox(height: 6),
//                   Text(
//                     items[index].label,
//                     style: textTheme.bodySmall?.copyWith(
//                       fontWeight:
//                           isSelected ? FontWeight.w600 : FontWeight.w500,
//                       color: isSelected
//                           ? const Color(0xFF4F7CF5)
//                           : inactiveColor,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           );
//         }),
//       ),
//     );
//   }
// }

// class _PageTile extends StatelessWidget {
//   final PageItem page;
//   final VoidCallback onTap;

//   const _PageTile({
//     required this.page,
//     required this.onTap,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final textTheme = Theme.of(context).textTheme;
//     final isDark = Theme.of(context).brightness == Brightness.dark;
//     final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
//     final categoryColor =
//         isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
//     final metaColor =
//         isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
//     final chevronColor =
//         isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);

//     return InkWell(
//       splashColor: Colors.transparent,
//       highlightColor: Colors.transparent,
//       hoverColor: Colors.transparent,
//       onTap: onTap,
//       child: Padding(
//         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
//         child: Row(
//           children: [
//             CircleAvatar(
//               radius: 28,
//               backgroundColor: Color.alphaBlend(
//                 page.color.withOpacity(0.12),
//                 Colors.transparent,
//               ),
//               child: Text(
//                 page.avatar,
//                 style: textTheme.headlineLarge?.copyWith(
//                   fontWeight: FontWeight.w800,
//                   color: page.color,
//                 ),
//               ),
//             ),
//             const SizedBox(width: 14),
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Row(
//                     children: [
//                       Flexible(
//                         child: Text(
//                           page.name,
//                           maxLines: 1,
//                           overflow: TextOverflow.ellipsis,
//                           style: textTheme.titleLarge?.copyWith(
//                             color: titleColor,
//                           ),
//                         ),
//                       ),
//                       if (page.isVerified) ...[
//                         const SizedBox(width: 6),
//                         const Icon(
//                           Icons.verified_rounded,
//                           size: 18,
//                           color: Color(0xFF4F7CF5),
//                         ),
//                       ],
//                     ],
//                   ),
//                   const SizedBox(height: 4),
//                   Text(
//                     page.category,
//                     style: textTheme.bodyMedium?.copyWith(
//                       color: categoryColor,
//                       fontWeight: FontWeight.w500,
//                     ),
//                   ),
//                   const SizedBox(height: 4),
//                   Text(
//                     page.membersOrFollowers,
//                     style: textTheme.bodySmall?.copyWith(
//                       color: metaColor,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             const SizedBox(width: 10),
//             Icon(
//               Icons.chevron_right_rounded,
//               size: 24,
//               color: chevronColor,
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class PageItem {
//   final String id;
//   final String name;
//   final String category;
//   final String membersOrFollowers;
//   final String avatar;
//   final Color color;
//   final bool isVerified;

//   PageItem({
//     required this.id,
//     required this.name,
//     required this.category,
//     required this.membersOrFollowers,
//     required this.avatar,
//     required this.color,
//     this.isVerified = false,
//   });
// }

// class _BottomNavItemData {
//   final IconData icon;
//   final String label;

//   _BottomNavItemData(this.icon, this.label);
// }