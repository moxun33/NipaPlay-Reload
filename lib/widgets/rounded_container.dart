import 'package:flutter/material.dart';
import 'package:nipaplay/utils/theme_colors.dart';

class RoundedContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final double borderRadius;
  final double blurRadius;
  final double spreadRadius;

  const RoundedContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(vertical: 5.0, horizontal: 10.0),
    this.backgroundColor = Colors.white,
    this.borderRadius = 10.0,
    this.blurRadius = 6.0,
    this.spreadRadius = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    
    return 
    Padding(padding: padding, child: Container(
      padding: padding,
      decoration: BoxDecoration(
        color: getBorderColor(), // 背景颜色
        borderRadius: BorderRadius.circular(borderRadius), // 圆角半径
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: blurRadius,
            spreadRadius: spreadRadius,
          ),
        ], // 阴影效果
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,  // 设置为水平滚动
        child: child,
      ),
    ));
  }
}