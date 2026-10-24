// Finding things by what is typed: one way of matching, so a host found
// in one place is found the same in every other.

import '../src/rust/api/vault.dart' show HostView;
import 'providers.dart' show Library;

/// How well `text` matches `q` (lowercase): lower is better, null is no
/// match. The start, the start of a word, anywhere, then the letters in
/// order.
int? matchScore(String text, String q) {
  if (q.isEmpty) return 0;
  final t = text.toLowerCase();
  if (t.startsWith(q)) return 0;
  final at = t.indexOf(q);
  if (at > 0) {
    return _wordStart.hasMatch(t[at - 1]) ? 1 : 2;
  }
  if (q.length < 2) return null;
  var i = 0;
  for (var j = 0; j < t.length; j++) {
    if (t.codeUnitAt(j) == q.codeUnitAt(i) && ++i == q.length) return 3;
  }
  return null;
}

final _wordStart = RegExp(r'[\s/._@:-]');

/// Hosts by what is typed, the same in the sidebar, the hosts page, ⌘K,
/// the start page, a pane that asks and a key's installation: every word
/// must be in the host's label, address, user, tags or the names of its
/// groups (as the core's search), and where they are ranks the host.
class HostMatcher {
  HostMatcher(String query, this.library)
    : words = query
          .trim()
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();

  final List<String> words;
  final Library library;

  /// Nothing typed: every host matches.
  bool get isEmpty => words.isEmpty;

  bool matches(HostView h) => score(h) != null;

  /// Null if a word is nowhere in the host; lower is better: each word in
  /// the label (its start, a word, anywhere, its letters in order), then
  /// in the address, then elsewhere.
  int? score(HostView h) {
    var total = 0;
    for (final w in words) {
      final s = _word(h, w);
      if (s == null) return null;
      total += s;
    }
    return total;
  }

  int? _word(HostView h, String w) {
    int? best;
    void take(int? s) {
      if (s != null && (best == null || s < best!)) best = s;
    }

    take(matchScore(h.label, w));
    final address = matchScore(h.address, w);
    // In the address, but not its letters scattered: «db» is not in
    // 10.0.0.1's digits.
    if (address != null && address < 3) take(address + 1);
    if (best != null) return best;
    final elsewhere = [
      h.user,
      ...h.tags,
      for (final g in _groups(h.groupId)) g,
    ].any((t) => t.toLowerCase().contains(w));
    return elsewhere ? 4 : null;
  }

  /// The names of the host's group and the groups above it.
  Iterable<String> _groups(String? id) sync* {
    final seen = <String>{};
    while (id != null && seen.add(id)) {
      final g = library.group(id);
      if (g == null) return;
      yield g.name;
      id = g.parentId;
    }
  }

  /// `hosts` that match, the best first (then by label).
  List<HostView> filter(Iterable<HostView> hosts) {
    final scored = [
      for (final h in hosts)
        if (score(h) case final s?) (h, s),
    ];
    scored.sort((a, b) {
      final s = a.$2 - b.$2;
      return s != 0
          ? s
          : a.$1.label.toLowerCase().compareTo(b.$1.label.toLowerCase());
    });
    return [for (final (h, _) in scored) h];
  }
}
