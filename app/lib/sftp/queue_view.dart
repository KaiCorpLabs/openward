// The transfer queue: a strip under the browser, the list when opened, and
// a mark in the tab bar while anything moves.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../src/rust/api/sftp.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'dialogs.dart';
import 'format.dart';
import 'transfers.dart';

/// "1 en curso · 2 en cola · 1 con error".
String queueSummary(AppLocalizations l, List<TransferView> jobs) {
  int count(TransferState s) => jobs.where((j) => j.state == s).length;
  final parts = [
    if (count(TransferState.running) > 0)
      l.queueRunning(count(TransferState.running)),
    if (count(TransferState.queued) > 0)
      l.queueQueued(count(TransferState.queued)),
    if (count(TransferState.paused) > 0)
      l.queuePaused(count(TransferState.paused)),
    if (count(TransferState.failed) > 0)
      l.queueFailed(count(TransferState.failed)),
  ];
  if (parts.isEmpty) return l.queueAllDone;
  return parts.join(' · ');
}

/// What a job is doing, in a line.
String jobStatus(AppLocalizations l, TransferView j) {
  String size(int n) => formatSize(l, n);
  switch (j.state) {
    case TransferState.queued:
      return j.total > 0 ? l.jobQueued(size(j.total)) : l.jobQueuedNoSize;
    case TransferState.running:
      if (j.total == 0) return l.jobCounting;
      final left = j.rate > 0
          ? formatDuration(
              Duration(seconds: ((j.total - j.done) / j.rate).ceil()),
            )
          : null;
      final rate = j.rate > 0 ? '${size(j.rate.round())}/s' : null;
      return [
        l.jobProgress(size(j.done), size(j.total)),
        ?rate,
        if (left != null) l.timeLeft(left),
      ].join(' · ');
    case TransferState.paused:
      return l.jobPaused(size(j.done), size(j.total));
    case TransferState.failed:
      final e = j.error;
      if (e != null && e.kind == FileErrorKind.lost) {
        return l.jobLost(size(j.done), size(j.total));
      }
      return e == null ? l.jobFailed : fileErrorText(l, e);
    case TransferState.done:
      final skipped = j.skipped > 0 ? ' · ${l.jobSkipped(j.skipped)}' : '';
      return '${l.jobDone(size(j.total))}$skipped';
    case TransferState.cancelled:
      return l.jobCancelled;
  }
}

/// Where a job goes: `~/dist → web-1:/var/www/app`.
String jobRoute(AppLocalizations l, TransferView j) {
  final up = j.direction == TransferDirection.upload;
  final from = up ? _parent(j.source) : '${j.host}:${_parent(j.source)}';
  final to = up ? '${j.host}:${j.destDir}' : j.destDir;
  final what = j.isDir ? '${l.jobFolder(j.files)} ' : '';
  return '$what$from → $to';
}

String _parent(String path) {
  final i = path.replaceAll('\\', '/').lastIndexOf('/');
  return i <= 0 ? path : path.substring(0, i);
}

class _SmallButton extends StatelessWidget {
  const _SmallButton(
    this.text, {
    required this.onPressed,
    this.accent = false,
    super.key,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: const TextStyle(fontSize: 12),
        foregroundColor: accent ? c.accentText : null,
        backgroundColor: accent ? c.accentSoft : null,
      ),
      child: Text(text),
    );
  }
}

/// Under the browser while there are transfers: closed, a line with what
/// moves; open, every job.
class QueueView extends ConsumerWidget {
  const QueueView({super.key, required this.open, required this.onToggle});

  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(transferQueueProvider);
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        if (queue.jobs.isEmpty) return const SizedBox.shrink();
        return open
            ? QueuePanel(queue: queue, onHide: onToggle)
            : _QueueStrip(queue: queue, onOpen: onToggle);
      },
    );
  }
}

class _QueueStrip extends StatelessWidget {
  const _QueueStrip({required this.queue, required this.onOpen});

  final TransferQueue queue;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final running = queue.jobs
        .where((j) => j.state == TransferState.running)
        .firstOrNull;
    final progress = queue.progress;
    return Container(
      height: 44,
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
      ),
      child: Row(
        children: [
          Icon(Icons.swap_vert, size: 16, color: c.accentText),
          const SizedBox(width: 10),
          Text(
            l.transfers,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              queueSummary(l, queue.jobs),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.textMuted),
            ),
          ),
          if (progress != null) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: c.sunken,
                  color: c.accent,
                ),
              ),
            ),
          ],
          if (running != null) ...[
            const SizedBox(width: 12),
            Flexible(
              flex: 2,
              child: Text(
                '${running.name} · ${jobStatus(l, running)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoStyle(context, color: c.textMuted),
              ),
            ),
          ],
          const Spacer(),
          _SmallButton(
            l.showQueue,
            key: const ValueKey('queue.open'),
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }
}

/// Every job, with what can be done to it.
class QueuePanel extends StatelessWidget {
  const QueuePanel({super.key, required this.queue, this.onHide});

  final TransferQueue queue;

  /// Folds it back into a strip; without it, it is not offered.
  final VoidCallback? onHide;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    return Container(
      height: 280,
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                Icon(Icons.swap_vert, size: 16, color: c.accentText),
                const SizedBox(width: 10),
                Text(
                  l.transfers,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    queueSummary(l, queue.jobs),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.textMuted),
                  ),
                ),
                if (queue.moving > 0) ...[
                  _SmallButton(l.pauseAll, onPressed: queue.pauseAll),
                  const SizedBox(width: 6),
                ],
                if (queue.jobs.any((j) => j.finished)) ...[
                  _SmallButton(
                    l.clearFinished,
                    key: const ValueKey('queue.clear'),
                    onPressed: queue.clearFinished,
                  ),
                  const SizedBox(width: 6),
                ],
                if (onHide != null)
                  _SmallButton(l.hideQueue, onPressed: onHide),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: queue.jobs.length,
              itemBuilder: (context, i) =>
                  _JobRow(job: queue.jobs[i], queue: queue),
            ),
          ),
        ],
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.job, required this.queue});

  final TransferView job;
  final TransferQueue queue;

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    final l = context.l10n;
    final j = job;
    final up = j.direction == TransferDirection.upload;
    final tone = switch (j.state) {
      TransferState.failed => c.danger,
      TransferState.done || TransferState.cancelled => c.textSubtle,
      TransferState.running => c.accentText,
      _ => c.textMuted,
    };
    final progress = j.state == TransferState.running && j.total > 0
        ? j.done / j.total
        : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: up ? l.upload : l.download,
            child: Icon(
              up ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16,
              color: tone,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  j.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  jobRoute(l, j),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(context, size: 11, color: c.textSubtle),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  jobStatus(l, j),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: j.state == TransferState.failed ? c.danger : c.text,
                  ),
                ),
                if (progress != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: c.sunken,
                        color: c.accent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Wrap(
            spacing: 6,
            children: [
              if (j.moving)
                _SmallButton(l.pause, onPressed: () => queue.pause(j.id)),
              if (j.state == TransferState.paused ||
                  j.state == TransferState.failed)
                _SmallButton(
                  l.resume,
                  accent: true,
                  onPressed: () => queue.resume(j.id),
                ),
              if (!j.finished)
                _SmallButton(l.cancel, onPressed: () => queue.cancel(j.id))
              else
                _SmallButton(l.remove, onPressed: () => queue.remove(j.id)),
            ],
          ),
        ],
      ),
    );
  }
}

/// In the tab bar while there are transfers not finished: how far they
/// have got. Opens the queue.
class TransferIndicator extends ConsumerWidget {
  const TransferIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(transferQueueProvider);
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        if (queue.active == 0) return const SizedBox.shrink();
        final ow = context.ow;
        final c = ow.colors;
        final l = context.l10n;
        final progress = queue.progress;
        final failed = queue.jobs.any((j) => j.state == TransferState.failed);
        final text = progress != null
            ? '${(progress * 100).floor()} %'
            : '${queue.active}';
        return Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 5),
          child: Tooltip(
            message: '${l.transfers}: ${queueSummary(l, queue.jobs)}',
            child: OutlinedButton.icon(
              key: const ValueKey('queue.indicator'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => Dialog(
                  child: SizedBox(width: 760, child: QueuePanel(queue: queue)),
                ),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                foregroundColor: failed ? c.danger : c.accentText,
                backgroundColor: failed ? c.dangerSoft : c.accentSoft,
                side: BorderSide(color: failed ? c.dangerLine : c.accent),
                textStyle: const TextStyle(fontSize: 12),
              ),
              icon: const Icon(Icons.swap_vert, size: 15),
              label: Text(text),
            ),
          ),
        );
      },
    );
  }
}
