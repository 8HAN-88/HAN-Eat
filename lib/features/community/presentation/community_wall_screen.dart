import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/post.dart';
import '../../../models/post_types.dart';
import '../../../models/community.dart';
import '../../../services/community_management_service.dart';
import '../../../services/post_publication_service.dart';
import 'create_post_screen.dart';
import 'post_interactions_widget.dart';
import 'post_comments_page.dart';

/// Экран стены канала
class CommunityWallScreen extends StatefulWidget {
  final String communityId;

  const CommunityWallScreen({
    super.key,
    required this.communityId,
  });

  @override
  State<CommunityWallScreen> createState() => _CommunityWallScreenState();
}

class _CommunityWallScreenState extends State<CommunityWallScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Community? _community;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCommunity();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCommunity() async {
    final community = await CommunityManagementService.getCommunity(widget.communityId);
    setState(() => _community = community);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_community?.name ?? 'Канал'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // TODO: Настройки канала
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Все записи'),
            Tab(text: 'Записи канала'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAllPostsTab(),
          _buildCommunityPostsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreatePostScreen(communityId: widget.communityId),
            ),
          );
          if (result == true) {
            setState(() {}); // Обновляем список
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildAllPostsTab() {
    return StreamBuilder<List<Post>>(
      stream: CommunityManagementService.getCommunityWall(widget.communityId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Ошибка: ${snapshot.error}'));
        }

        final posts = snapshot.data ?? [];
        if (posts.isEmpty) {
          return const Center(child: Text('Пока нет записей'));
        }

        // Разделяем закреплённые и обычные посты
        final pinnedPosts = posts.where((p) => p.isPinned).toList();
        final regularPosts = posts.where((p) => !p.isPinned).toList();

        return ListView(
          children: [
            if (pinnedPosts.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  'Закреплено',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ...pinnedPosts.map((post) => _buildPostCard(post)),
            ],
            if (regularPosts.isNotEmpty) ...[
              if (pinnedPosts.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    'Все записи',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ...regularPosts.map((post) => _buildPostCard(post)),
            ],
          ],
        );
      },
    );
  }

  Widget _buildCommunityPostsTab() {
    return StreamBuilder<List<Post>>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .where('communityId', isEqualTo: widget.communityId)
          .where('isDeleted', isEqualTo: false)
          .orderBy('isPinned', descending: true)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => Post.fromFirestore(doc))
              .toList()),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Ошибка: ${snapshot.error}'));
        }

        final posts = snapshot.data ?? [];
        if (posts.isEmpty) {
          return const Center(child: Text('Пока нет записей канала'));
        }

        return ListView.builder(
          itemCount: posts.length,
          itemBuilder: (context, index) => _buildPostCard(posts[index]),
        );
      },
    );
  }

  Widget _buildPostCard(Post post) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundImage: post.communityId != null && post.groupAvatar != null
                  ? NetworkImage(post.groupAvatar!)
                  : post.authorAvatar != null
                      ? NetworkImage(post.authorAvatar!)
                      : null,
              child: post.communityId != null && post.groupAvatar == null && post.authorAvatar == null
                  ? const Icon(Icons.group)
                  : null,
            ),
            title: Text(
              post.communityId != null && post.groupName != null
                  ? post.groupName!
                  : post.authorName ?? 'Пользователь',
            ),
            subtitle: Text(_formatDate(post.createdAt)),
            trailing: post.isPinned
                ? const Icon(Icons.push_pin, size: 16)
                : null,
          ),
          if (post.text != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(post.text!),
            ),
          if (post.photos != null && post.photos!.isNotEmpty)
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: post.photos!.length,
                itemBuilder: (context, index) => Image.network(
                  post.photos![index],
                  fit: BoxFit.cover,
                  width: 200,
                ),
              ),
            ),
          if (post.type == PostType.reel && post.videoUrl != null)
            Container(
              height: 300,
              color: Colors.black,
              child: const Center(
                child: Icon(Icons.play_circle_outline, size: 64, color: Colors.white),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: PostInteractionsWidget(
              post: post,
              onCommentsTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PostCommentsPage(postId: post.idString),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }


  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes} мин назад';
      }
      return '${difference.inHours} ч назад';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} дн назад';
    } else {
      return '${date.day}.${date.month}.${date.year}';
    }
  }
}

