// A host's identity at a glance: its environment (a color and a short
// name, «prod», inherited from its group) and the system it runs (its
// logo in one color, the environment's). The vault keeps colors by name;
// each theme draws them.

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';
import 'svg_path.dart';
import 'system_logos.dart';
import 'tokens.dart';

/// The colors a mark can take, by the name the vault keeps.
const envColorNames = [
  'red',
  'orange',
  'yellow',
  'green',
  'blue',
  'violet',
  'pink',
  'gray',
];

/// A mark's color, the fill behind it and its outline, in this theme.
({Color fg, Color soft, Color line}) envColors(OwColors c, String name) {
  switch (name) {
    case 'red':
      return (fg: c.danger, soft: c.dangerSoft, line: c.dangerLine);
    case 'orange':
      return (fg: c.warn, soft: c.warnSoft, line: c.warnLine);
    case 'blue':
      return (fg: c.info, soft: c.infoSoft, line: c.infoLine);
  }
  final base = switch ((name, c.dark)) {
    ('yellow', true) => const Color(0xFFE3C55B),
    ('yellow', false) => const Color(0xFF6B5300),
    ('green', true) => const Color(0xFF6CCB8A),
    ('green', false) => const Color(0xFF1E6A3F),
    ('violet', true) => const Color(0xFFB9A3FF),
    ('violet', false) => const Color(0xFF5A3DB8),
    ('pink', true) => const Color(0xFFF28AC0),
    ('pink', false) => const Color(0xFF962F69),
    _ => c.textMuted,
  };
  return (
    fg: base,
    soft: Color.alphaBlend(base.withValues(alpha: 0.14), c.surface),
    line: Color.alphaBlend(base.withValues(alpha: 0.45), c.surface),
  );
}

/// The color's name, for the picker.
String envColorName(AppLocalizations l, String name) => switch (name) {
  'red' => l.colorRed,
  'orange' => l.colorOrange,
  'yellow' => l.colorYellow,
  'green' => l.colorGreen,
  'blue' => l.colorBlue,
  'violet' => l.colorViolet,
  'pink' => l.colorPink,
  _ => l.colorGray,
};

/// The four marks every install offers, in the user's language.
List<EnvironmentView> envPresets(AppLocalizations l) => [
  EnvironmentView(
    name: l.envProduction,
    short: l.envProductionShort,
    color: 'red',
  ),
  EnvironmentView(
    name: l.envStaging,
    short: l.envStagingShort,
    color: 'orange',
  ),
  EnvironmentView(name: l.envTesting, short: l.envTestingShort, color: 'blue'),
  EnvironmentView(
    name: l.envPersonal,
    short: l.envPersonalShort,
    color: 'violet',
  ),
];

/// The four marks in each of the app's languages, to know them.
final _presetsByLanguage = {
  for (final locale in AppLocalizations.supportedLocales)
    locale.languageCode: envPresets(lookupAppLocalizations(locale)),
};

/// A mark as it reads in the interface's language: one of the four every
/// install offers, made while the app was in another language, says its
/// name in this one. The vault keeps what it was made with.
EnvironmentView shownEnv(AppLocalizations l, EnvironmentView env) {
  for (final presets in _presetsByLanguage.values) {
    final i = presets.indexWhere(
      (p) => p.name == env.name && p.short == env.short && p.color == env.color,
    );
    if (i >= 0) return _presetsByLanguage[l.localeName]?[i] ?? env;
  }
  return env;
}

/// The systems there are, in the picker's order (families together);
/// «?» is unknown.
const systemCodes = [
  'deb',
  'ubu',
  'mint',
  'pop',
  'elem',
  'zor',
  'kali',
  'rpi',
  'fed',
  'rhel',
  'cent',
  'rock',
  'alma',
  'arch',
  'manj',
  'endv',
  'alp',
  'suse',
  'nix',
  'gent',
  'void',
  'owrt',
  'bsd',
  'obsd',
  'nbsd',
  'mac',
  'win',
  'lnx',
  '?',
];

/// What a system's code stands for.
String systemName(AppLocalizations l, String code) => switch (code) {
  'deb' => 'Debian',
  'ubu' => 'Ubuntu',
  'mint' => 'Linux Mint',
  'pop' => 'Pop!_OS',
  'elem' => 'elementary OS',
  'zor' => 'Zorin OS',
  'kali' => 'Kali Linux',
  'rpi' => 'Raspberry Pi OS',
  'fed' => 'Fedora',
  'rhel' => 'Red Hat',
  'cent' => 'CentOS',
  'rock' => 'Rocky Linux',
  'alma' => 'AlmaLinux',
  'arch' => 'Arch',
  'manj' => 'Manjaro',
  'endv' => 'EndeavourOS',
  'alp' => 'Alpine',
  'suse' => 'openSUSE',
  'nix' => 'NixOS',
  'gent' => 'Gentoo',
  'void' => 'Void Linux',
  'owrt' => 'OpenWrt',
  'bsd' => 'FreeBSD',
  'obsd' => 'OpenBSD',
  'nbsd' => 'NetBSD',
  'mac' => 'macOS',
  'win' => 'Windows',
  'lnx' => 'Linux',
  _ => l.systemUnknown,
};

/// Whether a host's system is told: «?» is as unknown as none.
bool systemKnown(String? code) => code != null && code != '?';

final _logoPaths = <String, Path>{};

/// Logos of fine lines, which fade below 24 px: there, an outline this
/// thick (in their 24×24 box) goes round them.
const _fineLogos = {
  'kali': 1.0,
  'nbsd': 0.8,
  'obsd': 0.7,
  'cent': 0.6,
  'deb': 0.4,
  'elem': 0.4,
};

/// What stands for a system, in `color`, `size` high: its logo; for macOS
/// and Windows, whose logos are not lent, the command key and a window;
/// its code where there is no logo (a newer version's); and a server's
/// outline (or `unknown`) when it is not known.
class SystemGlyph extends StatelessWidget {
  const SystemGlyph({
    super.key,
    required this.code,
    required this.color,
    this.size = 16,
    this.unknown,
  });

  final String? code;
  final Color color;
  final double size;

  /// Instead of the server's outline when the system is not known.
  final IconData? unknown;

  @override
  Widget build(BuildContext context) {
    final code = this.code;
    final icon = switch (code) {
      _ when !systemKnown(code) => unknown ?? Icons.dns_outlined,
      'mac' => Icons.keyboard_command_key,
      'win' => Icons.window_outlined,
      _ => null,
    };
    if (icon != null) return Icon(icon, size: size, color: color);
    final data = systemLogos[code];
    if (data == null) {
      return Text(
        code!,
        maxLines: 1,
        style: TextStyle(
          fontFamily: context.ow.fonts.mono,
          fontSize: size >= 20 ? 14 : 12,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
          color: color,
        ),
      );
    }
    final path = _logoPaths.putIfAbsent(code!, () => parseSvgPath(data));
    return CustomPaint(
      size: Size.square(size),
      painter: SystemLogoPainter(
        path,
        color,
        bold: size < 24 ? _fineLogos[code] ?? 0 : 0,
      ),
    );
  }
}

class SystemLogoPainter extends CustomPainter {
  SystemLogoPainter(this.logo, this.color, {this.bold = 0});

  /// In a 24×24 box.
  final Path logo;
  final Color color;

  /// An outline round it, in the box's units, for fine lines drawn small.
  final double bold;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(logo, Paint()..color = color);
    if (bold > 0) {
      canvas.drawPath(
        logo,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = bold
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(SystemLogoPainter old) =>
      old.logo != logo || old.color != color || old.bold != bold;
}

/// «prod», or «prod · Producción» where there is room.
class EnvChip extends StatelessWidget {
  const EnvChip(this.env, {super.key, this.big = false});

  final EnvironmentView env;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final env = shownEnv(context.l10n, this.env);
    final colors = envColors(ow.colors, env.color);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: big ? 2 : 0),
      decoration: BoxDecoration(
        color: colors.soft,
        border: Border.all(color: colors.line),
        borderRadius: BorderRadius.circular(ow.shape.radiusSmall),
      ),
      child: Text(
        big ? '${env.short} · ${env.name}' : env.short,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: colors.fg,
        ),
      ),
    );
  }
}

/// The system's logo, tinted by the environment. Before a connection
/// tells it (or when it cannot), a server's outline (or `icon`: a local
/// shell's).
class SystemBadge extends StatelessWidget {
  const SystemBadge({
    super.key,
    this.code,
    this.env,
    this.size = 26,
    this.icon,
    this.tagged = false,
  });

  final String? code;
  final EnvironmentView? env;

  /// The environment's short name on its corner too, where there is no
  /// room for it beside: the color alone does not tell it (a theme in one
  /// color, someone who does not see it).
  final bool tagged;

  /// Its height; a little wider, for the four letters of a code without a
  /// logo.
  final double size;

  /// Instead of the server's outline when the system is not known.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final c = ow.colors;
    final e = env;
    final (fg, soft, line) = e == null
        ? (c.textMuted, c.sunken, c.control)
        : switch (envColors(c, e.color)) {
            final x => (x.fg, x.soft, x.line),
          };
    final known = systemKnown(code);
    final badge = ExcludeSemantics(
      child: Container(
        width: size + 6,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: soft,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(6),
        ),
        child: SystemGlyph(
          code: code,
          color: fg,
          // A logo fills its box; the icons have their own margin.
          size: size * (known && systemLogos.containsKey(code) ? 0.6 : 0.55),
          unknown: icon,
        ),
      ),
    );
    if (!tagged || e == null) return badge;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        badge,
        Positioned(top: -7, right: -9, child: EnvTag(e)),
      ],
    );
  }
}

/// An environment's first letters, «pro», on a badge's corner.
class EnvTag extends StatelessWidget {
  const EnvTag(this.env, {super.key});

  final EnvironmentView env;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final env = shownEnv(context.l10n, this.env);
    final colors = envColors(ow.colors, env.color);
    final short = env.short.characters;
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: colors.soft,
          border: Border.all(color: colors.line),
          borderRadius: BorderRadius.circular(ow.shape.radiusSmall),
        ),
        child: Text(
          short.length > 3 ? short.take(3).toString() : env.short,
          maxLines: 1,
          style: TextStyle(
            fontSize: 12,
            height: 1.15,
            fontWeight: FontWeight.w700,
            color: colors.fg,
          ),
        ),
      ),
    );
  }
}
