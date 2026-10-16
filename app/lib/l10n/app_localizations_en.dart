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
  String get addCertificate => '+ Add a certificate';

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
  String get alreadyImported => 'already imported';

  @override
  String get alreadyUses => 'Already uses it';

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
  String get back => 'Back';

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
  String get checkedFingerprint => 'I have checked the new fingerprint';

  @override
  String get choiceKeepBoth => 'Keep both';

  @override
  String get choiceNewer => 'Only if mine is newer';

  @override
  String get choiceReplace => 'Replace';

  @override
  String get choiceSkip => 'Skip';

  @override
  String get cipher => 'Cipher';

  @override
  String get clear => 'Reset';

  @override
  String get clearFinished => 'Clear finished';

  @override
  String get clearSelection => 'Clear the selection';

  @override
  String get close => 'Close';

  @override
  String get closeAction => 'Close';

  @override
  String get closePane => 'Close the pane';

  @override
  String get closeTab => 'Close tab';

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
  String get connectingEllipsis => 'Connecting…';

  @override
  String connectingTo(String label) {
    return 'Connecting to $label';
  }

  @override
  String get connectionDetails => 'Connection details';

  @override
  String get connectionHint =>
      'What you don\'t change here is inherited; inherited values have a dashed border and say below where they come from. What the host sets wins, then its identity, then its groups and, last, the defaults.';

  @override
  String connectionLost(String label, String why) {
    return 'The connection to $label was lost$why.';
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
  String get copyAddress => 'Copy address';

  @override
  String get copyFingerprint => 'Copy the fingerprint';

  @override
  String get copyPath => 'Copy path';

  @override
  String get create => 'Create';

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
  String get deletedHost => '(deleted host)';

  @override
  String get deletedIdentity => '(deleted identity)';

  @override
  String get destination => 'Destination';

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
  String get dropAskFirst =>
      'If something already exists, you are asked before it is touched.';

  @override
  String get dropToDownload => 'Drop to download here';

  @override
  String get dropToUpload => 'Drop to upload here';

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
  String get editTheIdentity => 'Edit the identity';

  @override
  String get editTunnel => 'Edit tunnel';

  @override
  String get emptyFolder => 'This folder is empty';

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
  String failureNoSftp(String label) {
    return '$label has no SFTP: the server lacks sftp-server.';
  }

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
  String fileNotFound(String path) {
    return 'Not found: $path';
  }

  @override
  String get filterFolder => 'Filter this folder';

  @override
  String get filterHostsAndGroups => 'Filter hosts and groups';

  @override
  String get filterIdentities => 'Filter by name, user or key';

  @override
  String get filterTunnels => 'Filter by name, host or port';

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
  String get forAll => 'For all:';

  @override
  String get forward => 'Forward';

  @override
  String get fromDefault => 'Default value';

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
  String get hostsSection => 'Hosts';

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
  String inheritsFrom(String group) {
    return 'Inherits it from $group';
  }

  @override
  String get inputNotSent => 'What you type now is not sent.';

  @override
  String get inside => 'Inside';

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
  String get keyNoPublicHalf =>
      'No .pub next to it: its type shows when connecting';

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
  String get keys => 'Keys';

  @override
  String get keysHelp =>
      'One path per line. OpenWard keeps the path, never the key.';

  @override
  String get keysInOrder => 'Tried in this order; drag to change it.';

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
  String get library => 'Library';

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
  String localSentence(String here, String dest, String host) {
    return 'What connects to $here reaches $dest as if it came from $host.';
  }

  @override
  String get localTerminal => 'Local terminal';

  @override
  String get localUser => 'your local user';

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
  String get newLocalTerminal => 'New local terminal';

  @override
  String get newPane => 'New pane';

  @override
  String get newSubgroup => 'New subgroup';

  @override
  String get newTunnel => 'New tunnel';

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
  String get noKeysYet =>
      'No keys: the usual ones in ~/.ssh and the agent\'s are tried.';

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
  String get noResults => 'No host matches.';

  @override
  String get noTunnels => 'No tunnels yet';

  @override
  String get noTunnelsBody =>
      'A tunnel takes a port of this computer to a service only the server sees (a database, a dashboard), or the other way round. Create one, or bring them from your ~/.ssh/config.';

  @override
  String get notNow => 'Not now';

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
  String get onlyTheServer => 'Only the server';

  @override
  String get onlyThisComputer => 'Only this computer (127.0.0.1)';

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
  String get openSftp => 'Open SFTP';

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
  String get orTypeAPath => 'or type a path: ~, %h, %r and %u work';

  @override
  String ownUserWins(String user) {
    return 'It sets its own user ($user), which still wins.';
  }

  @override
  String get paneOptions => 'Pane options';

  @override
  String get paneWhat => 'What do you open in this pane?';

  @override
  String get partNote =>
      'Files are copied under a temporary name (.part) and renamed at the end: if it is cut short, the real file is never left half written and the copy can be resumed.';

  @override
  String get passphraseField => 'Passphrase';

  @override
  String get passphraseTitle => 'Key passphrase';

  @override
  String get passwordTitle => 'Password';

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
  String get pickIdentity => 'Pick an identity or «None».';

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
  String get preview => 'Preview';

  @override
  String get previewLive => 'Changes show at once across the window.';

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
  String get quickConnectHint => 'user@server:port';

  @override
  String get quickConnectInvalid => 'Type an address like user@server:port.';

  @override
  String get readyBody => 'These shortcuts get you almost everywhere:';

  @override
  String get readyTitle => 'All set';

  @override
  String get receives => 'Receives';

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
  String get removeKey => 'Remove the key';

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
  String renameTitle(String name) {
    return 'Rename $name';
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
  String get reportWhere => 'They are in the group “~/.ssh/config”.';

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
  String get sessionClosed => 'Session closed.';

  @override
  String sessionClosedCode(int code) {
    return 'Session closed (code $code).';
  }

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
  String get shortcutLocal => 'Opens a local terminal';

  @override
  String get shortcutNewHost => 'Saves a new host';

  @override
  String get shortcutSearch => 'Searches your hosts';

  @override
  String get shortcutSettings => 'Opens the settings';

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
  String get skipGuide => 'Skip the guide';

  @override
  String get splitDown => 'Split down';

  @override
  String get splitRight => 'Split right';

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
  String get startHere => 'Start here';

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
  String todayAt(String time) {
    return 'today $time';
  }

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
  String get tryAgain => 'Try again';

  @override
  String get tunnelBadAddress =>
      'That address does not exist on this computer.';

  @override
  String get tunnelClosed => 'Closed';

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
  String get uiColors => 'Interface colors';

  @override
  String get uiFont => 'Interface font';

  @override
  String get upOneLevel => 'Up one level';

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
  String get whoCanUse => 'Who can use it';

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
