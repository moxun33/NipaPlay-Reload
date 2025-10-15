import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/alist_provider.dart';
import '../models/playable_item.dart';

class AlistView extends StatefulWidget {
  final Function(PlayableItem) onPlayEpisode;
  final String? hostId; // 可选参数，如果提供则显示特定的AList服务器

  const AlistView({
    Key? key,
    required this.onPlayEpisode,
    this.hostId,
  }) : super(key: key);

  @override
  _AlistViewState createState() => _AlistViewState();
}

class _AlistViewState extends State<AlistView> {
  late AlistProvider _alistProvider;
  bool _isInitializing = true;
  SharedPreferences? _prefs;
  String _lastVisitedPath = '/'; // 默认根目录

  @override
  void initState() {
    super.initState();
    _alistProvider = Provider.of<AlistProvider>(context, listen: false);
    _initializeApp();
  }

  // 初始化应用，确保_loadPreferences完成后再执行_initializeView
  Future<void> _initializeApp() async {
    await _loadPreferences();
    await _initializeView();
  }

  // 加载SharedPreferences实例
  Future<void> _loadPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    // 尝试获取上次访问的路径
    final savedPath =
        _prefs?.getString('alist_last_path_${widget.hostId ?? 'default'}');
    if (savedPath != null) {
      _lastVisitedPath = savedPath;
    }
  }

  // 缓存当前路径
  Future<void> _cacheCurrentPath(String path) async {
    if (_prefs != null) {
      await _prefs!
          .setString('alist_last_path_${widget.hostId ?? 'default'}', path);
      _lastVisitedPath = path;
    }
  }

  // 自动连接当前AList服务器并加载上次路径
  Future<void> _initializeView() async {
    try {
      // 确保Provider已初始化
      if (!_alistProvider.hasActiveHost) {
        await _alistProvider.initialize();
      }

      // 如果提供了hostId，确保它是活动的
      if (widget.hostId != null &&
          widget.hostId != _alistProvider.activeHostId) {
        await _alistProvider.setActiveHost(widget.hostId!);
      }

      // 如果当前没有连接的服务器但有活动服务器，尝试连接
      if (!_alistProvider.isConnected && _alistProvider.hasActiveHost) {
        // 先尝试连接到上次访问的路径
        try {
          await _alistProvider.navigateTo(_lastVisitedPath);
        } catch (e) {
          debugPrint('加载上次路径失败，尝试加载根目录: $e');
          // 如果加载上次路径失败，回退到根目录
          await _alistProvider.navigateTo('/');
        }
      } else if (_alistProvider.isConnected &&
          _alistProvider.currentPath.isEmpty) {
        // 如果已连接但当前路径为空，加载上次访问的路径
        await _alistProvider.navigateTo(_lastVisitedPath);
      }
    } catch (e) {
      debugPrint('AList初始化失败: $e');
    } finally {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AlistProvider>(
      builder: (context, provider, child) {
        final theme = Theme.of(context);

        if (_isInitializing) {
          return Container(
            color: const Color(0xFF2F2F2F),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        if (!provider.isConnected) {
          return Container(
            color: const Color(0xFF2F2F2F),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off, size: 60, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    '未连接到AList服务器',
                    style: theme.textTheme.titleLarge,
                  ),
                  if (provider.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        provider.errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async {
                      await provider.initialize();
                      if (provider.hasActiveHost && !provider.isConnected) {
                        await provider.navigateTo('/');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: const Color(0xFF96F7E4),
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('重新连接'),
                  ),
                ],
              ),
            ),
          );
        }

        // 构建文件浏览器UI
        return Container(
          color: const Color(0xFF2F2F2F),
          child: Column(
            children: [
              // 路径导航栏
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: theme.dividerColor)),
                  color: const Color(0xFF3A3A3A),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () async {
                        if (provider.currentPath != '/') {
                          await provider.navigateUp();
                          // 缓存返回后的路径
                          await _cacheCurrentPath(provider.currentPath);
                        }
                      },
                      tooltip: '返回上级目录',
                      splashRadius: 20,
                      constraints: const BoxConstraints(),
                    ),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2F2F2F),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: Row(
                          children: provider.currentPath
                              .split('/')
                              .asMap()
                              .entries
                              .map((entry) {
                            final index = entry.key;
                            final pathSegment = entry.value;
                            // 拼接当前层级的完整路径
                            final fullPath = index == 0
                                ? '/'
                                : provider.currentPath
                                    .split('/')
                                    .sublist(0, index + 1)
                                    .join('/');
                            return GestureDetector(
                              onTap: () async {
                                await provider.navigateTo(fullPath);
                                await _cacheCurrentPath(fullPath);
                              },
                              child: Row(
                                children: [
                                  if (index != 0)
                                    Text('/',
                                        style: TextStyle(
                                            color: theme
                                                .textTheme.bodyMedium?.color)),
                                  Text(
                                    pathSegment,
                                    style: TextStyle(
                                      color: theme.textTheme.bodyMedium?.color,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () => provider.refreshCurrentDirectory(),
                      tooltip: '刷新',
                      splashRadius: 20,
                    ),
                  ],
                ),
              ),
              // 错误提示
              if (provider.errorMessage != null)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withValues(alpha: 0.3),
                    border:
                        Border(bottom: BorderSide(color: Colors.red.shade700)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          provider.errorMessage!,
                          style: const TextStyle(color: Colors.red),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.red, size: 16),
                        onPressed: () => provider.clearError(),
                        splashRadius: 16,
                      ),
                    ],
                  ),
                ),
              // 加载指示器
              if (provider.isLoading)
                const LinearProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF96F7E4)),
                  backgroundColor: Colors.transparent,
                  minHeight: 2,
                ),
              // 文件列表 - 修改为ListView
              Expanded(
                child: provider.currentFiles.isEmpty && !provider.isLoading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3A3A3A),
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Icon(Icons.folder_off,
                                  size: 60, color: theme.hintColor),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '当前目录为空',
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: theme.hintColor,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: provider.currentFiles.length,
                        itemBuilder: (context, index) {
                          final file = provider.currentFiles[index];
                          return Card(
                            elevation: 3,
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            color: const Color(0xFF3A3A3A),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              onTap: () async {
                                if (file.isDir) {
                                  final newPath =
                                      '${provider.currentPath == '/' ? '' : provider.currentPath}/${file.name}';
                                  await provider.navigateTo(newPath);
                                  // 缓存新路径
                                  await _cacheCurrentPath(newPath);
                                } else if (file.isVideo) {
                                  try {
                                    final playableItem =
                                        provider.buildPlayableItem(file);
                                    widget.onPlayEpisode(playableItem);
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('播放失败: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: file.isDir
                                      ? const Color(0xFF96F7E4)
                                          .withValues(alpha: 0.1)
                                      : file.isVideo
                                          ? Colors.red.shade900
                                              .withValues(alpha: 0.1)
                                          : Colors.grey.shade800,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  file.isDir
                                      ? Icons.folder
                                      : file.isVideo
                                          ? Icons.video_file
                                          : Icons.insert_drive_file,
                                  size: 24,
                                  color: file.isDir
                                      ? const Color(0xFF96F7E4)
                                      : file.isVideo
                                          ? Colors.red
                                          : Colors.grey,
                                ),
                              ),
                              title: Text(
                                file.name,
                                style: theme.textTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    file.isDir
                                        ? '文件夹'
                                        : _formatFileSize(file.size),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.hintColor,
                                    ),
                                  ),
                                  Text(
                                    _formatDateTime(file.modified),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.hintColor,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  String _formatDateTime(DateTime dateTime) {
    // 显示日期 时分秒
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }
}
