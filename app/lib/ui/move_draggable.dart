import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// How far a press moves before it becomes a drag, in logical pixels: about
/// what the systems wait for. Flutter's own is one pixel for a mouse, less
/// than a click on a trackpad wobbles.
const double dragSlop = 4;

/// A [Draggable] that starts once the pointer moves, never on a press alone.
/// A plain one starts at once when nothing else on its child wants the
/// press (a tap, say), so a click shows its feedback for a moment.
class MoveDraggable<T extends Object> extends Draggable<T> {
  const MoveDraggable({
    super.key,
    required super.data,
    required super.feedback,
    required super.child,
    super.dragAnchorStrategy,
    super.onDragStarted,
    super.onDragEnd,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => _MoveDragRecognizer()..onStart = onStart;
}

class _MoveDragRecognizer extends ImmediateMultiDragGestureRecognizer {
  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _MovePointerState(event.position, event.kind, gestureSettings);
}

/// Waits for the pointer to move, even once the press is its own.
class _MovePointerState extends MultiDragPointerState {
  _MovePointerState(super.initialPosition, super.kind, super.gestureSettings);

  /// Given by the arena before the pointer moved.
  GestureMultiDragStartCallback? _start;

  bool get _moved =>
      pendingDelta!.distance >
      math.max(dragSlop, computeHitSlop(kind, gestureSettings));

  @override
  void checkForResolutionAfterMove() {
    if (!_moved) return;
    if (_start case final start?) {
      _start = null;
      start(initialPosition);
    } else {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    if (_moved) {
      starter(initialPosition);
    } else {
      _start = starter;
    }
  }
}
