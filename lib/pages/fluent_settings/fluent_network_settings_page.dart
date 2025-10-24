import 'package:fluent_ui/fluent_ui.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_info_bar.dart';

class FluentNetworkSettingsPage extends StatefulWidget {
  const FluentNetworkSettingsPage({super.key});

  @override
  State<FluentNetworkSettingsPage> createState() =>
      _FluentNetworkSettingsPageState();
}

class _FluentNetworkSettingsPageState extends State<FluentNetworkSettingsPage> {
  String _currentServer = '';
  bool _isLoading = true;
  List<Map<String, String>> _servers = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final server = await NetworkSettings.getDandanplayServer();
    final servers = await NetworkSettings.getAllAvailableServers();

    if (!mounted) return;
    setState(() {
      _currentServer = server;
      _servers = servers;
      _isLoading = false;
    });
  }

  Future<void> _refreshServers() async {
    final servers = await NetworkSettings.getAllAvailableServers();
    if (!mounted) return;
    setState(() {
      _servers = servers;
    });
  }

  Future<void> _changeServer(String serverUrl) async {
    await NetworkSettings.setDandanplayServer(serverUrl);
    if (!mounted) return;
    setState(() {
      _currentServer = serverUrl;
    });

    final displayName = _getServerDisplayName(serverUrl);
    FluentInfoBar.show(
      context,
      '弹弹play 服务器已切换到 $displayName',
      severity: InfoBarSeverity.success,
    );
  }

  String _getServerDisplayName(String serverUrl) {
    final server = _servers.firstWhere((s) => s['url'] == serverUrl,
        orElse: () => {'name': serverUrl});
    return server['name']!;
  }

  void _showAddServerDialog() {
    _showEditServerDialog();
  }

  void _showEditServerDialog({Map<String, String>? server}) {
    final isEdit = server != null;
    final nameController =
        TextEditingController(text: isEdit ? server['name'] : '');
    final urlController =
        TextEditingController(text: isEdit ? server['url'] : '');
    final descController =
        TextEditingController(text: isEdit ? server['description'] : '');

    showDialog(
      context: context,
      builder: (context) {
        return ContentDialog(
          title: Text(isEdit ? '编辑服务器' : '添加服务器'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                InfoLabel(label: '服务器名称'),
                TextBox(
                  controller: nameController,
                  placeholder: '输入服务器名称',
                ),
                const SizedBox(height: 16),
                InfoLabel(label: '服务器URL'),
                TextBox(
                  controller: urlController,
                  placeholder: 'http://example.com',
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 16),
                InfoLabel(label: '服务器描述（可选）'),
                TextBox(
                  controller: descController,
                  placeholder: '输入服务器描述',
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            Button(
                child: const Text('取消'),
                onPressed: () => Navigator.pop(context)),
            Button(
              onPressed: () async {
                final name = nameController.text.trim();
                final url = urlController.text.trim();
                final description = descController.text.trim();

                if (name.isEmpty || url.isEmpty) {
                  FluentInfoBar.show(
                    context,
                    '请填写服务器名称和URL',
                    severity: InfoBarSeverity.error,
                  );
                  return;
                }

                if (!NetworkSettings.isValidUrl(url)) {
                  FluentInfoBar.show(
                    context,
                    '请输入有效的URL（http或https开头）',
                    severity: InfoBarSeverity.error,
                  );
                  return;
                }

                Navigator.pop(context);

                if (isEdit) {
                  await NetworkSettings.updateCustomServer(
                    server['url']!,
                    name,
                    url,
                    description,
                  );
                  FluentInfoBar.show(
                    context,
                    '服务器已更新',
                    severity: InfoBarSeverity.success,
                  );
                } else {
                  await NetworkSettings.addCustomServer(name, url, description);
                  FluentInfoBar.show(
                    context,
                    '服务器已添加',
                    severity: InfoBarSeverity.success,
                  );
                }

                await _refreshServers();
              },
              child: Text(isEdit ? '保存' : '添加'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteServer(String url) async {
    final isCurrentServer = _currentServer == url;

    if (isCurrentServer) {
      FluentInfoBar.show(
        context,
        '不能删除当前正在使用的服务器',
        severity: InfoBarSeverity.error,
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return ContentDialog(
          title: const Text('确认删除'),
          content: const Text('确定要删除此服务器吗？此操作无法撤销。'),
          actions: [
            Button(
              child: const Text('取消'),
              onPressed: () => Navigator.pop(context),
            ),
            Button(
              onPressed: () async {
                Navigator.pop(context);
                await NetworkSettings.deleteCustomServer(url);
                FluentInfoBar.show(
                  context,
                  '服务器已删除',
                  severity: InfoBarSeverity.success,
                );
                await _refreshServers();
              },
              style: ButtonStyle(padding: ButtonState.all(EdgeInsets.zero)),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const ScaffoldPage(
        content: Center(
          child: ProgressRing(),
        ),
      );
    }

    return ScaffoldPage(
      header: const PageHeader(
        title: Text('网络设置'),
      ),
      content: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 服务器选择
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '弹弹play 服务器',
                      style: FluentTheme.of(context).typography.subtitle,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '选择弹弹play 弹幕数据来源，当主服务器不可用时可切换至备用服务器。',
                      style: FluentTheme.of(context).typography.caption,
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ComboBox<String>(
                        value: _currentServer,
                        items: _servers.map((server) {
                          return ComboBoxItem<String>(
                            value: server['url']!,
                            child: Text(server['name']!),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null && value != _currentServer) {
                            _changeServer(value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 当前服务器信息
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          FluentIcons.info,
                          color: FluentTheme.of(context).accentColor,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '当前服务器信息',
                          style: FluentTheme.of(context).typography.subtitle,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    InfoLabel(
                      label: '服务器',
                      child: Text(_getServerDisplayName(_currentServer)),
                    ),
                    const SizedBox(height: 8),
                    InfoLabel(
                      label: 'URL',
                      child: Text(_currentServer),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 服务器管理
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              FluentIcons.server,
                              color: FluentTheme.of(context).accentColor,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '服务器管理',
                              style:
                                  FluentTheme.of(context).typography.subtitle,
                            ),
                          ],
                        ),
                        FilledButton(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Ionicons.add_outline, size: 16),
                              const SizedBox(width: 6),
                              const Text('添加服务器'),
                            ],
                          ),
                          onPressed: _showAddServerDialog,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 服务器列表
                    if (_servers.isNotEmpty)
                      Column(
                        children: _servers.map((server) {
                          final isCustom = server['isCustom'] == 'true';
                          final isSelected = _currentServer == server['url'];

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Card(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Text(server['name']!,
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.normal)),
                                          if (isSelected)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  left: 8),
                                              child: Icon(
                                                FluentIcons.check_mark,
                                                color: Colors.green,
                                                size: 16,
                                              ),
                                            ),
                                        ],
                                      ),
                                      if (isCustom)
                                        Row(
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                  Ionicons.create_outline,
                                                  size: 18),
                                              onPressed: () =>
                                                  _showEditServerDialog(
                                                      server: server),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                  Ionicons.trash_outline,
                                                  size: 18),
                                              onPressed: () =>
                                                  _deleteServer(server['url']!),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    server['url']!,
                                    style: const TextStyle(
                                        fontSize: 12, fontFamily: 'monospace'),
                                  ),
                                  if (server['description'] != null &&
                                      server['description']!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        server['description']!,
                                        style: const TextStyle(
                                            fontSize: 12, color: Colors.grey),
                                      ),
                                    ),
                                  if (!isCustom)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        '系统默认服务器，不可编辑或删除',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[700]),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
