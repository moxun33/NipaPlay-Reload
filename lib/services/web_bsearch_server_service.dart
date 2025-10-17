import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:path/path.dart' as p;
import 'package:nipaplay/utils/storage_service.dart';

class WebBSearchServerService {
  static const int _fixedPort = 34568;
  
  HttpServer? _server;
  bool _isRunning = false;

  bool get isRunning => _isRunning;
  int get port => _fixedPort; // 固定端口

  Future<bool> startServer() async {
    if (_isRunning) {
      debugPrint('bsearch Web server is already running on port $_fixedPort');
      return true;
    }

    try {
      // bsearch搜索服务资源路径
      final bWebAppPath = p.join(
          (await StorageService.getAppStorageDirectory()).path, 'bsearch');
      
      // 解压assets/bsearch资源到存储目录
      await _extractBSearchAssets(bWebAppPath);
      
      // 创建静态文件处理器
      final staticHandler = createStaticHandler(bWebAppPath, defaultDocument: 'index.html');

      // 设置中间件和处理器
      final handler = const Pipeline()
          .addMiddleware(corsHeaders())
          .addMiddleware(logRequests())
          .addHandler(staticHandler);

      // 启动服务器，监听所有网络接口
      _server = await shelf_io.serve(handler, '0.0.0.0', _fixedPort);
      _isRunning = true;
      debugPrint('bsearch Web server started on port $_fixedPort');
      return true;
    } catch (e) {
      debugPrint('Failed to start bsearch web server: $e');
      _isRunning = false;
      return false;
    }
  }

  Future<void> stopServer() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      _isRunning = false;
      debugPrint('bsearch Web server stopped.');
    }
  }

  Future<List<String>> getAccessUrls() async {
    if (!_isRunning || _server == null) return [];

    final urls = <String>[];
    urls.add('http://localhost:$_fixedPort');
    urls.add('http://127.0.0.1:$_fixedPort');

    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            urls.add('http://${addr.address}:$_fixedPort');
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting network interfaces for bsearch server: $e');
    }
    return urls;
  }

  /// 专门用于解压bsearch资源的方法
  Future<void> _extractBSearchAssets(String targetDirectory) async {
    try {
      // 确保目标目录存在
      final targetDir = Directory(targetDirectory);
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
        debugPrint('Created bsearch directory: $targetDirectory');
      }

      // 使用rootBundle加载AssetManifest.json获取所有资源
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);

      // 筛选出assets/bsearch/目录下的资源
      final bsearchAssetPaths = manifestMap.keys
          .where((String key) => key.startsWith('assets/bsearch/'))
          .toList();

      if (bsearchAssetPaths.isEmpty) {
        debugPrint('Warning: No assets found under "assets/bsearch/" in AssetManifest.json.');
        return;
      }
      
      debugPrint('Found ${bsearchAssetPaths.length} bsearch assets to extract');

      for (final String assetPath in bsearchAssetPaths) {
        // 计算相对路径，移除assets/bsearch/前缀
        final relativePath = p.relative(assetPath, from: 'assets/bsearch');
        
        // 跳过特殊文件
        if (relativePath == '.' || relativePath.isEmpty || p.basename(relativePath).startsWith('.')) {
          debugPrint('Skipping special/hidden file: $assetPath');
          continue;
        }

        final destinationFile = File(p.join(targetDirectory, relativePath));

        try {
          debugPrint('Extracting [${assetPath}] to [${destinationFile.path}]');
          await destinationFile.parent.create(recursive: true);
          final assetData = await rootBundle.load(assetPath);
          await destinationFile.writeAsBytes(assetData.buffer.asUint8List(), flush: true);
        } catch (e) {
          debugPrint('Failed to extract asset [${assetPath}]: $e');
        }
      }
      debugPrint('BSearch asset extraction complete');
    } catch (e) {
      debugPrint('Error during BSearch asset extraction: $e');
    }
  }
}