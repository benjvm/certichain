import 'package:flutter/material.dart';

abstract final class AppShadows {
  static const level1 = [
    BoxShadow(color: Color(0x14101828), offset: Offset(0, 1), blurRadius: 3),
  ];
  static const level2 = [
    BoxShadow(color: Color(0x1A101828), offset: Offset(0, 4), blurRadius: 12),
  ];
  static const level3 = [
    BoxShadow(color: Color(0x29101828), offset: Offset(0, 12), blurRadius: 32),
  ];
}
