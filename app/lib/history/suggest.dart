// Inline suggestions: the rest of a command line, dimmed after the cursor,
// from what this device knows (the host's history, the snippets and some
// common commands). Nothing leaves the device. An AI source would be one
// more [SuggestionSource] (phase 3, ADR-008).

import '../terminal/visible_text.dart';

/// Commands typed everywhere: what can be suggested before a host has any
/// history.
const commonCommands = [
  'ls -la',
  'ls -lah',
  'cd ..',
  'cd ~',
  'cat /etc/os-release',
  'df -h',
  'du -sh *',
  'free -h',
  'uptime',
  'top',
  'htop',
  'ps aux',
  'ps aux | grep ',
  'tail -f /var/log/syslog',
  'tail -n 100 ',
  'grep -rn ',
  'find . -name ',
  'ip addr',
  'ip -br addr',
  'ip route',
  'ss -tulpn',
  'ping -c 4 ',
  'curl -I ',
  'sudo -i',
  'sudo systemctl status ',
  'sudo systemctl restart ',
  'systemctl status ',
  'systemctl list-units --failed',
  'journalctl -xe',
  'journalctl -u ',
  'journalctl -f',
  'sudo apt update && sudo apt upgrade',
  'sudo dnf upgrade',
  'git status',
  'git log --oneline -20',
  'git pull',
  'git diff',
  'docker ps',
  'docker ps -a',
  'docker compose up -d',
  'docker compose logs -f',
  'docker logs -f ',
  'kubectl get pods',
  'kubectl get pods -A',
  'kubectl describe pod ',
  'kubectl logs -f ',
  'tmux attach',
  'exit',
];

/// Commands to suggest from, in the order they count, and how much must
/// be typed before they do.
class SuggestionSource {
  const SuggestionSource(this.commands, {this.minTyped = 1});

  final Iterable<String> commands;
  final int minTyped;
}

/// The rest of the first command of `sources` that starts with `typed`
/// and goes on; null when none does. Nothing for a line that starts with
/// a space (the shells' "keep this out of the history").
String? suggestFor(String typed, List<SuggestionSource> sources) {
  if (typed.isEmpty ||
      typed.startsWith(' ') ||
      hasHidden(typed, lines: false)) {
    return null;
  }
  for (final source in sources) {
    if (typed.length < source.minTyped) continue;
    for (final c in source.commands) {
      if (c.length > typed.length &&
          c.startsWith(typed) &&
          !hasHidden(c, lines: false)) {
        return c.substring(typed.length);
      }
    }
  }
  return null;
}
