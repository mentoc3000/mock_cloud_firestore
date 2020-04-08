library mock_cloud_firestore;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mock_cloud_firestore/factories.dart';
import 'package:mock_cloud_firestore/mock_types.dart';
import 'package:mockito/mockito.dart';

dynamic _reviveTimestamp(key, value) {
  if (value is Map && value.containsKey('_seconds') && value.containsKey('_nanoseconds')) {
    try {
      return Timestamp(value['_seconds'], value['_nanoseconds']);
    } catch (e) {
      return value;
    }
  }
  final timestampExp = RegExp(r'^Timestamp\(seconds=\d+, nanoseconds=\d+\)$');
  if (value is String && timestampExp.hasMatch(value)) {
    try {
      final secondsExp = RegExp(r'(?:\(seconds=)(\d+)(?:,)');
      final nanosecondsExp = RegExp(r'(?:nanoseconds=)(\d+)(?:\))');
      final seconds = int.tryParse(secondsExp.firstMatch(value).group(1));
      final nanoseconds = int.tryParse(nanosecondsExp.firstMatch(value).group(1));
      return Timestamp(seconds, nanoseconds);
    } catch (e) {
      return value;
    }
  }
  return value;
}

String newId() {
    // Alphanumeric characters
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    String autoId = '';
    final random = Random();
    for (int i = 0; i < 20; i++) {
      autoId += chars[(random.nextDouble() * chars.length).floor()];
    }
    return autoId;
  }

class MockCloudFirestore extends Mock {
  Map<String, dynamic> sourceParsed;
  Map<String, dynamic> whereData = {};
  Map<String, StreamController<QuerySnapshot>> snapshotStreams = {};
  Map<String, MockCollectionReference> collectionReferenceCache = {};

  MockCloudFirestore(String source) {
    sourceParsed = json.decode(source, reviver: _reviveTimestamp); 
    if (sourceParsed != null) {
      whereData = sourceParsed["__where__"];
    }
  }

  MockCollectionReference collection(String collectionName,
      {Map<String, dynamic> source}) {
    if (collectionReferenceCache[collectionName] != null) {
      return collectionReferenceCache[collectionName];
    }

    source ??= sourceParsed;
    Map<String, dynamic> colData = source[collectionName];
    Map<String, dynamic> whereData = {};
    if (colData != null) {
      whereData = colData["__where__"];
      colData.remove("__where__");
    }

    MockCollectionReference mcr =
        createCollectionReference(collectionName, colData, whereData);
    collectionReferenceCache[collectionName] = mcr;

    when(mcr.add(any)).thenAnswer((Invocation inv) {
      var value = inv.positionalArguments[0];
      final uuid = newId();
      MockDocumentReference mdr = createDocumentReferance(uuid, value);

      MockQuerySnapshot mqs = createMockQuerySnapshot(colData, added: [value]);
      mcr.controller.add(mqs);

      return Future.value(mdr);
    });

    when(mcr.document(any)).thenAnswer((invocation) {
      String documentID = invocation.positionalArguments[0];
      MockDocumentReference mdr = createDocumentReferance(documentID, null);
      return mdr;
    });
    if (colData == null) {
      return mcr;
    }
    colData.forEach((String key, dynamic value) {
      MockDocumentReference mdr = createDocumentReferance(key, value);
      when(mdr.documentID).thenReturn(key);
      when(mcr.document(key)).thenAnswer((_) => mdr);

      (value as Map<String, dynamic>).forEach((String k, dynamic v) {
        if (v is Map<String, dynamic> &&
            v.length > 0 &&
            v.entries.first.value is Map<String, dynamic>) {
          Map<String, dynamic> map = Map<String, dynamic>();
          map.addEntries([MapEntry<String, dynamic>(k, v)]);
          MockCollectionReference c = collection(k, source: map);
          when(mdr.collection(k)).thenAnswer((_) => c);
        }
      });
    });

    MockQuerySnapshot mqs = createMockQuerySnapshot(colData);

    when(mcr.snapshots()).thenAnswer((_) {
      Future<Null>.delayed(Duration.zero, () {
        mcr.controller.add(mqs);
      });
      return mcr.controller.stream;
    });
    when(mcr.getDocuments()).thenAnswer((_) {
      return Future<MockQuerySnapshot>.delayed(Duration.zero, () => mqs);
    });
    return mcr;
  }
}
