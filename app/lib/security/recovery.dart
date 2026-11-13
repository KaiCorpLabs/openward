import '../core/save_file.dart';

import 'dart:math';
import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/app.dart';

Future<void> saveRecoveryPdf(OpenWard app) async {
  final location = await chooseSave(
    'openward-recovery-kit.pdf',
    types: const [
      XTypeGroup(label: 'PDF', extensions: ['pdf']),
    ],
  );
  if (location == null) return;
  try {
    await app.exportPreparedRecovery(path: location.path);
  } catch (_) {
    await location.cancel();
    rethrow;
  }
  await location.finish();
}

/// No network image, clipboard or semantic string contains this secret.
/// Include the white quiet border returned by Rust even in a dark theme.
class RecoveryQr extends StatelessWidget {
  const RecoveryQr({required this.modules, super.key});
  final List<int> modules;
  @override
  Widget build(BuildContext context) => Semantics(
    label: context.l10n.vaultQrLabel,
    image: true,
    child: Center(
      child: CustomPaint(
        size: const Size.square(224),
        painter: _QrPainter(modules),
      ),
    ),
  );
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.modules);
  final List<int> modules;
  @override
  void paint(Canvas canvas, Size size) {
    final side = sqrt(modules.length).round();
    if (side == 0 || side * side != modules.length) return;
    final scale = size.width / side;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final ink = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (var i = 0; i < modules.length; i++) {
      if (modules[i] != 0) {
        canvas.drawRect(
          Rect.fromLTWH((i % side) * scale, (i ~/ side) * scale, scale, scale),
          ink,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) => oldDelegate.modules != modules;
}

class VaultPasswordChange extends ConsumerStatefulWidget {
  const VaultPasswordChange({super.key});
  @override
  ConsumerState<VaultPasswordChange> createState() =>
      _VaultPasswordChangeState();
}

class _VaultPasswordChangeState extends ConsumerState<VaultPasswordChange> {
  final authorization = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool useKit = false;
  bool busy = false;
  String? error;
  int score = 0;
  int generation = 0;
  Timer? debounce;
  @override
  void dispose() {
    debounce?.cancel();
    generation++;
    for (final controller in [authorization, password, confirmation]) {
      controller.clear();
      controller.dispose();
    }
    super.dispose();
  }

  void strength(String value) {
    final request = ++generation;
    debounce?.cancel();
    final app = ref.read(openWardProvider);
    debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final result = await app.passwordScore(password: value);
        if (mounted && generation == request) setState(() => score = result);
      } on Object {
        if (mounted && generation == request) setState(() => score = 0);
      }
    });
  }

  Future<void> change() async {
    final l = context.l10n;
    if (password.text != confirmation.text) {
      setState(() => error = l.vaultMismatch);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(openWardProvider)
          .changeVaultPassword(
            authorization: authorization.text,
            useKit: useKit,
            password: password.text,
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.vaultPasswordChanged)));
      }
    } on Object {
      if (mounted) setState(() => error = l.vaultPasswordChangeError);
    } finally {
      if (mounted) {
        authorization.clear();
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Widget field(
      TextEditingController controller,
      String label, {
      int? maxLength,
    }) => TextField(
      controller: controller,
      enabled: !busy,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      maxLength: maxLength,
      onChanged: controller == password ? strength : null,
      decoration: InputDecoration(labelText: label),
    );
    return AlertDialog(
      title: Text(l.vaultChangePassword),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.vaultChangeExplain),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.vaultUseKit),
                value: useKit,
                onChanged: busy
                    ? null
                    : (value) => setState(() {
                        useKit = value;
                        authorization.clear();
                      }),
              ),
              field(
                authorization,
                useKit ? l.vaultKit : l.vaultCurrentPassword,
                maxLength: useKit ? 256 : 128,
              ),
              Text(l.vaultPasswordHint),
              field(password, l.vaultNewPassword, maxLength: 128),
              LinearProgressIndicator(
                value: score / 4,
                semanticsLabel: l.vaultStrength,
              ),
              field(confirmation, l.vaultConfirmPassword, maxLength: 128),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: Text(l.vaultCancel),
        ),
        FilledButton(
          onPressed: busy ? null : change,
          child: Text(busy ? l.vaultBusy : l.vaultChangePassword),
        ),
      ],
    );
  }
}
