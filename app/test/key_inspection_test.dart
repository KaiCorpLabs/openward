import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openward/identities/key_inspection.dart';
import 'package:openward/src/rust/api/identities.dart';

void main() {
  test('inspection identity snapshots mutable certificate selections', () {
    final certificates = ['first'];
    final before = KeyInspectionQuery('key', certificates);
    certificates.add('second');
    expect(before.certificates, ['first']);
    expect(before, KeyInspectionQuery('key', ['first']));
    expect(before.hashCode, KeyInspectionQuery('key', ['first']).hashCode);
    expect(before, isNot(KeyInspectionQuery('key', certificates)));
    expect(() => before.certificates.add('third'), throwsUnsupportedError);
  });

  test(
    'pending inspection is cached and a changed certificate reloads',
    () async {
      final pending = <Completer<KeyView>>[];
      final requests = <KeyInspectionQuery>[];
      final container = ProviderContainer(
        overrides: [
          keyInfoReaderProvider.overrideWithValue((path, certificates) {
            requests.add(KeyInspectionQuery(path, certificates));
            final result = Completer<KeyView>();
            pending.add(result);
            return result.future;
          }),
        ],
      );
      addTearDown(container.dispose);
      final original = keyInspectionProvider(
        KeyInspectionQuery('key', ['first']),
      );
      final subscription = container.listen(original, (_, _) {});
      addTearDown(subscription.close);
      expect(container.read(original).isLoading, isTrue);
      final same = keyInspectionProvider(KeyInspectionQuery('key', ['first']));
      expect(container.read(same).isLoading, isTrue);
      expect(requests.length, 1);
      // Other asynchronous work remains runnable while native inspection waits.
      var responsive = false;
      await Future<void>(() {
        responsive = true;
      });
      expect(responsive, isTrue);
      const info = KeyView(path: 'key', state: KeyStateKind.found);
      pending[0].complete(info);
      expect(await container.read(original.future), info);
      final changed = keyInspectionProvider(
        KeyInspectionQuery('key', ['second']),
      );
      final changedSubscription = container.listen(changed, (_, _) {});
      addTearDown(changedSubscription.close);
      expect(requests.length, 2);
      expect(requests.last.certificates, ['second']);
      pending[1].completeError(StateError('unreadable'));
      await expectLater(container.read(changed.future), throwsStateError);
      expect(container.read(changed).hasError, isTrue);
    },
  );
}
