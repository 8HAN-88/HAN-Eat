import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_router.dart';
import '../models/post_model.dart';

/// Кто показывается как «автор» поста/рилса: канал или пользователь.
class PostPublisherDisplay {
  PostPublisherDisplay._();

  static bool isChannel(PostModel post) => post.channelId != null;

  static String? _channelNameFromBody(Map<String, dynamic>? body) {
    if (body == null) return null;
    final name = body['channel_name'];
    if (name is String && name.trim().isNotEmpty) return name.trim();
    return null;
  }

  static String? _channelAvatarFromBody(Map<String, dynamic>? body) {
    if (body == null) return null;
    final avatar = body['channel_avatar'];
    if (avatar is String && avatar.trim().isNotEmpty) return avatar.trim();
    return null;
  }

  static String label(PostModel post) {
    if (isChannel(post)) {
      final ch = post.channel;
      if (ch != null && ch.name.trim().isNotEmpty) return ch.name.trim();
      final fromBody = _channelNameFromBody(post.body);
      if (fromBody != null) return fromBody;
      return 'Канал';
    }
    final author = post.author;
    if (author?.username?.trim().isNotEmpty == true) {
      return author!.username!.trim();
    }
    if (author?.name.trim().isNotEmpty == true) return author!.name.trim();
    return 'unknown';
  }

  static String atLabel(PostModel post) {
    final text = label(post);
    if (isChannel(post)) return text;
    return text.startsWith('@') ? text : '@$text';
  }

  static String? avatarUrl(PostModel post) {
    if (isChannel(post)) {
      return post.channel?.avatarUrl ?? _channelAvatarFromBody(post.body);
    }
    return post.author?.avatarUrl;
  }

  static String avatarInitial(PostModel post) {
    final name = label(post);
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  static void open(BuildContext context, PostModel post) {
    if (isChannel(post) && post.channelId != null) {
      context.push(ChannelDetailRoute.pathFor(post.channelId!));
      return;
    }
    context.push('${ProfileRoute.path}?userId=${post.userId}');
  }
}
