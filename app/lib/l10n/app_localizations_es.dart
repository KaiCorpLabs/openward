// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get about => 'Acerca de';

  @override
  String aboutVersion(String version) {
    return 'OpenWard $version';
  }

  @override
  String get accessibility => 'Accesibilidad';

  @override
  String get add => 'Añadir';

  @override
  String get addCertificate => '+ Añadir certificado';

  @override
  String get addKeyEllipsis => 'Añadir clave…';

  @override
  String get addSavedHost => 'Añadir un host guardado';

  @override
  String get addTag => 'Añadir';

  @override
  String get address => 'Dirección';

  @override
  String get addressHint => 'servidor.example.com o 10.0.0.5';

  @override
  String get agent => 'Agente SSH';

  @override
  String get agentNone => 'Ninguno';

  @override
  String get agentOtherSocket => 'Otro socket';

  @override
  String get agentShort => 'Agente';

  @override
  String get agentSocket => 'Otro socket…';

  @override
  String get agentSystem => 'El del sistema';

  @override
  String allCount(int count) {
    return 'Todas · $count';
  }

  @override
  String get alreadyImported => 'ya importado';

  @override
  String get alreadyUses => 'Ya la usa';

  @override
  String announceClosed(String name) {
    return '$name: desconectado';
  }

  @override
  String announceConnected(String name) {
    return '$name: conectado';
  }

  @override
  String announceFailed(String name, String why) {
    return '$name: no se pudo conectar. $why';
  }

  @override
  String announcePrompt(String name) {
    return '$name pregunta algo antes de seguir';
  }

  @override
  String announceReconnecting(String name) {
    return '$name: se cortó, reconectando';
  }

  @override
  String announceTunnelFailed(String name, String why) {
    return 'El túnel «$name» no se abrió: $why';
  }

  @override
  String announceTunnelLost(String name) {
    return 'Se cortó el túnel «$name»';
  }

  @override
  String announceTunnelOpen(String name, int port) {
    return 'Túnel «$name» abierto en el puerto $port';
  }

  @override
  String get anyDestination => 'Cualquier destino';

  @override
  String get appearanceStepBody =>
      'Puedes cambiarlo cuando quieras en Ajustes.';

  @override
  String get appearanceStepTitle => '¿Cómo la quieres ver?';

  @override
  String get apply => 'Aplicar';

  @override
  String get asSystem => 'Como el sistema';

  @override
  String get askedWhenRun => 'Se pregunta al ejecutarlo';

  @override
  String get askedWhenRunHint => 'Sale de lo que escribes entre llaves.';

  @override
  String get asks => 'Pregunta';

  @override
  String asksNothing(String example) {
    return 'No pregunta nada. Escribe $example donde quieras que pregunte.';
  }

  @override
  String get back => 'Atrás';

  @override
  String get badgeChanges => 'cambia';

  @override
  String get badgeLeaves => 'la deja';

  @override
  String get badgeNew => 'nueva';

  @override
  String get bellFlash => 'Destello con la campana';

  @override
  String get bellFlashHelp =>
      'Cuando un programa hace sonar la campana. Si la pestaña no está delante, se marca igualmente.';

  @override
  String get bellRang => 'Ha sonado la campana';

  @override
  String get bracesWord => 'llaves';

  @override
  String bringsTunnels(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'trae $count túneles',
      one: 'trae 1 túnel',
    );
    return '$_temp0';
  }

  @override
  String broadcastBanner(int count, int total, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Broadcast: lo que escribas va a $count de $total paneles ($names).',
      one: 'Broadcast: lo que escribas va a 1 de $total paneles ($names).',
    );
    return '$_temp0';
  }

  @override
  String broadcastExit(String keys) {
    return 'Salir $keys';
  }

  @override
  String get broadcastOff => 'Apagar el broadcast';

  @override
  String get broadcastOn => 'Broadcast en esta pestaña';

  @override
  String get broadcastPasteAlways =>
      'Con broadcast, pegar siempre lo pregunta, aunque sea una línea.';

  @override
  String broadcastPasteBody(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Va a $names. Son $count líneas, y cada una puede ejecutarse al llegar.',
      one: 'Va a $names. Es 1 línea.',
    );
    return '$_temp0';
  }

  @override
  String broadcastPasteTitle(int total) {
    return '¿Pegar en $total paneles a la vez?';
  }

  @override
  String broadcastStatus(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Broadcast · $count paneles',
      one: 'Broadcast · 1 panel',
    );
    return '$_temp0';
  }

  @override
  String get bySsh => 'por SSH';

  @override
  String get cancel => 'Cancelar';

  @override
  String cancelThese(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'No copiar estos $count',
      one: 'No copiar este',
    );
    return '$_temp0';
  }

  @override
  String get cancelled => 'Cancelado.';

  @override
  String cannotConnect(String label) {
    return 'No se ha podido conectar con $label';
  }

  @override
  String certExpiredOn(String date) {
    return 'caducó el $date';
  }

  @override
  String get certForever => 'sin caducidad';

  @override
  String get certNextToKey =>
      'Junto a la clave (-cert.pub): se usa sin añadirlo.';

  @override
  String certUntil(String date) {
    return 'hasta el $date';
  }

  @override
  String get certificate => 'certificado';

  @override
  String get certificateExpired => 'certificado caducado';

  @override
  String get certificateTitle => 'Certificado';

  @override
  String get change => 'Cambiar';

  @override
  String get changedMeanwhile =>
      'Otro cambio ha llegado antes: cierra y vuelve a abrir el editor.';

  @override
  String get checkedFingerprint => 'He comprobado la huella nueva';

  @override
  String get choiceKeepBoth => 'Mantener los dos';

  @override
  String get choiceNewer => 'Solo si el mío es más nuevo';

  @override
  String get choiceReplace => 'Reemplazar';

  @override
  String get choiceSkip => 'Saltar';

  @override
  String get cipher => 'Cifrado';

  @override
  String get clear => 'Quitar';

  @override
  String get clearFinished => 'Quitar las terminadas';

  @override
  String get clearSelection => 'Quitar la selección';

  @override
  String get close => 'Cerrar';

  @override
  String get closeAction => 'Cerrar';

  @override
  String get closePane => 'Cerrar el panel';

  @override
  String get closeTab => 'Cerrar la pestaña';

  @override
  String get closeTheTab => 'Cerrar la pestaña';

  @override
  String get colModified => 'Modificado';

  @override
  String get colName => 'Nombre';

  @override
  String get colPermissions => 'Permisos';

  @override
  String get colSize => 'Tamaño';

  @override
  String get command => 'Comando';

  @override
  String commandHint(String open, String escaped) {
    return 'Cada línea se envía como si la escribieras. Para escribir $open tal cual, pon $escaped.';
  }

  @override
  String get conflictChoose => '. Elige qué hacer con cada uno:';

  @override
  String get conflictFile => 'Fichero';

  @override
  String get conflictFolder => 'carpeta';

  @override
  String get conflictIn => 'En ';

  @override
  String get conflictMerge => 'las dos carpetas se juntan';

  @override
  String conflictRest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '. Los otros $count se copian ya. Elige qué hacer con cada uno:',
      one: '. El otro se copia ya. Elige qué hacer con cada uno:',
    );
    return '$_temp0';
  }

  @override
  String get conflictSame => 'igual tamaño y fecha';

  @override
  String conflictTheirs(String where) {
    return 'En $where';
  }

  @override
  String conflictTheirsNewer(String where) {
    return 'el de $where es más nuevo';
  }

  @override
  String conflictTitle(int count, int total, String where) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count de los $total ya existen en $where',
      one: '1 de los $total ya existe en $where',
    );
    return '$_temp0';
  }

  @override
  String conflictTitleOne(String where) {
    return 'Ya existe en $where';
  }

  @override
  String get conflictWhat => 'Qué hacer';

  @override
  String get conflictYours => 'El tuyo';

  @override
  String get conflictYoursNewer => 'el tuyo es más nuevo';

  @override
  String get connect => 'Conectar';

  @override
  String get connectingEllipsis => 'Conectando…';

  @override
  String connectingTo(String label) {
    return 'Conectando con $label';
  }

  @override
  String get connectionDetails => 'Detalles de la conexión';

  @override
  String get connectionHint =>
      'Lo que no cambies aquí se hereda; los valores heredados llevan el borde discontinuo y debajo dicen de dónde vienen. Manda lo del host, luego su identidad, luego sus grupos y, al final, los valores por defecto.';

  @override
  String connectionLost(String label, String why) {
    return 'Se perdió la conexión con $label$why.';
  }

  @override
  String get continueAction => 'Seguir';

  @override
  String get continueLabel => 'Continuar';

  @override
  String contrastFails(String ratio) {
    return 'Contraste del texto $ratio:1. No llega a AA (4,5:1).';
  }

  @override
  String contrastPasses(String ratio) {
    return 'Contraste del texto $ratio:1. Cumple AA.';
  }

  @override
  String contrastWarning(String ratio) {
    return 'Con esta combinación, parte del texto no llega al contraste recomendado (queda en $ratio:1).';
  }

  @override
  String get copy => 'Copiar';

  @override
  String get copyAction => 'Copiar';

  @override
  String get copyAddress => 'Copiar dirección';

  @override
  String get copyFingerprint => 'Copiar la huella';

  @override
  String get copyPath => 'Copiar la ruta';

  @override
  String get create => 'Crear';

  @override
  String get ctrlShiftPrefix => 'Ctrl+Mayús+';

  @override
  String get cursor => 'Cursor';

  @override
  String get cursorBar => 'Barra';

  @override
  String get cursorBlink => 'Cursor parpadeante';

  @override
  String get cursorBlock => 'Bloque';

  @override
  String get cursorHelp => 'Mientras el programa no pida otro.';

  @override
  String get cursorUnderline => 'Línea';

  @override
  String customize(String name) {
    return 'Personalizar $name';
  }

  @override
  String get customizeHint =>
      'Cambia una capa y el resto se queda igual. Los cambios son solo de este tema.';

  @override
  String get defaultKeys =>
      '~/.ssh/id_ed25519, id_ecdsa, id_rsa (las habituales)';

  @override
  String get defaultValueOptional => 'Valor por defecto (opcional)';

  @override
  String get delete => 'Eliminar';

  @override
  String get deleteEllipsis => 'Eliminar…';

  @override
  String deleteFailed(String error) {
    return 'No se ha podido eliminar: $error';
  }

  @override
  String get deleteGroup => 'Eliminar grupo';

  @override
  String get deleteGroupBody => 'Lo que contiene pasa a su grupo padre.';

  @override
  String deleteGroupTitle(String name) {
    return '¿Eliminar el grupo «$name»?';
  }

  @override
  String get deleteHostBody =>
      'Desaparece de la lista. Esto no se puede deshacer.';

  @override
  String deleteHostTitle(String name) {
    return '¿Eliminar el host «$name»?';
  }

  @override
  String deleteIdentityBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Los $count hosts que la usan volverán a heredar el usuario y las claves de sus grupos.',
      one: 'El host que la usa volverá a heredar el usuario y las claves de su grupo.',
    );
    return '$_temp0';
  }

  @override
  String deleteIdentityTitle(String name) {
    return '¿Eliminar «$name»?';
  }

  @override
  String get deleteIdentityUnused =>
      'Nadie la usa. Las claves siguen en su sitio: solo se borra la identidad.';

  @override
  String get deleteLocalBody =>
      'Se eliminan de este equipo sin pasar por la papelera: no se puede deshacer.';

  @override
  String deleteMany(int count) {
    return '¿Eliminar $count elementos?';
  }

  @override
  String deleteOne(String name) {
    return '¿Eliminar $name?';
  }

  @override
  String deleteRemoteBody(String host) {
    return 'Se eliminan en $host. En el servidor no hay papelera: no se puede deshacer.';
  }

  @override
  String get deletedHost => '(host eliminado)';

  @override
  String get deletedIdentity => '(identidad eliminada)';

  @override
  String get destination => 'Destino';

  @override
  String get dontTrust => 'No confiar';

  @override
  String get download => 'Descarga';

  @override
  String get downloadArrow => '← Descargar';

  @override
  String downloadTo(String path) {
    return 'Descargar a $path';
  }

  @override
  String get dropAskFirst =>
      'Si alguno ya existe, te preguntamos antes de tocarlo.';

  @override
  String get dropToDownload => 'Suelta para descargar aquí';

  @override
  String get dropToUpload => 'Suelta para subir aquí';

  @override
  String dynamicSentence(String here, String host) {
    return 'Usa $here como proxy SOCKS5: las conexiones salen de $host.';
  }

  @override
  String get editEllipsis => 'Editar…';

  @override
  String get editGroup => 'Editar grupo…';

  @override
  String get editGroupTitle => 'Editar grupo';

  @override
  String get editHostTitle => 'Editar host';

  @override
  String get editIdentity => 'Editar identidad';

  @override
  String get editSnippet => 'Editar snippet';

  @override
  String get editTheIdentity => 'Editar la identidad';

  @override
  String get editTunnel => 'Editar túnel';

  @override
  String get emptyFolder => 'Esta carpeta está vacía';

  @override
  String get exampleVariable => 'nombre';

  @override
  String failureAuth(String user, String label) {
    return '$user@$label no ha podido autenticarse.';
  }

  @override
  String failureAuthMethods(String user, String label, String methods) {
    return '$user@$label no ha podido autenticarse (el servidor acepta: $methods).';
  }

  @override
  String failureBadCertificate(String label, String reason) {
    return 'El certificado de $label no es válido: $reason.';
  }

  @override
  String failureHostKeyChanged(String label, String fingerprint) {
    return 'La clave de $label ha cambiado (ahora $fingerprint). Puede ser un ataque: no se ha conectado.';
  }

  @override
  String failureHostKeyRejected(String label) {
    return 'No se ha confiado en la clave de $label.';
  }

  @override
  String failureHostKeyRevoked(String label, String fingerprint) {
    return '$label usa una clave revocada ($fingerprint): se rechaza siempre. Si es un error, quítala de la lista de hosts conocidos.';
  }

  @override
  String failureNoSftp(String label) {
    return '$label no tiene SFTP: al servidor le falta sftp-server.';
  }

  @override
  String fileChanged(String path) {
    return '$path cambió mientras se copiaba.';
  }

  @override
  String fileDenied(String path) {
    return 'Sin permiso: $path';
  }

  @override
  String fileExists(String path) {
    return 'Ya existe: $path';
  }

  @override
  String get fileLost => 'Se perdió la conexión.';

  @override
  String fileNotFound(String path) {
    return 'No existe: $path';
  }

  @override
  String get filledInEachPane => 'También se rellenan solas, en cada panel:';

  @override
  String get filterFolder => 'Filtrar en esta carpeta';

  @override
  String get filterHostsAndGroups => 'Filtrar hosts y grupos';

  @override
  String get filterIdentities => 'Filtrar por nombre, usuario o clave';

  @override
  String get filterSnippets => 'Filtrar por nombre o comando';

  @override
  String get filterTunnels => 'Filtrar por nombre, host o puerto';

  @override
  String get findASnippet => 'Buscar un snippet';

  @override
  String get findClose => 'Cerrar la búsqueda (Esc)';

  @override
  String findCount(int selected, int total) {
    return '$selected de $total';
  }

  @override
  String get findHint => 'Buscar en el terminal';

  @override
  String get findNewer => 'Siguiente, más abajo (Mayús+Intro)';

  @override
  String get findOlder => 'Anterior, más arriba (Intro)';

  @override
  String findTotal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count resultados',
      one: '1 resultado',
      zero: 'Sin resultados',
    );
    return '$_temp0';
  }

  @override
  String get fingerprint => 'Huella';

  @override
  String firstConnectionTo(String label) {
    return 'Primera conexión con $label';
  }

  @override
  String get fontFromTheme => 'La del tema';

  @override
  String get fontOther => 'Otra fuente instalada…';

  @override
  String get fontOtherHint => 'Su nombre exacto, como «Fira Code»';

  @override
  String get fontOtherTitle => 'Otra fuente instalada';

  @override
  String get fontSize => 'Tamaño de letra';

  @override
  String get fontSystem => 'La del sistema';

  @override
  String get forAll => 'A todos:';

  @override
  String get forgetAction => 'Olvidar';

  @override
  String get forgetFileKeyBody =>
      'Se borra esa línea del fichero, que también usa el ssh de tu sistema, y antes se guarda una copia en known_hosts.old, como hace ssh-keygen -R.';

  @override
  String forgetFileKeyTitle(String name, String file) {
    return '¿Quitar la clave de $name de $file?';
  }

  @override
  String get forgetKeyBody => 'OpenWard deja de confiar en esta clave.';

  @override
  String get forgetKeyThen =>
      'La próxima vez que conectes se preguntará otra vez por su clave, salvo que haya otra en la que confíes.';

  @override
  String forgetKeyTitle(String name) {
    return '¿Olvidar la clave de $name?';
  }

  @override
  String get forward => 'Reenvío';

  @override
  String get fromDefault => 'Valor por defecto';

  @override
  String fromGroup(String name) {
    return 'Del grupo $name';
  }

  @override
  String get fromHere => 'desde aquí';

  @override
  String fromIdentity(String name) {
    return 'De la identidad $name';
  }

  @override
  String get fromNowhere => 'Sin valor: lo decide la conexión';

  @override
  String get fromSshConfig => 'de ~/.ssh/config';

  @override
  String get fromThere => 'desde allí';

  @override
  String get group => 'Grupo';

  @override
  String get groupInsideItself => 'Un grupo no puede estar dentro de sí mismo.';

  @override
  String groupNamed(String name) {
    return 'Grupo $name';
  }

  @override
  String get groupNeedsName => 'El grupo necesita un nombre.';

  @override
  String get groupSettingsSection => 'Ajustes para todo lo que contiene';

  @override
  String get groups => 'Grupos';

  @override
  String get hashedName => 'Nombre cifrado';

  @override
  String get hideHiddenFiles => 'No mostrar los ocultos';

  @override
  String get hideQueue => 'Ocultar';

  @override
  String get host => 'Host';

  @override
  String hostCountText(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hosts',
      one: '1 host',
      zero: 'ningún host',
    );
    return '$_temp0';
  }

  @override
  String hostInUse(String name) {
    return 'Otros hosts saltan por «$name»: cámbialos antes de eliminarlo.';
  }

  @override
  String get hostKey => 'Clave del host';

  @override
  String hostKeyUnknownBody(String where) {
    return 'OpenWard aún no conoce la clave de $where. Compara la huella con la que te dé quien administra el servidor antes de confiar en ella.';
  }

  @override
  String get hostKeys => 'Claves de host nuevas';

  @override
  String get hostNeedsName => 'El host necesita un nombre.';

  @override
  String get hostsSection => 'Hosts';

  @override
  String get identities => 'Identidades';

  @override
  String identitiesCount(int total, int used) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total identidades',
      one: '1 identidad',
    );
    return '$_temp0 · $used en uso';
  }

  @override
  String get identitiesIntro =>
      'Usuario, claves y agente con un nombre, para usarlos en varios hosts y grupos. Cambiar una identidad cambia todos los que la usan.';

  @override
  String get identitiesNoSecrets =>
      'No se guardan contraseñas ni frases de paso: se piden al conectar, como hasta ahora. De cada clave solo se lee su parte pública (.pub).';

  @override
  String get identity => 'Identidad';

  @override
  String get identityEditorHint =>
      'Usuario, claves y agente con un nombre, para usarlos en varios hosts.';

  @override
  String identityKeyMissingHere(String user) {
    return '$user · falta su clave en este equipo';
  }

  @override
  String get identityNeedsName => 'Ponle un nombre.';

  @override
  String get identityNewNote =>
      'Úsala desde el editor de un host o de un grupo, o con «Usar en…» en la lista de identidades.';

  @override
  String get identityNone => 'Ninguna';

  @override
  String get identityNoneNote => 'Aunque se herede una de más arriba';

  @override
  String identitySaveChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Al guardar cambian los $count hosts que la usan.',
      one: 'Al guardar cambia el host que la usa.',
    );
    return '$_temp0 Un host que pone su propio usuario o sus claves mantiene los suyos.';
  }

  @override
  String identityUsedBy(String who) {
    return 'La usan: $who';
  }

  @override
  String get ignore => 'Ignorar';

  @override
  String get importEllipsis => 'Importar…';

  @override
  String importFailed(String error) {
    return 'No se ha podido importar: $error';
  }

  @override
  String importFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Hemos encontrado $count hosts en tu ~/.ssh/config.',
      one: 'Hemos encontrado 1 host en tu ~/.ssh/config.',
    );
    return '$_temp0';
  }

  @override
  String get importFrom => 'Importar de ~/.ssh/config';

  @override
  String get importFromSshConfig => 'Importar de ~/.ssh/config';

  @override
  String get importIntoGroup =>
      'Se guardan en el grupo «~/.ssh/config». Un host trae consigo los hosts por los que salta.';

  @override
  String get importKeepsFile =>
      'El fichero no se toca, y las claves se quedan donde están: OpenWard guarda la ruta, nunca la clave.';

  @override
  String get importLater => 'Puedes importar más tarde desde la barra lateral.';

  @override
  String importN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Importar $count hosts',
      one: 'Importar 1 host',
      zero: 'Importar',
    );
    return '$_temp0';
  }

  @override
  String get importNothing =>
      'No hay hosts nuevos en ~/.ssh/config (o no existe).';

  @override
  String get importScheme => 'Importar de iTerm2 o Ghostty…';

  @override
  String importSchemeDone(String name) {
    return '«$name» importado y puesto en el terminal.';
  }

  @override
  String get importSchemeFailed =>
      'Ese fichero no es un tema de iTerm2 (.itermcolors) ni de Ghostty.';

  @override
  String get importSshConfigMenu => 'Importar de ~/.ssh/config…';

  @override
  String get importTitle => 'Importar ~/.ssh/config';

  @override
  String get inDark => 'En oscuro';

  @override
  String inGroup(String name) {
    return 'en el grupo $name';
  }

  @override
  String get inLight => 'En claro';

  @override
  String inWhere(String where) {
    return 'en $where';
  }

  @override
  String inheritsFrom(String group) {
    return 'La hereda de $group';
  }

  @override
  String get inputNotSent => 'Lo que escribas ahora no se envía.';

  @override
  String get inside => 'Dentro de';

  @override
  String itemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos',
      one: '1 elemento',
    );
    return '$_temp0';
  }

  @override
  String get itsPort => 'Su puerto';

  @override
  String get jobCancelled => 'Cancelada';

  @override
  String get jobCounting => 'Contando…';

  @override
  String jobDone(String size) {
    return 'Hecho · $size';
  }

  @override
  String get jobFailed => 'Ha fallado';

  @override
  String jobFolder(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'carpeta, $count ficheros',
      one: 'carpeta, 1 fichero',
    );
    return '$_temp0';
  }

  @override
  String jobLost(String done, String total) {
    return 'Se cortó la conexión con $done de $total copiados';
  }

  @override
  String jobPaused(String done, String total) {
    return 'En pausa · $done de $total';
  }

  @override
  String jobProgress(String done, String total) {
    return '$done de $total';
  }

  @override
  String jobQueued(String size) {
    return 'En cola · $size';
  }

  @override
  String get jobQueuedNoSize => 'En cola';

  @override
  String jobSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ya estaban',
      one: '1 ya estaba',
    );
    return '$_temp0';
  }

  @override
  String get jumpThrough => 'Saltar por, en orden';

  @override
  String jumpVia(String hosts) {
    return 'Saltando por $hosts';
  }

  @override
  String jumpsVia(String hosts) {
    return 'salta por $hosts';
  }

  @override
  String get keyBefore => 'Antes';

  @override
  String get keyChangedBody =>
      'Puede ser una reinstalación del servidor o alguien interceptando la conexión. No se ha enviado ninguna contraseña ni clave.';

  @override
  String keyChangedDialogBody(String where) {
    return '$where se presenta con una clave distinta de la que tenías como buena. Puede que el servidor se haya reinstalado o haya cambiado de clave, pero también que alguien esté interceptando la conexión. No sigas sin comprobar la huella nueva con quien administra el servidor.';
  }

  @override
  String keyChangedTitle(String label) {
    return 'La clave de $label ha cambiado';
  }

  @override
  String get keyColumn => 'Clave';

  @override
  String get keyExchange => 'Intercambio';

  @override
  String get keyInKnownHosts => 'en ~/.ssh/known_hosts';

  @override
  String get keyInOpenWard => 'guardada en OpenWard';

  @override
  String get keyMissing => 'No está en este equipo';

  @override
  String keyMissingWarning(String path, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Los $count hosts que la usan no podrán usar esa clave hasta que la copies o cambies la ruta.',
      one: 'El host que la usa no podrá usar esa clave hasta que la copies o cambies la ruta.',
      zero: 'Cópiala o cambia la ruta antes de usarla.',
    );
    return '$path no está en este equipo. $_temp0';
  }

  @override
  String get keyNoPublicHalf =>
      'Sin .pub al lado: su tipo se sabrá al conectar';

  @override
  String keyNow(String algorithm) {
    return 'Ahora ($algorithm)';
  }

  @override
  String get keyPerHost => 'Una por host (lleva %h, %r…)';

  @override
  String keyProtected(String key) {
    return 'La clave $key está protegida.';
  }

  @override
  String get keyReceived => 'Recibida';

  @override
  String get keySaved => 'Guardada';

  @override
  String get keys => 'Claves';

  @override
  String get keysHelp =>
      'Una ruta por línea. OpenWard guarda la ruta, nunca la clave.';

  @override
  String get keysInOrder =>
      'Se prueban en este orden; arrastra para cambiarlo.';

  @override
  String get kindDynamic => 'Dinámico (-D)';

  @override
  String get kindDynamicShort => 'Dinámico';

  @override
  String get kindLocal => 'Local (-L)';

  @override
  String get kindLocalShort => 'Local';

  @override
  String get kindRemote => 'Remoto (-R)';

  @override
  String get kindRemoteShort => 'Remoto';

  @override
  String get knownHosts => 'Hosts conocidos';

  @override
  String get knownHostsFileChanged =>
      'El fichero ha cambiado desde que se mostró. Vuelve a mirarlo antes de quitar nada.';

  @override
  String knownHostsIntro(String file) {
    return 'Las claves de servidor en las que confías. Al conectar se miran las de OpenWard y las de $file; las nuevas se guardan en OpenWard.';
  }

  @override
  String get lanLocalNote =>
      'Cualquiera de tu red podrá usarlo mientras esté abierto.';

  @override
  String get lanRemoteNote =>
      'El servidor tiene que permitirlo (GatewayPorts en sshd); si no, escucha solo en sí mismo.';

  @override
  String get language => 'Idioma';

  @override
  String get languageSystem => 'Como el sistema';

  @override
  String get library => 'Biblioteca';

  @override
  String get licenses => 'Licencias';

  @override
  String get lightAndDark => 'Claro y oscuro';

  @override
  String get lineHeight => 'Interlineado del terminal';

  @override
  String lineNumber(int line) {
    return 'línea $line';
  }

  @override
  String linesCount(int count) {
    return '$count líneas';
  }

  @override
  String linkNotOpened(String scheme) {
    return 'Los enlaces «$scheme:» no se abren desde el terminal.';
  }

  @override
  String localSentence(String here, String dest, String host) {
    return 'Lo que conecte a $here llega a $dest como si saliera de $host.';
  }

  @override
  String get localTerminal => 'Terminal local';

  @override
  String get localUser => 'tu usuario local';

  @override
  String get manageSnippets => 'Gestionar snippets…';

  @override
  String get markerCertAuthority =>
      'Autoridad de certificados: confía en los hosts que firma';

  @override
  String get markerRevoked => 'Revocada: se rechaza siempre';

  @override
  String matchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count coinciden',
      one: '1 coincide',
      zero: 'ninguna coincide',
    );
    return '$_temp0';
  }

  @override
  String matchesHost(String host) {
    return 'Coincide con $host';
  }

  @override
  String get maximizePane => 'Maximizar el panel';

  @override
  String milliseconds(int ms) {
    return '$ms ms';
  }

  @override
  String get minimumContrast => 'Contraste mínimo';

  @override
  String get minimumContrastHelp =>
      'Aclara u oscurece el texto del terminal que no se lee sobre su fondo.';

  @override
  String get missingAddress => 'Falta la dirección.';

  @override
  String get missingJump => 'Añade al menos un host por el que saltar.';

  @override
  String get missingProxy => 'Falta el servidor o el puerto del proxy.';

  @override
  String get missingProxyCommand => 'Falta el ProxyCommand.';

  @override
  String get missingSocket => 'Falta la ruta del socket del agente.';

  @override
  String get monthsShort => 'ene,feb,mar,abr,may,jun,jul,ago,sept,oct,nov,dic';

  @override
  String get moreActions => 'Más acciones';

  @override
  String get moreOptions => 'Más opciones';

  @override
  String get name => 'Nombre';

  @override
  String nameAndMore(String name, int count) {
    return '$name y $count más';
  }

  @override
  String get nameNoSlash => 'Un nombre no puede llevar «/».';

  @override
  String namesAndMore(String names, int count) {
    return '$names y $count más';
  }

  @override
  String get netLost => 'se ha perdido la conexión.';

  @override
  String get netNotFound => 'no se encuentra el host.';

  @override
  String get netRefused => 'conexión rechazada.';

  @override
  String get netTimeout => 'tiempo de espera agotado.';

  @override
  String get newEllipsis => 'Nuevo…';

  @override
  String get newFolder => 'Nueva carpeta';

  @override
  String get newGroup => 'Nuevo grupo';

  @override
  String get newGroupTitle => 'Nuevo grupo';

  @override
  String get newHost => 'Nuevo host';

  @override
  String get newHostHere => 'Nuevo host aquí';

  @override
  String get newHostTitle => 'Nuevo host';

  @override
  String get newIdentity => 'Nueva identidad';

  @override
  String get newIdentityEllipsis => 'Nueva identidad…';

  @override
  String get newLocalTerminal => 'Terminal local nuevo';

  @override
  String get newPane => 'Panel nuevo';

  @override
  String get newSnippet => 'Nuevo snippet';

  @override
  String get newSubgroup => 'Nuevo subgrupo';

  @override
  String get newTunnel => 'Nuevo túnel';

  @override
  String get newsIdentitiesBody =>
      'Usuario, claves y agente con un nombre, para un grupo entero o varios hosts a la vez.';

  @override
  String get newsIdentitiesTitle => 'Identidades';

  @override
  String newsPanesBody(String split, String broadcast) {
    return 'Divide una pestaña ($split) y escribe en varios paneles a la vez ($broadcast), con aviso fijo y pegado confirmado.';
  }

  @override
  String get newsPanesTitle => 'Paneles y broadcast';

  @override
  String newsSftpBody(String shortcut) {
    return 'Arrastra entre este equipo y el servidor, con cola, reanudación y lo que ya existe resuelto a tu manera ($shortcut).';
  }

  @override
  String get newsSftpTitle => 'SFTP de doble panel';

  @override
  String newsSnippetsBody(String shortcut) {
    return 'Comandos con variables a un atajo ($shortcut), y las claves en las que confías, con las de ~/.ssh/known_hosts.';
  }

  @override
  String get newsSnippetsTitle => 'Snippets y hosts conocidos';

  @override
  String get newsThemesBody =>
      'Cinco temas en claro y oscuro, capas que se combinan, tamaño del texto, contraste mínimo y reducir movimiento.';

  @override
  String get newsThemesTitle => 'Temas y accesibilidad visual';

  @override
  String get newsTunnelsBody =>
      'Local, remoto y SOCKS5, que se abren al conectar; también proxy HTTP y SOCKS5 para llegar al servidor.';

  @override
  String get newsTunnelsTitle => 'Túneles guardados y proxy';

  @override
  String get next => 'Siguiente';

  @override
  String get no => 'No';

  @override
  String get noGroup => 'Sin grupo';

  @override
  String get noHostsBody => 'Añade uno o tráelos de tu ~/⁠.ssh/⁠config.';

  @override
  String get noHostsTitle => 'Aún no tienes hosts';

  @override
  String get noIdentities => 'Aún no hay identidades';

  @override
  String get noIdentitiesBody =>
      'Una identidad junta un usuario, sus claves y el agente con un nombre («deploy en producción»). Ponla en un grupo y todos sus hosts entran igual; cámbiala una vez y cambian todos.';

  @override
  String get noIdentityInherited => 'Ningún grupo pone una';

  @override
  String get noIdentityNow => 'Sin identidad';

  @override
  String get noJumpsYet => 'Ninguno todavía.';

  @override
  String get noKeysYet =>
      'Sin claves: se prueban las habituales de ~/.ssh y las del agente.';

  @override
  String get noKnownHostMatches => 'Ninguna clave coincide';

  @override
  String get noKnownHosts => 'Aún no confías en ninguna clave';

  @override
  String get noKnownHostsBody =>
      'Las claves de los servidores aparecen aquí cuando conectas y confías en ellas.';

  @override
  String noMatches(String filter) {
    return 'Nada coincide con «$filter»';
  }

  @override
  String get noParent => 'Ningún grupo';

  @override
  String get noPostQuantumNote =>
      'El servidor no ofrece un intercambio poscuántico (mlkem768x25519; OpenSSH lo trae desde la 10.0).';

  @override
  String get noResults => 'Ningún host coincide.';

  @override
  String get noSnippetMatches => 'Ningún snippet coincide';

  @override
  String get noSnippets => 'Aún no hay snippets';

  @override
  String noSnippetsBody(String braces) {
    return 'Un snippet es un comando guardado que envías a un terminal con un atajo. Lo que escribas entre $braces se pregunta al ejecutarlo.';
  }

  @override
  String get noSnippetsYet =>
      'Aún no hay snippets. Crea uno en Biblioteca › Snippets.';

  @override
  String get noTunnels => 'Aún no hay túneles';

  @override
  String get noTunnelsBody =>
      'Un túnel lleva un puerto de este equipo a un servicio que solo ve el servidor (una base de datos, un panel), o al revés. Crea uno o tráelos de tu ~/.ssh/config.';

  @override
  String get notNow => 'Ahora no';

  @override
  String get notes => 'Notas';

  @override
  String nowIdentity(String identity) {
    return 'Ahora: $identity';
  }

  @override
  String nowIdentityFromGroup(String identity, String group) {
    return 'Ahora: $identity, del grupo $group';
  }

  @override
  String get nowNoIdentity => 'ahora: ninguna';

  @override
  String get offerOnlyTheseKeys => 'Ofrecer solo estas claves';

  @override
  String get offerOnlyTheseKeysNote =>
      'No probar las demás claves del agente (IdentitiesOnly). Útil si el servidor corta tras varios intentos.';

  @override
  String get ok => 'Aceptar';

  @override
  String get onConnect => 'Al conectar';

  @override
  String get onSend => 'Al enviar';

  @override
  String get onlyTheServer => 'Solo el servidor';

  @override
  String get onlyThisComputer => 'Solo este equipo (127.0.0.1)';

  @override
  String get openATerminalFirst => 'Abre un terminal para ejecutarlo';

  @override
  String get openAction => 'Abrir';

  @override
  String openCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count abiertos',
      one: '1 abierto',
    );
    return '$_temp0';
  }

  @override
  String get openLocal => 'Abrir un terminal local';

  @override
  String openOnConnect(String host) {
    return 'Abrir al conectar a $host';
  }

  @override
  String get openOnConnectNote =>
      'Desde un terminal o un SFTP. Si el puerto está ocupado, la conexión sigue y el túnel avisa.';

  @override
  String get openSftp => 'Abrir SFTP';

  @override
  String openSshStillWarns(String command) {
    return 'OpenWard no modifica ~/.ssh/known_hosts: ssh seguirá avisando hasta que quites la clave vieja de allí ($command).';
  }

  @override
  String get optionAsAlt => 'Opción como Alt';

  @override
  String get optionAsAltHelp =>
      'Opción envía Esc + tecla, como esperan emacs y readline, en vez de escribir símbolos como @ o €.';

  @override
  String get orAnAddress => 'o una dirección: usuario@host:puerto';

  @override
  String get orTypeAPath => 'o escribe una ruta: admite ~, %h, %r y %u';

  @override
  String ownUserWins(String user) {
    return 'Pone su propio usuario ($user), que seguirá mandando.';
  }

  @override
  String get paletteChoose => 'elegir';

  @override
  String get paletteRun => 'ejecutar';

  @override
  String get paletteTypeOnly => 'solo escribir';

  @override
  String get paneOptions => 'Opciones del panel';

  @override
  String get paneWhat => '¿Qué abres en este panel?';

  @override
  String get partNote =>
      'Se copia con un nombre temporal (.part) y se renombra al terminar: si se corta, el fichero bueno no queda a medias y la copia se puede reanudar.';

  @override
  String get passphraseField => 'Frase';

  @override
  String get passphraseTitle => 'Frase de la clave';

  @override
  String get passwordTitle => 'Contraseña';

  @override
  String get paste => 'Pegar';

  @override
  String pasteInPanes(int total) {
    return 'Pegar en $total paneles';
  }

  @override
  String get pasteMultiBody =>
      'El texto contiene saltos de línea u otras secuencias que pueden ejecutar comandos al pegarlo.';

  @override
  String get pasteMultiTitle => '¿Pegar varias líneas?';

  @override
  String pasteOnlyHere(String name) {
    return 'Pegar solo en $name';
  }

  @override
  String get pause => 'Pausar';

  @override
  String get pauseAll => 'Pausar todo';

  @override
  String percent(int number) {
    return '$number %';
  }

  @override
  String permApplied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Permisos cambiados en $count elementos',
      one: 'Permisos cambiados en 1 elemento',
    );
    return '$_temp0';
  }

  @override
  String permBefore(String mode) {
    return 'Antes: $mode';
  }

  @override
  String get permEnter => 'Entrar';

  @override
  String get permExecute => 'Ejecutar';

  @override
  String get permGroup => 'Grupo';

  @override
  String get permOctal => 'En octal';

  @override
  String get permOthers => 'Otros';

  @override
  String get permOwner => 'Propietario';

  @override
  String get permOwnerNote =>
      'El propietario y el grupo no se cambian desde aquí.';

  @override
  String get permRead => 'Leer';

  @override
  String get permRecursive => 'Aplicar también a lo que hay dentro';

  @override
  String get permRecursiveNote =>
      'A los ficheros solo se les deja «Ejecutar» si ya lo tenían.';

  @override
  String get permWrite => 'Escribir';

  @override
  String get permissionsEllipsis => 'Permisos…';

  @override
  String permissionsOf(String name) {
    return 'Permisos de $name';
  }

  @override
  String get pickIdentity => 'Elige una identidad o «Ninguna».';

  @override
  String pixels(int size) {
    return '$size px';
  }

  @override
  String get policyAcceptNew => 'Aceptar nuevas';

  @override
  String get policyAsk => 'Preguntar';

  @override
  String get policyStrict => 'Estricta';

  @override
  String get port => 'Puerto';

  @override
  String get portBusyNow => 'ocupado ahora';

  @override
  String get portHere => 'Puerto aquí';

  @override
  String portOnHost(String host) {
    return 'Puerto en $host';
  }

  @override
  String get portRange => 'El puerto va de 1 a 65535.';

  @override
  String get postQuantum => 'poscuántico';

  @override
  String postQuantumKex(String kex) {
    return '$kex (poscuántico)';
  }

  @override
  String get pressEnterAtTheEnd => 'Pulsar Intro al final';

  @override
  String get pressEnterAtTheEndNote =>
      'Apágalo para dejar el comando escrito y revisarlo antes de ejecutarlo.';

  @override
  String get preview => 'Vista previa';

  @override
  String get previewLive => 'Los cambios se ven al momento en toda la ventana.';

  @override
  String get proxy => 'Proxy';

  @override
  String get proxyHttpNote =>
      'Con un proxy HTTP, la petición CONNECT va sin cifrar: el proxy ve a qué host y puerto te conectas, pero no lo que pasa por SSH.';

  @override
  String proxyLoginBody(String proxy) {
    return '$proxy pide usuario y contraseña para dejarte pasar. No se guardan.';
  }

  @override
  String get proxyLoginTitle => 'El proxy pide entrar';

  @override
  String get proxyNone => 'Sin proxy';

  @override
  String get proxyNotWithCommand => 'Con ProxyCommand no se usa el proxy.';

  @override
  String get proxyRouteTitle => 'La ruta queda así';

  @override
  String get proxyServer => 'Servidor proxy';

  @override
  String get proxyUser => 'Usuario del proxy';

  @override
  String get proxyUserHelp =>
      'Opcional. La contraseña se pide al conectar y no se guarda.';

  @override
  String get queueAllDone => 'Todo terminado';

  @override
  String queueFailed(int count) {
    return '$count con error';
  }

  @override
  String queuePaused(int count) {
    return '$count en pausa';
  }

  @override
  String queueQueued(int count) {
    return '$count en cola';
  }

  @override
  String queueRunning(int count) {
    return '$count en curso';
  }

  @override
  String get quickConnectHint => 'usuario@servidor:puerto';

  @override
  String get quickConnectInvalid =>
      'Escribe una dirección como usuario@servidor:puerto.';

  @override
  String get readyBody => 'Estos atajos te llevan a casi todo:';

  @override
  String get readyTitle => 'Todo listo';

  @override
  String get receives => 'Recibe';

  @override
  String get reconnect => 'Reconectar';

  @override
  String get reconnectingEllipsis => 'Reconectando…';

  @override
  String reconnectingStage(String stage) {
    return 'Reconectando: $stage';
  }

  @override
  String get reduceMotion => 'Reducir movimiento';

  @override
  String get reload => 'Recargar';

  @override
  String remoteSentence(String host, String port, String dest) {
    return 'Lo que se conecte en $host al puerto $port llega a $dest de este equipo.';
  }

  @override
  String get remove => 'Quitar';

  @override
  String get removeCertificate => 'Quitar el certificado';

  @override
  String get removeKey => 'Quitar la clave';

  @override
  String removeTag(String tag) {
    return 'Quitar $tag';
  }

  @override
  String get removeTheLine => 'Quitar la línea';

  @override
  String get rename => 'Renombrar';

  @override
  String get renameTabHelp => 'Vacío para volver al nombre del host';

  @override
  String get renameTabTitle => 'Renombrar pestaña';

  @override
  String renameTitle(String name) {
    return 'Renombrar $name';
  }

  @override
  String get reportCopied => 'Copiado. Pégalo en tu informe.';

  @override
  String get reportCore => 'núcleo';

  @override
  String reportCounts(
    int hosts,
    int groups,
    int tunnels,
    int identities,
    int snippets,
  ) {
    return 'Hosts: $hosts · grupos: $groups · túneles: $tunnels · identidades: $identities · snippets: $snippets';
  }

  @override
  String reportCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hosts nuevos',
      one: '1 host nuevo',
    );
    return '$_temp0';
  }

  @override
  String get reportHow =>
      'Pégalo en la issue junto con qué hacías, qué esperabas y qué pasó, como pide la guía de prueba.';

  @override
  String get reportNotEverything => 'No todo se ha podido traer:';

  @override
  String get reportProblem => 'Informar de un problema';

  @override
  String get reportProblemEllipsis => 'Informar de un problema…';

  @override
  String get reportProblemHint =>
      'Copia la versión y el sistema para pegarlos en tu informe.';

  @override
  String reportSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ya estaban importados y no se han tocado',
      one: '1 ya estaba importado y no se ha tocado',
    );
    return '$_temp0';
  }

  @override
  String get reportText => 'texto';

  @override
  String get reportTheme => 'Tema';

  @override
  String reportTunnels(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count túneles nuevos',
      one: '1 túnel nuevo',
    );
    return '$_temp0';
  }

  @override
  String get reportWhat =>
      'Esto es lo que se copia. No incluye hosts, direcciones, usuarios ni claves.';

  @override
  String get reportWhere => 'Están en el grupo «~/.ssh/config».';

  @override
  String get resetTheme => 'Restablecer';

  @override
  String get restart => 'Reiniciar';

  @override
  String get restorePanes => 'Volver a los paneles';

  @override
  String get resume => 'Reanudar';

  @override
  String get retry => 'Reintentar';

  @override
  String retryIn(int attempt, int max, int secs) {
    return 'Reintento $attempt de $max en $secs s.';
  }

  @override
  String get retryNow => 'Reintentar ahora';

  @override
  String get reviewKey => 'Revisar la clave…';

  @override
  String get route => 'Cómo llegar';

  @override
  String get routeDirect => 'Directo';

  @override
  String get routeJump => 'Saltando por otro host';

  @override
  String get routeStart => 'este equipo';

  @override
  String get runEllipsis => 'Ejecutar…';

  @override
  String get runIn => 'Ejecutar en…';

  @override
  String runSnippetBroadcast(int count) {
    return 'Va a los $count paneles que reciben el broadcast';
  }

  @override
  String get runSnippetHint => 'Rellena lo que pregunta. No se guarda.';

  @override
  String runSnippetIn(String where) {
    return 'En $where';
  }

  @override
  String runSnippetTitle(String name) {
    return 'Ejecutar «$name»';
  }

  @override
  String get sameHost => 'el mismo host';

  @override
  String get sampleComment => 'comentario en gris';

  @override
  String get sampleError => 'error:';

  @override
  String get sampleErrorText => 'no se pudo leer .env';

  @override
  String get sampleWarning => 'aviso:';

  @override
  String get sampleWarningText => '2 migraciones pendientes';

  @override
  String get save => 'Guardar';

  @override
  String get saveAndConnect => 'Guardar y conectar';

  @override
  String get saveAndOpen => 'Guardar y abrir';

  @override
  String saveFailed(String error) {
    return 'No se ha podido guardar: $error';
  }

  @override
  String saveKeyFailed(String error) {
    return 'No se ha podido guardar la clave: $error';
  }

  @override
  String get saveNewHost => 'Guardar un host nuevo';

  @override
  String get savedHost => 'Host guardado';

  @override
  String get scrollback => 'Historial';

  @override
  String get scrollbackHelp => 'Para las pestañas nuevas.';

  @override
  String scrollbackLines(String lines) {
    return '$lines líneas';
  }

  @override
  String get searchHosts => 'Buscar hosts';

  @override
  String get searchKnownHosts => 'Buscar un host, una huella…';

  @override
  String get sectionConnection => 'Conexión';

  @override
  String get sectionGeneral => 'General';

  @override
  String seenFrom(String host) {
    return 'visto desde $host';
  }

  @override
  String get seenFromHere => 'visto desde este equipo';

  @override
  String get selectAll => 'Todos';

  @override
  String get selectAllText => 'Seleccionar todo';

  @override
  String selectedCount(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seleccionados ($size)',
      one: '1 seleccionado ($size)',
    );
    return '$_temp0';
  }

  @override
  String selectedCountOnly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seleccionados',
      one: '1 seleccionado',
    );
    return '$_temp0';
  }

  @override
  String selectedOf(int selected, int total) {
    return '$selected de $total';
  }

  @override
  String get sendAction => 'Enviar';

  @override
  String sendToPanes(int count) {
    return 'Enviar a $count paneles';
  }

  @override
  String get sessionClosed => 'Sesión cerrada.';

  @override
  String sessionClosedCode(int code) {
    return 'Sesión cerrada (código $code).';
  }

  @override
  String setHereIdentitySays(String value) {
    return 'Cambiado aquí; la identidad dice $value';
  }

  @override
  String setHereWouldInherit(String value) {
    return 'Cambiado aquí; heredaría $value';
  }

  @override
  String get settings => 'Ajustes';

  @override
  String get settingsAppearance => 'Apariencia';

  @override
  String get settingsGeneral => 'General';

  @override
  String get settingsTerminal => 'Terminal';

  @override
  String sftpConnected(String label) {
    return 'SFTP en $label';
  }

  @override
  String get sftpKeysApple =>
      'Intro abre · ⌘↑ sube · Tab cambia de lado · F2 renombra · ⌘⌫ elimina';

  @override
  String get sftpKeysOther =>
      'Intro abre · Retroceso sube · Tab cambia de lado · F2 renombra · Supr elimina';

  @override
  String sftpTabTitle(String label) {
    return 'SFTP · $label';
  }

  @override
  String get shape => 'Forma';

  @override
  String get shortcutLocal => 'Abre un terminal local';

  @override
  String get shortcutNewHost => 'Guarda un host nuevo';

  @override
  String get shortcutSearch => 'Busca entre tus hosts';

  @override
  String get shortcutSettings => 'Abre los ajustes';

  @override
  String get showHiddenFiles => 'Mostrar los ocultos';

  @override
  String get showQueue => 'Ver la cola';

  @override
  String showRest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ver los $count restantes',
      one: 'Ver el que falta',
    );
    return '$_temp0';
  }

  @override
  String get skipGuide => 'Saltar la guía';

  @override
  String get snippetEditorHint =>
      'Comandos que envías a un terminal; lo que va entre llaves se pregunta.';

  @override
  String get snippetNeedsCommand => 'Escribe el comando.';

  @override
  String get snippetNeedsName => 'Ponle un nombre.';

  @override
  String get snippetNoSecrets =>
      'Se guarda sin secretos, como el resto del vault. Lo que escribas al ejecutarlo no se guarda.';

  @override
  String get snippetTypeOnlyNote => 'Se deja escrito, sin pulsar Intro.';

  @override
  String get snippetWithEnter => 'Con Intro al final.';

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
    return 'En un terminal: $shortcut o el botón «Snippets» de la barra de estado. Con broadcast, van a todos los paneles que reciben.';
  }

  @override
  String snippetsIntro(String braces) {
    return 'Comandos guardados que envías a un terminal con un atajo. Lo que va entre $braces se pregunta al ejecutarlo.';
  }

  @override
  String get splitDown => 'Dividir abajo';

  @override
  String get splitRight => 'Dividir a la derecha';

  @override
  String stageAuthenticating(String label, String hop) {
    return 'Autenticando en $label$hop…';
  }

  @override
  String stageConnecting(String label, String hop) {
    return 'Conectando con $label$hop…';
  }

  @override
  String stageOpeningSftp(String label) {
    return 'Abriendo SFTP en $label…';
  }

  @override
  String stageOpeningShell(String label) {
    return 'Abriendo el shell en $label…';
  }

  @override
  String get start => 'Empezar';

  @override
  String get startAction => 'Empezar';

  @override
  String get startHere => 'Empieza aquí';

  @override
  String get starting => 'Arrancando…';

  @override
  String get state => 'Estado';

  @override
  String get statusConnected => 'Conectado';

  @override
  String get statusConnecting => 'Conectando';

  @override
  String statusError(String error) {
    return 'Error: $error';
  }

  @override
  String get statusFailed => 'Ha fallado la conexión';

  @override
  String get statusIdle => 'Sin conectar';

  @override
  String get stepAppearance => 'Apariencia';

  @override
  String get stepAuthenticating => 'autenticando…';

  @override
  String get stepConnecting => 'conectando…';

  @override
  String get stepImport => 'Importar';

  @override
  String get stepOpeningSftp => 'abriendo SFTP…';

  @override
  String get stepOpeningShell => 'abriendo el shell…';

  @override
  String get stepReady => 'Listo';

  @override
  String get tags => 'Etiquetas';

  @override
  String get terminalAlwaysDark => 'Siempre oscuro';

  @override
  String get terminalAsTheme => 'Como el tema';

  @override
  String get terminalColors => 'Colores del terminal';

  @override
  String get terminalFont => 'Fuente del terminal';

  @override
  String get terminalScheme => 'Esquema propio';

  @override
  String terminalShortcuts(String key) {
    return '${key}F busca en el terminal y su historial. $key+ y $key− cambian el tamaño de la letra de la pestaña, y ${key}0 lo devuelve. Con $key pulsado, un clic abre un enlace.';
  }

  @override
  String get textSize => 'Tamaño del texto';

  @override
  String get textSizeHelp =>
      'De la interfaz, sobre el del sistema. El terminal tiene el suyo.';

  @override
  String get theHost => 'el host';

  @override
  String get theLocalNetwork => 'Toda la red local';

  @override
  String get theServerNetwork => 'La red del servidor';

  @override
  String get theme => 'Tema';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get themeHelp => 'En claro, Papel; en oscuro, Grafito.';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeSystem => 'Seguir al sistema';

  @override
  String themeVariant(String name, String variant) {
    return '$name ($variant)';
  }

  @override
  String get thisComputer => 'Este equipo';

  @override
  String get time => 'Tiempo';

  @override
  String timeLeft(String time) {
    return 'quedan $time';
  }

  @override
  String todayAt(String time) {
    return 'hoy $time';
  }

  @override
  String get transfers => 'Transferencias';

  @override
  String get trust => 'Confianza';

  @override
  String get trustAndConnect => 'Confiar y conectar';

  @override
  String trustCertified(String ca) {
    return 'certificada por la CA $ca';
  }

  @override
  String get trustKnown => 'conocida';

  @override
  String get trustNew => 'nueva, guardada ahora';

  @override
  String get trustNewKey => 'Confiar en la clave nueva';

  @override
  String get trustNewKeyEllipsis => 'Confiar en la clave nueva…';

  @override
  String trustedOn(String date) {
    return 'confiada el $date';
  }

  @override
  String get tryAgain => 'Reintentar';

  @override
  String get tunnelBadAddress => 'Esa dirección no existe en este equipo.';

  @override
  String get tunnelClosed => 'Cerrado';

  @override
  String tunnelDidNotOpen(String name, String why) {
    return 'No se abrió «$name» al conectar: $why';
  }

  @override
  String get tunnelEditorHint =>
      'Un puerto de este equipo que lleva a un servicio que solo ve el servidor, o al revés.';

  @override
  String get tunnelFailed => 'No se abrió';

  @override
  String get tunnelLost => 'Se cortó';

  @override
  String tunnelLostBody(String host) {
    return 'Se perdió la conexión con $host. Vuelve a abrirlo cuando haya conexión.';
  }

  @override
  String get tunnelNeedsDest => 'Falta el destino o su puerto.';

  @override
  String get tunnelNeedsHost => 'Elige el host por el que va.';

  @override
  String get tunnelNeedsName => 'Ponle un nombre.';

  @override
  String get tunnelOpen => 'Abierto';

  @override
  String tunnelOpenWith(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Abierto · $count conexiones',
      one: 'Abierto · 1 conexión',
    );
    return '$_temp0';
  }

  @override
  String get tunnelOpening => 'Abriendo…';

  @override
  String tunnelPortBusy(int port) {
    return 'el puerto $port de este equipo está ocupado.';
  }

  @override
  String tunnelRemotePortBusy(int port, String host) {
    return '$host no abrió el puerto $port (en uso o no permitido).';
  }

  @override
  String get tunnelType => 'Tipo';

  @override
  String get tunnels => 'Túneles';

  @override
  String tunnelsCount(int total, int open) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total túneles',
      one: '1 túnel',
    );
    String _temp1 = intl.Intl.pluralLogic(
      open,
      locale: localeName,
      other: '$open abiertos',
      one: '1 abierto',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get tunnelsIntro =>
      'Reenvíos de puertos guardados, cada uno con un host. Se abren a mano o al conectar al host, por la misma conexión que el terminal.';

  @override
  String get tunnelsKeepConnection =>
      'Un túnel abierto mantiene la conexión con su host aunque cierres la pestaña. Se cierra al cerrarlo aquí o al salir de OpenWard.';

  @override
  String tunnelsOf(String host) {
    return 'Túneles de $host';
  }

  @override
  String tunnelsOpenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count túneles abiertos',
      one: '1 túnel abierto',
    );
    return '$_temp0';
  }

  @override
  String get tunnelsStayOpen =>
      'Siguen abiertos si cierras esta pestaña. Todos en Biblioteca › Túneles.';

  @override
  String twoNames(String a, String b) {
    return '$a y $b';
  }

  @override
  String get typeOnly => 'Solo escribe';

  @override
  String get uiColors => 'Colores de la interfaz';

  @override
  String get uiFont => 'Fuente de la interfaz';

  @override
  String get upOneLevel => 'Subir un nivel';

  @override
  String get upload => 'Subida';

  @override
  String uploadToArrow(String where) {
    return 'Subir a $where →';
  }

  @override
  String uploadToHost(String host) {
    return 'Subir a $host';
  }

  @override
  String get useIdentityHint =>
      'Marca grupos o hosts. Un grupo la pasa a todos sus hosts, también a los que añadas después.';

  @override
  String useIdentityOn(String name) {
    return 'Usar «$name» en…';
  }

  @override
  String useIdentitySummary(int changed, int using) {
    String _temp0 = intl.Intl.pluralLogic(
      changed,
      locale: localeName,
      other: 'Cambian $changed hosts',
      one: 'Cambia 1 host',
      zero: 'No cambia ningún host',
    );
    String _temp1 = intl.Intl.pluralLogic(
      using,
      locale: localeName,
      other: 'la usarán $using',
      one: 'la usará 1',
      zero: 'no la usará ninguno',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get useOn => 'Usar en…';

  @override
  String usePort(int port) {
    return 'Usar el $port';
  }

  @override
  String get usedBy => 'La usan';

  @override
  String get usedByNobody => 'Nadie la usa todavía';

  @override
  String get user => 'Usuario';

  @override
  String get usualKeys => 'las habituales';

  @override
  String get variantDark => 'oscuro';

  @override
  String get variantDarkOnly => 'Oscuro';

  @override
  String get variantLight => 'claro';

  @override
  String get variantLightOnly => 'Claro';

  @override
  String get verificationTitle => 'Verificación';

  @override
  String via(String hops) {
    return 'vía $hops';
  }

  @override
  String get waitingAnswer => 'Esperando respuesta…';

  @override
  String get waitingForYou => 'Espera tu respuesta';

  @override
  String warnBadValue(String subject, String at, String detail) {
    return 'Valor no válido en $subject$at: $detail.';
  }

  @override
  String warnIncludeTooDeep(String at) {
    return 'Include anidado demasiado hondo$at.';
  }

  @override
  String warnJumpLossy(String alias, String jump) {
    return '$alias salta por $jump, que no es un host importado: se guarda como dirección, sin sus claves ni su ruta.';
  }

  @override
  String warnMatch(String at) {
    return 'Bloque Match$at: OpenWard no lo evalúa y sus líneas se han saltado.';
  }

  @override
  String warnStricter(String at) {
    return 'StrictHostKeyChecking no$at: se importa como «aceptar nuevas»; una clave que cambia nunca se acepta sin preguntar.';
  }

  @override
  String warnUnreadable(String file, String error) {
    return 'No se ha podido leer $file: $error.';
  }

  @override
  String warnUnsupported(String subject, String at) {
    return '$subject: no se importa$at.';
  }

  @override
  String get welcomeNoConfig =>
      'No hemos encontrado hosts en ~/.ssh/config. Podrás añadirlos a mano en un momento.';

  @override
  String get welcomeTitle => 'Te damos la bienvenida a OpenWard';

  @override
  String get whatsNew => 'Qué hay de nuevo';

  @override
  String get whatsNewIntro =>
      'Todo lo que hacías con tu cliente anterior, ya aquí. Lo verás una vez; está también en Ajustes › General.';

  @override
  String get whatsNewReport =>
      '¿Algo no va? Ajustes › General › Informar de un problema copia lo que hace falta para contarlo.';

  @override
  String get whereItIs => 'Dónde está';

  @override
  String get whoCanUse => 'Quién puede usarlo';

  @override
  String get withEnter => 'Intro al final';

  @override
  String get wrongAnswer => 'Respuesta incorrecta.';

  @override
  String get wrongPassphrase => 'Frase incorrecta.';

  @override
  String get wrongPassword => 'Contraseña incorrecta.';

  @override
  String get yes => 'Sí';

  @override
  String yesterdayAt(String time) {
    return 'ayer $time';
  }
}
