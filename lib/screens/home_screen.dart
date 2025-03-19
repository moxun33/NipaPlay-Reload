import 'package:flutter/material.dart'; // 这个导入无需改变
import 'package:nipaplay/widgets/navigation_bar.dart' as navigation_bar_widgets; // 改为别名
import 'package:nipaplay/screens/setting_screen.dart';  // 确保这行存在
// 然后在代码中使用别名来调用 NavigationBar
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // 使用别名
          const navigation_bar_widgets.NavigationBar(),
          // 主内容区域
          Expanded(child: SettingScreen()),
        ],
      ),
    );
  }
}