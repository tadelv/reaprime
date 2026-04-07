import 'package:flutter/material.dart';

/// Wraps a [ShadButton] (or variant) with explicit [Semantics] to ensure
/// screen readers announce the button role.
///
/// Required because ShadButton's internal `Semantics(container: true)`
/// creates a semantic boundary that prevents TalkBack from reading the
/// button role on child text nodes. This widget provides a single semantic
/// node with the correct label, role, and tap action.
class AccessibleButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Widget child;

  const AccessibleButton({
    super.key,
    required this.label,
    this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(child: child),
    );
  }
}
