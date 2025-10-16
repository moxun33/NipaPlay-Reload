import 'dart:convert';

class AlistHost {
  AlistHost({
    required this.id,
    this.displayName = 'AList',
    required this.baseUrl,
    this.username = '',
    this.password = '',
    this.token,
    this.tokenExpiresAt,
    this.lastConnectedAt,
    this.lastError,
    this.isOnline = false,
    this.enabled = true,
  });

  final String id;
  final String displayName;
  final String baseUrl;
  final String username;
  final String password;
  final String? token;
  final DateTime? tokenExpiresAt;
  final DateTime? lastConnectedAt;
  final String? lastError;
  final bool isOnline;
  final bool enabled;

  AlistHost copyWith({
    String? id,
    String? displayName,
    String? baseUrl,
    String? username,
    String? password,
    String? token,
    DateTime? tokenExpiresAt,
    DateTime? lastConnectedAt,
    String? lastError,
    bool? isOnline,
    bool? enabled,
  }) {
    return AlistHost(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      token: token ?? this.token,
      tokenExpiresAt: tokenExpiresAt,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      lastError: lastError,
      isOnline: isOnline ?? this.isOnline,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'baseUrl': baseUrl,
      'username': username,
      'password': password,
      'token': token,
      'tokenExpiresAt': tokenExpiresAt?.toIso8601String(),
      'lastConnectedAt': lastConnectedAt?.toIso8601String(),
      'lastError': lastError,
      'isOnline': isOnline,
      'enabled': enabled,
    };
  }

  factory AlistHost.fromJson(Map<String, dynamic> json) {
    // 确保json是Map<String, dynamic>类型
    final safeJson = Map<String, dynamic>.from(json);
    return AlistHost(
      id: safeJson['id'] as String? ?? '',
      displayName: safeJson['displayName'] as String? ?? 'AList',
      baseUrl: safeJson['baseUrl'] as String? ?? '',
      username: safeJson['username'] as String? ?? '',
      password: safeJson['password'] as String? ?? '',
      token: safeJson['token'] as String?,
      tokenExpiresAt: safeJson['tokenExpiresAt'] != null
          ? DateTime.tryParse(safeJson['tokenExpiresAt'] as String? ?? '')
          : null,
      lastConnectedAt: safeJson['lastConnectedAt'] != null
          ? DateTime.tryParse(safeJson['lastConnectedAt'] as String? ?? '')
          : null,
      lastError: safeJson['lastError'] as String?,
      isOnline: safeJson['isOnline'] as bool? ?? false,
      enabled: safeJson['enabled'] as bool? ?? true,
    );
  }

  static List<AlistHost> decodeList(String raw) {
    final decoded = json.decode(raw) as List<dynamic>;
    return decoded
        .map((item) => AlistHost.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static String encodeList(List<AlistHost> hosts) {
    return json.encode(hosts.map((host) => host.toJson()).toList());
  }
}

class AlistFile {
  AlistFile({
    required this.name,
    required this.size,
    required this.isDir,
    required this.modified,
    required this.sign,
    required this.thumb,
    required this.type,
    this.created,
    this.hashinfo,
  });

  final String name;
  final int size;
  final bool isDir;
  final DateTime modified;
  final String sign;
  final String thumb;
  final int type;
  final DateTime? created;
  final String? hashinfo;

  factory AlistFile.fromJson(Map<String, dynamic> json) {
    // 确保json是Map<String, dynamic>类型
    final safeJson = Map<String, dynamic>.from(json);
    return AlistFile(
      name: safeJson['name'] as String? ?? '',
      size: safeJson['size'] as int? ?? 0,
      isDir: safeJson['is_dir'] as bool? ?? false,
      modified: DateTime.tryParse(safeJson['modified'] as String? ?? '') ??
          DateTime.now(),
      sign: safeJson['sign'] as String? ?? '',
      thumb: safeJson['thumb'] as String? ?? '',
      type: safeJson['type'] as int? ?? 0,
      created: safeJson['created'] != null
          ? DateTime.tryParse(safeJson['created'] as String? ?? '')
          : null,
      hashinfo: safeJson['hashinfo'] as String?,
    );
  }

  bool get isVideo =>
      !isDir &&
      (name.endsWith('.mp4') ||
          name.endsWith('.mkv') ||
          name.endsWith('.avi') ||
          name.endsWith('.mov') ||
          name.endsWith('.wmv') ||
          name.endsWith('.webm'));
}

class AlistFileListResponse {
  AlistFileListResponse({
    required this.code,
    required this.message,
    required this.data,
  });

  final int code;
  final String message;
  final AlistFileListData data;

  factory AlistFileListResponse.fromJson(Map<String, dynamic> json) {
    return AlistFileListResponse(
      code: json['code'] as int? ?? -1,
      message: json['message'] as String? ?? '未知错误',
      data: AlistFileListData.fromJson(
          Map<String, dynamic>.from(json['data'] ?? {})),
    );
  }
}

class AlistFileListData {
  AlistFileListData({
    required this.content,
    required this.total,
    required this.readme,
    required this.header,
    required this.write,
    required this.provider,
  });

  final List<AlistFile> content;
  final int total;
  final String readme;
  final String header;
  final bool write;
  final String provider;

  factory AlistFileListData.fromJson(Map<String, dynamic> json) {
    return AlistFileListData(
      content: json.containsKey('content') && json['content'] != null
          ? (json['content'] as List<dynamic>)
              .map(
                  (item) => AlistFile.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : [],
      total: json['total'] as int? ?? 0,
      readme: json['readme'] as String? ?? '',
      header: json['header'] as String? ?? '',
      write: json['write'] as bool? ?? false,
      provider: json['provider'] as String? ?? '',
    );
  }
}

class AlistAuthResponse {
  AlistAuthResponse({
    required this.code,
    required this.message,
    required this.data,
  });

  final int code;
  final String message;
  final AlistAuthData data;

  factory AlistAuthResponse.fromJson(Map<String, dynamic> json) {
    return AlistAuthResponse(
      code: json['code'] as int,
      message: json['message'] as String,
      data: AlistAuthData.fromJson(json['data'] as Map<String, dynamic>),
    );
  }
}

class AlistAuthData {
  AlistAuthData({
    required this.token,
  });

  final String token;

  factory AlistAuthData.fromJson(Map<String, dynamic> json) {
    return AlistAuthData(
      token: json['token'] as String,
    );
  }
}
