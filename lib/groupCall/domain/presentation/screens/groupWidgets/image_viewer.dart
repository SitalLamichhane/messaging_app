import 'package:flutter/material.dart';

class ImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const ImageViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late final PageController controller;
  late int current;

  @override
  void initState() {
    super.initState();

    if (widget.images.isEmpty) {
      current = 0;
    } else {
      current = widget.initialIndex.clamp(
        0,
        widget.images.length - 1,
      );
    }

    controller = PageController(
      initialPage: current,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,

        leading: IconButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          icon: const Icon(
            Icons.arrow_back_rounded,
          ),
        ),

        title: Text(
          widget.images.isEmpty
              ? '0/0'
              : '${current + 1}/${widget.images.length}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      body: widget.images.isEmpty
          ? const Center(
              child: Text(
                'No image available',
                style: TextStyle(
                  color: Colors.white70,
                ),
              ),
            )
          : PageView.builder(
              controller: controller,
              itemCount: widget.images.length,

              onPageChanged: (index) {
                if (!mounted) return;

                setState(() {
                  current = index;
                });
              },

              itemBuilder: (context, index) {
                final imageUrl =
                    widget.images[index].trim();

                return Center(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    panEnabled: true,

                    child: imageUrl.isEmpty
                        ? const _ImageError()
                        : Image.network(
                            imageUrl,
                            width: double.infinity,
                            fit: BoxFit.contain,

                            loadingBuilder: (
                              context,
                              child,
                              loadingProgress,
                            ) {
                              if (loadingProgress ==
                                  null) {
                                return child;
                              }

                              final total =
                                  loadingProgress
                                      .expectedTotalBytes;

                              final loaded =
                                  loadingProgress
                                      .cumulativeBytesLoaded;

                              return Center(
                                child:
                                    CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                  value: total != null
                                      ? loaded / total
                                      : null,
                                ),
                              );
                            },

                            errorBuilder: (
                              context,
                              error,
                              stackTrace,
                            ) {
                              return const _ImageError();
                            },
                          ),
                  ),
                );
              },
            ),
    );
  }
}

class _ImageError extends StatelessWidget {
  const _ImageError();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            color: Colors.white70,
            size: 56,
          ),
          SizedBox(height: 10),
          Text(
            'Unable to load image',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}