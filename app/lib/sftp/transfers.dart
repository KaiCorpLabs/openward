import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../src/rust/api/app.dart';
import '../src/rust/api/sftp.dart';

extension TransferViewX on TransferView {
  /// Running or waiting its turn.
  bool get moving =>
      state == TransferState.running || state == TransferState.queued;

  /// Done or cancelled: nothing more will happen to it.
  bool get finished =>
      state == TransferState.done || state == TransferState.cancelled;
}

/// The app's transfer queue, asked for a few times a second while anything
/// moves. Lives in the core: closing a browser does not stop its copies.
class TransferQueue extends ChangeNotifier {
  TransferQueue(this.app);

  final OpenWard app;
  List<TransferView> jobs = const [];
  Timer? _timer;
  bool _disposed = false;

  /// Asks again now, and keeps asking while anything moves. Call after
  /// queueing or changing a job.
  void poke() {
    _poll();
    if (_timer == null && jobs.any((j) => j.moving)) {
      _timer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _poll(),
      );
    }
  }

  void _poll() {
    if (_disposed) return;
    jobs = app.transfers();
    if (!jobs.any((j) => j.moving)) {
      _timer?.cancel();
      _timer = null;
    }
    notifyListeners();
  }

  /// Not finished: running, waiting, paused or failed.
  int get active => jobs.where((j) => !j.finished).length;

  int get moving => jobs.where((j) => j.moving).length;

  /// How far what moves has got, 0 to 1; null if nothing moves or its size
  /// is not known yet.
  double? get progress {
    var total = 0, done = 0;
    for (final j in jobs.where((j) => j.moving)) {
      total += j.total;
      done += j.done;
    }
    return total == 0 ? null : (done / total).clamp(0, 1);
  }

  void pause(BigInt id) {
    app.pauseTransfer(id: id);
    poke();
  }

  void resume(BigInt id) {
    app.resumeTransfer(id: id);
    poke();
  }

  void cancel(BigInt id) {
    app.cancelTransfer(id: id);
    poke();
  }

  void remove(BigInt id) {
    app.removeTransfer(id: id);
    poke();
  }

  void pauseAll() {
    app.pauseTransfers();
    poke();
  }

  void clearFinished() {
    app.clearFinishedTransfers();
    poke();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

final transferQueueProvider = Provider<TransferQueue>((ref) {
  final queue = TransferQueue(ref.watch(openWardProvider));
  ref.onDispose(queue.dispose);
  return queue;
});
