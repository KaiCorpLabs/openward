// What went wrong, in the interface's language. The core says it in
// English for the logs; the app says it in its own words and keeps the
// core's text in «Detalles». Nothing decides by reading that text.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart'
    show AnyhowException;

import '../l10n/l10n.dart';
import '../sftp/dialogs.dart' show fileErrorText;
import '../src/rust/api/keychain.dart' show SshKeyFailure;
import '../src/rust/api/programs.dart' show ReadFailure;
import '../src/rust/api/session.dart' show FailureView;
import '../src/rust/api/sftp.dart' show FileError;
import '../src/rust/api/tunnels.dart' show TunnelErrorView;
import '../src/rust/api/vault.dart' show VaultError, VaultErrorKind;
import '../ui/tokens.dart';
import '../ui/widgets.dart' show monoStyle;

/// Why it failed, short, to follow «No se ha podido guardar: …».
String errorReason(AppLocalizations l, Object e) => switch (e) {
  VaultError(:final kind) => switch (kind) {
    VaultErrorKind.conflict => l.errConflict,
    VaultErrorKind.notFound => l.errNotFound,
    VaultErrorKind.inUse => l.errInUse,
    VaultErrorKind.cycle => l.errCycle,
    VaultErrorKind.invalid => l.errInvalid,
    VaultErrorKind.newerFormat => l.errNewerFormat,
    VaultErrorKind.openElsewhere => l.errOpenElsewhere,
    VaultErrorKind.fileChanged => l.errFileChanged,
    VaultErrorKind.storage => l.errStorage,
    VaultErrorKind.other => l.errInternal,
  },
  FileError() => fileErrorText(l, e),
  _ => l.errInternal,
};

/// The core's own words, in English, for «Detalles».
String errorDetails(Object e) => switch (e) {
  VaultError(:final message) => message,
  FileError(:final message) => message,
  FailureView(:final message) => message,
  TunnelErrorView(:final failure?) => failure.message,
  TunnelErrorView(:final message) => message,
  SshKeyFailure(:final message) => message,
  ReadFailure(:final message) => message,
  AnyhowException(:final message) => message,
  _ => '$e',
};

/// The vault said it changed meanwhile.
bool isConflict(Object e) =>
    e is VaultError && e.kind == VaultErrorKind.conflict;

/// The vault said it of `kind`.
bool isVaultError(Object e, VaultErrorKind kind) =>
    e is VaultError && e.kind == kind;

/// A save that failed, in words: a conflict says what to do.
String saveErrorText(AppLocalizations l, Object e) =>
    isConflict(e) ? l.changedMeanwhile : l.saveFailed(errorReason(l, e));

/// The core's text, to read or copy.
Future<void> showErrorDetails(BuildContext context, Object e) {
  final l = context.l10n;
  final details = errorDetails(e);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.errorDetailsTitle),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.errorDetailsHint,
              style: TextStyle(
                fontSize: 12,
                color: context.ow.colors.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.ow.colors.sunken,
                borderRadius: BorderRadius.circular(context.ow.shape.radius),
              ),
              child: SelectableText(details, style: monoStyle(context)),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Clipboard.setData(ClipboardData(text: details)),
          child: Text(l.copy),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
      ],
    ),
  );
}

/// «Detalles»: the core's words for `error`, to read or copy.
class DetailsButton extends StatelessWidget {
  const DetailsButton(this.error, {super.key});

  final Object error;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => showErrorDetails(context, error),
    child: Text(context.l10n.details),
  );
}

/// A notice that something failed: `text` in words, «Detalles» with the
/// core's. Shown on `messenger`, which outlives a panel that closed; the
/// details open on `navigator`, the app's by default.
void showErrorNotice(
  ScaffoldMessengerState messenger,
  String text,
  Object e, {
  NavigatorState? navigator,
}) {
  messenger.showSnackBar(
    SnackBar(
      content: Text(text),
      action: SnackBarAction(
        label: messenger.context.l10n.details,
        onPressed: () {
          final dialogs = (navigator ?? appNavigator.currentState)?.overlay;
          if (dialogs != null && dialogs.mounted) {
            showErrorDetails(dialogs.context, e);
          }
        },
      ),
    ),
  );
}

/// The app's own messenger: notices with nowhere else to go (an error
/// nobody caught) show there.
final appMessenger = GlobalKey<ScaffoldMessengerState>();

/// The app's navigator, for the details of a notice: the messenger sits
/// above it.
final appNavigator = GlobalKey<NavigatorState>();

/// Runs a change that may fail (a star, a switch, a delete) and, if it
/// does, says so in words, with «Detalles». False if it failed. `failed`
/// words it; a failed save by default.
Future<bool> runAction(
  BuildContext context,
  Future<void> Function() action, {
  String Function(AppLocalizations l, Object e)? failed,
}) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final navigator = Navigator.maybeOf(context, rootNavigator: true);
  try {
    await action();
    return true;
  } catch (e) {
    final m = messenger ?? appMessenger.currentState;
    if (m != null) {
      showErrorNotice(
        m,
        (failed ?? saveErrorText)(l, e),
        e,
        navigator: navigator,
      );
    }
    return false;
  }
}

/// An error nobody caught: said, not lost. Framework errors keep their
/// own report; this is for the asynchronous ones, which a release build
/// would otherwise drop without a word.
bool reportUncaught(Object error, StackTrace stack) {
  debugPrint('uncaught: $error\n$stack');
  final m = appMessenger.currentState;
  if (m != null && m.mounted) {
    showErrorNotice(m, m.context.l10n.errInternal, error);
  }
  return true;
}
