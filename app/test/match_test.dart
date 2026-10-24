import 'package:flutter_test/flutter_test.dart';
import 'package:openward/core/match.dart';
import 'package:openward/core/providers.dart';
import 'package:openward/src/rust/api/vault.dart';

HostView _host(
  String id,
  String label,
  String address, {
  String user = '',
  String? group,
  List<String> tags = const [],
}) => HostView(
  id: id,
  label: label,
  address: address,
  groupId: group,
  tags: tags,
  user: user,
  port: 22,
);

GroupView _group(String id, String name, {String? parent}) =>
    GroupView(id: id, name: name, parentId: parent);

void main() {
  final library = Library(
    hosts: [
      _host('1', 'web-1', '10.0.0.1', group: 'web'),
      _host('2', 'web-2', 'web-2.example.com', group: 'staging'),
      _host('3', 'db-main', 'db.prod.example.com', user: 'postgres'),
      _host('4', 'cobweb', '10.0.9.9', tags: ['legacy']),
      _host('5', 'bastion', 'jump.example.com', group: 'prod'),
    ],
    groups: [
      _group('prod', 'Producción'),
      _group('web', 'Web', parent: 'prod'),
      _group('staging', 'Pruebas'),
    ],
  );
  List<String> found(String q) => [
    for (final h in HostMatcher(q, library).filter(library.hosts)) h.label,
  ];

  test('every word somewhere in the host, as the core searches', () {
    // «web prod»: web-1 is in Web, under Producción; db-main's address
    // says prod but not web; web-2 is in Pruebas.
    expect(found('web prod'), ['web-1']);
    expect(found('WEB   Producción'), ['web-1']);
    expect(found('postgres'), ['db-main'], reason: 'by user');
    expect(found('legacy'), ['cobweb'], reason: 'by tag');
    expect(found('pruebas'), ['web-2'], reason: 'by group');
    expect(found('nothing here'), isEmpty);
  });

  test('ranked by where it matched: the label first, its start best', () {
    expect(found('web'), ['web-1', 'web-2', 'cobweb']);
    // The same place in each: by label.
    expect(found('example'), ['bastion', 'db-main', 'web-2']);
    // The label's letters in order, but not the address's digits.
    expect(found('bstn'), ['bastion']);
    expect(found('101'), isEmpty);
    expect(HostMatcher('  ', library).isEmpty, isTrue);
  });

  test('a group that loops is read once', () {
    final looped = Library(
      hosts: [_host('1', 'a', 'a.example.com', group: 'x')],
      groups: [
        _group('x', 'X', parent: 'y'),
        _group('y', 'Y', parent: 'x'),
      ],
    );
    expect(HostMatcher('y', looped).filter(looped.hosts), hasLength(1));
    expect(HostMatcher('z', looped).filter(looped.hosts), isEmpty);
  });

  test('matchScore: the start, a word, anywhere, then the letters', () {
    expect(matchScore('web-1', ''), 0);
    expect(matchScore('prod-web', 'web'), 1);
    expect(matchScore('cobweb', 'web'), 2);
    expect(matchScore('bastion', 'btn'), 3);
    expect(matchScore('bastion', 'nb'), isNull);
  });
}
