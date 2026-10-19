// SVG path data as a Path, for the systems' logos (ui/system_logos.dart):
// every command of the SVG spec, absolute and relative, with the packed
// forms Simple Icons uses («.4.08», «a3 3 0 01-.99.05»).

import 'dart:ui';

/// `d` («M13.88 12.685c-.4 0 …») as a [Path]. Throws a [FormatException]
/// on data that is not a path.
Path parseSvgPath(String d) {
  final s = _Scanner(d);
  final path = Path();
  var current = Offset.zero;
  var start = Offset.zero;
  // The last control point, for S and T to mirror; null after anything
  // else.
  Offset? cubic;
  Offset? quad;
  String? command;
  while (!s.done) {
    // A command letter, or more numbers for the one before (after M, for
    // L).
    final letter = s.command();
    if (letter != null) {
      command = letter;
    } else if (command == null || command == 'Z' || command == 'z') {
      throw FormatException('expected a command', d, s.at);
    } else if (command == 'M') {
      command = 'L';
    } else if (command == 'm') {
      command = 'l';
    }
    final relative = command == command.toLowerCase();
    Offset point() {
      final p = Offset(s.number(), s.number());
      return relative ? current + p : p;
    }

    Offset? nextCubic;
    Offset? nextQuad;
    switch (command.toUpperCase()) {
      case 'M':
        current = start = point();
        path.moveTo(current.dx, current.dy);
      case 'L':
        current = point();
        path.lineTo(current.dx, current.dy);
      case 'H':
        final x = s.number();
        current = Offset(relative ? current.dx + x : x, current.dy);
        path.lineTo(current.dx, current.dy);
      case 'V':
        final y = s.number();
        current = Offset(current.dx, relative ? current.dy + y : y);
        path.lineTo(current.dx, current.dy);
      case 'C':
        final c1 = point();
        final c2 = point();
        current = point();
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, current.dx, current.dy);
        nextCubic = c2;
      case 'S':
        final c1 = cubic == null ? current : current * 2 - cubic;
        final c2 = point();
        current = point();
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, current.dx, current.dy);
        nextCubic = c2;
      case 'Q':
        final c = point();
        current = point();
        path.quadraticBezierTo(c.dx, c.dy, current.dx, current.dy);
        nextQuad = c;
      case 'T':
        final c = quad == null ? current : current * 2 - quad;
        current = point();
        path.quadraticBezierTo(c.dx, c.dy, current.dx, current.dy);
        nextQuad = c;
      case 'A':
        final rx = s.number();
        final ry = s.number();
        final rotation = s.number();
        final large = s.flag();
        final sweep = s.flag();
        current = point();
        path.arcToPoint(
          current,
          radius: Radius.elliptical(rx.abs(), ry.abs()),
          rotation: rotation,
          largeArc: large,
          // SVG's positive angles go clockwise on a screen, as Flutter's.
          clockwise: sweep,
        );
      case 'Z':
        path.close();
        current = start;
    }
    cubic = nextCubic;
    quad = nextQuad;
  }
  return path;
}

class _Scanner {
  _Scanner(this.text);

  final String text;
  int at = 0;

  static const _commands = 'MmLlHhVvCcSsQqTtAaZz';

  void _skip() {
    while (at < text.length && ' ,\n\r\t'.contains(text[at])) {
      at++;
    }
  }

  bool get done {
    _skip();
    return at >= text.length;
  }

  /// The command letter here, if there is one.
  String? command() {
    _skip();
    final c = text[at];
    if (!_commands.contains(c)) return null;
    at++;
    return c;
  }

  bool _digit() {
    if (at >= text.length) return false;
    final c = text.codeUnitAt(at);
    return c >= 0x30 && c <= 0x39;
  }

  double number() {
    _skip();
    final from = at;
    if (at < text.length && '+-'.contains(text[at])) at++;
    while (_digit()) {
      at++;
    }
    // «.4.08» is two numbers: a point ends the one that has one.
    if (at < text.length && text[at] == '.') {
      at++;
      while (_digit()) {
        at++;
      }
    }
    if (at < text.length && 'eE'.contains(text[at])) {
      final mark = at;
      at++;
      if (at < text.length && '+-'.contains(text[at])) at++;
      if (_digit()) {
        while (_digit()) {
          at++;
        }
      } else {
        at = mark;
      }
    }
    final value = double.tryParse(text.substring(from, at));
    if (value == null) throw FormatException('expected a number', text, from);
    return value;
  }

  /// An arc's flag: one digit, which may touch what follows («01-.99»).
  bool flag() {
    _skip();
    if (at < text.length && '01'.contains(text[at])) {
      return text[at++] == '1';
    }
    throw FormatException('expected a flag', text, at);
  }
}
