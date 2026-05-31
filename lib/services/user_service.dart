// Сервис для работы с пользователями
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'auth_service.dart';
import 'media_upload_service.dart';
import 'server_config.dart';

class UserService {
  static String get baseUrl => ServerConfig.apiBaseUrl;
  
  // Singleton instance
  static final UserService instance = UserService._();
  UserService._();
  
  // Кэшированный профиль текущего пользователя
  final ValueNotifier<UserProfile?> profile = ValueNotifier(null);
  
  /// Инициализация сервиса
  static Future<void> init() async {
    // Пока ничего не делаем при инициализации
  }
  
  /// Получить публичный профиль пользователя
  Future<UserProfile> loadPublicProfile(String userId) async {
    return await getProfile(int.tryParse(userId) ?? 0);
  }
  
  /// Загрузить профиль текущего пользователя
  Future<void> ensureProfileLoaded() async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) return;
    try {
      final userProfile = await getProfile(currentUser.id);
      profile.value = userProfile;
    } catch (e) {
      debugPrint('ensureProfileLoaded: $e');
    }
  }
  
  /// Выбрать изображение аватара
  Future<XFile?> pickAvatarImage() async {
    final ImagePicker picker = ImagePicker();
    try {
      // На веб доступна только галерея, на мобильных можно выбрать источник
      final XFile? image = await picker.pickImage(
        source: kIsWeb ? ImageSource.gallery : ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      return image;
    } catch (e) {
      // Игнорируем ошибки (пользователь отменил выбор и т.д.)
      return null;
    }
  }
  
  /// Обновить аватар из XFile (загрузка на API через /uploads, затем PATCH avatar_url).
  Future<void> updateAvatarFromXFile(dynamic xFile, {Function(double)? onProgress}) async {
    if (AuthService.instance.currentUser == null) {
      throw Exception('Not authenticated');
    }
    if (xFile is! XFile) {
      throw ArgumentError.value(xFile, 'xFile', 'Expected XFile');
    }
    final complete = await MediaUploadService.uploadMediaFile(
      file: xFile,
      fileType: 'image',
      onProgress: onProgress,
    );
    var url = complete.url;
    if (url == null || url.isEmpty) {
      throw Exception('Сервер не вернул URL загруженного файла');
    }
    url = ServerConfig.resolveMediaUrl(url);
    final updated = await UserService.updateProfile(avatarUrl: url);
    await AuthService.persistUpdatedUser(updated);
    _applyCachedProfileUser(updated);
  }
  
  void _applyCachedProfileUser(User user) {
    final current = profile.value;
    profile.value = UserProfile(
      user: user,
      stats: current?.stats ??
          UserStats(
            postsCount: 0,
            reelsCount: 0,
            savedCount: 0,
            followersCount: 0,
            followingCount: 0,
          ),
      isFollowing: current?.isFollowing,
      isFollowedBy: current?.isFollowedBy,
      uid: user.uid,
    );
  }

  /// Обновить имя и/или описание профиля.
  Future<void> updateProfileFields({String? name, String? bio}) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      throw Exception('Войдите в аккаунт');
    }
    final trimmedName = name?.trim();
    if (trimmedName != null && trimmedName.isEmpty) {
      throw Exception('Имя не может быть пустым');
    }
    String? bioPayload;
    if (bio != null) {
      final t = bio.trim();
      bioPayload = t.isEmpty ? '' : t;
    }
    final updated = await UserService.updateProfile(
      name: trimmedName,
      bio: bioPayload,
    );
    await AuthService.persistUpdatedUser(updated);
    _applyCachedProfileUser(updated);
  }

  /// Обновить отображаемое имя
  Future<void> updateDisplayName(String name) async {
    await updateProfileFields(name: name);
  }
  
  /// Подписан ли текущий пользователь на пользователя с id [userId] (числовой id API).
  Future<bool> isFollowing(String userId) async {
    final id = int.tryParse(userId);
    if (id == null || id <= 0) return false;
    try {
      final p = await UserService.getProfile(id);
      return p.isFollowing ?? false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('UserService.isFollowing: $e');
      }
      return false;
    }
  }

  /// Снимок профиля и статистики (резервная копия / обмен).
  Future<Map<String, dynamic>> exportToJson() async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      throw Exception('Not authenticated');
    }
    final p = await UserService.getProfile(currentUser.id);
    return {
      'export_version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'user': p.user.toJson(),
      'stats': {
        'posts_count': p.stats.postsCount,
        'reels_count': p.stats.reelsCount,
        'saved_count': p.stats.savedCount,
        'followers_count': p.stats.followersCount,
        'following_count': p.stats.followingCount,
      },
    };
  }

  /// Восстановить поля профиля из экспорта (только свой аккаунт).
  Future<void> importFromJson(Map<String, dynamic> json, {bool merge = true}) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      throw Exception('Not authenticated');
    }
    final ver = json['export_version'];
    if (ver is! int || ver != 1) {
      throw FormatException('Неподдерживаемая версия экспорта: $ver');
    }
    final userMap = json['user'] as Map<String, dynamic>?;
    if (userMap == null) return;
    final importedId = userMap['id'];
    final id = importedId is int
        ? importedId
        : int.tryParse(importedId?.toString() ?? '');
    if (id == null || id != currentUser.id) {
      throw Exception('Данные относятся к другому аккаунту');
    }
    if (!merge) return;

    String? name;
    final rawName = userMap['name'];
    if (rawName is String && rawName.trim().isNotEmpty) {
      name = rawName.trim();
    }
    String? bio;
    final rawBio = userMap['bio'];
    if (rawBio is String && rawBio.trim().isNotEmpty) {
      bio = rawBio.trim();
    }
    bool? isPrivate;
    if (userMap.containsKey('is_private')) {
      isPrivate = userMap['is_private'] as bool?;
    }

    if (name == null && bio == null && !userMap.containsKey('is_private')) {
      return;
    }

    final updated = await UserService.updateProfile(
      name: name,
      bio: bio,
      isPrivate: isPrivate,
    );
    await AuthService.persistUpdatedUser(updated);
    await ensureProfileLoaded();
  }
  
  /// Проверить, инициализирован ли сервис
  static bool get isInitialized => true;
  
  /// Получить профиль пользователя
  static Future<UserProfile> getProfile(int userId) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/users/$userId');
    try {
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Превышено время ожидания ответа от сервера');
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return UserProfile.fromJson(data);
      } else {
        throw Exception('Failed to load profile: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error in getProfile: $e');
      }
      if (e.toString().contains('Failed host lookup') || 
          e.toString().contains('Connection refused') ||
          e.toString().contains('Failed to fetch') ||
          e.toString().contains('Превышено время ожидания')) {
        throw Exception('Сервер недоступен. Проверьте подключение к серверу.');
      }
      rethrow;
    }
  }
  
  /// Подписаться на пользователя
  static Future<void> follow(int userId) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/users/$userId/follow');
    try {
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Превышено время ожидания ответа от сервера');
        },
      );
      
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to follow user');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error in follow: $e');
      }
      if (e.toString().contains('Failed host lookup') || 
          e.toString().contains('Connection refused') ||
          e.toString().contains('Failed to fetch') ||
          e.toString().contains('Превышено время ожидания')) {
        throw Exception('Сервер недоступен. Проверьте подключение к серверу.');
      }
      rethrow;
    }
  }
  
  /// Подписаться на пользователя (алиас)
  static Future<void> followUser(String userId) async {
    final id = int.tryParse(userId);
    if (id == null || id <= 0) {
      throw Exception('Некорректный id пользователя');
    }
    return await follow(id);
  }
  
  /// Отписаться от пользователя (алиас)
  static Future<void> unfollowUser(String userId) async {
    final id = int.tryParse(userId);
    if (id == null || id <= 0) {
      throw Exception('Некорректный id пользователя');
    }
    return await unfollow(id);
  }
  
  /// Отписаться от пользователя
  static Future<void> unfollow(int userId) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/users/$userId/follow');
    try {
      final response = await http.delete(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Превышено время ожидания ответа от сервера');
        },
      );
      
      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Failed to unfollow user');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error in unfollow: $e');
      }
      if (e.toString().contains('Failed host lookup') || 
          e.toString().contains('Connection refused') ||
          e.toString().contains('Failed to fetch') ||
          e.toString().contains('Превышено время ожидания')) {
        throw Exception('Сервер недоступен. Проверьте подключение к серверу.');
      }
      rethrow;
    }
  }
  
  /// Обновить профиль
  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null || token.isEmpty) {
      throw Exception('Сессия истекла. Войдите снова.');
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  static String _apiErrorMessage(http.Response response, String fallback) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) {
        final detail = data['detail'];
        if (detail is String && detail.isNotEmpty) return detail;
        if (detail is List && detail.isNotEmpty) {
          return detail.map((e) => e.toString()).join(', ');
        }
      }
    } catch (_) {}
    return '$fallback (${response.statusCode})';
  }

  static Future<User> updateProfile({
    String? name,
    String? bio,
    bool? isPrivate,
    String? avatarUrl,
    String? fcmToken,
  }) async {
    final uri = Uri.parse('$baseUrl/users/me');
    try {
      var headers = await _authHeaders();
      var response = await http
          .patch(
            uri,
            headers: headers,
            body: jsonEncode({
              if (name != null) 'name': name,
              if (bio != null) 'bio': bio,
              if (isPrivate != null) 'is_private': isPrivate,
              if (avatarUrl != null) 'avatar_url': avatarUrl,
              if (fcmToken != null) 'fcm_token': fcmToken,
            }),
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception(
              'Превышено время ожидания ответа от сервера',
            ),
          );

      if (response.statusCode == 401) {
        final refreshed = await AuthService.refreshToken();
        headers = {
          'Authorization': 'Bearer $refreshed',
          'Content-Type': 'application/json',
        };
        response = await http.patch(
          uri,
          headers: headers,
          body: jsonEncode({
            if (name != null) 'name': name,
            if (bio != null) 'bio': bio,
            if (isPrivate != null) 'is_private': isPrivate,
            if (avatarUrl != null) 'avatar_url': avatarUrl,
            if (fcmToken != null) 'fcm_token': fcmToken,
          }),
        );
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return User.fromJson(data);
      }
      throw Exception(
        _apiErrorMessage(response, 'Не удалось обновить профиль'),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error in updateProfile: $e');
      }
      final s = e.toString();
      if (s.contains('Failed host lookup') ||
          s.contains('Connection refused') ||
          s.contains('Failed to fetch') ||
          s.contains('SocketException') ||
          s.contains('Превышено время ожидания')) {
        throw Exception('Сервер недоступен. Проверьте подключение к серверу.');
      }
      rethrow;
    }
  }
}

// Временные модели (позже вынести)
class UserProfile {
  final User user;
  final UserStats stats;
  final bool? isFollowing;
  final bool? isFollowedBy;
  final String? uid; // Для совместимости
  
  // Геттеры для совместимости
  String get displayName => user.name;
  String? get avatarUrl => user.avatarUrl;
  
  UserProfile({
    User? user,
    UserStats? stats,
    this.isFollowing,
    this.isFollowedBy,
    this.uid,
  }) : user = user ?? User(
          id: int.tryParse(uid ?? '0') ?? 0,
          email: '',
          name: '',
          isPrivate: false,
          createdAt: DateTime.now(),
        ),
        stats = stats ?? UserStats(
          postsCount: 0,
          reelsCount: 0,
          savedCount: 0,
          followersCount: 0,
          followingCount: 0,
        );
  
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    // Преобразуем данные пользователя из JSON
    final userJson = {
      'id': json['id'],
      'email': json['email'],
      'name': json['name'],
      'username': json['username'],
      'avatar_url': json['avatar_url'],
      'bio': json['bio'],
      'is_private': json['is_private'],
      'created_at': json['created_at'],
    };
    
    return UserProfile(
      user: User.fromJson(userJson),
      stats: UserStats.fromJson(json['stats'] as Map<String, dynamic>),
      isFollowing: json['is_following'] as bool?,
      isFollowedBy: json['is_followed_by'] as bool?,
    );
  }
}

class UserStats {
  final int postsCount;
  final int reelsCount;
  final int savedCount;
  final int followersCount;
  final int followingCount;
  
  UserStats({
    required this.postsCount,
    required this.reelsCount,
    required this.savedCount,
    required this.followersCount,
    required this.followingCount,
  });
  
  factory UserStats.fromJson(Map<String, dynamic> json) {
    return UserStats(
      postsCount: json['posts_count'] as int? ?? 0,
      reelsCount: json['reels_count'] as int? ?? 0,
      savedCount: json['saved_count'] as int? ?? 0,
      followersCount: json['followers_count'] as int? ?? 0,
      followingCount: json['following_count'] as int? ?? 0,
    );
  }
}
