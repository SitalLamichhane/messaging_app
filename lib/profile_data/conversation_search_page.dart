
import 'package:flutter/material.dart';
import 'package:hiddenly/chat_models.dart';
import 'package:hiddenly/theme_controller.dart';


class ConversationSearchPage extends StatefulWidget {
  final String chatName;
  final List<ChatMessage> messages; // ✅ your existing model

  const ConversationSearchPage({
    super.key,
    required this.chatName,
    required this.messages,
  });

  @override
  State<ConversationSearchPage> createState() => _ConversationSearchPageState();
}

class _ConversationSearchPageState extends State<ConversationSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  late List<ChatMessage> _results;

  @override
  void initState() {
    super.initState();
    _results = [];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _runSearch(String query) {
    final q = query.trim().toLowerCase();

    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }

    final filtered = widget.messages.where((message) {
      final text = (message.text ?? '').toString().toLowerCase();
      final fileName = (message.fileName ?? '').toString().toLowerCase();
      return text.contains(q) || fileName.contains(q);
    }).toList();

    filtered.sort((a, b) => b.sentAt.compareTo(a.sentAt));

    setState(() {
      _results = filtered;
    });
  }

  String _preview(ChatMessage message) {
    if ((message.text ?? '').toString().trim().isNotEmpty) {
      return message.text.toString().trim();
    }

    switch (message.type) {
      case MessageType.image:
        return 'Photo';
      case MessageType.video:
        return 'Video';
      case MessageType.file:
        return message.fileName?.trim().isNotEmpty == true
            ? 'File • ${message.fileName}'
            : 'File';
      case MessageType.audio:
        return 'Voice message';
      case MessageType.call:
        return 'Call';
      default:
        return 'Message';
    }
  }

  InlineSpan _highlight(
    String source,
    String query,
    TextStyle normal,
    TextStyle highlighted,
  ) {
    if (query.isEmpty || source.isEmpty) {
      return TextSpan(text: source, style: normal);
    }

    final lowerSource = source.toLowerCase();
    final lowerQuery = query.toLowerCase();

    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final index = lowerSource.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.add(TextSpan(text: source.substring(start), style: normal));
        break;
      }

      if (index > start) {
        spans.add(TextSpan(text: source.substring(start, index), style: normal));
      }

      spans.add(
        TextSpan(
          text: source.substring(index, index + query.length),
          style: highlighted,
        ),
      );

      start = index + query.length;
    }

    return TextSpan(children: spans);
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final amPm = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.day}/${local.month}/${local.year} • $hour:$minute $amPm';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isAppDarkMode;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF0F2F5);
    final cardColor = isDark ? const Color(0xFF111827) : Colors.white;
    final primaryText = isDark ? Colors.white : const Color(0xFF111827);
    final secondaryText =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF65676B);
    final dividerColor =
        isDark ? const Color(0xFF243041) : const Color(0xFFE4E6EB);
    final fieldBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF3F4F6);
    const accent = Color(0xFF1877F2);

    final query = _searchController.text.trim();

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: accent,
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: fieldBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: dividerColor),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          const Icon(Icons.search_rounded, color: accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              focusNode: _focusNode,
                              onChanged: _runSearch,
                              style: TextStyle(
                                color: primaryText,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Search in conversation',
                                hintStyle: TextStyle(
                                  color: secondaryText,
                                ),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                          if (query.isNotEmpty)
                            IconButton(
                              onPressed: () {
                                _searchController.clear();
                                _runSearch('');
                              },
                              icon: Icon(
                                Icons.close_rounded,
                                color: secondaryText,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: query.isEmpty
                  ? Center(
                      child: Text(
                        'Search messages',
                        style: TextStyle(
                          color: primaryText,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            'No results found',
                            style: TextStyle(
                              color: secondaryText,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _results.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final message = _results[index];
                            final preview = _preview(message);

                            return Material(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  Navigator.pop(context, message.id);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: dividerColor),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: const Color(0x141877F2),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: const Icon(
                                          Icons.chat_bubble_rounded,
                                          color: accent,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            RichText(
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              text: _highlight(
                                                preview,
                                                query,
                                                TextStyle(
                                                  color: secondaryText,
                                                  fontSize: 14.2,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                TextStyle(
                                                  color: primaryText,
                                                  fontSize: 14.2,
                                                  fontWeight: FontWeight.w800,
                                                  backgroundColor:
                                                      const Color(0x331877F2),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              _formatTime(message.sentAt),
                                              style: TextStyle(
                                                color: secondaryText,
                                                fontSize: 12.8,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: secondaryText,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}