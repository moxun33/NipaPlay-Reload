import 'dart:convert';

import 'package:flutter/foundation.dart';

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
    };
  }

  factory AlistHost.fromJson(Map<String, dynamic> json) {
    return AlistHost(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'AList',
      baseUrl: json['baseUrl'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      token: json['token'] as String?,
      tokenExpiresAt: json['tokenExpiresAt'] != null
          ? DateTime.tryParse(json['tokenExpiresAt'] as String? ?? '')
          : null,
      lastConnectedAt: json['lastConnectedAt'] != null
          ? DateTime.tryParse(json['lastConnectedAt'] as String? ?? '')
          : null,
      lastError: json['lastError'] as String?,
      isOnline: json['isOnline'] as bool? ?? false,
    );
  }

  static List<AlistHost> decodeList(String raw) {
    final decoded = json.decode(raw) as List<dynamic>;
    return decoded
        .map((item) => AlistHost.fromJson(item as Map<String, dynamic>))
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
    return AlistFile(
      name: json['name'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      isDir: json['is_dir'] as bool? ?? false,
      modified: DateTime.tryParse(json['modified'] as String? ?? '') ?? DateTime.now(),
      sign: json['sign'] as String? ?? '',
      thumb: json['thumb'] as String? ?? '',
      type: json['type'] as int? ?? 0,
      created: json['created'] != null
          ? DateTime.tryParse(json['created'] as String)
          : null,
      hashinfo: json['hashinfo'] as String?,    
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
          (json['data'] ?? {}) as Map<String, dynamic>),
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
              .map((item) => AlistFile.fromJson(item as Map<String, dynamic>))
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
