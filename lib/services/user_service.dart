// Сервис для работы с пользователями
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'auth_service.dart';
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
      // Игнорируем ошибки
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
  
  /// Обновить аватар из XFile
  Future<void> updateAvatarFromXFile(dynamic xFile, {Function(double)? onProgress}) async {
    // TODO: Реализовать загрузку аватара
    throw UnimplementedError('updateAvatarFromXFile not implemented');
  }
  
  /// Обновить отображаемое имя
  Future<void> updateDisplayName(String name) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) throw Exception('Not authenticated');
    
    await updateProfile(name: name);
    // Обновляем кэш
    await ensureProfileLoaded();
  }
  
  /// Проверить, подписан ли пользователь
  Future<bool> isFollowing(String userId) async {
    // TODO: Реализовать проверку подписки
    return false;
  }
  
  /// Экспортировать данные пользователя в JSON
  Future<Map<String, dynamic>> exportToJson() async {
    // TODO: Реализовать экспорт
    throw UnimplementedError('exportToJson not implemented');
  }
  
  /// Импортировать данные пользователя из JSON
  Future<void> importFromJson(Map<String, dynamic> json, {bool merge = true}) async {
    // TODO: Реализовать импорт
    throw UnimplementedError('importFromJson not implemented');
  }
  
  /// Проверить, инициализирован ли сервис
  static bool get isInitialized => true;
  
  /// Получить профиль пользователя
  static Future<UserProfile> getProfile(int userId) async {
    final token = await AuthService.getAccessToken();
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
    final token = await AuthService.getAccessToken();
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
    return await follow(int.tryParse(userId) ?? 0);
  }
  
  /// Отписаться от пользователя (алиас)
  static Future<void> unfollowUser(String userId) async {
    return await unfollow(int.tryParse(userId) ?? 0);
  }
  
  /// Отписаться от пользователя
  static Future<void> unfollow(int userId) async {
    final token = await AuthService.getAccessToken();
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
  static Future<User> updateProfile({
    String? name,
    String? bio,
    bool? isPrivate,
    String? avatarUrl,
    String? fcmToken,
  }) async {
    final token = await AuthService.getAccessToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    final uri = Uri.parse('$baseUrl/users/me');
    try {
      final response = await http.patch(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          if (name != null) 'name': name,
          if (bio != null) 'bio': bio,
          if (isPrivate != null) 'is_private': isPrivate,
          if (avatarUrl != null) 'avatar_url': avatarUrl,
          if (fcmToken != null) 'fcm_token': fcmToken,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Превышено время ожидания ответа от сервера');
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return User.fromJson(data);
      } else {
        throw Exception('Failed to update profile');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error in updateProfile: $e');
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
