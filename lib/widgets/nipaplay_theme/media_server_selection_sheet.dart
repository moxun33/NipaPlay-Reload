import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';

class MediaServerSelectionSheet extends StatelessWidget {
  const MediaServerSelectionSheet({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF2F2F2F), // 设置背景主色调
      isScrollControlled: true,
      builder: (context) => const MediaServerSelectionSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.5,
      decoration: const BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: GlassmorphicContainer(
        width: double.infinity,
        height: double.infinity,
        borderRadius: 20,
        blur: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect
            ? 20
            : 0,
        alignment: Alignment.center,
        border: 1,
        linearGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.3),
            Colors.white.withOpacity(0.25),
          ],
        ),
        borderGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.5),
            Colors.white.withOpacity(0.5),
          ],
        ),
        child: Column(
          children: [
            // 拖拽条
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // 标题
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                '选择媒体服务器',
                locale: Locale("zh-Hans", "zh"),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // 服务器选项列表
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // NipaPlay 选项
                    _buildServerOptionWithImage(
                      imageAsset: 'assets/nipaplay.png',
                      title: 'NipaPlay',
                      subtitle: '局域网媒体共享',
                      color: const Color(0xFFB39DDB), // 淡紫色
                      onTap: () => Navigator.of(context).pop('nipaplay'),
                    ),

                    const SizedBox(height: 12),

                    // Jellyfin 选项
                    _buildServerOptionWithSvg(
                      svgAsset: 'assets/jellyfin.svg',
                      title: 'Jellyfin',
                      subtitle: '开源媒体服务器',
                      color: Colors.lightBlueAccent,
                      onTap: () => Navigator.of(context).pop('jellyfin'),
                    ),

                    const SizedBox(height: 12),

                    // Emby 选项
                    _buildServerOptionWithSvg(
                      svgAsset: 'assets/emby.svg',
                      title: 'Emby',
                      subtitle: '功能丰富的媒体服务器',
                      color: const Color(0xFF52B54B),
                      onTap: () => Navigator.of(context).pop('emby'),
                    ),

                    const SizedBox(height: 12),

                    // AList 选项 - 已优化样式
                    _buildServerOptionWithSvg(
                      svgAsset: 'assets/alist.svg',
                      title: 'AList',
                      subtitle: '文件列表管理工具',
                      color: const Color(0xFF96F7E4), // 保持主色调一致
                      onTap: () => Navigator.of(context).pop('alist'),
                    ),

                    // 添加底部边距，确保最后一项可以完全显示
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerOptionWithSvg({
    required String svgAsset,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              // Logo图标
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: color.withOpacity(0.5),
                    width: 1,
                  ),
                  // 为AList图标添加发光效果
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 0),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SvgPicture.asset(
                    svgAsset,
                    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                    width: 32,
                    height: 32,
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // 文本信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      locale: Locale("zh-Hans", "zh"),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              // 箭头图标
              Icon(
                Ionicons.chevron_forward,
                size: 16,
                color: Colors.white.withOpacity(0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServerOptionWithImage({
    required String imageAsset,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              // Logo图标
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      color,
                      BlendMode.srcIn,
                    ),
                    child: Image.asset(
                      imageAsset,
                      width: 32,
                      height: 32,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // 文本信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      locale: const Locale("zh-Hans", "zh"),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              // 箭头图标
              Icon(
                Ionicons.chevron_forward,
                size: 16,
                color: Colors.white.withOpacity(0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
