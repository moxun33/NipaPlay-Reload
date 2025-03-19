// lib/widgets/fluid_background_widget.dart
import 'package:flutter/material.dart';
import 'package:fluid_background/fluid_background.dart';

class FluidBackgroundWidget extends StatelessWidget {
  final Widget child;

  const FluidBackgroundWidget({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return FluidBackground(
      initialColors: InitialColors.random(4),
      initialPositions: InitialOffsets.predefined(),
      velocity: 160,
      bubblesSize: 50,
      sizeChangingRange: const [40, 60],
      allowColorChanging: true,
      bubbleMutationDuration: const Duration(seconds: 4),
      child: child,
    );
  }
}