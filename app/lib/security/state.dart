import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../src/rust/api/security.dart';

bool vaultVisible(SecurityView view) =>
    view.phase == VaultPhase.legacy || view.phase == VaultPhase.unlocked;

class SecurityNotifier extends Notifier<SecurityView> {
  @override
  SecurityView build() {
    final app = ref.read(openWardProvider);
    final subscription = app.watchSecurity().listen((view) => state = view);
    ref.onDispose(subscription.cancel);
    return app.securityState();
  }
}

final securityProvider = NotifierProvider<SecurityNotifier, SecurityView>(
  SecurityNotifier.new,
);
