import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:hiddenly/theme_controller.dart';

class PhotosMediaPage extends StatefulWidget {
  final String chatId;
  final String chatName;

  const PhotosMediaPage({
    super.key,
    required this.chatId,
    required this.chatName,
  });

  @override
  State<PhotosMediaPage> createState() => _PhotosMediaPageState();
}

class _PhotosMediaPageState extends State<PhotosMediaPage> {
  String selected = "photos";

  bool _isLoading = true;
  String? _error;

  List<MediaItem> _photos = [];
  List<MediaItem> _videos = [];
  List<MediaItem> _files = [];
  List<MediaItem> _audios = [];

  bool get isDark => isAppDarkMode;

  Color get bgColor =>
      isDark ? const Color(0xFF0F172A) : const Color(0xFFF0F2F5);

  Color get cardColor =>
      isDark ? const Color(0xFF111827) : Colors.white;

  Color get primaryText =>
      isDark ? Colors.white : Colors.black;

  Color get secondaryText =>
      isDark ? const Color(0xFF94A3B8) : const Color(0xFF65676B);

  Color get borderColor =>
      isDark ? const Color(0xFF243041) : const Color(0xFFE5E7EB);

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    await Future.delayed(const Duration(milliseconds: 400));

    final items = <MediaItem>[
      MediaItem(
        id: "1",
        type: "image",
        url: "https://picsum.photos/300",
        sentAt: DateTime.now(),
      ),
      MediaItem(
        id: "2",
        type: "video",
        url:
            "https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4",
        sentAt: DateTime.now(),
      ),
    ];

    setState(() {
      _photos = items.where((e) => e.type == 'image').toList();
      _videos = items.where((e) => e.type == 'video').toList();
      _files = items.where((e) => e.type == 'file').toList();
      _audios = items.where((e) => e.type == 'audio').toList();
      _isLoading = false;
    });
  }

  String _formatDate(DateTime dt) {
    return DateFormat('MMM d, yyyy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, themeMode, _) {
        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            backgroundColor: cardColor,
            elevation: 0.5,
            iconTheme: IconThemeData(color: primaryText),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Photos & media",
                  style: TextStyle(color: primaryText),
                ),
                Text(
                  widget.chatName,
                  style: TextStyle(
                    fontSize: 12,
                    color: secondaryText,
                  ),
                ),
              ],
            ),
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          _topButton("Photos", _photos.length, "photos"),
                          const SizedBox(width: 8),
                          _topButton("Videos", _videos.length, "videos"),
                          const SizedBox(width: 8),
                          _topButton("Files", _files.length, "files"),
                          const SizedBox(width: 8),
                          _topButton("Audio", _audios.length, "audio"),
                        ],
                      ),
                    ),
                    Expanded(
                      child: selected == "photos"
                          ? _MediaGridTab(
                              items: _photos,
                              isVideo: false,
                              primaryText: primaryText,
                            )
                          : selected == "videos"
                              ? _MediaGridTab(
                                  items: _videos,
                                  isVideo: true,
                                  primaryText: primaryText,
                                )
                              : selected == "files"
                                  ? _FilesTab(
                                      items: _files,
                                      secondaryText: secondaryText,
                                      primaryText: primaryText,
                                      dateFormatter: _formatDate,
                                    )
                                  : _AudioTab(
                                      items: _audios,
                                      secondaryText: secondaryText,
                                      primaryText: primaryText,
                                      dateFormatter: _formatDate,
                                    ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _topButton(String label, int count, String type) {
    final isActive = selected == type;

    return GestureDetector(
      onTap: () => setState(() => selected = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1877F2) : cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : primaryText,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              "($count)",
              style: TextStyle(
                color: isActive ? Colors.white : secondaryText,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MediaItem {
  final String id;
  final String type;
  final String url;
  final DateTime sentAt;

  MediaItem({
    required this.id,
    required this.type,
    required this.url,
    required this.sentAt,
  });
}

class _MediaGridTab extends StatelessWidget {
  final List<MediaItem> items;
  final bool isVideo;
  final Color primaryText;

  const _MediaGridTab({
    required this.items,
    required this.isVideo,
    required this.primaryText,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          "Empty",
          style: TextStyle(color: primaryText),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemBuilder: (context, index) {
        final item = items[index];

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MediaViewerPage(
                  items: items,
                  initialIndex: index,
                  isVideo: isVideo,
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  item.url,
                  fit: BoxFit.cover,
                ),
                if (isVideo)
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class MediaViewerPage extends StatefulWidget {
  final List<MediaItem> items;
  final int initialIndex;
  final bool isVideo;

  const MediaViewerPage({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.isVideo,
  });

  @override
  State<MediaViewerPage> createState() => _MediaViewerPageState();
}

class _MediaViewerPageState extends State<MediaViewerPage> {
  late PageController controller;
  int index = 0;
  VideoPlayerController? video;

  @override
  void initState() {
    super.initState();
    index = widget.initialIndex;
    controller = PageController(initialPage: index);
    _initVideo();
  }

  Future<void> _initVideo() async {
    video?.dispose();
    video = null;

    if (!widget.isVideo) return;

    final item = widget.items[index];

    video = VideoPlayerController.networkUrl(Uri.parse(item.url));
    await video!.initialize();
    await video!.play();

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.dispose();
    video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: PageView.builder(
        controller: controller,
        itemCount: widget.items.length,
        onPageChanged: (i) {
          index = i;
          _initVideo();
        },
        itemBuilder: (_, i) {
          final item = widget.items[i];

          return Center(
            child: widget.isVideo
                ? video != null && video!.value.isInitialized
                    ? AspectRatio(
                        aspectRatio: video!.value.aspectRatio,
                        child: VideoPlayer(video!),
                      )
                    : const CircularProgressIndicator()
                : InteractiveViewer(
                    child: Image.network(item.url),
                  ),
          );
        },
      ),
    );
  }
}

class _FilesTab extends StatelessWidget {
  final List<MediaItem> items;
  final Color secondaryText;
  final Color primaryText;
  final String Function(DateTime) dateFormatter;

  const _FilesTab({
    required this.items,
    required this.secondaryText,
    required this.primaryText,
    required this.dateFormatter,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          "Files here",
          style: TextStyle(color: primaryText),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];

        return ListTile(
          leading: Icon(
            Icons.insert_drive_file_rounded,
            color: primaryText,
          ),
          title: Text(
            "File",
            style: TextStyle(color: primaryText),
          ),
          subtitle: Text(
            dateFormatter(item.sentAt),
            style: TextStyle(color: secondaryText),
          ),
        );
      },
    );
  }
}

class _AudioTab extends StatelessWidget {
  final List<MediaItem> items;
  final Color secondaryText;
  final Color primaryText;
  final String Function(DateTime) dateFormatter;

  const _AudioTab({
    required this.items,
    required this.secondaryText,
    required this.primaryText,
    required this.dateFormatter,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          "Audio here",
          style: TextStyle(color: primaryText),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];

        return ListTile(
          leading: Icon(
            Icons.mic_rounded,
            color: primaryText,
          ),
          title: Text(
            "Voice message",
            style: TextStyle(color: primaryText),
          ),
          subtitle: Text(
            dateFormatter(item.sentAt),
            style: TextStyle(color: secondaryText),
          ),
        );
      },
    );
  }
}