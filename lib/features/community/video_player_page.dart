import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../services/community_service.dart';
import '../../services/auth_service.dart';
import 'comments_page.dart';

class VideoPlayerPage extends StatefulWidget {
  final String videoUrl;
  final String title;
  final String videoDocId;
  const VideoPlayerPage(
      {required this.videoUrl,
      required this.title,
      required this.videoDocId,
      Key? key})
      : super(key: key);

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        setState(() => _initialized = true);
        _controller?.play();
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          // likes count & toggle
          StreamBuilder<int>(
            stream: CommunityService.likeCountStream(widget.videoDocId),
            builder: (context, snapCount) {
              final count = snapCount.data ?? 0;
              return StreamBuilder<bool>(
                stream: CommunityService.isLikedStream(
                    widget.videoDocId, AuthService.instance.currentUser?.uid),
                builder: (context, snapLiked) {
                  final liked = snapLiked.data ?? false;
                  return Row(
                    children: [
                      IconButton(
                        icon: Icon(
                            liked ? Icons.favorite : Icons.favorite_border,
                            color: liked ? Colors.red : null),
                        onPressed: () async {
                          final uid = AuthService.instance.currentUser?.uid;
                          if (uid == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Sign in to like')));
                            return;
                          }
                          await CommunityService.toggleLike(
                              widget.videoDocId, uid);
                        },
                      ),
                      Text('$count'),
                      IconButton(
                        icon: const Icon(Icons.comment),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  CommentsPage(videoDocId: widget.videoDocId)),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
      body: Center(
        child: _initialized && _controller != null
            ? GestureDetector(
                onTap: () {
                  setState(() {
                    _isPaused = !_isPaused;
                  });
                  if (_isPaused) {
                    _controller!.pause();
                  } else {
                    _controller!.play();
                  }
                },
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    ),
                    // Индикатор паузы
                    if (_isPaused)
                      IgnorePointer(
                        child: Container(
                          color: Colors.black.withOpacity(0.3),
                          child: const Center(
                            child: Icon(
                              Icons.pause_circle_filled,
                              color: Colors.white,
                              size: 80,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
