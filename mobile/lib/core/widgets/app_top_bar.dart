import 'package:flutter/material.dart';

import '../../app/theme/app_icons.dart';
import '../../app/theme/app_sizes.dart';

class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    this.title,
    this.onBack,
    this.onRefresh,
    this.textScale = 1,
    super.key,
  });
  final String? title;
  final VoidCallback? onBack;
  final VoidCallback? onRefresh;
  final double textScale;

  @override
  Size get preferredSize =>
      Size.fromHeight(AppSizes.topBar * textScale.clamp(1, 2));

  @override
  Widget build(BuildContext context) => AppBar(
    toolbarHeight: preferredSize.height,
    automaticallyImplyLeading: false,
    leading: onBack == null
        ? null
        : IconButton(
            tooltip: 'Volver',
            onPressed: onBack,
            icon: const Icon(AppIcons.back),
          ),
    title: title == null ? null : Text(title!, maxLines: 2),
    actions: [
      if (onRefresh != null)
        IconButton(
          tooltip: 'Actualizar datos',
          onPressed: onRefresh,
          icon: const Icon(AppIcons.refresh),
        ),
    ],
  );
}
