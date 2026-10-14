import 'package:flutter_test/flutter_test.dart';
import 'package:openward/hosts/editors.dart';

void main() {
  test('jump addresses', () {
    String? show(String text) {
      final j = parseJumpAddress(text);
      return j == null ? null : '${j.user}|${j.address}|${j.port}';
    }

    expect(show('bastion'), 'null|bastion|null');
    expect(show('ops@bastion:2222'), 'ops|bastion|2222');
    expect(show('ops@[::1]:22'), 'ops|::1|22');
    expect(show('[fe80::1]'), 'null|fe80::1|null');
    expect(show('host:port'), isNull);
    expect(show('@host'), isNull);
    expect(show('a b'), isNull);
    expect(show('host:70000'), isNull);
    expect(show(''), isNull);
  });
}
