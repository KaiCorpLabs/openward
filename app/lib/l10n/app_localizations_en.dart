// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String aboutVersion(String version) {
    return 'OpenWard $version';
  }

  @override
  String get accessibility => 'Accessibility';

  @override
  String get add => 'Add';

  @override
  String get addSavedHost => 'Add a saved host';

  @override
  String get addTag => 'Add';

  @override
  String get address => 'Address';

  @override
  String get addressHint => 'server.example.com or 10.0.0.5';

  @override
  String get agent => 'SSH agent';

  @override
  String get agentNone => 'None';

  @override
  String get agentSocket => 'Another socket…';

  @override
  String get agentSystem => 'The system\'s';

  @override
  String get alreadyImported => 'already imported';

  @override
  String get appearanceStepBody => 'You can change it any time in Settings.';

  @override
  String get appearanceStepTitle => 'How do you want it to look?';

  @override
  String get asSystem => 'As the system';

  @override
  String get back => 'Back';

  @override
  String get bellFlash => 'Flash on bell';

  @override
  String get bellFlashHelp =>
      'When a program rings the bell. A tab in the background is marked anyway.';

  @override
  String get bellRang => 'The bell rang';

  @override
  String get cancel => 'Cancel';

  @override
  String get cancelled => 'Cancelled.';

  @override
  String cannotConnect(String label) {
    return 'Could not connect to $label';
  }

  @override
  String get change => 'Change';

  @override
  String get changedMeanwhile =>
      'Another change got there first: close and reopen the editor.';

  @override
  String get checkedFingerprint => 'I have checked the new fingerprint';

  @override
  String get cipher => 'Cipher';

  @override
  String get clear => 'Reset';

  @override
  String get clearSelection => 'Clear the selection';

  @override
  String get close => 'Close';

  @override
  String get closeTab => 'Close tab';

  @override
  String get closeTheTab => 'Close the tab';

  @override
  String get connect => 'Connect';

  @override
  String get connectingEllipsis => 'Connecting…';

  @override
  String connectingTo(String label) {
    return 'Connecting to $label';
  }

  @override
  String get connectionDetails => 'Connection details';

  @override
  String get connectionHint =>
      'What you don\'t change here is inherited. Under each value you can see where it comes from; inherited values have a dashed border.';

  @override
  String connectionLost(String label, String why) {
    return 'The connection to $label was lost$why.';
  }

  @override
  String get continueLabel => 'Continue';

  @override
  String contrastFails(String ratio) {
    return 'Text contrast $ratio:1. Below AA (4.5:1).';
  }

  @override
  String contrastPasses(String ratio) {
    return 'Text contrast $ratio:1. Meets AA.';
  }

  @override
  String contrastWarning(String ratio) {
    return 'With this combination, some text falls short of the recommended contrast ($ratio:1).';
  }

  @override
  String get copy => 'Copy';

  @override
  String get copyFingerprint => 'Copy the fingerprint';

  @override
  String get ctrlShiftPrefix => 'Ctrl+Shift+';

  @override
  String get cursor => 'Cursor';

  @override
  String get cursorBar => 'Bar';

  @override
  String get cursorBlink => 'Blinking cursor';

  @override
  String get cursorBlock => 'Block';

  @override
  String get cursorHelp => 'Unless the program asks for another.';

  @override
  String get cursorUnderline => 'Underline';

  @override
  String customize(String name) {
    return 'Customize $name';
  }

  @override
  String get customizeHint =>
      'Change a layer and the rest stays. Changes apply to this theme only.';

  @override
  String get defaultKeys =>
      '~/.ssh/id_ed25519, id_ecdsa, id_rsa (the usual ones)';

  @override
  String get delete => 'Delete';

  @override
  String deleteFailed(String error) {
    return 'Could not delete: $error';
  }

  @override
  String get deleteGroup => 'Delete group';

  @override
  String get deleteGroupBody => 'What it holds moves up to its parent group.';

  @override
  String deleteGroupTitle(String name) {
    return 'Delete the group “$name”?';
  }

  @override
  String get deleteHostBody =>
      'It disappears from the list. This cannot be undone.';

  @override
  String deleteHostTitle(String name) {
    return 'Delete the host “$name”?';
  }

  @override
  String get deletedHost => '(deleted host)';

  @override
  String get destination => 'Destination';

  @override
  String get dontTrust => 'Don\'t trust';

  @override
  String get editEllipsis => 'Edit…';

  @override
  String get editGroup => 'Edit group…';

  @override
  String get editGroupTitle => 'Edit group';

  @override
  String get editHostTitle => 'Edit host';

  @override
  String failureAuth(String user, String label) {
    return '$user@$label could not sign in.';
  }

  @override
  String failureAuthMethods(String user, String label, String methods) {
    return '$user@$label could not sign in (the server accepts: $methods).';
  }

  @override
  String failureBadCertificate(String label, String reason) {
    return 'The certificate of $label is not valid: $reason.';
  }

  @override
  String failureHostKeyChanged(String label, String fingerprint) {
    return 'The key of $label has changed (now $fingerprint). It may be an attack: not connected.';
  }

  @override
  String failureHostKeyRejected(String label) {
    return 'The key of $label was not trusted.';
  }

  @override
  String get findClose => 'Close the search (Esc)';

  @override
  String findCount(int selected, int total) {
    return '$selected of $total';
  }

  @override
  String get findHint => 'Search the terminal';

  @override
  String get findNewer => 'Next, further down (Shift+Enter)';

  @override
  String get findOlder => 'Previous, further up (Enter)';

  @override
  String findTotal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '1 result',
      zero: 'No results',
    );
    return '$_temp0';
  }

  @override
  String get fingerprint => 'Fingerprint';

  @override
  String firstConnectionTo(String label) {
    return 'First connection to $label';
  }

  @override
  String get fontFromTheme => 'The theme\'s';

  @override
  String get fontOther => 'Another installed font…';

  @override
  String get fontOtherHint => 'Its exact name, like “Fira Code”';

  @override
  String get fontOtherTitle => 'Another installed font';

  @override
  String get fontSize => 'Font size';

  @override
  String get fontSystem => 'The system\'s';

  @override
  String get fromDefault => 'Default value';

  @override
  String fromGroup(String name) {
    return 'From the group $name';
  }

  @override
  String get fromNowhere => 'Not set: the connection decides';

  @override
  String get group => 'Group';

  @override
  String get groupInsideItself => 'A group cannot be inside itself.';

  @override
  String get groupNeedsName => 'The group needs a name.';

  @override
  String get groupSettingsSection => 'Settings for everything inside';

  @override
  String hostInUse(String name) {
    return 'Other hosts jump through “$name”: change them before deleting it.';
  }

  @override
  String get hostKey => 'Host key';

  @override
  String hostKeyUnknownBody(String where) {
    return 'OpenWard does not know the key of $where yet. Compare the fingerprint with the one the server\'s administrator gives you before trusting it.';
  }

  @override
  String get hostKeys => 'New host keys';

  @override
  String get hostNeedsName => 'The host needs a name.';

  @override
  String get importEllipsis => 'Import…';

  @override
  String importFailed(String error) {
    return 'Could not import: $error';
  }

  @override
  String importFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'We found $count hosts in your ~/.ssh/config.',
      one: 'We found 1 host in your ~/.ssh/config.',
    );
    return '$_temp0';
  }

  @override
  String get importFrom => 'Import from ~/.ssh/config';

  @override
  String get importIntoGroup =>
      'They go into the group “~/.ssh/config”. A host brings along the hosts it jumps through.';

  @override
  String get importKeepsFile =>
      'The file is left as it is, and keys stay where they are: OpenWard keeps the path, never the key.';

  @override
  String get importLater => 'You can import later from the sidebar.';

  @override
  String importN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Import $count hosts',
      one: 'Import 1 host',
      zero: 'Import',
    );
    return '$_temp0';
  }

  @override
  String get importNothing =>
      'There are no new hosts in ~/.ssh/config (or it does not exist).';

  @override
  String get importScheme => 'Import from iTerm2 or Ghostty…';

  @override
  String importSchemeDone(String name) {
    return '“$name” imported and set on the terminal.';
  }

  @override
  String get importSchemeFailed =>
      'That file is not an iTerm2 (.itermcolors) or Ghostty theme.';

  @override
  String get importSshConfigMenu => 'Import from ~/.ssh/config…';

  @override
  String get importTitle => 'Import ~/.ssh/config';

  @override
  String get inDark => 'In dark';

  @override
  String inGroup(String name) {
    return 'in the group $name';
  }

  @override
  String get inLight => 'In light';

  @override
  String get inputNotSent => 'What you type now is not sent.';

  @override
  String get inside => 'Inside';

  @override
  String get jumpThrough => 'Jump through, in order';

  @override
  String jumpVia(String hosts) {
    return 'Jumping through $hosts';
  }

  @override
  String jumpsVia(String hosts) {
    return 'jumps through $hosts';
  }

  @override
  String get keyBefore => 'Before';

  @override
  String get keyChangedBody =>
      'It may be a reinstalled server or someone intercepting the connection. No password or key has been sent.';

  @override
  String keyChangedDialogBody(String where) {
    return '$where shows a key different from the one you had as good. The server may have been reinstalled or changed its key, but someone may also be intercepting the connection. Do not go on without checking the new fingerprint with the server\'s administrator.';
  }

  @override
  String keyChangedTitle(String label) {
    return 'The key of $label has changed';
  }

  @override
  String get keyExchange => 'Key exchange';

  @override
  String get keyInKnownHosts => 'in ~/.ssh/known_hosts';

  @override
  String get keyInOpenWard => 'saved in OpenWard';

  @override
  String keyNow(String algorithm) {
    return 'Now ($algorithm)';
  }

  @override
  String keyProtected(String key) {
    return 'The key $key is protected.';
  }

  @override
  String get keyReceived => 'Received';

  @override
  String get keySaved => 'Saved';

  @override
  String get keys => 'Keys';

  @override
  String get keysHelp =>
      'One path per line. OpenWard keeps the path, never the key.';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'As the system';

  @override
  String get licenses => 'Licenses';

  @override
  String get lightAndDark => 'Light and dark';

  @override
  String get lineHeight => 'Terminal line height';

  @override
  String linkNotOpened(String scheme) {
    return '“$scheme:” links are not opened from the terminal.';
  }

  @override
  String get localTerminal => 'Local terminal';

  @override
  String get localUser => 'your local user';

  @override
  String milliseconds(int ms) {
    return '$ms ms';
  }

  @override
  String get minimumContrast => 'Minimum contrast';

  @override
  String get minimumContrastHelp =>
      'Lightens or darkens terminal text that does not read on its background.';

  @override
  String get missingAddress => 'The address is missing.';

  @override
  String get missingJump => 'Add at least one host to jump through.';

  @override
  String get missingProxyCommand => 'The ProxyCommand is missing.';

  @override
  String get missingSocket => 'The agent socket path is missing.';

  @override
  String get moreActions => 'More actions';

  @override
  String get moreOptions => 'More options';

  @override
  String get name => 'Name';

  @override
  String get netLost => 'the connection was lost.';

  @override
  String get netNotFound => 'host not found.';

  @override
  String get netRefused => 'connection refused.';

  @override
  String get netTimeout => 'timed out.';

  @override
  String get newGroup => 'New group';

  @override
  String get newGroupTitle => 'New group';

  @override
  String get newHost => 'New host';

  @override
  String get newHostHere => 'New host here';

  @override
  String get newHostTitle => 'New host';

  @override
  String get newLocalTerminal => 'New local terminal';

  @override
  String get newSubgroup => 'New subgroup';

  @override
  String get next => 'Next';

  @override
  String get no => 'No';

  @override
  String get noGroup => 'No group';

  @override
  String get noHostsBody => 'Add one or bring them from your ~/⁠.ssh/⁠config.';

  @override
  String get noHostsTitle => 'No hosts yet';

  @override
  String get noJumpsYet => 'None yet.';

  @override
  String get noParent => 'No group';

  @override
  String get noPostQuantumNote =>
      'The server offers no post-quantum key exchange (mlkem768x25519; OpenSSH has it since 10.0).';

  @override
  String get noResults => 'No host matches.';

  @override
  String get notNow => 'Not now';

  @override
  String get notes => 'Notes';

  @override
  String get ok => 'OK';

  @override
  String get openLocal => 'Open a local terminal';

  @override
  String openSshStillWarns(String command) {
    return 'OpenWard does not change ~/.ssh/known_hosts: ssh will keep warning until you remove the old key from there ($command).';
  }

  @override
  String get optionAsAlt => 'Option as Alt';

  @override
  String get optionAsAltHelp =>
      'Option sends Esc + key, as emacs and readline expect, instead of typing symbols like @ or €.';

  @override
  String get orAnAddress => 'or an address: user@host:port';

  @override
  String get passphraseField => 'Passphrase';

  @override
  String get passphraseTitle => 'Key passphrase';

  @override
  String get passwordTitle => 'Password';

  @override
  String get paste => 'Paste';

  @override
  String get pasteMultiBody =>
      'The text has line breaks or other sequences that can run commands when pasted.';

  @override
  String get pasteMultiTitle => 'Paste several lines?';

  @override
  String percent(int number) {
    return '$number%';
  }

  @override
  String pixels(int size) {
    return '$size px';
  }

  @override
  String get policyAcceptNew => 'Accept new';

  @override
  String get policyAsk => 'Ask';

  @override
  String get policyStrict => 'Strict';

  @override
  String get port => 'Port';

  @override
  String get portRange => 'The port goes from 1 to 65535.';

  @override
  String get postQuantum => 'post-quantum';

  @override
  String postQuantumKex(String kex) {
    return '$kex (post-quantum)';
  }

  @override
  String get preview => 'Preview';

  @override
  String get previewLive => 'Changes show at once across the window.';

  @override
  String get quickConnectHint => 'user@server:port';

  @override
  String get quickConnectInvalid => 'Type an address like user@server:port.';

  @override
  String get readyBody => 'These shortcuts get you almost everywhere:';

  @override
  String get readyTitle => 'All set';

  @override
  String get reconnect => 'Reconnect';

  @override
  String get reconnectingEllipsis => 'Reconnecting…';

  @override
  String reconnectingStage(String stage) {
    return 'Reconnecting: $stage';
  }

  @override
  String get reduceMotion => 'Reduce motion';

  @override
  String removeTag(String tag) {
    return 'Remove $tag';
  }

  @override
  String get rename => 'Rename';

  @override
  String get renameTabHelp => 'Empty to go back to the host\'s name';

  @override
  String get renameTabTitle => 'Rename tab';

  @override
  String reportCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new hosts',
      one: '1 new host',
    );
    return '$_temp0';
  }

  @override
  String get reportNotEverything => 'Not everything could be brought in:';

  @override
  String reportSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count were imported before and left as they were',
      one: '1 was imported before and left as it was',
    );
    return '$_temp0';
  }

  @override
  String get reportWhere => 'They are in the group “~/.ssh/config”.';

  @override
  String get resetTheme => 'Reset';

  @override
  String get restart => 'Restart';

  @override
  String retryIn(int attempt, int max, int secs) {
    return 'Try $attempt of $max in $secs s.';
  }

  @override
  String get retryNow => 'Retry now';

  @override
  String get reviewKey => 'Review the key…';

  @override
  String get route => 'How to get there';

  @override
  String get routeDirect => 'Direct';

  @override
  String get routeJump => 'Jumping through another host';

  @override
  String get routeStart => 'this computer';

  @override
  String get sampleComment => 'a grey comment';

  @override
  String get sampleError => 'error:';

  @override
  String get sampleErrorText => 'could not read .env';

  @override
  String get sampleWarning => 'warning:';

  @override
  String get sampleWarningText => '2 pending migrations';

  @override
  String get save => 'Save';

  @override
  String get saveAndConnect => 'Save and connect';

  @override
  String saveFailed(String error) {
    return 'Could not save: $error';
  }

  @override
  String saveKeyFailed(String error) {
    return 'Could not save the key: $error';
  }

  @override
  String get saveNewHost => 'Save a new host';

  @override
  String get scrollback => 'Scrollback';

  @override
  String get scrollbackHelp => 'For new tabs.';

  @override
  String scrollbackLines(String lines) {
    return '$lines lines';
  }

  @override
  String get searchHosts => 'Search hosts';

  @override
  String get sectionConnection => 'Connection';

  @override
  String get sectionGeneral => 'General';

  @override
  String get selectAll => 'All';

  @override
  String get selectAllText => 'Select all';

  @override
  String selectedOf(int selected, int total) {
    return '$selected of $total';
  }

  @override
  String get sessionClosed => 'Session closed.';

  @override
  String sessionClosedCode(int code) {
    return 'Session closed (code $code).';
  }

  @override
  String setHereWouldInherit(String value) {
    return 'Set here; it would inherit $value';
  }

  @override
  String get settings => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsGeneral => 'General';

  @override
  String get settingsTerminal => 'Terminal';

  @override
  String get shape => 'Shape';

  @override
  String get shortcutLocal => 'Opens a local terminal';

  @override
  String get shortcutNewHost => 'Saves a new host';

  @override
  String get shortcutSearch => 'Searches your hosts';

  @override
  String get shortcutSettings => 'Opens the settings';

  @override
  String showRest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Show the other $count',
      one: 'Show the other one',
    );
    return '$_temp0';
  }

  @override
  String get skipGuide => 'Skip the guide';

  @override
  String stageAuthenticating(String label, String hop) {
    return 'Signing in to $label$hop…';
  }

  @override
  String stageConnecting(String label, String hop) {
    return 'Connecting to $label$hop…';
  }

  @override
  String stageOpeningShell(String label) {
    return 'Opening the shell on $label…';
  }

  @override
  String get start => 'Get started';

  @override
  String get startHere => 'Start here';

  @override
  String get starting => 'Starting…';

  @override
  String get statusConnected => 'Connected';

  @override
  String get statusConnecting => 'Connecting';

  @override
  String statusError(String error) {
    return 'Error: $error';
  }

  @override
  String get statusFailed => 'The connection failed';

  @override
  String get statusIdle => 'Not connected';

  @override
  String get stepAppearance => 'Appearance';

  @override
  String get stepAuthenticating => 'signing in…';

  @override
  String get stepConnecting => 'connecting…';

  @override
  String get stepImport => 'Import';

  @override
  String get stepOpeningShell => 'opening the shell…';

  @override
  String get stepReady => 'Done';

  @override
  String get tags => 'Tags';

  @override
  String get terminalAlwaysDark => 'Always dark';

  @override
  String get terminalAsTheme => 'As the theme';

  @override
  String get terminalColors => 'Terminal colors';

  @override
  String get terminalFont => 'Terminal font';

  @override
  String get terminalScheme => 'Own scheme';

  @override
  String terminalShortcuts(String key) {
    return '${key}F searches the terminal and its history. $key+ and $key− size the tab\'s text, and ${key}0 resets it. Holding $key, a click opens a link.';
  }

  @override
  String get textSize => 'Text size';

  @override
  String get textSizeHelp =>
      'Of the interface, on top of the system\'s. The terminal has its own.';

  @override
  String get theme => 'Theme';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeHelp => 'Light: Papel. Dark: Grafito.';

  @override
  String get themeLight => 'Light';

  @override
  String get themeSystem => 'Follow the system';

  @override
  String themeVariant(String name, String variant) {
    return '$name ($variant)';
  }

  @override
  String get thisComputer => 'This computer';

  @override
  String get time => 'Time';

  @override
  String get trust => 'Trust';

  @override
  String get trustAndConnect => 'Trust and connect';

  @override
  String trustCertified(String ca) {
    return 'certified by the CA $ca';
  }

  @override
  String get trustKnown => 'known';

  @override
  String get trustNew => 'new, saved now';

  @override
  String get trustNewKey => 'Trust the new key';

  @override
  String get trustNewKeyEllipsis => 'Trust the new key…';

  @override
  String get tryAgain => 'Try again';

  @override
  String get uiColors => 'Interface colors';

  @override
  String get uiFont => 'Interface font';

  @override
  String get user => 'User';

  @override
  String get variantDark => 'dark';

  @override
  String get variantDarkOnly => 'Dark';

  @override
  String get variantLight => 'light';

  @override
  String get variantLightOnly => 'Light';

  @override
  String get verificationTitle => 'Verification';

  @override
  String via(String hops) {
    return 'via $hops';
  }

  @override
  String get waitingAnswer => 'Waiting for an answer…';

  @override
  String get waitingForYou => 'Waiting for you';

  @override
  String warnBadValue(String subject, String at, String detail) {
    return 'Invalid value in $subject$at: $detail.';
  }

  @override
  String warnIncludeTooDeep(String at) {
    return 'Include nested too deep$at.';
  }

  @override
  String warnJumpLossy(String alias, String jump) {
    return '$alias jumps through $jump, which is not an imported host: it is kept as an address, without its keys or its route.';
  }

  @override
  String warnMatch(String at) {
    return 'Match block$at: OpenWard does not evaluate it, and its lines were skipped.';
  }

  @override
  String warnStricter(String at) {
    return 'StrictHostKeyChecking no$at: imported as “accept new”; a changed key is never accepted without asking.';
  }

  @override
  String warnUnreadable(String file, String error) {
    return 'Could not read $file: $error.';
  }

  @override
  String warnUnsupported(String subject, String at) {
    return '$subject: not imported$at.';
  }

  @override
  String get welcomeNoConfig =>
      'We found no hosts in ~/.ssh/config. You can add them by hand in a moment.';

  @override
  String get welcomeTitle => 'Welcome to OpenWard';

  @override
  String get wrongAnswer => 'Wrong answer.';

  @override
  String get wrongPassphrase => 'Wrong passphrase.';

  @override
  String get wrongPassword => 'Wrong password.';

  @override
  String get yes => 'Yes';
}
