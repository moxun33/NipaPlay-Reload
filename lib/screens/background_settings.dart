import 'package:flutter/material.dart';
import 'package:nipaplay/services/settings_service.dart';
import 'package:nipaplay/utils/theme_utils.dart';
import 'package:nipaplay/widgets/rounded_button.dart';
import 'package:nipaplay/widgets/rounded_container.dart';  // 导入 RoundedContainer

class BackgroundSettings extends StatelessWidget {
  final SettingsService settingsService;

  const BackgroundSettings({super.key, required this.settingsService});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "背景图片设置",
          style: getTitleTextStyle(context),
        ),
        RoundedContainer(  // 使用 RoundedContainer 包裹按钮行
          child: Row(
            children: [
              RoundedButton(
                text: "看板娘",
                onPressed: () {
                  settingsService.setBackgroundImage('kanban.jpg');
                },
              ),
              const SizedBox(width: 10),
              RoundedButton(
                text: "关闭",
                onPressed: () {
                  settingsService.setBackgroundImage('default.jpg');
                },
              ),
              const SizedBox(width: 10),
              RoundedButton(
                text: "自定义",
                onPressed: () {
                  settingsService.setBackgroundImage('custom.jpg');
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}