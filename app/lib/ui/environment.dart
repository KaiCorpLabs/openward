// A host's identity at a glance: its environment (a color and a short
// name, «prod», inherited from its group) and the system it runs (a
// monogram, «deb»). The vault keeps colors by name; each theme draws them.

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n.dart';
import '../src/rust/api/vault.dart';
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

/// The monograms there are, in the picker's order; «?» is unknown.
const systemCodes = [
  'deb',
  'ubu',
  'fed',
  'rhel',
  'alp',
  'arch',
  'bsd',
  'mac',
  'win',
  '?',
];

/// What a monogram stands for.
String systemName(AppLocalizations l, String code) => switch (code) {
  'deb' => 'Debian',
  'ubu' => 'Ubuntu',
  'fed' => 'Fedora',
  'rhel' => 'Red Hat',
  'alp' => 'Alpine',
  'arch' => 'Arch',
  'bsd' => 'BSD',
  'mac' => 'macOS',
  'win' => 'Windows',
  _ => l.systemUnknown,
};

/// «prod», or «prod · Producción» where there is room.
class EnvChip extends StatelessWidget {
  const EnvChip(this.env, {super.key, this.big = false});

  final EnvironmentView env;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
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

/// The system's monogram, tinted by the environment. Before the first
/// connection tells it, a server's outline (or `icon`: a local shell's).
class SystemBadge extends StatelessWidget {
  const SystemBadge({
    super.key,
    this.code,
    this.env,
    this.size = 26,
    this.icon,
  });

  final String? code;
  final EnvironmentView? env;

  /// Its height; a little wider, for four letters.
  final double size;

  /// Instead of the server's outline when there is no monogram.
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
    final code = this.code;
    return ExcludeSemantics(
      child: Container(
        width: size + 6,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: soft,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(6),
        ),
        child: code == null
            ? Icon(icon ?? Icons.dns_outlined, size: size * 0.55, color: fg)
            : Text(
                code,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: ow.fonts.mono,
                  fontSize: size >= 36 ? 14 : 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                  color: fg,
                ),
              ),
      ),
    );
  }
}
