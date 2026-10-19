// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get about => 'About';

  @override
  String aboutVersion(String version) {
    return 'OpenWard $version';
  }

  @override
  String get accessibility => 'Accessibility';

  @override
  String get add => 'Add';

  @override
  String get addCertificate => '+ Add a certificate';

  @override
  String get addFavorite => 'Add to favorites';

  @override
  String get addKeyEllipsis => 'Add a key…';

  @override
  String get addSavedHost => 'Add a saved host';

  @override
  String get addTag => 'Add';

  @override
  String get address => 'Address';

  @override
  String get addressHint => 'server.example.com or 10.0.0.5';

  @override
  String get advanced => 'Advanced';

  @override
  String get advancedList =>
      'proxy, host keys, persistent session, checks and agent';

  @override
  String advancedSetHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count set here',
      one: '1 set here',
    );
    return '$_temp0';
  }

  @override
  String get agent => 'SSH agent';

  @override
  String get agentNone => 'None';

  @override
  String get agentOtherSocket => 'Another socket';

  @override
  String get agentShort => 'Agent';

  @override
  String get agentSocket => 'Another socket…';

  @override
  String get agentSystem => 'The system\'s';

  @override
  String agoDays(int count) {
    return '$count d ago';
  }

  @override
  String agoHours(int count) {
    return '$count h ago';
  }

  @override
  String agoMinutes(int count) {
    return '$count min ago';
  }

  @override
  String get agoNow => 'now';

  @override
  String allCount(int count) {
    return 'All · $count';
  }

  @override
  String get alreadyImported => 'already imported';

  @override
  String get alreadyUses => 'Already uses it';

  @override
  String get alsoOnThisComputer => 'Also on this computer';

  @override
  String announceClosed(String name) {
    return '$name: disconnected';
  }

  @override
  String announceConnected(String name) {
    return '$name: connected';
  }

  @override
  String announceFailed(String name, String why) {
    return '$name: could not connect. $why';
  }

  @override
  String announcePrompt(String name) {
    return '$name asks something before going on';
  }

  @override
  String announceReconnecting(String name) {
    return '$name: dropped, reconnecting';
  }

  @override
  String announceTunnelFailed(String name, String why) {
    return 'The tunnel «$name» did not open: $why';
  }

  @override
  String announceTunnelLost(String name) {
    return 'The tunnel «$name» dropped';
  }

  @override
  String announceTunnelOpen(String name, int port) {
    return 'Tunnel «$name» open on port $port';
  }

  @override
  String get anyDestination => 'Any destination';

  @override
  String get appearanceStepBody => 'You can change it any time in Settings.';

  @override
  String get appearanceStepTitle => 'How do you want it to look?';

  @override
  String get apply => 'Apply';

  @override
  String get asSystem => 'As the system';

  @override
  String get asTyped => 'as typed, without saving it';

  @override
  String get askedWhenRun => 'Asked when it runs';

  @override
  String get askedWhenRunHint => 'Comes from what you write between braces.';

  @override
  String get asks => 'Asks';

  @override
  String asksNothing(String example) {
    return 'It asks nothing. Write $example where it should ask.';
  }

  @override
  String awayFor(String time) {
    return 'away for $time';
  }

  @override
  String get back => 'Back';

  @override
  String backAgain(String host) {
    return 'Connected to $host again';
  }

  @override
  String get badgeChanges => 'changes';

  @override
  String get badgeLeaves => 'leaves it';

  @override
  String get badgeNew => 'new';

  @override
  String get bellFlash => 'Flash on bell';

  @override
  String get bellFlashHelp =>
      'When a program rings the bell. A tab in the background is marked anyway.';

  @override
  String get bellRang => 'The bell rang';

  @override
  String get bracesWord => 'braces';

  @override
  String bringsTunnels(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'brings $count tunnels',
      one: 'brings 1 tunnel',
    );
    return '$_temp0';
  }

  @override
  String broadcastBanner(int count, int total, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Broadcast: what you type goes to $count of $total panes ($names).',
      one: 'Broadcast: what you type goes to 1 of $total panes ($names).',
    );
    return '$_temp0';
  }

  @override
  String broadcastExit(String keys) {
    return 'Stop $keys';
  }

  @override
  String get broadcastOff => 'Turn broadcast off';

  @override
  String get broadcastOn => 'Broadcast in this tab';

  @override
  String get broadcastPasteAlways =>
      'With broadcast, pasting always asks, even a single line.';

  @override
  String broadcastPasteBody(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'It goes to $names. They are $count lines, and each may run as it arrives.',
      one: 'It goes to $names. It is 1 line.',
    );
    return '$_temp0';
  }

  @override
  String broadcastPasteTitle(int total) {
    return 'Paste in $total panes at once?';
  }

  @override
  String broadcastStatus(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Broadcast · $count panes',
      one: 'Broadcast · 1 pane',
    );
    return '$_temp0';
  }

  @override
  String get bySsh => 'over SSH';

  @override
  String get cancel => 'Cancel';

  @override
  String cancelThese(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Don\'t copy these $count',
      one: 'Don\'t copy this one',
    );
    return '$_temp0';
  }

  @override
  String get cancelled => 'Cancelled.';

  @override
  String cannotConnect(String label) {
    return 'Could not connect to $label';
  }

  @override
  String certExpiredOn(String date) {
    return 'expired on $date';
  }

  @override
  String get certForever => 'never expires';

  @override
  String get certNextToKey =>
      'Next to the key (-cert.pub): used without adding it.';

  @override
  String certUntil(String date) {
    return 'until $date';
  }

  @override
  String get certificate => 'certificate';

  @override
  String get certificateExpired => 'expired certificate';

  @override
  String get certificateTitle => 'Certificate';

  @override
  String get change => 'Change';

  @override
  String get changedMeanwhile =>
      'Another change got there first: close and reopen the editor.';

  @override
  String checkNotImported(String label, String protocol) {
    return '$label uses $protocol and was not imported.';
  }

  @override
  String checkTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Check $count things',
      one: 'Check 1 thing',
    );
    return '$_temp0';
  }

  @override
  String checkWithoutKey(String label) {
    return '“$label” has no key now: its key is not in ~/.ssh.';
  }

  @override
  String get checkedFingerprint => 'I have checked the new fingerprint';

  @override
  String get checking => 'checking…';

  @override
  String get choiceKeepBoth => 'Keep both';

  @override
  String get choiceNewer => 'Only if mine is newer';

  @override
  String get choiceReplace => 'Replace';

  @override
  String get choiceSkip => 'Skip';

  @override
  String get chooseExportedFile => 'Choose the exported file';

  @override
  String get chooseFile => 'Choose…';

  @override
  String get cipher => 'Cipher';

  @override
  String get clear => 'Reset';

  @override
  String get clearFinished => 'Clear finished';

  @override
  String clearHistory(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Clear $count commands',
      one: 'Clear 1 command',
      zero: 'Clear the history',
    );
    return '$_temp0';
  }

  @override
  String clearRecent(int count) {
    return 'Clear ($count)';
  }

  @override
  String get clearSelection => 'Clear the selection';

  @override
  String get close => 'Close';

  @override
  String get closeAction => 'Close';

  @override
  String get closeOtherTabs => 'Close the others';

  @override
  String get closePane => 'Close the pane';

  @override
  String get closeTab => 'Close tab';

  @override
  String closeTabs(int count) {
    return 'Close all $count';
  }

  @override
  String get closeTheTab => 'Close the tab';

  @override
  String get colModified => 'Modified';

  @override
  String get colName => 'Name';

  @override
  String get colPermissions => 'Permissions';

  @override
  String get colSize => 'Size';

  @override
  String get collapse => 'Collapse';

  @override
  String get colorBlue => 'Blue';

  @override
  String get colorGray => 'Gray';

  @override
  String get colorGreen => 'Green';

  @override
  String get colorOrange => 'Orange';

  @override
  String get colorPink => 'Pink';

  @override
  String get colorRed => 'Red';

  @override
  String get colorViolet => 'Violet';

  @override
  String get colorYellow => 'Yellow';

  @override
  String comebackLine(String time, String away) {
    return 'connected again at $time · away for $away · new terminal';
  }

  @override
  String get comingFromOther => 'Coming from PuTTY, MobaXterm or SecureCRT?';

  @override
  String get command => 'Command';

  @override
  String commandHint(String open, String escaped) {
    return 'Each line is sent as if typed. To write $open as it is, put $escaped.';
  }

  @override
  String get commandHistory => 'Command history';

  @override
  String commandHistoryHelp(String keys) {
    return 'What you run in terminals is kept on this computer (never in the vault), to find and run again with $keys. What the screen does not show, like a password, is never kept, nor what starts with a space.';
  }

  @override
  String get commandPalette => 'Command palette';

  @override
  String get conflictChoose => '. Choose what to do with each:';

  @override
  String get conflictFile => 'File';

  @override
  String get conflictFolder => 'folder';

  @override
  String get conflictIn => 'In ';

  @override
  String get conflictMerge => 'the folders are merged';

  @override
  String conflictRest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '. The other $count are copied now. Choose what to do with each:',
      one: '. The other one is copied now. Choose what to do with each:',
    );
    return '$_temp0';
  }

  @override
  String get conflictSame => 'same size and date';

  @override
  String conflictTheirs(String where) {
    return 'On $where';
  }

  @override
  String conflictTheirsNewer(String where) {
    return 'the one on $where is newer';
  }

  @override
  String conflictTitle(int count, int total, String where) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count of the $total already exist on $where',
      one: '1 of the $total already exists on $where',
    );
    return '$_temp0';
  }

  @override
  String conflictTitleOne(String where) {
    return 'It already exists on $where';
  }

  @override
  String get conflictWhat => 'What to do';

  @override
  String get conflictYours => 'Yours';

  @override
  String get conflictYoursNewer => 'yours is newer';

  @override
  String get connect => 'Connect';

  @override
  String connectToAddress(String address) {
    return 'Connect to $address';
  }

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
      'What you do not change here is inherited. The host\'s own comes first, then its identity, then its groups and, last, the defaults.';

  @override
  String connectionLost(String label, String why) {
    return 'The connection to $label was lost$why.';
  }

  @override
  String connectionLostTitle(String host) {
    return 'The connection to $host was lost';
  }

  @override
  String get continueAction => 'Continue';

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
  String get copyAction => 'Copy';

  @override
  String get copyAddress => 'Copy address';

  @override
  String get copyFingerprint => 'Copy the fingerprint';

  @override
  String get copyPath => 'Copy path';

  @override
  String get copyPublicKey => 'Copy the public key';

  @override
  String get copyReport => 'Copy the report';

  @override
  String get create => 'Create';

  @override
  String get csvSpreadsheet => 'CSV (spreadsheet)';

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
  String get defaultValueOptional => 'Default value (optional)';

  @override
  String get delete => 'Delete';

  @override
  String get deleteEllipsis => 'Delete…';

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
  String deleteIdentityBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'The $count hosts that use it go back to their groups\' user and keys.',
      one: 'The host that uses it goes back to its group\'s user and keys.',
    );
    return '$_temp0';
  }

  @override
  String deleteIdentityTitle(String name) {
    return 'Delete «$name»?';
  }

  @override
  String get deleteIdentityUnused =>
      'Nobody uses it. The keys stay where they are: only the identity goes.';

  @override
  String get deleteLocalBody =>
      'They are deleted from this computer without going to the trash: this cannot be undone.';

  @override
  String deleteMany(int count) {
    return 'Delete $count items?';
  }

  @override
  String deleteOne(String name) {
    return 'Delete $name?';
  }

  @override
  String deleteRemoteBody(String host) {
    return 'They are deleted on $host. Servers have no trash: this cannot be undone.';
  }

  @override
  String get deleteWorkspaceBody =>
      'Only the saved layout goes: the hosts, and what is open, stay.';

  @override
  String deleteWorkspaceTitle(String name) {
    return 'Delete “$name”?';
  }

  @override
  String get deletedHost => '(deleted host)';

  @override
  String get deletedIdentity => '(deleted identity)';

  @override
  String get destination => 'Destination';

  @override
  String get dividerHint => 'Drag to resize · double-click: half and half';

  @override
  String get dontTrust => 'Don\'t trust';

  @override
  String get download => 'Download';

  @override
  String get downloadArrow => '← Download';

  @override
  String downloadTo(String path) {
    return 'Download to $path';
  }

  @override
  String get dragPaneHint =>
      'Drag to move the pane: onto another pane or the tab bar';

  @override
  String get dragToOrder => 'drag to reorder';

  @override
  String dropAbove(String pane) {
    return 'above $pane';
  }

  @override
  String get dropAskFirst =>
      'If something already exists, you are asked before it is touched.';

  @override
  String dropBelow(String pane) {
    return 'below $pane';
  }

  @override
  String get dropBottom => 'below';

  @override
  String dropHostNewTab(String name) {
    return 'Drop here: open $name in a new tab';
  }

  @override
  String get dropLeft => 'on the left';

  @override
  String dropLeftOf(String pane) {
    return 'left of $pane';
  }

  @override
  String dropMove(String name, String where) {
    return 'Drop: $name $where';
  }

  @override
  String dropNewTab(String name) {
    return 'Drop here: $name in a new tab';
  }

  @override
  String dropOpenHost(String name, String where) {
    return 'Drop: open $name $where';
  }

  @override
  String get dropRight => 'on the right';

  @override
  String dropRightOf(String pane) {
    return 'right of $pane';
  }

  @override
  String dropSplitAround(String name, String where, String other) {
    return 'Drop: $name $where; $other, a new pane';
  }

  @override
  String dropTabLast(String name) {
    return 'Drop here: $name at the end';
  }

  @override
  String get dropToDownload => 'Drop to download here';

  @override
  String get dropToImport =>
      'Or drop the file or folder here: it is recognized on its own.';

  @override
  String get dropToUpload => 'Drop to upload here';

  @override
  String get dropTop => 'above';

  @override
  String get duplicateTab => 'Duplicate';

  @override
  String durationHours(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String durationMinSec(int minutes, int seconds) {
    return '$minutes min $seconds s';
  }

  @override
  String durationMinutes(int count) {
    return '$count min';
  }

  @override
  String durationSec(int seconds) {
    return '$seconds s';
  }

  @override
  String get durationUnderMinute => 'under 1 min';

  @override
  String dynamicSentence(String here, String host) {
    return 'Use $here as a SOCKS5 proxy: connections leave from $host.';
  }

  @override
  String get editEllipsis => 'Edit…';

  @override
  String get editGroup => 'Edit group…';

  @override
  String get editGroupTitle => 'Edit group';

  @override
  String get editHostTitle => 'Edit host';

  @override
  String get editIdentity => 'Edit identity';

  @override
  String get editSnippet => 'Edit snippet';

  @override
  String get editTheIdentity => 'Edit the identity';

  @override
  String get editTunnel => 'Edit tunnel';

  @override
  String get emptyFolder => 'This folder is empty';

  @override
  String get emptyPane => 'empty pane';

  @override
  String get envColor => 'Color';

  @override
  String get envDialogTitle => 'Another environment';

  @override
  String get envHint =>
      'Marks these hosts\' tabs and terminals with a color and a short name, so as not to mistake one server for another.';

  @override
  String envInheritors(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'The group\'s $count hosts and its subgroups\' inherit it; each host can change it.',
      one: 'The group\'s host inherits it; it can change it.',
    );
    return '$_temp0';
  }

  @override
  String get envName => 'Name';

  @override
  String get envNeedsName => 'Give the environment a name.';

  @override
  String get envNone => 'None';

  @override
  String get envNoneNote => 'no mark';

  @override
  String get envOther => 'Other, with its name and color…';

  @override
  String get envPersonal => 'Personal';

  @override
  String get envPersonalShort => 'home';

  @override
  String envPreview(String name) {
    return 'Preview: a tab and a terminal marked as $name';
  }

  @override
  String get envPreviewHost => 'web-1';

  @override
  String get envProduction => 'Production';

  @override
  String get envProductionShort => 'prod';

  @override
  String get envShort => 'Short name';

  @override
  String get envShortHelp => 'On tabs and in the sidebar';

  @override
  String get envStaging => 'Staging';

  @override
  String get envStagingShort => 'stage';

  @override
  String get envTesting => 'Testing';

  @override
  String get envTestingShort => 'test';

  @override
  String get envUse => 'Use';

  @override
  String get environment => 'Environment';

  @override
  String get equalizePanes => 'Equal sizes';

  @override
  String get exampleVariable => 'name';

  @override
  String get expand => 'Expand';

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
  String failureHostKeyRevoked(String label, String fingerprint) {
    return '$label uses a revoked key ($fingerprint): it is always refused. If that is wrong, remove it from the known hosts.';
  }

  @override
  String failureNoSftp(String label) {
    return '$label has no SFTP: the server lacks sftp-server.';
  }

  @override
  String get favorite => 'Favorite';

  @override
  String get favoriteLower => 'favorite';

  @override
  String get favoriteNote =>
      'at the top of the sidebar, in the rail and on the start page';

  @override
  String get favorites => 'Favorites';

  @override
  String get favoritesEmpty =>
      'Mark the hosts you use most with ★ (on their page on hover, or in their editor) and they will show here, in the order you give them.';

  @override
  String get favoritesEmptyShort => 'Star the ones you use most in Hosts.';

  @override
  String featureFirewall(String name) {
    return 'SecureCRT’s firewall “$name”';
  }

  @override
  String get featureHardwareKey => 'a security key';

  @override
  String get featureJumpNotSsh => 'a jump through a profile that is not SSH';

  @override
  String featureJumpThrough(String target) {
    return 'a jump through $target, which is not there';
  }

  @override
  String get featureMobaCredential => 'a credential saved in MobaXterm';

  @override
  String featureProxy(String kind) {
    return 'a $kind proxy';
  }

  @override
  String get featureSecureCrtGlobalKey => 'SecureCRT’s global key';

  @override
  String get featureSocks4 => 'a SOCKS4 proxy';

  @override
  String get featureTabbyVault => 'a key in Tabby’s vault';

  @override
  String get featureTelnetProxy => 'a Telnet proxy';

  @override
  String get featureX11 => 'X11 forwarding';

  @override
  String fileChanged(String path) {
    return '$path changed while it was being copied.';
  }

  @override
  String fileDenied(String path) {
    return 'Permission denied: $path';
  }

  @override
  String fileExists(String path) {
    return 'Already exists: $path';
  }

  @override
  String get fileLost => 'The connection was lost.';

  @override
  String get fileName => 'File';

  @override
  String fileNotFound(String path) {
    return 'Not found: $path';
  }

  @override
  String get filledInEachPane => 'Also filled in on their own, in each pane:';

  @override
  String get filterFolder => 'Filter this folder';

  @override
  String get filterHostsAndGroups => 'Filter hosts and groups';

  @override
  String get filterIdentities => 'Filter by name, user or key';

  @override
  String get filterSnippets => 'Filter by name or command';

  @override
  String get filterTunnels => 'Filter by name, host or port';

  @override
  String get findASnippet => 'Find a snippet';

  @override
  String get findClose => 'Close the search (Esc)';

  @override
  String findCount(int selected, int total) {
    return '$selected of $total';
  }

  @override
  String get findHint => 'Search the terminal';

  @override
  String get findInTerminal => 'Find in the terminal';

  @override
  String get findNewer => 'Next, further down (Shift+Enter)';

  @override
  String get findOlder => 'Previous, further up (Enter)';

  @override
  String get findOutSystem => 'Find out the system';

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
  String get fingerprintNeedsPublic => 'No .pub: fingerprint unknown';

  @override
  String firstConnectionTo(String label) {
    return 'First connection to $label';
  }

  @override
  String get foldSidebar => 'Fold the sidebar';

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
  String get forAll => 'For all:';

  @override
  String get forgetAction => 'Forget';

  @override
  String get forgetFileKeyBody =>
      'That line goes from the file, which your system\'s ssh uses too, and a copy is kept first in known_hosts.old, as ssh-keygen -R does.';

  @override
  String forgetFileKeyTitle(String name, String file) {
    return 'Remove the key of $name from $file?';
  }

  @override
  String get forgetKeyBody => 'OpenWard stops trusting this key.';

  @override
  String get forgetKeyThen =>
      'Next time you connect its key is asked about again, unless another one you trust is there.';

  @override
  String forgetKeyTitle(String name) {
    return 'Forget the key of $name?';
  }

  @override
  String get forward => 'Forward';

  @override
  String foundMobaXterm(String path) {
    return 'Sessions in $path';
  }

  @override
  String foundSessions(String path) {
    return 'Saved sessions in $path';
  }

  @override
  String foundSshConfig(int count, int existing) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hosts',
      one: '1 host',
    );
    String _temp1 = intl.Intl.pluralLogic(
      existing,
      locale: localeName,
      other: ' · $existing imported before',
      zero: '',
    );
    return '$_temp0$_temp1';
  }

  @override
  String foundTabby(String path) {
    return 'Its configuration, in $path';
  }

  @override
  String get foundTermius =>
      'Installed: its data is read directly, nothing to export';

  @override
  String get fromDefault => 'Default value';

  @override
  String get fromExportedFile => 'From an exported file';

  @override
  String fromGroup(String name) {
    return 'From the group $name';
  }

  @override
  String get fromHere => 'from here';

  @override
  String fromIdentity(String name) {
    return 'From the identity $name';
  }

  @override
  String get fromNowhere => 'Not set: the connection decides';

  @override
  String get fromSshConfig => 'from ~/.ssh/config';

  @override
  String get fromThere => 'from there';

  @override
  String goToPage(String page) {
    return 'Go to $page';
  }

  @override
  String get group => 'Group';

  @override
  String get groupInsideItself => 'A group cannot be inside itself.';

  @override
  String groupNamed(String name) {
    return 'Group $name';
  }

  @override
  String get groupNeedsName => 'The group needs a name.';

  @override
  String get groupSettingsSection => 'Settings for everything inside';

  @override
  String get groups => 'Groups';

  @override
  String get hashedName => 'Hashed name';

  @override
  String get hideHiddenFiles => 'Hide hidden files';

  @override
  String get hideQueue => 'Hide';

  @override
  String get host => 'Host';

  @override
  String hostCountText(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hosts',
      one: '1 host',
      zero: 'no hosts',
    );
    return '$_temp0';
  }

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
  String get hosts => 'Hosts';

  @override
  String get hostsAll => 'All';

  @override
  String get hostsClearFilters => 'Clear the filters';

  @override
  String get hostsColAddress => 'Address';

  @override
  String get hostsColEnvironment => 'Environment';

  @override
  String get hostsColLast => 'Last connection';

  @override
  String get hostsColName => 'Name';

  @override
  String get hostsColSystem => 'System';

  @override
  String get hostsFilters => 'Filters';

  @override
  String get hostsHintConnect => 'connect';

  @override
  String get hostsHintDrag => 'drag one to the tab bar to open it there';

  @override
  String get hostsHintEdit => 'edit';

  @override
  String get hostsHintFavorite => 'favorite';

  @override
  String get hostsNoGroup => 'No group';

  @override
  String get hostsOpenNow => 'open now';

  @override
  String get hostsSearchHint => 'Search by name, address, tag or system';

  @override
  String get hostsSection => 'Hosts';

  @override
  String hostsSummary(int hosts, int groups) {
    String _temp0 = intl.Intl.pluralLogic(
      groups,
      locale: localeName,
      other: '$groups groups',
      one: '1 group',
      zero: 'no groups',
    );
    return '$hosts · $_temp0';
  }

  @override
  String get hostsViewCards => 'Cards';

  @override
  String get hostsViewList => 'List';

  @override
  String get howCsv =>
      'One host a row, with a header: Termius\'s template, or columns such as name, host, port, user and group.';

  @override
  String get howMobaXterm =>
      'Sessions › Export all sessions to file: a .mxtsessions file';

  @override
  String get howPutty =>
      'A .reg exported from the registry (reg export HKCU\\Software\\SimonTatham\\PuTTY\\Sessions putty.reg)';

  @override
  String get howSecureCrt => 'Tools › Export Settings…: an .xml file';

  @override
  String get howTabby => 'Its config.yaml, if it is not on this computer';

  @override
  String get identities => 'Identities';

  @override
  String identitiesCount(int total, int used) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total identities',
      one: '1 identity',
    );
    return '$_temp0 · $used in use';
  }

  @override
  String get identitiesIntro =>
      'A user, keys and an agent with a name, to use on several hosts and groups. Changing an identity changes everything that uses it.';

  @override
  String get identitiesNoSecrets =>
      'No passwords or passphrases are kept: they are asked for when connecting, as before. Only the public half of each key (.pub) is read.';

  @override
  String get identity => 'Identity';

  @override
  String get identityEditorHint =>
      'A user, keys and an agent with a name, to use on several hosts.';

  @override
  String identityKeyMissingHere(String user) {
    return '$user · its key is not on this computer';
  }

  @override
  String get identityNeedsName => 'Give it a name.';

  @override
  String get identityNewNote =>
      'Use it from the editor of a host or a group, or with «Use on…» in the list of identities.';

  @override
  String get identityNone => 'None';

  @override
  String get identityNoneNote => 'Even if one is inherited from above';

  @override
  String identitySaveChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Saving changes the $count hosts that use it.',
      one: 'Saving changes the host that uses it.',
    );
    return '$_temp0 A host that sets its own user or keys keeps them.';
  }

  @override
  String identityUsedBy(String who) {
    return 'Used by: $who';
  }

  @override
  String get ignore => 'Ignore';

  @override
  String get importAction => 'Import';

  @override
  String get importAnything => 'Import from another program or ~/.ssh/config';

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
  String get importFromSshConfig => 'Import from ~/.ssh/config';

  @override
  String get importHostsTitle => 'Import hosts';

  @override
  String get importIntoGroup =>
      'They go into the group “~/.ssh/config”. A host brings along the hosts it jumps through.';

  @override
  String get importIntro =>
      'Bring your hosts from another program. They are only read: the original does not change.';

  @override
  String get importKeepsFile =>
      'The file is left as it is, and keys stay where they are: OpenWard keeps the path, never the key.';

  @override
  String get importKey => 'Import a key';

  @override
  String get importKeyAction => 'Import…';

  @override
  String get importKeyIntro =>
      'Paste a private key or choose its file. It is saved as a new file in ~/.ssh; the original stays as it is.';

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
  String get importReportCopied => 'Report copied';

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
  String inWhere(String where) {
    return 'in $where';
  }

  @override
  String get inheritAgain => 'Inherit again';

  @override
  String inheritsFrom(String group) {
    return 'Inherits it from $group';
  }

  @override
  String get inputNotSent => 'What you type now is not sent.';

  @override
  String get inside => 'Inside';

  @override
  String get installKeyAction => 'Put on a server…';

  @override
  String installKeyAdded(String host) {
    return 'Key added on $host';
  }

  @override
  String installKeyFailed(String host) {
    return 'It could not be put on $host';
  }

  @override
  String get installKeyIntro =>
      'Its public half is added to the server\'s ~/.ssh/authorized_keys, as ssh-copy-id does. You sign in once with what you use now.';

  @override
  String get installKeyNext =>
      'To sign in with it, choose it on the host or on its identity.';

  @override
  String get installKeyNoHosts =>
      'No host matches. Type an address to use it without saving it.';

  @override
  String get installKeySearch => 'Find a host, or type user@address';

  @override
  String installKeyTitle(String name) {
    return 'Put $name on a server';
  }

  @override
  String installKeyToAddress(String address) {
    return 'Put it on $address';
  }

  @override
  String installKeyWasThere(String host) {
    return '$host had this key already';
  }

  @override
  String installKeyWriteFailed(String error) {
    return 'The server did not let ~/.ssh/authorized_keys be written: $error';
  }

  @override
  String installingKey(String host) {
    return 'Adding the key on $host…';
  }

  @override
  String itemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get itsPort => 'Its port';

  @override
  String get jobCancelled => 'Cancelled';

  @override
  String get jobCounting => 'Counting…';

  @override
  String jobDone(String size) {
    return 'Done · $size';
  }

  @override
  String get jobFailed => 'Failed';

  @override
  String jobFolder(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'folder, $count files',
      one: 'folder, 1 file',
    );
    return '$_temp0';
  }

  @override
  String jobLost(String done, String total) {
    return 'The connection dropped with $done of $total copied';
  }

  @override
  String jobPaused(String done, String total) {
    return 'Paused · $done of $total';
  }

  @override
  String jobProgress(String done, String total) {
    return '$done of $total';
  }

  @override
  String jobQueued(String size) {
    return 'Queued · $size';
  }

  @override
  String get jobQueuedNoSize => 'Queued';

  @override
  String jobSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count were already there',
      one: '1 was already there',
    );
    return '$_temp0';
  }

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
  String keepaliveEvery(int every, int lost) {
    return 'Every $every s · lost after $lost s';
  }

  @override
  String get keepaliveLabel => 'Check the connection';

  @override
  String get keepaliveOff => 'Never';

  @override
  String keyAdded(String path) {
    return 'Saved as $path.';
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
  String get keyColumn => 'Key';

  @override
  String get keyCommentLabel => 'Comment';

  @override
  String get keyDelete => 'Del';

  @override
  String get keyExchange => 'Key exchange';

  @override
  String keyFailed(String error) {
    return 'It could not be done: $error';
  }

  @override
  String get keyInKnownHosts => 'in ~/.ssh/known_hosts';

  @override
  String get keyInOpenWard => 'saved in OpenWard';

  @override
  String get keyMissing => 'Not on this computer';

  @override
  String keyMissingWarning(String path, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'The $count hosts that use it cannot use that key until you copy it or change the path.',
      one: 'The host that uses it cannot use that key until you copy it or change the path.',
      zero: 'Copy it or change the path before using it.',
    );
    return '$path is not on this computer. $_temp0';
  }

  @override
  String get keyNameInvalid =>
      'That name cannot be a key file: use letters, digits, “-”, “_”, “.” or “@”.';

  @override
  String keyNameTaken(String name) {
    return 'There is a file named $name in ~/.ssh already. Choose another name.';
  }

  @override
  String get keyNoPublicHalf =>
      'No .pub next to it: its type shows when connecting';

  @override
  String get keyNotReadable =>
      'That is not a private key OpenWard can read (OpenSSH, PEM or PuTTY).';

  @override
  String keyNow(String algorithm) {
    return 'Now ($algorithm)';
  }

  @override
  String get keyPerHost => 'One per host (it has %h, %r…)';

  @override
  String keyProtected(String key) {
    return 'The key $key is protected.';
  }

  @override
  String get keyReceived => 'Received';

  @override
  String get keySaved => 'Saved';

  @override
  String get keyType => 'Type';

  @override
  String get keyTypeEcdsa => 'For servers or rules that ask for NIST curves.';

  @override
  String get keyTypeEd25519 =>
      'The one to choose: short, fast, and taken by servers of the last ten years.';

  @override
  String get keyTypeRsa =>
      'For old servers that take nothing newer. It takes a few seconds to make.';

  @override
  String get keys => 'Keys';

  @override
  String get keysHelp =>
      'One path per line. OpenWard keeps the path, never the key.';

  @override
  String get keysInOrder => 'Tried in this order; drag to change it.';

  @override
  String get keysIntro =>
      'The private keys in ~/.ssh. They stay there: the vault only keeps which key each host uses. Here you can make keys, bring in the ones you have and put the public half on a server.';

  @override
  String get kindDynamic => 'Dynamic (-D)';

  @override
  String get kindDynamicShort => 'Dynamic';

  @override
  String get kindLocal => 'Local (-L)';

  @override
  String get kindLocalShort => 'Local';

  @override
  String get kindRemote => 'Remote (-R)';

  @override
  String get kindRemoteShort => 'Remote';

  @override
  String get knownHosts => 'Known hosts';

  @override
  String get knownHostsFileChanged =>
      'The file changed since it was shown. Look at it again before removing anything.';

  @override
  String knownHostsIntro(String file) {
    return 'The server keys you trust. Connecting looks at OpenWard\'s and those in $file; new ones are kept in OpenWard.';
  }

  @override
  String get lanLocalNote =>
      'Anyone on your network can use it while it is open.';

  @override
  String get lanRemoteNote =>
      'The server has to allow it (GatewayPorts in sshd); otherwise it listens only on itself.';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'As the system';

  @override
  String latencyChecks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'the last $count checks',
      one: 'the last check',
    );
    return '$_temp0';
  }

  @override
  String get latencyClick =>
      'A click opens the connection\'s details and its fingerprint.';

  @override
  String latencyHigh(int ms, int times) {
    return '$ms ms: $times times the usual';
  }

  @override
  String latencyUsual(int ms) {
    return 'usual $ms ms';
  }

  @override
  String latencyWith(String host) {
    return 'Latency to $host';
  }

  @override
  String get legendInheritAgain => 'inherits again';

  @override
  String get legendInherited => 'inherited';

  @override
  String get legendSetHere => 'set here';

  @override
  String get library => 'Library';

  @override
  String get licenses => 'Licenses';

  @override
  String get lightAndDark => 'Light and dark';

  @override
  String get lineHeight => 'Terminal line height';

  @override
  String lineNumber(int line) {
    return 'line $line';
  }

  @override
  String linesCount(int count) {
    return '$count lines';
  }

  @override
  String linkNotOpened(String scheme) {
    return '“$scheme:” links are not opened from the terminal.';
  }

  @override
  String localSentence(String here, String dest, String host) {
    return 'What connects to $here reaches $dest as if it came from $host.';
  }

  @override
  String get localShell => 'Local';

  @override
  String get localTerminal => 'Local terminal';

  @override
  String get localUser => 'your local user';

  @override
  String lostKeptInTmux(String host) {
    return 'Your session goes on in tmux on $host: you will find it as it was when it is back. What you type now is not sent.';
  }

  @override
  String lostNewShell(String host) {
    return 'What you type now is not sent. When it is back, a new terminal opens: what was running on $host does not go on.';
  }

  @override
  String madeGroups(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count groups, with their settings',
      one: '1 group, with its settings',
    );
    return '$_temp0';
  }

  @override
  String madeIdentities(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count identities',
      one: '1 identity',
    );
    return '$_temp0';
  }

  @override
  String madeKey(String path) {
    return 'Key saved to $path';
  }

  @override
  String madeKnownHosts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trusted host keys, in Library › Known hosts',
      one: '1 trusted host key, in Library › Known hosts',
    );
    return '$_temp0';
  }

  @override
  String madeSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hosts were there from before and were left as they were',
      one: '1 host was there from before and was left as it was',
    );
    return '$_temp0';
  }

  @override
  String madeSnippets(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count snippets, in Library › Snippets',
      one: '1 snippet, in Library › Snippets',
    );
    return '$_temp0';
  }

  @override
  String madeTunnels(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tunnels, in Library › Tunnels',
      one: '1 tunnel, in Library › Tunnels',
    );
    return '$_temp0';
  }

  @override
  String get makeKey => 'Make the key';

  @override
  String get makingKey => 'Making…';

  @override
  String get manageSnippets => 'Manage snippets…';

  @override
  String get markerCertAuthority =>
      'Certificate authority: trusts the hosts it signs';

  @override
  String get markerRevoked => 'Revoked: always refused';

  @override
  String matchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count match',
      one: '1 matches',
      zero: 'none match',
    );
    return '$_temp0';
  }

  @override
  String matchesHost(String host) {
    return 'Matches $host';
  }

  @override
  String get maximizePane => 'Maximize the pane';

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
  String get missingProxy => 'The proxy needs a server and a port.';

  @override
  String get missingProxyCommand => 'The ProxyCommand is missing.';

  @override
  String get missingSocket => 'The agent socket path is missing.';

  @override
  String get monthsShort => 'Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec';

  @override
  String get moreActions => 'More actions';

  @override
  String get moreOptions => 'More options';

  @override
  String get moveEarlier => 'Move earlier';

  @override
  String get moveLater => 'Move later';

  @override
  String get moveToNewTab => 'Move to a new tab';

  @override
  String get name => 'Name';

  @override
  String nameAndMore(String name, int count) {
    return '$name and $count more';
  }

  @override
  String get nameNoSlash => 'A name cannot contain “/”.';

  @override
  String namesAndMore(String names, int count) {
    return '$names and $count more';
  }

  @override
  String get netLost => 'the connection was lost.';

  @override
  String get netNotFound => 'host not found.';

  @override
  String get netRefused => 'connection refused.';

  @override
  String get netTimeout => 'timed out.';

  @override
  String get newEllipsis => 'New…';

  @override
  String get newFolder => 'New folder';

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
  String get newIdentity => 'New identity';

  @override
  String get newIdentityEllipsis => 'New identity…';

  @override
  String get newKey => 'New key';

  @override
  String get newKeyAction => 'New key…';

  @override
  String newKeyWhere(String private, String public) {
    return 'It is saved as $private (only you can read it), and its public half as $public.';
  }

  @override
  String get newLocalTerminal => 'New local terminal';

  @override
  String get newPane => 'New pane';

  @override
  String get newSnippet => 'New snippet';

  @override
  String get newSubgroup => 'New subgroup';

  @override
  String get newTunnel => 'New tunnel';

  @override
  String get newsConnectionBody =>
      'If the server goes away, it shows within seconds and the connection comes back by itself; with a persistent session, you get back to the same terminal in tmux. While connecting and reconnecting, the way to the host, animated.';

  @override
  String get newsConnectionTitle => 'A connection that stays aware';

  @override
  String get newsEditorBody =>
      'Inherited values show with a dashed border and where they come from; type over one to change it, and ↺ inherits it again. Advanced settings stay folded. The same in groups, and the same grid in identities.';

  @override
  String get newsEditorTitle => 'A clearer host editor';

  @override
  String get newsEnvBody =>
      'Mark a group as Production, Testing or with a name and color of your own: its tabs and terminals say so, so as not to type into the wrong server.';

  @override
  String get newsEnvTitle => 'Each server\'s environment in sight';

  @override
  String get newsFavoritesBody =>
      'The star on hover over a host: at the top of the sidebar, in the rail, in the palette and on the start page, in the order you give them.';

  @override
  String get newsFavoritesTitle => 'Favorites';

  @override
  String newsFocusBody(String keys) {
    return 'The sidebar folds to a rail of icons or hides ($keys), by itself when a session opens if you like, and when hidden it shows as the pointer rests on the edge. Drag its edge to change its width; the terminal has more margin. All in Settings › General.';
  }

  @override
  String get newsFocusTitle => 'More room for the terminal';

  @override
  String get newsFresh => 'new';

  @override
  String get newsHopsBody =>
      'Through a jump host, the latency card tells how long each hop takes, to see which part of the route is slow.';

  @override
  String get newsHopsTitle => 'Each hop\'s latency';

  @override
  String get newsIdentitiesBody =>
      'A user, keys and an agent with a name, for a whole group or several hosts at once.';

  @override
  String get newsIdentitiesTitle => 'Identities';

  @override
  String get newsImportBody =>
      'Hosts, groups, identities and tunnels from Termius, PuTTY, KiTTY, MobaXterm, Tabby or SecureCRT, and hosts from a CSV, from «…» › Import… in the sidebar. Passwords do not come along.';

  @override
  String get newsImportTitle => 'Import from your previous client';

  @override
  String get newsKeysBody =>
      'Make Ed25519, ECDSA or RSA keys, import yours, see their fingerprints and put them on a server without leaving OpenWard, as ssh-copy-id does.';

  @override
  String get newsKeysTitle => 'Keys';

  @override
  String get newsLatencyBody =>
      'The status bar shows how long the server takes to answer, with a chart of the last checks; amber when it rises well above the usual. Hover for the route and the cipher.';

  @override
  String get newsLatencyTitle => 'Latency in sight';

  @override
  String get newsLogoBody =>
      'Umbral, an open O with a chevron: in the app\'s icon and, inside, on the welcome, the start page, About and here, in your theme\'s color.';

  @override
  String get newsLogoTitle => 'A new logo';

  @override
  String get newsMoreThemesBody =>
      'Monitor, with real green letters; Berenjena, with an aubergine terminal; Búnker, all in one phosphor; Marino, green on navy; and Catppuccin, Dracula and Tokyo Night for the whole window. In Settings › Appearance.';

  @override
  String get newsMoreThemesTitle => 'Seven more theme families';

  @override
  String newsPaletteBody(String shortcut) {
    return 'Everything the window does, your hosts, snippets and the commands you ran, a few letters away ($shortcut). The history stays on this computer and never keeps passwords.';
  }

  @override
  String get newsPaletteTitle => 'Command palette and history';

  @override
  String newsPanesBody(String split, String broadcast) {
    return 'Split a tab ($split) or drag another one, or a host, onto a terminal; type into several panes at once ($broadcast). With exit, the tab closes by itself.';
  }

  @override
  String newsPanesBody2(String keys) {
    return 'Dragging a tab onto a terminal no longer moves the window. Each pane\'s menu moves it to its own tab, swaps it or evens the sizes ($keys); a new pane offers the open tabs, each pane has its name and the border between them shows and can be grabbed.';
  }

  @override
  String get newsPanesTitle => 'Panes and broadcast';

  @override
  String get newsPanesTitle2 => 'Panes without guessing';

  @override
  String newsSearchBody(String keys) {
    return '$keys opens the palette with the open tabs, recent connections, hosts, actions and what you ran before. Start with > for actions only.';
  }

  @override
  String get newsSearchTitle => 'One shortcut to find anything';

  @override
  String newsSftpBody(String shortcut) {
    return 'Drag between this computer and the server, with a queue, resuming, and what already exists settled your way ($shortcut).';
  }

  @override
  String get newsSftpTitle => 'Two-pane SFTP';

  @override
  String newsShortcutsBody(String keys) {
    return '$keys opens the list of shortcuts, with search, and buttons tell theirs on hover.';
  }

  @override
  String get newsShortcutsTitle => 'Every shortcut at hand';

  @override
  String newsSidebarBody(String keys) {
    return 'Every host is in Hosts ($keys), with filters by environment, tag and system. The sidebar keeps what you use every day: what is open, the favorites and the recent ones, with the Library in one row; folded to a rail, what is open fits in a counter.';
  }

  @override
  String get newsSidebarTitle => 'Hosts on their own page';

  @override
  String newsSnippetsBody(String shortcut) {
    return 'Commands with variables one shortcut away ($shortcut), and the keys you trust, with those of ~/.ssh/known_hosts.';
  }

  @override
  String get newsSnippetsTitle => 'Snippets and known hosts';

  @override
  String get newsStartBody =>
      'Quick connect completes with your hosts and the addresses you have used; below, recent connections with how long they lasted, and the open tunnels.';

  @override
  String get newsStartTitle => 'A start page to get back to work';

  @override
  String get newsSystemBody2 =>
      'Debian, Ubuntu, Fedora, Alpine and 22 more systems, by their logo in the color of their environment; macOS and Windows, by an icon of their own. For the ones that do not say it when connecting, such as those behind Tailscale SSH, «Find out the system» in their menu reads /etc/os-release; or on every host, from Settings › General.';

  @override
  String get newsSystemTitle2 => 'Each server\'s system, by its logo';

  @override
  String get newsThemesBody =>
      'Five themes in light and dark, layers that mix, text size, minimum contrast and reduced motion.';

  @override
  String get newsThemesTitle => 'Themes and visual accessibility';

  @override
  String get newsTunnelsBody =>
      'Local, remote and SOCKS5, opened on connect; and HTTP and SOCKS5 proxies to reach the server.';

  @override
  String get newsTunnelsTitle => 'Saved tunnels and proxy';

  @override
  String get newsWorkspacesBody =>
      'Save your tabs and panes by name and open them again, connected, from the library or the palette.';

  @override
  String get newsWorkspacesTitle => 'Workspaces';

  @override
  String get next => 'Next';

  @override
  String get no => 'No';

  @override
  String noAnswerFor(int seconds) {
    return 'No answer for $seconds s.';
  }

  @override
  String get noGroup => 'No group';

  @override
  String get noHostsBody => 'Add one or bring them from your ~/⁠.ssh/⁠config.';

  @override
  String get noHostsTitle => 'No hosts yet';

  @override
  String get noIdentities => 'No identities yet';

  @override
  String get noIdentitiesBody =>
      'An identity puts a user, their keys and the agent under a name («deploy in production»). Put it on a group and all its hosts log in the same way; change it once and they all change.';

  @override
  String get noIdentityInherited => 'No group sets one';

  @override
  String get noIdentityNow => 'No identity';

  @override
  String get noJumpsYet => 'None yet.';

  @override
  String get noKeyMatches => 'No key matches.';

  @override
  String get noKeys => 'No keys in ~/.ssh';

  @override
  String get noKeysBody =>
      'Make one with “New key…”, or bring in one you have with “Import…”.';

  @override
  String get noKeysYet =>
      'No keys: the usual ones in ~/.ssh and the agent\'s are tried.';

  @override
  String get noKnownHostMatches => 'No key matches';

  @override
  String get noKnownHosts => 'You trust no keys yet';

  @override
  String get noKnownHostsBody =>
      'Server keys show up here when you connect and trust them.';

  @override
  String noMatches(String filter) {
    return 'Nothing matches “$filter”';
  }

  @override
  String get noParent => 'No group';

  @override
  String get noPostQuantumNote =>
      'The server offers no post-quantum key exchange (mlkem768x25519; OpenSSH has it since 10.0).';

  @override
  String noPublicKey(String name) {
    return '$name has no .pub and is encrypted: its public half cannot be read without the passphrase.';
  }

  @override
  String get noResponse => 'no answer';

  @override
  String get noResults => 'No host matches.';

  @override
  String get noSnippetMatches => 'No snippet matches';

  @override
  String get noSnippets => 'No snippets yet';

  @override
  String noSnippetsBody(String braces) {
    return 'A snippet is a saved command you send to a terminal with a shortcut. What you write between $braces is asked when it runs.';
  }

  @override
  String get noSnippetsYet =>
      'No snippets yet. Make one in Library › Snippets.';

  @override
  String get noTunnels => 'No tunnels yet';

  @override
  String get noTunnelsBody =>
      'A tunnel takes a port of this computer to a service only the server sees (a database, a dashboard), or the other way round. Create one, or bring them from your ~/.ssh/config.';

  @override
  String get noWorkspaces => 'No workspaces yet';

  @override
  String get noWorkspacesBody =>
      'Open the tabs and split the panes as you like them, then keep them with “Save the open tabs…” (also in a tab\'s menu and in the command palette).';

  @override
  String get notNow => 'Not now';

  @override
  String notResponding(String host) {
    return '$host is not responding';
  }

  @override
  String get notSaved => 'not saved';

  @override
  String get notes => 'Notes';

  @override
  String nowIdentity(String identity) {
    return 'Now: $identity';
  }

  @override
  String nowIdentityFromGroup(String identity, String group) {
    return 'Now: $identity, from the group $group';
  }

  @override
  String get nowNoIdentity => 'now: none';

  @override
  String get offerOnlyTheseKeys => 'Offer only these keys';

  @override
  String get offerOnlyTheseKeysNote =>
      'Do not try the agent\'s other keys (IdentitiesOnly). Useful when the server gives up after a few tries.';

  @override
  String get ok => 'OK';

  @override
  String get onConnect => 'On connect';

  @override
  String get onExit => 'When the shell exits';

  @override
  String get onExitAlways => 'Always close';

  @override
  String get onExitClean => 'Close if it ends well';

  @override
  String get onExitHelp =>
      'With exit or logout, the pane (or the tab, if it is the last one) closes by itself. If the program ends with an error, it stays open so you can read what happened, unless “Always close” is on. A connection that drops never closes by itself: it keeps reconnecting.';

  @override
  String get onExitNever => 'Keep it open';

  @override
  String get onSend => 'On send';

  @override
  String get onSessionHide => 'Hidden';

  @override
  String get onSessionKeep => 'As it is';

  @override
  String get onSessionRail => 'Rail';

  @override
  String get onThisComputer => 'On this computer';

  @override
  String get onlyTheServer => 'Only the server';

  @override
  String get onlyThisComputer => 'Only this computer (127.0.0.1)';

  @override
  String get open => 'Open';

  @override
  String get openATerminalFirst => 'Open a terminal to run it';

  @override
  String get openAction => 'Open';

  @override
  String openCount(int count) {
    return '$count open';
  }

  @override
  String get openLocal => 'Open a local terminal';

  @override
  String openOnConnect(String host) {
    return 'Open when connecting to $host';
  }

  @override
  String get openOnConnectNote =>
      'From a terminal or SFTP. If the port is taken, the connection goes on and the tunnel says so.';

  @override
  String get openOtherHere => 'Open something else here…';

  @override
  String get openSection => 'Open';

  @override
  String get openSftp => 'Open SFTP';

  @override
  String openSshStillWarns(String command) {
    return 'OpenWard does not change ~/.ssh/known_hosts: ssh will keep warning until you remove the old key from there ($command).';
  }

  @override
  String openTabsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open tabs',
      one: '1 open tab',
    );
    return '$_temp0';
  }

  @override
  String get openTunnels => 'Open tunnels';

  @override
  String get optionAsAlt => 'Option as Alt';

  @override
  String get optionAsAltHelp =>
      'Option sends Esc + key, as emacs and readline expect, instead of typing symbols like @ or €.';

  @override
  String get orAnAddress => 'or an address: user@host:port';

  @override
  String get orTypeAPath => 'or type a path: ~, %h, %r and %u work';

  @override
  String ownUserWins(String user) {
    return 'It sets its own user ($user), which still wins.';
  }

  @override
  String get paletteActions => 'Actions';

  @override
  String get paletteBroadcast => 'Broadcast in this tab (on or off)';

  @override
  String get paletteChoose => 'choose';

  @override
  String get paletteDo => 'do it';

  @override
  String get paletteForget => 'remove from history';

  @override
  String get paletteHere => 'here';

  @override
  String get paletteHint =>
      'Find a host, a tab, an action or a command you ran…';

  @override
  String get paletteHistory => 'History';

  @override
  String get paletteHosts => 'Hosts';

  @override
  String get paletteNothing => 'Nothing matches.';

  @override
  String get paletteOnlyActions => 'actions only';

  @override
  String get paletteRecent => 'Recent';

  @override
  String get paletteRun => 'run';

  @override
  String get paletteTabs => 'Open tabs';

  @override
  String get paletteTypeOnly => 'type only';

  @override
  String get paneOpenTabs => 'Open tabs';

  @override
  String get paneOpenTabsNote => 'move into this pane';

  @override
  String get paneOptions => 'Pane options';

  @override
  String get paneSearch => 'Search a tab or a host';

  @override
  String get paneWhat => 'What do you open in this pane?';

  @override
  String get partNote =>
      'Files are copied under a temporary name (.part) and renamed at the end: if it is cut short, the real file is never left half written and the copy can be resumed.';

  @override
  String get passphraseField => 'Passphrase';

  @override
  String get passphraseOptional => 'Passphrase (optional)';

  @override
  String get passphraseTitle => 'Key passphrase';

  @override
  String get passphrasesDiffer => 'The two passphrases differ.';

  @override
  String get passwordTitle => 'Password';

  @override
  String get passwordsNever =>
      'Passwords never come along: OpenWard asks for them when connecting.';

  @override
  String get paste => 'Paste';

  @override
  String pasteInPanes(int total) {
    return 'Paste in $total panes';
  }

  @override
  String get pasteMultiBody =>
      'The text has line breaks or other sequences that can run commands when pasted.';

  @override
  String get pasteMultiTitle => 'Paste several lines?';

  @override
  String pasteOnlyHere(String name) {
    return 'Paste only in $name';
  }

  @override
  String get pause => 'Pause';

  @override
  String get pauseAll => 'Pause all';

  @override
  String percent(int number) {
    return '$number%';
  }

  @override
  String permApplied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Permissions changed on $count items',
      one: 'Permissions changed on 1 item',
    );
    return '$_temp0';
  }

  @override
  String permBefore(String mode) {
    return 'Before: $mode';
  }

  @override
  String get permEnter => 'Enter';

  @override
  String get permExecute => 'Execute';

  @override
  String get permGroup => 'Group';

  @override
  String get permOctal => 'Octal';

  @override
  String get permOthers => 'Others';

  @override
  String get permOwner => 'Owner';

  @override
  String get permOwnerNote => 'The owner and the group are not changed here.';

  @override
  String get permRead => 'Read';

  @override
  String get permRecursive => 'Also apply to everything inside';

  @override
  String get permRecursiveNote =>
      'Files keep “Execute” only if they already had it.';

  @override
  String get permWrite => 'Write';

  @override
  String get permissionsEllipsis => 'Permissions…';

  @override
  String permissionsOf(String name) {
    return 'Permissions of $name';
  }

  @override
  String get persistentOff => 'No';

  @override
  String get persistentOn => 'Yes, in tmux: it goes on after a cut';

  @override
  String get persistentSession => 'Persistent session';

  @override
  String get pickIdentity => 'Pick an identity or «None».';

  @override
  String get pinSidebar => 'Keep the sidebar open';

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
  String get portBusyNow => 'taken now';

  @override
  String get portHere => 'Port here';

  @override
  String portOnHost(String host) {
    return 'Port on $host';
  }

  @override
  String get portRange => 'The port goes from 1 to 65535.';

  @override
  String get postQuantum => 'post-quantum';

  @override
  String postQuantumKex(String kex) {
    return '$kex (post-quantum)';
  }

  @override
  String get pressEnterAtTheEnd => 'Press Enter at the end';

  @override
  String get pressEnterAtTheEndNote =>
      'Turn it off to leave the command typed and check it before running it.';

  @override
  String get preview => 'Preview';

  @override
  String previewCannotImport(String protocol) {
    return '$protocol: not usable yet';
  }

  @override
  String previewHostsOf(int selected, int total) {
    return '$selected of $total hosts';
  }

  @override
  String previewIdentities(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count identities',
      one: '1 identity',
    );
    return '$_temp0';
  }

  @override
  String previewIntoExisting(String name) {
    return 'In “$name”, the group of the earlier import';
  }

  @override
  String get previewIntoGroup => 'In the group';

  @override
  String previewKeyFound(String path) {
    return '→ $path · the same public key';
  }

  @override
  String previewKeyMissing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'It is not in ~/.ssh. Without it, the $count that use it have no key.',
      one: 'It is not in ~/.ssh. Without it, what uses it has no key.',
      zero: 'It is not in ~/.ssh.',
    );
    return '$_temp0';
  }

  @override
  String get previewKeys => 'Keys';

  @override
  String previewKnownHosts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count known hosts',
      one: '1 known host',
    );
    return '$_temp0';
  }

  @override
  String get previewLive => 'Changes show at once across the window.';

  @override
  String previewNoPasswords(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'The $count saved passwords and passphrases do not come along: OpenWard asks for them when connecting.',
      one: 'The saved password or passphrase does not come along: OpenWard asks for it when connecting.',
    );
    return '$_temp0';
  }

  @override
  String previewSaveKey(String path) {
    return 'Save it to $path, readable only by you';
  }

  @override
  String previewSnippets(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count snippets',
      one: '1 snippet',
    );
    return '$_temp0';
  }

  @override
  String previewSubtitle(int hosts, int groups) {
    String _temp0 = intl.Intl.pluralLogic(
      hosts,
      locale: localeName,
      other: '$hosts hosts',
      one: '1 host',
    );
    String _temp1 = intl.Intl.pluralLogic(
      groups,
      locale: localeName,
      other: ' in $groups groups',
      one: ' in 1 group',
      zero: '',
    );
    return '$_temp0$_temp1';
  }

  @override
  String previewTitle(String program) {
    return 'Import from $program';
  }

  @override
  String previewTunnels(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tunnels',
      one: '1 tunnel',
    );
    return '$_temp0';
  }

  @override
  String get privateKey => 'Private key';

  @override
  String get protection => 'Protection';

  @override
  String get proxy => 'Proxy';

  @override
  String get proxyHttpNote =>
      'With an HTTP proxy the CONNECT request is not encrypted: the proxy sees which host and port you connect to, not what goes over SSH.';

  @override
  String proxyLoginBody(String proxy) {
    return '$proxy asks for a user and password to let you through. They are not saved.';
  }

  @override
  String get proxyLoginTitle => 'The proxy asks you to log in';

  @override
  String get proxyNone => 'No proxy';

  @override
  String get proxyNotWithCommand =>
      'With a ProxyCommand the proxy is not used.';

  @override
  String get proxyRouteTitle => 'The route becomes';

  @override
  String get proxyServer => 'Proxy server';

  @override
  String get proxyUser => 'Proxy user';

  @override
  String get proxyUserHelp =>
      'Optional. The password is asked for when connecting and not saved.';

  @override
  String publicKeyCopied(String name) {
    return 'Public key of $name copied.';
  }

  @override
  String get queueAllDone => 'All finished';

  @override
  String queueFailed(int count) {
    return '$count failed';
  }

  @override
  String queuePaused(int count) {
    return '$count paused';
  }

  @override
  String queueQueued(int count) {
    return '$count queued';
  }

  @override
  String queueRunning(int count) {
    return '$count running';
  }

  @override
  String get quickConnectHint => 'user@server:port or a host\'s name';

  @override
  String get quickConnectInvalid => 'Type an address like user@server:port.';

  @override
  String get readFailedTitle => 'Could not read it';

  @override
  String readFormat(String program, String message) {
    return 'It is $program’s, but not as expected: $message';
  }

  @override
  String get readNotRecognized =>
      'Which program it comes from is not recognized. Choose the one PuTTY (.reg), MobaXterm (.mxtsessions) or SecureCRT (.xml) exports, or Tabby’s config.yaml.';

  @override
  String get readOsRelease => 'Read /etc/os-release';

  @override
  String get readOsReleaseEverywhere => 'Read /etc/os-release on every host';

  @override
  String get readOsReleaseEverywhereHelp =>
      'To tell the system of the servers that do not say it when connecting. It runs a command on each one; a host or a group can turn it off. On this device only.';

  @override
  String get readOsReleaseNote =>
      'To tell the system better; it runs a command on the server. Off, nothing runs.';

  @override
  String get readOsReleaseOff => 'No';

  @override
  String get readOsReleaseOn => 'Yes, when connecting';

  @override
  String get readTermius => 'Read Termius';

  @override
  String get readTermiusKeychain =>
      'The system did not let OpenWard use Termius’s key from the keychain. Try again and choose “Allow”.';

  @override
  String get readTermiusNoKey =>
      'Termius’s key is not in the keychain. Open Termius once on this computer and try again.';

  @override
  String get readTermiusNotFound =>
      'There is no Termius data on this computer.';

  @override
  String get readTermiusWrongKey =>
      'The keychain’s key does not open Termius’s data; Termius may have changed its format. Nothing was imported.';

  @override
  String readUnreadable(String message) {
    return 'Could not read it: $message';
  }

  @override
  String get readingFile => 'Reading the file…';

  @override
  String readingProgram(String program) {
    return 'Reading $program’s data…';
  }

  @override
  String get readyBody => 'These shortcuts get you almost everywhere:';

  @override
  String get readyTitle => 'All set';

  @override
  String get receives => 'Receives';

  @override
  String get recentConnections => 'Recent connections';

  @override
  String get recentConnectionsHelp =>
      'The connections you open are kept on this device (never in the vault) to go back to them from the palette. Local terminals are not.';

  @override
  String get recentEmptyBody =>
      'What you open shows here, with when and for how long, to go back with a click.';

  @override
  String get recentEmptyTitle => 'No connections yet';

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
  String get reimportNote =>
      'If you import again, what you brought before stays as it is, with your changes. Only what is new comes in.';

  @override
  String get reload => 'Reload';

  @override
  String remoteSentence(String host, String port, String dest) {
    return 'What connects on $host to port $port reaches $dest on this computer.';
  }

  @override
  String get remove => 'Remove';

  @override
  String get removeCertificate => 'Remove the certificate';

  @override
  String get removeFavorite => 'Remove from favorites';

  @override
  String get removeKey => 'Remove the key';

  @override
  String removeTag(String tag) {
    return 'Remove $tag';
  }

  @override
  String get removeTheLine => 'Remove the line';

  @override
  String get rename => 'Rename';

  @override
  String get renameTab => 'Rename…';

  @override
  String get renameTabHelp => 'Empty to go back to the host\'s name';

  @override
  String get renameTabTitle => 'Rename tab';

  @override
  String renameTitle(String name) {
    return 'Rename $name';
  }

  @override
  String get renameWorkspace => 'Rename the workspace';

  @override
  String get repeatPassphrase => 'Again';

  @override
  String get reportCopied => 'Copied. Paste it in your report.';

  @override
  String get reportCore => 'core';

  @override
  String reportCounts(
    int hosts,
    int groups,
    int tunnels,
    int identities,
    int snippets,
  ) {
    return 'Hosts: $hosts · groups: $groups · tunnels: $tunnels · identities: $identities · snippets: $snippets';
  }

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
  String get reportHow =>
      'Paste it in the issue with what you were doing, what you expected and what happened, as the test guide asks.';

  @override
  String get reportNotEverything => 'Not everything could be brought in:';

  @override
  String get reportProblem => 'Report a problem';

  @override
  String get reportProblemEllipsis => 'Report a problem…';

  @override
  String get reportProblemHint =>
      'Copies the version and the system to paste in your report.';

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
  String get reportText => 'text';

  @override
  String get reportTheme => 'Theme';

  @override
  String reportTitle(int count, String program) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hosts imported from $program',
      one: '1 host imported from $program',
      zero: 'Nothing new from $program',
    );
    return '$_temp0';
  }

  @override
  String reportTunnels(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new tunnels',
      one: '1 new tunnel',
    );
    return '$_temp0';
  }

  @override
  String get reportWhat =>
      'This is what gets copied. It has no hosts, addresses, users or keys.';

  @override
  String get reportWhere => 'They are in the group “~/.ssh/config”.';

  @override
  String reportWhere2(String group) {
    return 'They are in the “$group” group of the sidebar, with its subgroups.';
  }

  @override
  String get resetTheme => 'Reset';

  @override
  String get restart => 'Restart';

  @override
  String get restorePanes => 'Back to the panes';

  @override
  String get resume => 'Resume';

  @override
  String get retry => 'Retry';

  @override
  String retryIn(int attempt, int max, int secs) {
    return 'Try $attempt of $max in $secs s.';
  }

  @override
  String get retryNow => 'Retry now';

  @override
  String get review => 'Review';

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
  String get runEllipsis => 'Run…';

  @override
  String get runIn => 'Run in…';

  @override
  String runSnippetBroadcast(int count) {
    return 'Goes to the $count panes that receive the broadcast';
  }

  @override
  String get runSnippetHint => 'Fill in what it asks. It is not saved.';

  @override
  String runSnippetIn(String where) {
    return 'In $where';
  }

  @override
  String runSnippetTitle(String name) {
    return 'Run «$name»';
  }

  @override
  String get sameHost => 'the same host';

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
  String get saveAndOpen => 'Save and open';

  @override
  String get saveAs => 'Save as';

  @override
  String get saveAsHost => 'Save as a host…';

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
  String get saveOpenTabs => 'Save the open tabs…';

  @override
  String get saveTabsNeedsTabs => 'Open a tab to be able to save it.';

  @override
  String get saveWorkspaceIntro =>
      'The open terminal and file tabs, with their panes. When it opens, each pane connects again.';

  @override
  String get saveWorkspaceTitle => 'Save as a workspace';

  @override
  String get savedHost => 'Saved host';

  @override
  String get scrollback => 'Scrollback';

  @override
  String get scrollbackHelp => 'For new tabs.';

  @override
  String scrollbackLines(String lines) {
    return '$lines lines';
  }

  @override
  String get search => 'Search';

  @override
  String get searchHosts => 'Search hosts';

  @override
  String get searchKeys => 'Search by name, fingerprint or host';

  @override
  String get searchKnownHosts => 'Search a host, a fingerprint…';

  @override
  String get sectionConnection => 'Connection';

  @override
  String get sectionEnvironment => 'Environment';

  @override
  String get sectionGeneral => 'General';

  @override
  String get sectionSystem => 'System';

  @override
  String seenFrom(String host) {
    return 'as $host sees it';
  }

  @override
  String get seenFromHere => 'as this computer sees it';

  @override
  String get selectAll => 'All';

  @override
  String get selectAllText => 'Select all';

  @override
  String selectedCount(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected ($size)',
      one: '1 selected ($size)',
    );
    return '$_temp0';
  }

  @override
  String selectedCountOnly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected',
      one: '1 selected',
    );
    return '$_temp0';
  }

  @override
  String selectedOf(int selected, int total) {
    return '$selected of $total';
  }

  @override
  String get sendAction => 'Send';

  @override
  String sendToPanes(int count) {
    return 'Send to $count panes';
  }

  @override
  String get separatePanes => 'Split the panes into tabs';

  @override
  String get sessionClosed => 'Session closed.';

  @override
  String sessionClosedCode(int code) {
    return 'Session closed (code $code).';
  }

  @override
  String get sessionResumed => 'tmux session found again';

  @override
  String get setHereHint => 'A click sets it here only';

  @override
  String setHereIdentitySays(String value) {
    return 'Set here; the identity says $value';
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
  String get settingsWindow => 'Window';

  @override
  String sftpConnected(String label) {
    return 'SFTP on $label';
  }

  @override
  String get sftpKeysApple =>
      'Return opens · ⌘↑ goes up · Tab switches side · F2 renames · ⌘⌫ deletes';

  @override
  String get sftpKeysOther =>
      'Enter opens · Backspace goes up · Tab switches side · F2 renames · Del deletes';

  @override
  String sftpTabTitle(String label) {
    return 'SFTP · $label';
  }

  @override
  String get shape => 'Shape';

  @override
  String get shiftPrefix => 'Shift+';

  @override
  String get shortcutAll => 'all shortcuts';

  @override
  String get shortcutConnectTyped =>
      'Connect to what you typed, on the start page';

  @override
  String get shortcutFindNewer => 'Next match, further down';

  @override
  String get shortcutFindOlder => 'Previous match, further up';

  @override
  String get shortcutGoToPane => 'Go to the pane in that direction';

  @override
  String get shortcutGoToTab => 'Go to tab 1 to 8';

  @override
  String get shortcutHosts => 'All hosts, on their page';

  @override
  String get shortcutLastTab => 'Go to the last tab';

  @override
  String get shortcutLocal => 'Opens a local terminal';

  @override
  String get shortcutNewHost => 'Saves a new host';

  @override
  String get shortcutNextTab => 'Next tab';

  @override
  String get shortcutPalette => 'Search everything: hosts, tabs and actions';

  @override
  String get shortcutPermissions => 'Permissions';

  @override
  String get shortcutPreviousTab => 'Previous tab';

  @override
  String get shortcutSearch => 'Searches your hosts';

  @override
  String get shortcutSettings => 'Opens the settings';

  @override
  String get shortcutSidebar => 'sidebar';

  @override
  String get shortcutSwitchSide => 'Switch to the other side';

  @override
  String get shortcutTextBigger => 'Larger text in the tab';

  @override
  String get shortcutTextReset => 'Usual text size';

  @override
  String get shortcutTextSmaller => 'Smaller text in the tab';

  @override
  String get shortcutsForms => 'Editors and dialogs';

  @override
  String shortcutsNone(String query) {
    return 'No shortcut matches “$query”';
  }

  @override
  String get shortcutsPanes => 'Panes';

  @override
  String get shortcutsSearch => 'Search an action or a key';

  @override
  String get shortcutsTabs => 'Tabs';

  @override
  String get shortcutsTerminal => 'Terminal';

  @override
  String get shortcutsTitle => 'Keyboard shortcuts';

  @override
  String get shortcutsWindow => 'Window';

  @override
  String get showHiddenFiles => 'Show hidden files';

  @override
  String get showQueue => 'Show queue';

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
  String get showSidebar => 'Show the sidebar';

  @override
  String get sidebarHelp =>
      'Remembered when OpenWard closes. Hidden, it shows when the pointer rests on the window\'s left edge.';

  @override
  String get sidebarHidden => 'Hidden';

  @override
  String get sidebarOnSession => 'With a terminal in front';

  @override
  String get sidebarOnSessionHelp =>
      'With a terminal or file tab in front, the sidebar can fold by itself. On the start page and the library pages it is as set above.';

  @override
  String get sidebarOpen => 'Open';

  @override
  String get sidebarRail => 'Rail';

  @override
  String get sidebarSearchHint => 'Search or connect…';

  @override
  String get sidebarSetting => 'Sidebar';

  @override
  String get sidebarWidth => 'Sidebar width';

  @override
  String get sidebarWidthHelp =>
      'Drag the sidebar\'s edge to change it, between 220 and 420 px. A double click on the edge resets it.';

  @override
  String sinceSeconds(int seconds) {
    return 'for $seconds s';
  }

  @override
  String get skipGuide => 'Skip the guide';

  @override
  String get snippetEditorHint =>
      'Commands you send to a terminal; what goes between braces is asked.';

  @override
  String get snippetNeedsCommand => 'Write the command.';

  @override
  String get snippetNeedsName => 'Give it a name.';

  @override
  String get snippetNoSecrets =>
      'It is kept without secrets, like the rest of the vault. What you type when it runs is not kept.';

  @override
  String get snippetTypeOnlyNote => 'It is left typed, without pressing Enter.';

  @override
  String get snippetWithEnter => 'With Enter at the end.';

  @override
  String get snippets => 'Snippets';

  @override
  String snippetsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count snippets',
      one: '1 snippet',
    );
    return '$_temp0';
  }

  @override
  String snippetsHowToRun(String shortcut) {
    return 'In a terminal: $shortcut or the «Snippets» button of the status bar. With broadcast, they go to every pane that receives.';
  }

  @override
  String snippetsIntro(String braces) {
    return 'Saved commands you send to a terminal with a shortcut. What goes between $braces is asked when it runs.';
  }

  @override
  String get splitDown => 'Split down';

  @override
  String get splitRight => 'Split right';

  @override
  String splitWith(String name) {
    return 'Split with $name';
  }

  @override
  String get splitWithNote => 'right of the active pane';

  @override
  String stageAuthenticating(String label, String hop) {
    return 'Signing in to $label$hop…';
  }

  @override
  String stageConnecting(String label, String hop) {
    return 'Connecting to $label$hop…';
  }

  @override
  String stageOpeningSftp(String label) {
    return 'Opening SFTP on $label…';
  }

  @override
  String stageOpeningShell(String label) {
    return 'Opening the shell on $label…';
  }

  @override
  String get start => 'Get started';

  @override
  String get startAction => 'Start';

  @override
  String get startHere => 'Start here';

  @override
  String get startShortcutHosts => 'all hosts';

  @override
  String get startShortcutLocal => 'local terminal';

  @override
  String get startShortcutNewHost => 'new host';

  @override
  String get startShortcutSearch => 'search';

  @override
  String get startTitle => 'Start';

  @override
  String get starting => 'Starting…';

  @override
  String get state => 'State';

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
  String get statusStalled => 'No answer · checking…';

  @override
  String get stepAppearance => 'Appearance';

  @override
  String get stepAuthenticating => 'signing in…';

  @override
  String get stepConnecting => 'connecting…';

  @override
  String get stepImport => 'Import';

  @override
  String get stepOpeningSftp => 'opening SFTP…';

  @override
  String get stepOpeningShell => 'opening the shell…';

  @override
  String get stepReady => 'Done';

  @override
  String get stopAction => 'Stop';

  @override
  String swapWith(String name) {
    return 'Swap with $name';
  }

  @override
  String get systemByBanner => 'From the server\'s banner:';

  @override
  String get systemByOsRelease => 'From /etc/os-release:';

  @override
  String get systemDetectAgain => 'Tell it again when connecting';

  @override
  String get systemIcon => 'System icon';

  @override
  String get systemManual => 'Chosen by hand';

  @override
  String systemNotTold(String name) {
    return '“$name” does not tell its system when connecting.';
  }

  @override
  String get systemNotYet => 'Connecting will tell, from the server\'s banner.';

  @override
  String systemOnNextConnection(String name) {
    return 'It will be read when connecting to “$name”.';
  }

  @override
  String systemStillUnknown(String name) {
    return '“$name” does not say it in /etc/os-release either.';
  }

  @override
  String systemTold(String name, String system) {
    return '“$name” runs $system.';
  }

  @override
  String get systemUnknown => 'Unknown';

  @override
  String get systemUnknownYet => 'Not known yet';

  @override
  String get tabMenuHint =>
      'You can also drag the tab onto a terminal to split it, or elsewhere in the bar to reorder it.';

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
  String get terminalMenuHint =>
      'Drag a tab or a host here to open it in one half of this pane.';

  @override
  String get terminalPadding => 'Terminal margin';

  @override
  String get terminalPaddingHelp => 'Room around the text, in every pane.';

  @override
  String get terminalScheme => 'Own scheme';

  @override
  String terminalShortcuts(String key) {
    return '${key}F searches the terminal and its history. $key+ and $key− size the tab\'s text, and ${key}0 resets it. Holding $key, a click opens a link.';
  }

  @override
  String get termiusBrings => 'Comes along';

  @override
  String get termiusBringsHosts =>
      'Hosts and nested groups, with their settings';

  @override
  String get termiusBringsIdentities => 'Identities: user and key';

  @override
  String get termiusBringsSnippets => 'Snippets, tags and known hosts';

  @override
  String get termiusBringsTunnels => 'Tunnels and proxy';

  @override
  String get termiusIntro =>
      'Termius keeps your hosts encrypted on this computer, with the key in the keychain. To read them, the system will ask you first: “Allow” is enough for this time.';

  @override
  String get termiusLeaves => 'Does not come along';

  @override
  String get termiusLeavesChains => 'Host chains: add them by hand';

  @override
  String get termiusLeavesKeys =>
      'Private keys: the same one is looked for in ~/.ssh, or saved there if you ask';

  @override
  String get termiusLeavesPasswords => 'Passwords and passphrases';

  @override
  String get termiusLeavesTelnet =>
      'Telnet or serial hosts; Mosh ones come in as SSH';

  @override
  String get termiusReadOnly =>
      'It only reads: Termius is not changed and may stay open.';

  @override
  String get termiusTitle => 'Read Termius’s data';

  @override
  String get termiusUnofficial =>
      'This is not a Termius feature: OpenWard understands its format, and a new version of Termius may change it. If something is not understood, nothing is half-imported and you are told.';

  @override
  String get textSize => 'Text size';

  @override
  String get textSizeHelp =>
      'Of the interface, on top of the system\'s. The terminal has its own.';

  @override
  String get theHost => 'the host';

  @override
  String get theLocalNetwork => 'The whole local network';

  @override
  String get theServerNetwork => 'The server\'s network';

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
  String timeLeft(String time) {
    return '$time left';
  }

  @override
  String get tmuxMissing => 'no tmux';

  @override
  String get tmuxMissingTip =>
      'tmux is not on this server: the terminal does not survive a cut. Install it to keep the session.';

  @override
  String get tmuxTip =>
      'The terminal runs in tmux on the server: it goes on after a cut. The wheel scrolls its history; Shift and drag selects text.';

  @override
  String get toStart => 'To start';

  @override
  String todayAt(String time) {
    return 'today $time';
  }

  @override
  String get toggleSidebar => 'Fold or show the sidebar';

  @override
  String get transfers => 'Transfers';

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
  String trustedOn(String date) {
    return 'trusted on $date';
  }

  @override
  String get tryAgain => 'Try again';

  @override
  String get tryAnother => 'Try another';

  @override
  String get tunnelBadAddress =>
      'That address does not exist on this computer.';

  @override
  String get tunnelClosed => 'Stopped';

  @override
  String tunnelDidNotOpen(String name, String why) {
    return '«$name» did not open on connect: $why';
  }

  @override
  String get tunnelEditorHint =>
      'A port of this computer that leads to a service only the server sees, or the other way round.';

  @override
  String get tunnelFailed => 'Did not open';

  @override
  String get tunnelLost => 'Dropped';

  @override
  String tunnelLostBody(String host) {
    return 'The connection to $host was lost. Open it again once it is back.';
  }

  @override
  String get tunnelNeedsDest => 'It needs a destination and its port.';

  @override
  String get tunnelNeedsHost => 'Pick the host it goes through.';

  @override
  String get tunnelNeedsName => 'Give it a name.';

  @override
  String get tunnelOpen => 'Open';

  @override
  String tunnelOpenWith(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Open · $count connections',
      one: 'Open · 1 connection',
    );
    return '$_temp0';
  }

  @override
  String get tunnelOpening => 'Opening…';

  @override
  String tunnelPortBusy(int port) {
    return 'port $port on this computer is taken.';
  }

  @override
  String tunnelRemotePortBusy(int port, String host) {
    return '$host did not open port $port (in use or not allowed).';
  }

  @override
  String get tunnelType => 'Type';

  @override
  String tunnelVia(String host) {
    return 'through $host';
  }

  @override
  String get tunnels => 'Tunnels';

  @override
  String tunnelsCount(int total, int open) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total tunnels',
      one: '1 tunnel',
    );
    return '$_temp0 · $open open';
  }

  @override
  String get tunnelsIntro =>
      'Saved port forwards, each with a host. They open by hand or when connecting to the host, over the same connection as the terminal.';

  @override
  String get tunnelsKeepConnection =>
      'An open tunnel keeps its host\'s connection even if you close the tab. It closes when you close it here or quit OpenWard.';

  @override
  String tunnelsOf(String host) {
    return 'Tunnels of $host';
  }

  @override
  String tunnelsOpenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tunnels open',
      one: '1 tunnel open',
    );
    return '$_temp0';
  }

  @override
  String get tunnelsStayOpen =>
      'They stay open if you close this tab. All of them in Library › Tunnels.';

  @override
  String twoNames(String a, String b) {
    return '$a and $b';
  }

  @override
  String get typeAndFingerprint => 'Type and fingerprint';

  @override
  String get typeOnly => 'Types only';

  @override
  String get uiColors => 'Interface colors';

  @override
  String get uiFont => 'Interface font';

  @override
  String get unknownKeyType => 'Unknown type';

  @override
  String get upOneLevel => 'Up one level';

  @override
  String get updateWithOpenTabs => 'Replace with the open tabs';

  @override
  String get upload => 'Upload';

  @override
  String uploadToArrow(String where) {
    return 'Upload to $where →';
  }

  @override
  String uploadToHost(String host) {
    return 'Upload to $host';
  }

  @override
  String get useIdentityHint =>
      'Tick groups or hosts. A group passes it on to all its hosts, also those you add later.';

  @override
  String useIdentityOn(String name) {
    return 'Use «$name» on…';
  }

  @override
  String useIdentitySummary(int changed, int using) {
    String _temp0 = intl.Intl.pluralLogic(
      changed,
      locale: localeName,
      other: '$changed hosts change',
      one: '1 host changes',
      zero: 'No host changes',
    );
    String _temp1 = intl.Intl.pluralLogic(
      using,
      locale: localeName,
      other: '$using will use it',
      one: '1 will use it',
      zero: 'none will use it',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get useOn => 'Use on…';

  @override
  String usePort(int port) {
    return 'Use $port';
  }

  @override
  String get usedBy => 'Used by';

  @override
  String get usedByNobody => 'Nobody uses it yet';

  @override
  String usedNotSaved(String ago) {
    return 'connected before, not saved · $ago';
  }

  @override
  String get user => 'User';

  @override
  String get usualKeys => 'the usual ones';

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
  String warnFeature(String host, String feature) {
    return '$host: $feature did not come along.';
  }

  @override
  String warnFeatureGeneral(String feature) {
    return '$feature did not come along.';
  }

  @override
  String get warnHostChain =>
      'Termius’s host chains did not come along: add the jumps by hand on each host.';

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
  String warnMosh(String host) {
    return '$host used Mosh: it will connect over SSH.';
  }

  @override
  String warnPartlyUnreadable(String detail) {
    return 'Part of the data could not be read: $detail.';
  }

  @override
  String warnShared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items shared from a team cannot be read on this computer.',
      one: '1 item shared from a team cannot be read on this computer.',
    );
    return '$_temp0';
  }

  @override
  String warnStartupCommand(String host) {
    return '$host ran a command on connect; OpenWard does not do that on its own yet.';
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
  String warnValue(String host, String field, String value) {
    return '$host: the value “$value” of $field is not valid and did not come along.';
  }

  @override
  String get welcomeNoConfig =>
      'We found no hosts in ~/.ssh/config. You can add them by hand in a moment.';

  @override
  String get welcomeTitle => 'Welcome to OpenWard';

  @override
  String get whatsNew => 'What\'s new';

  @override
  String get whatsNewIntro =>
      'All you did with your previous client, here now. You see this once; it is also in Settings › General.';

  @override
  String get whatsNewReport =>
      'Something wrong? Settings › General › Report a problem copies what it takes to tell.';

  @override
  String get whereItIs => 'Where it is';

  @override
  String get whoCanUse => 'Who can use it';

  @override
  String get withCertificate => 'with certificate';

  @override
  String get withEnter => 'Enter at the end';

  @override
  String get withPassphrase => 'Passphrase';

  @override
  String get withoutPassphrase => 'No passphrase';

  @override
  String workspaceNumbered(int number) {
    return 'Workspace $number';
  }

  @override
  String workspaceSaved(String name) {
    return '“$name” saved.';
  }

  @override
  String workspaceSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions',
      one: '1 session',
    );
    return '$_temp0';
  }

  @override
  String workspaceTabs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tabs',
      one: '1 tab',
    );
    return '$_temp0';
  }

  @override
  String workspaceUpdated(String name) {
    return '“$name” now has the open tabs.';
  }

  @override
  String get workspaces => 'Workspaces';

  @override
  String get workspacesIntro =>
      'Tabs and panes saved by name, to open again together. What each pane connects to is kept, never what it showed.';

  @override
  String get wrongAnswer => 'Wrong answer.';

  @override
  String get wrongPassphrase => 'Wrong passphrase.';

  @override
  String get wrongPassword => 'Wrong password.';

  @override
  String get yes => 'Yes';

  @override
  String yesterdayAt(String time) {
    return 'yesterday $time';
  }
}
