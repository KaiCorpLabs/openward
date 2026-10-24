import 'dart:async';

import 'package:flutter/widgets.dart';

/// A focus scope that takes the focus back when it falls out of
/// everything. A focused field, pane or page that goes away (a tab
/// closed, a setting back to inheriting) leaves the focus on a scope above
/// it, the root's, where no shortcut hears the keys: Esc, ⌘W, ⌘K. While
/// its route is the one in front (a dialog or a menu is a route of its
/// own), the focus comes back here.
class KeepFocus extends StatefulWidget {
  const KeepFocus({
    super.key,
    required this.debugLabel,
    this.autofocus = false,
    required this.child,
  });

  final String debugLabel;
  final bool autofocus;
  final Widget child;

  @override
  State<KeepFocus> createState() => _KeepFocusState();
}

class _KeepFocusState extends State<KeepFocus> {
  late final _scope = FocusScopeNode(debugLabel: widget.debugLabel);

  /// Its route, to tell whether it is the one in front.
  ModalRoute<Object?>? _route;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_keep);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_keep);
    _scope.dispose();
    super.dispose();
  }

  void _keep() {
    // Lost, not taken: on a scope, not on anything in it.
    final lost = FocusManager.instance.primaryFocus is FocusScopeNode;
    if (!mounted || _scope.hasFocus || !lost || _route?.isCurrent != true) {
      return;
    }
    scheduleMicrotask(() {
      if (mounted && !_scope.hasFocus && _route?.isCurrent == true) {
        _scope.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) => FocusScope(
    node: _scope,
    autofocus: widget.autofocus,
    child: widget.child,
  );
}
