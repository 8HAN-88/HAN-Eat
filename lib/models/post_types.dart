// Типы постов и статусы

enum PostType {
  text,
  photo,
  recipe,
  reel,
  link,
  photoGallery,
  repost,
  video,
  poll,
  
  // Для обратной совместимости со строковыми значениями
  ;
  
  String get value {
    switch (this) {
      case PostType.text:
        return 'text';
      case PostType.photo:
        return 'photo';
      case PostType.recipe:
        return 'recipe';
      case PostType.reel:
        return 'reel';
      case PostType.link:
        return 'link';
      case PostType.photoGallery:
        return 'photo_gallery';
      case PostType.repost:
        return 'repost';
      case PostType.video:
        return 'video';
      case PostType.poll:
        return 'poll';
    }
  }
  
  static PostType? fromString(String? value) {
    if (value == null) return null;
    switch (value.toLowerCase()) {
      case 'text':
        return PostType.text;
      case 'photo':
        return PostType.photo;
      case 'recipe':
        return PostType.recipe;
      case 'reel':
        return PostType.reel;
      case 'link':
        return PostType.link;
      case 'photo_gallery':
      case 'photoGallery':
        return PostType.photoGallery;
      case 'repost':
        return PostType.repost;
      case 'video':
        return PostType.video;
      case 'poll':
        return PostType.poll;
      default:
        return null;
    }
  }
}

enum PostStatus {
  draft,
  published,
  pending,
  rejected,
  archived,
  deleted,
  
  // Для обратной совместимости со строковыми значениями
  ;
  
  String get value {
    switch (this) {
      case PostStatus.draft:
        return 'draft';
      case PostStatus.published:
        return 'published';
      case PostStatus.pending:
        return 'pending';
      case PostStatus.rejected:
        return 'rejected';
      case PostStatus.archived:
        return 'archived';
      case PostStatus.deleted:
        return 'deleted';
    }
  }
  
  static PostStatus? fromString(String? value) {
    if (value == null) return null;
    switch (value.toLowerCase()) {
      case 'draft':
        return PostStatus.draft;
      case 'published':
        return PostStatus.published;
      case 'pending':
        return PostStatus.pending;
      case 'rejected':
        return PostStatus.rejected;
      case 'archived':
        return PostStatus.archived;
      case 'deleted':
        return PostStatus.deleted;
      default:
        return null;
    }
  }
}

enum FeedSortMode {
  personalized,
  recent,
  popular,
  trending,
  
  // Для обратной совместимости
  ;
  
  String get value {
    switch (this) {
      case FeedSortMode.personalized:
        return 'personalized';
      case FeedSortMode.recent:
        return 'recent';
      case FeedSortMode.popular:
        return 'popular';
      case FeedSortMode.trending:
        return 'trending';
    }
  }
  
  static FeedSortMode? fromString(String? value) {
    if (value == null) return null;
    switch (value.toLowerCase()) {
      case 'personalized':
        return FeedSortMode.personalized;
      case 'recent':
        return FeedSortMode.recent;
      case 'popular':
        return FeedSortMode.popular;
      case 'trending':
        return FeedSortMode.trending;
      default:
        return null;
    }
  }
}

