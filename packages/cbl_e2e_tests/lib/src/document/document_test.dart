import 'dart:typed_data';

import 'package:cbl/cbl.dart';

import '../../test_binding_impl.dart';
import '../test_binding.dart';
import '../utils/api_variant.dart';
import '../utils/database_utils.dart';
import '../utils/matchers.dart';

void main() {
  setupTestBinding();

  Future<Document> savedDocument(
    Database db, [
    Map<String, Object?>? data,
  ]) async {
    final doc = MutableDocument(data);
    await db.saveDocument(doc);
    return (await db.document(doc.id))!;
  }

  group('Document', () {
    apiTest('properties', () async {
      final db = await openTestDatabase();
      const revisionId = '1-581ad726ee407c8376fc94aad966051d013893c4';
      final doc = MutableDocument.withId('id');

      expect(doc.id, 'id');
      expect(doc.revisionId, isNull);
      expect(doc.sequence, 0);

      await db.saveDocument(doc);

      expect(doc.revisionId, revisionId);
      expect(doc.sequence, 1);

      final loadedDoc = (await db.document(doc.id))!;

      expect(loadedDoc.id, 'id');
      expect(loadedDoc.revisionId, revisionId);
      expect(loadedDoc.sequence, 1);
    });

    apiTest('==', () async {
      final db = await openTestDatabase();
      final doc = await savedDocument(db, {'type': 'immutable'});

      // Identical docs are equal.
      expect(doc, equality(doc));

      // Two instances at the same revision are equal.
      expect(await db.document(doc.id), equality(doc));

      final mutableDoc = doc.toMutable();

      // Unmutated mutable copy is equal to original.
      expect(mutableDoc, equality(doc));

      mutableDoc['a'].value = 'b';

      // Mutated mutable copy is not equal.
      expect(mutableDoc, isNot(equality(doc)));

      expect(
        MutableDocument.withId('a'),
        equality(MutableDocument.withId('a')),
      );
      expect(
        MutableDocument.withId('a'),
        isNot(equality(MutableDocument.withId('b'))),
      );

      expect(
        MutableDocument.withId('a', {'a': true}),
        equality(MutableDocument.withId('a', {'a': true})),
      );
      expect(
        MutableDocument.withId('a', {'a': true}),
        isNot(equality(MutableDocument.withId('b', {'a': false}))),
      );
    });

    apiTest('hashCode', () async {
      final db = await openTestDatabase();
      final doc = await savedDocument(db, {'type': 'immutable'});

      expect(doc.hashCode, doc.hashCode);
      expect((await db.document(doc.id)).hashCode, doc.hashCode);

      expect(
        MutableDocument.withId('a').hashCode,
        MutableDocument.withId('a').hashCode,
      );
      expect(
        MutableDocument.withId('a').hashCode,
        isNot(MutableDocument.withId('b').hashCode),
      );

      expect(
        MutableDocument.withId('a', {'a': true}).hashCode,
        MutableDocument.withId('a', {'a': true}).hashCode,
      );
      expect(
        MutableDocument.withId('a', {'a': true}).hashCode,
        isNot(MutableDocument.withId('b', {'a': false}).hashCode),
      );
    });

    group('immutable', () {
      apiTest('implements DictionaryInterface for properties', () async {
        final db = await openTestDatabase();
        final date = DateTime.now();
        final blob = Blob.fromData('', Uint8List(0));
        final doc = await savedDocument(db, {
          'value': 'x',
          'string': 'a',
          'int': 1,
          'float': .2,
          'number': 3,
          'bool': true,
          'date': date,
          'blob': blob,
          'array': [false],
          'dictionary': {'key': 'value'},
        });

        expect(doc.length, 10);
        expect(
          doc.keys,
          unorderedEquals(<dynamic>[
            'value',
            'string',
            'int',
            'float',
            'number',
            'bool',
            'date',
            'blob',
            'array',
            'dictionary',
          ]),
        );
        expect(doc.value('value'), 'x');
        expect(doc.string('string'), 'a');
        expect(doc.integer('int'), 1);
        expect(doc.float('float'), .2);
        expect(doc.number('number'), 3);
        expect(doc.boolean('bool'), true);
        expect(doc.date('date'), date);
        expect(doc.blob('blob'), blob);
        expect(doc.array('array'), MutableArray([false]));
        expect(
          doc.dictionary('dictionary'),
          MutableDictionary({'key': 'value'}),
        );
        expect(doc.contains('value'), isTrue);
        expect(doc.contains('foo'), isFalse);
        expect(doc.toPlainMap(), {
          'value': 'x',
          'string': 'a',
          'int': 1,
          'float': .2,
          'number': 3,
          'bool': true,
          'date': date.toIso8601String(),
          'blob': blob,
          'array': [false],
          'dictionary': {'key': 'value'},
        });

        expect(doc['value'].value, 'x');
      });

      test('implements Iterable<String> for keys', () {
        final doc = MutableDocument({'a': null, 'b': null, 'c': null});
        expect(doc.toList(), ['a', 'b', 'c']);
      });

      apiTest('toMutable', () async {
        final db = await openTestDatabase();
        final doc = await savedDocument(db, {'type': 'immutable'});
        expect(doc, isNot(isA<MutableDocument>()));
        final mutableDoc = doc.toMutable();
        expect(mutableDoc, doc);
      });

      test('toString', () {
        final db = openSyncTestDatabase();
        final doc = MutableDocument();
        db.saveDocument(doc);
        final loadedDoc = db.document(doc.id);
        expect(
          loadedDoc.toString(),
          'Document('
          'id: ${doc.id}, '
          'revisionId: ${doc.revisionId}, '
          // ignore: missing_whitespace_between_adjacent_strings
          'sequence: ${doc.sequence}'
          ')',
        );
      });
    });

    group('mutable', () {
      test('create with id', () {
        final doc = MutableDocument.withId('id');
        expect(doc.id, 'id');
      });

      test('create with generated it', () {
        final doc = MutableDocument();
        expect(doc.id, startsWith('-'));
      });

      test('initialize with data', () {
        final data = {
          'null': null,
          'int': 1,
          'float': 3.1,
          'string': 'a',
          'bool': true,
          'array': [false],
          'dictionary': {'key': 'value'},
          'blob': Blob.fromData('', Uint8List(0)),
        };
        final doc = MutableDocument(data);
        expect(doc.toPlainMap(), data);
      });
    });

    test('implements MutableDictionaryInterface for properties', () {
      final date = DateTime.now();
      final blob = Blob.fromData('', Uint8List(0));
      final doc = MutableDocument()
        ..setValue('x', key: 'value')
        ..setString('a', key: 'string')
        ..setInteger(1, key: 'int')
        ..setFloat(.2, key: 'float')
        ..setNumber(3, key: 'number')
        ..setBoolean(true, key: 'bool')
        ..setDate(date, key: 'date')
        ..setBlob(blob, key: 'blob')
        ..setArray(MutableArray([true]), key: 'array')
        ..setDictionary(MutableDictionary({'key': 'value'}), key: 'dictionary');

      expect(doc.toPlainMap(), {
        'value': 'x',
        'string': 'a',
        'int': 1,
        'float': .2,
        'number': 3,
        'bool': true,
        'date': date.toIso8601String(),
        'blob': blob,
        'array': [true],
        'dictionary': {'key': 'value'},
      });

      doc.setData({'data': 'data'});
      expect(doc.toPlainMap(), {'data': 'data'});

      doc.removeValue('data');
      expect(doc, isEmpty);

      doc.setData({'array': <Object?>[], 'dictionary': <String, Object?>{}});
      expect(doc.array('array'), MutableArray());
      expect(doc.dictionary('dictionary'), MutableDictionary());

      doc['value'].value = 'x';
      expect(doc['value'].value, 'x');
    });

    test('toMutable', () {
      final doc = MutableDocument();
      expect(doc.toMutable(), same(doc));
    });

    test('toString', () {
      final mutableDoc = MutableDocument();
      expect(
        mutableDoc.toString(),
        'MutableDocument('
        'id: ${mutableDoc.id}, '
        'revisionId: ${mutableDoc.revisionId}, '
        // ignore: missing_whitespace_between_adjacent_strings
        'sequence: ${mutableDoc.sequence}'
        ')',
      );
    });
  });
}
