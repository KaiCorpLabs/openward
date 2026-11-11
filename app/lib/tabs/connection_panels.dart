// What a tab shows about its connection besides the terminal: progress hop
// by hop, a lost connection coming back, a failure with what to do about
// it, the details of a live connection, and a host key that changed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/session.dart';
import '../src/rust/api/vault.dart' show ProtocolKind;
import '../terminal/controller.dart';
import '../ui/confirm.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'connection_motion.dart';
import 'messages.dart';
import 'tabs.dart';

/// The labels of a connection's details, and what lines up under them.
const double _labelColumn = 140;

/// A card over the terminal, in the theme's raised color.
class OverlayPanel extends StatelessWidget {
  const OverlayPanel({super.key, required this.child, this.width = 440});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    return Container(
      constraints: BoxConstraints(maxWidth: width),
      padding: const EdgeInsets.fromLTRB(
        OwSpace.s11,
        OwSpace.s10,
        OwSpace.s11,
        OwSpace.s8,
      ),
      decoration: BoxDecoration(
        color: ow.colors.raised,
        borderRadius: BorderRadius.circular(ow.shape.radiusLarge),
        border: Border.all(color: ow.colors.control),
        boxShadow: OwElevation.overlay,
      ),
      child: child,
    );
  }
}

/// The route, hop by hop: done, in progress (and what it is doing), or
/// still ahead. Each state has its own mark, not just a color.
class _RouteSteps extends StatelessWidget {
  const _RouteSteps({required this.controller});

  final ConnectionController controller;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final s = controller;
    final stage = s.stage;
    final current = stage?.hop ?? 0;
    final steps = s.route.isEmpty ? [s.label] : s.route;
    Widget row(
      Widget icon,
      String text, {
      String? detail,
      bool dim = false,
      bool now = false,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: OwSpace.s2),
      child: Row(
        children: [
          SizedBox(width: 18, height: 18, child: Center(child: icon)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: dim ? c.textSubtle : c.text,
                fontWeight: now ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (detail != null) ...[
            const SizedBox(width: 8),
            Text(
              detail,
              style: TextStyle(fontSize: OwText.small, color: c.textMuted),
            ),
          ],
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // This computer is already the route's first node: here, only the
        // hops and how each is going.
        for (var i = 0; i < steps.length; i++)
          if (i < current)
            row(Icon(Icons.check, size: 16, color: c.accent), steps[i])
          else if (i == current && stage != null)
            row(
              SizedBox.square(
                dimension: 13,
                child: CircularProgressIndicator(strokeWidth: 2, color: c.text),
              ),
              steps[i],
              now: true,
              detail: switch (stage.stage) {
                StageKind.connecting => l.stepConnecting,
                StageKind.authenticating => l.stepAuthenticating,
                StageKind.touchKey => l.stepTouchKey,
                StageKind.openingShell => l.stepOpeningShell,
                StageKind.openingSftp => l.stepOpeningSftp,
              },
            )
          else
            row(
              Icon(Icons.radio_button_unchecked, size: 14, color: c.textSubtle),
              steps[i],
              dim: true,
            ),
      ],
    );
  }
}

/// Over an empty terminal while the first connection comes up.
class ConnectingCard extends StatelessWidget {
  const ConnectingCard({super.key, required this.controller});

  final ConnectionController controller;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final via = viaText(l, controller);
    return OverlayPanel(
      width: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.connectingTo(controller.label),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (via != null)
            Text(via, style: TextStyle(color: context.ow.colors.textMuted)),
          const SizedBox(height: 16),
          connectingRoute(l, controller),
          const SizedBox(height: 4),
          _RouteSteps(controller: controller),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: controller.cancel,
              child: Text(l.cancel),
            ),
          ),
        ],
      ),
    );
  }
}

/// Across the top of a terminal whose connection was lost: why, which
/// try is next and when, and that typing goes nowhere meanwhile.
class ReconnectBanner extends ConsumerStatefulWidget {
  const ReconnectBanner({super.key, required this.controller});

  final ConnectionController controller;

  @override
  ConsumerState<ReconnectBanner> createState() => _ReconnectBannerState();
}

class _ReconnectBannerState extends ConsumerState<ReconnectBanner> {
  // Started in initState: a `late` initializer runs at the first read,
  // which would be dispose().
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final s = widget.controller;
    final r = s.reconnecting;
    final at = s.reconnectAt;
    final String text;
    if (at != null && r != null) {
      final left = at.difference(DateTime.now()).inMilliseconds;
      final secs = (left / 1000).ceil().clamp(0, 60);
      final f = r.reason;
      final reason = f.kind != FailureKind.network
          ? failureText(l, f)
          : f.net == NetKind.lost
          ? ''
          : networkReason(l, f);
      final why = reason.isEmpty
          ? ''
          : ' (${reason.endsWith('.') ? reason.substring(0, reason.length - 1) : reason})';
      final max = ref.read(openWardProvider).reconnectAttempts();
      text =
          '${l.connectionLost(s.label, why)} '
          '${l.retryIn(r.attempt, max, secs)} ${l.inputNotSent}';
    } else {
      final stage = s.stage;
      text = stage == null
          ? l.reconnectingEllipsis
          : l.reconnectingStage(stageText(l, stage));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OwSpace.s6,
        OwSpace.s5,
        OwSpace.s6,
        OwSpace.s1,
      ),
      child: Semantics(
        liveRegion: true,
        child: Callout(
          tone: Tone.warn,
          padding: const EdgeInsets.fromLTRB(
            OwSpace.s6,
            OwSpace.s3,
            OwSpace.s3,
            OwSpace.s3,
          ),
          child: Row(
            children: [
              Icon(Icons.sync, size: 16, color: c.warn),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.text),
                ),
              ),
              if (at != null)
                OutlinedButton(
                  onPressed: s.start,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    side: BorderSide(color: c.warnLine),
                  ),
                  child: Text(l.retryNow),
                ),
              TextButton(
                onPressed: s.cancel,
                style: TextButton.styleFrom(foregroundColor: c.textMuted),
                child: Text(l.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Over a terminal that never connected: what went wrong and what can be
/// done. A changed host key gets its own card: stopping is what it offers
/// first, trusting the new key takes a second look.
class FailureCard extends ConsumerWidget {
  const FailureCard({super.key, required this.controller});

  final ConnectionController controller;

  /// Its pane, or its tab when it is the only one.
  void _closeTab(WidgetRef ref) =>
      ref.read(tabsProvider.notifier).closeConnection(controller);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final s = controller;
    final failure = s.closed?.failure;
    final theme = Theme.of(context);
    if (failure != null && failure.kind == FailureKind.hostKeyChanged) {
      final saved = failure.previous.isEmpty
          ? null
          : failure.previous.first.fingerprint;
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Callout(
          tone: Tone.danger,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: c.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.keyChangedTitle(failure.label),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: c.danger,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(l.keyChangedBody, style: const TextStyle(height: 1.45)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(OwSpace.s5),
                decoration: BoxDecoration(
                  color: c.sunken,
                  borderRadius: BorderRadius.circular(ow.shape.radius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (saved != null)
                      _KeyLine(label: l.keySaved, fingerprint: saved),
                    _KeyLine(
                      label: l.keyReceived,
                      fingerprint: failure.fingerprint,
                      highlight: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => showHostKeyChanged(context, ref, s),
                    style: TextButton.styleFrom(foregroundColor: c.danger),
                    child: Text(l.trustNewKeyEllipsis),
                  ),
                  FilledButton(
                    onPressed: () => _closeTab(ref),
                    child: Text(l.closeTheTab),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return OverlayPanel(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: c.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l.cannotConnect(s.label),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(statusText(l, s), style: const TextStyle(height: 1.45)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (s.closed?.failure ?? s.errorCause case final e?) ...[
                DetailsButton(e),
                const Spacer(),
              ],
              OutlinedButton(
                onPressed: () => _closeTab(ref),
                child: Text(l.closeTheTab),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: s.start, child: Text(l.tryAgain)),
            ],
          ),
        ],
      ),
    );
  }
}

class _KeyLine extends StatelessWidget {
  const _KeyLine({
    required this.label,
    required this.fingerprint,
    this.highlight = false,
  });

  final String label;
  final String fingerprint;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.ow.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OwSpace.s1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(fontSize: OwText.small, color: c.textMuted),
            ),
          ),
          Expanded(
            child: SelectableText(
              fingerprint,
              style: monoStyle(context, color: highlight ? c.danger : c.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// The new and the old fingerprints of a host whose key changed; trusting
/// the new one takes an explicit confirmation.
Future<void> showHostKeyChanged(
  BuildContext context,
  WidgetRef ref,
  ConnectionController c,
) async {
  final f = c.closed?.failure;
  if (f == null || f.kind != FailureKind.hostKeyChanged) return;
  final l = context.l10n;
  final trusted = await showDialog<bool>(
    context: context,
    builder: (context) => _HostKeyChangedDialog(failure: f),
  );
  if (trusted != true) return;
  try {
    await ref
        .read(openWardProvider)
        .trustHostKey(
          host: f.host,
          port: f.port,
          key: f.key,
          previousKeys: f.previous.map((p) => p.key).toList(),
        );
  } catch (e) {
    if (context.mounted) {
      showErrorNotice(
        ScaffoldMessenger.of(context),
        l.saveKeyFailed(errorReason(l, e)),
        e,
      );
    }
    return;
  }
  c.start();
}

class _HostKeyChangedDialog extends StatefulWidget {
  const _HostKeyChangedDialog({required this.failure});

  final FailureView failure;

  @override
  State<_HostKeyChangedDialog> createState() => _HostKeyChangedDialogState();
}

class _HostKeyChangedDialogState extends State<_HostKeyChangedDialog> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final l = context.l10n;
    final theme = Theme.of(context);
    final f = widget.failure;
    final where = f.port == 22 ? f.host : '${f.host}:${f.port}';
    final inOpenSsh = f.previous.any((p) => p.source == KeySourceKind.openSsh);
    return AlertDialog(
      icon: Icon(Icons.gpp_maybe_outlined, color: c.danger, size: 30),
      title: Text(l.keyChangedTitle(f.label)),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.keyChangedDialogBody(where),
              style: const TextStyle(height: 1.45),
            ),
            const SizedBox(height: 16),
            Text(l.keyBefore, style: theme.textTheme.titleSmall),
            for (final p in f.previous)
              Padding(
                padding: const EdgeInsets.only(top: OwSpace.s2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      p.fingerprint,
                      style: monoStyle(context, color: c.text),
                    ),
                    Text(
                      p.source == KeySourceKind.openWard
                          ? l.keyInOpenWard
                          : l.keyInKnownHosts,
                      style: TextStyle(
                        fontSize: OwText.small,
                        color: c.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text(l.keyNow(f.algorithm), style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            SelectableText(
              f.fingerprint,
              style: monoStyle(context, color: c.text),
            ),
            if (inOpenSsh) ...[
              const SizedBox(height: 12),
              Text(
                l.openSshStillWarns(
                  'ssh-keygen -R ${f.port == 22 ? f.host : '"[${f.host}]:${f.port}"'}',
                ),
                style: TextStyle(fontSize: OwText.small, color: c.textMuted),
              ),
            ],
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _checked,
              onChanged: (v) => setState(() => _checked = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l.checkedFingerprint),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          style: dangerButtonStyle(c),
          onPressed: _checked ? () => Navigator.pop(context, true) : null,
          child: Text(l.trustNewKey),
        ),
      ],
    );
  }
}

/// The details of a live connection.
Future<void> showConnectionInfo(BuildContext context, ConnectionController c) {
  final k = c.connected;
  if (k == null) return Future.value();
  final l = context.l10n;
  final ssh = k.protocol == ProtocolKind.ssh;
  final where = switch (k.protocol) {
    ProtocolKind.ssh => k.port == 22 ? k.host : '${k.host}:${k.port}',
    ProtocolKind.telnet => k.port == 23 ? k.host : '${k.host}:${k.port}',
    ProtocolKind.serial => k.host,
  };
  final trust = switch (k.trust) {
    TrustKind.known => l.trustKnown,
    TrustKind.new_ => l.trustNew,
    TrustKind.certified => l.trustCertified(k.ca),
  };
  return showDialog<void>(
    context: context,
    builder: (context) {
      final ow = context.ow;
      Widget row(String name, String value, {bool mono = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: OwSpace.s2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _labelColumn,
              child: Text(name, style: TextStyle(color: ow.colors.textMuted)),
            ),
            Expanded(
              child: SelectableText(
                value,
                style: mono ? monoStyle(context, color: ow.colors.text) : null,
              ),
            ),
          ],
        ),
      );
      return AlertDialog(
        title: Text(c.label),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row(l.destination, where),
              if (c.route.length > 1)
                row(l.route, [l.routeStart, ...c.route].join(' → ')),
              // Nothing of SSH's to tell: what it is, and that Telnet
              // encrypts nothing.
              if (!ssh)
                row(
                  l.protocol,
                  k.protocol == ProtocolKind.telnet
                      ? l.telnetUnencrypted
                      : l.protocolSerial,
                ),
              if (ssh) ...[
                row(
                  l.keyExchange,
                  k.postQuantum ? l.postQuantumKex(k.kex) : k.kex,
                  mono: true,
                ),
                if (!k.postQuantum)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: _labelColumn,
                      bottom: OwSpace.s2,
                    ),
                    child: Text(
                      l.noPostQuantumNote,
                      style: TextStyle(
                        fontSize: OwText.small,
                        color: ow.colors.textMuted,
                      ),
                    ),
                  ),
                row(l.cipher, k.cipher, mono: true),
                row(l.hostKey, k.hostKeyAlgorithm, mono: true),
                row(l.fingerprint, k.fingerprint, mono: true),
                row(l.trust, trust),
              ],
              row(l.time, l.milliseconds(k.connectMs.round())),
            ],
          ),
        ),
        actions: [
          if (ssh)
            OutlinedButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: k.fingerprint));
                Navigator.pop(context);
              },
              child: Text(l.copyFingerprint),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.close),
          ),
        ],
      );
    },
  );
}
