import '../src/rust/api/session.dart';
import 'controller.dart';

/// A delivery decision belongs to this terminal and this shell, never whatever
/// tab or replacement connection happens to be current after a dialog.
class TerminalSendTarget {
  TerminalSendTarget(this.controller)
    : session = controller.session,
      generation = controller.shellGeneration,
      destination = controller.connected == null
          ? controller.displayTitle
          : '${controller.displayTitle} · ${controller.connected!.user == null ? '' : '${controller.connected!.user}@'}${controller.connected!.host}:${controller.connected!.port}';

  final TerminalController controller;
  final TerminalSession session;
  final int generation;
  final String destination;

  bool get current =>
      !controller.isDisposed &&
      identical(controller.session, session) &&
      controller.shellGeneration == generation &&
      (controller.phase == Phase.running ||
          controller.phase == Phase.connected);

  bool paste(String text, {required bool allowUnsafe}) =>
      current && session.paste(text: text, allowUnsafe: allowUnsafe);

  bool execute(String text) {
    if (!current) return false;
    session.text(text: '$text\n');
    return true;
  }
}
