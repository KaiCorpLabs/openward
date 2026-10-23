import 'package:flutter_test/flutter_test.dart';
import 'package:openward/terminal/terminal_pane.dart';

void main() {
  test('a link whose text names another site misleads', () {
    expect(linkMisleads('bank.example.com', 'https://evil.test/x'), isTrue);
    expect(
      linkMisleads('https://bank.example.com/login', 'https://evil.test'),
      isTrue,
    );
    expect(
      linkMisleads('Bank.Example.com', 'https://bank.example.com/x'),
      isFalse,
    );
    // Words, or the URL itself, say nothing about where it goes.
    expect(linkMisleads('the docs', 'https://openward.dev'), isFalse);
    expect(linkMisleads('docs', 'https://openward.dev'), isFalse);
    expect(
      linkMisleads('https://openward.dev', 'https://openward.dev'),
      isFalse,
    );
  });
}
