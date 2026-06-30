// Модели для BotFather API

class BotCreateRequest {
  final String name;
  final String username;
  final String? description;
  final String? shortDescription;
  final List<BotCommandCreate> commands;

  BotCreateRequest({
    required this.name,
    required this.username,
    this.description,
    this.shortDescription,
    this.commands = const [],
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'username': username,
        if (description != null) 'description': description,
        if (shortDescription != null) 'short_description': shortDescription,
        'commands': commands.map((c) => c.toJson()).toList(),
      };
}

class BotCommandCreate {
  final String command;
  final String description;

  BotCommandCreate({required this.command, required this.description});

  Map<String, dynamic> toJson() => {
        'command': command,
        'description': description,
      };
}

class BotResponse {
  final int id;
  final String name;
  final String username;
  final String botToken;
  final String? description;
  final String? shortDescription;
  final String? avatarUrl;

  BotResponse({
    required this.id,
    required this.name,
    required this.username,
    required this.botToken,
    this.description,
    this.shortDescription,
    this.avatarUrl,
  });

  factory BotResponse.fromJson(Map<String, dynamic> json) => BotResponse(
        id: json['id'] as int,
        name: json['name'] as String,
        username: json['username'] as String,
        botToken: json['bot_token'] as String,
        description: json['description'] as String?,
        shortDescription: json['short_description'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );
}

class BotListItem {
  final int id;
  final String name;
  final String username;
  final String? description;
  final String? shortDescription;
  final String? avatarUrl;

  BotListItem({
    required this.id,
    required this.name,
    required this.username,
    this.description,
    this.shortDescription,
    this.avatarUrl,
  });

  factory BotListItem.fromJson(Map<String, dynamic> json) => BotListItem(
        id: json['id'] as int,
        name: json['name'] as String,
        username: json['username'] as String,
        description: json['description'] as String?,
        shortDescription: json['short_description'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );
}
