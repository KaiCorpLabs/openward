// Links in a terminal: anyone's output can carry one, so they say where
// they lead and only some open.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../src/rust/api/session.dart';
import '../ui/tokens.dart';

/// Web and mail links open in their apps; others are not opened from a
/// terminal, where anyone's output can carry them.
Future<void> openTerminalLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (!const {'http', 'https', 'mailto', 'ftp'}.contains(uri.scheme)) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(context.l10n.linkNotOpened(uri.scheme))),
    );
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Whether a link's `text` reads as an address of another host than the
/// `url` it opens (an OSC 8 link's text is anything the program wrote).
bool linkMisleads(String text, String url) {
  final shown = text.trim();
  if (shown == url || !shown.contains('.') || shown.contains(' ')) {
    return false;
  }
  final said = Uri.tryParse(shown.contains('://') ? shown : 'https://$shown');
  final real = Uri.tryParse(url);
  if (said == null || real == null || said.host.isEmpty) return false;
  return said.host.toLowerCase() != real.host.toLowerCase();
}

/// Where the link under the pointer leads, as a browser says it: an OSC 8
/// link's text can name another site than the one it opens.
class LinkTarget extends StatelessWidget {
  const LinkTarget({super.key, required this.link});

  final LinkView link;

  @override
  Widget build(BuildContext context) {
    final ow = context.ow;
    final warn = linkMisleads(link.text, link.url);
    return Semantics(
      liveRegion: true,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.all(OwSpace.s2),
        padding: const EdgeInsets.symmetric(
          horizontal: OwSpace.s4,
          vertical: OwSpace.s2,
        ),
        decoration: BoxDecoration(
          color: warn ? ow.colors.warnSoft : ow.colors.raised,
          borderRadius: BorderRadius.circular(ow.shape.radius),
          border: Border.all(
            color: warn ? ow.colors.warnLine : ow.colors.control,
          ),
        ),
        child: Text(
          warn ? context.l10n.linkLeadsElsewhere(link.url) : link.url,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: OwText.small, color: ow.colors.text),
        ),
      ),
    );
  }
}
