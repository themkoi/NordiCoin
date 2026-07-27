import 'package:flutter/material.dart';

// (1.8V = 0%, 3.3V = 100%)
double batteryPercentageFromVoltage(double voltage) {
  final clamped = voltage.clamp(1.8, 3.3);
  return ((clamped - 1.8) / 1.5 * 100).roundToDouble();
}

Color batteryColorFromPercentage(double percentage) {
  if (percentage >= 50) return Colors.green;
  if (percentage >= 20) return Colors.amber;
  return Colors.red;
}
