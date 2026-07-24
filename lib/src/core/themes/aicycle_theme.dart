import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Applies the SDK typography to the widget subtree.
class AICycleTheme extends StatelessWidget {
  const AICycleTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.apply(Theme.of(context)),
      child: child,
    );
  }
}
