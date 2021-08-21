import 'dart:async';

import 'package:cbl_ffi/cbl_ffi.dart';

import '../database/proxy_database.dart';
import '../document/document.dart';
import '../document/proxy_document.dart';
import '../service/cbl_service.dart';
import '../service/cbl_service_api.dart';
import '../service/proxy_object.dart';
import '../support/encoding.dart';
import '../support/resource.dart';
import '../support/streams.dart';
import '../support/utils.dart';
import 'configuration.dart';
import 'conflict.dart';
import 'conflict_resolver.dart';
import 'document_replication.dart';
import 'replicator.dart';
import 'replicator_change.dart';

class ProxyReplicator extends ProxyObject
    with ClosableResourceMixin
    implements AsyncReplicator {
  ProxyReplicator({
    required this.database,
    required int objectId,
    required ReplicatorConfiguration configuration,
    required void Function() unregisterCallbacks,
  })  : assert(database == configuration.database),
        _config = ReplicatorConfiguration.from(configuration),
        _unregisterCallbacks = unregisterCallbacks,
        super(database.channel, objectId) {
    database.registerChildResource(this);
  }

  static Future<ProxyReplicator> create(
    ReplicatorConfiguration configuration,
  ) async {
    final database = configuration.database;
    if (database is! ProxyDatabase) {
      throw ArgumentError.value(
        database,
        'configuration.database',
        'must be a ProxyDatabase',
      );
    }
    final client = database.client;

    final pushFilterId = configuration.pushFilter
        ?.let((it) => _wrapReplicationFilter(it, database))
        .let(client.registerReplicationFilter);
    final pullFilterId = configuration.pullFilter
        ?.let((it) => _wrapReplicationFilter(it, database))
        .let(client.registerReplicationFilter);
    final conflictResolverId = configuration.conflictResolver
        ?.let((it) => _wrapConflictResolver(it, database))
        .let(client.registerConflictResolver);

    void unregisterCallbacks() {
      pushFilterId?.let(client.unregisterReplicationFilter);
      pullFilterId?.let(client.unregisterReplicationFilter);
      conflictResolverId?.let(client.unregisterConflictResolver);
    }

    try {
      final objectId = await database.channel.call(CreateReplicator(
        databaseObjectId: database.objectId,
        propertiesFormat: EncodingFormat.fleece,
        target: configuration.target,
        replicatorType: configuration.replicatorType,
        continuous: configuration.continuous,
        authenticator: configuration.authenticator,
        pinnedServerCertificate:
            configuration.pinnedServerCertificate?.toData(),
        headers: configuration.headers,
        channels: configuration.channels,
        documentIds: configuration.documentIds,
        pushFilterId: pushFilterId,
        pullFilterId: pullFilterId,
        conflictResolverId: conflictResolverId,
        heartbeat: configuration.heartbeat,
        maxRetries: configuration.maxRetries,
        maxRetryWaitTime: configuration.maxRetryWaitTime,
      ));
      return ProxyReplicator(
        database: database,
        objectId: objectId,
        configuration: configuration,
        unregisterCallbacks: unregisterCallbacks,
      );
    }
    // ignore: avoid_catches_without_on_clauses
    catch (e) {
      unregisterCallbacks();
      rethrow;
    }
  }

  final ProxyDatabase database;

  final void Function() _unregisterCallbacks;

  @override
  ReplicatorConfiguration get config => ReplicatorConfiguration.from(_config);
  final ReplicatorConfiguration _config;

  @override
  Future<ReplicatorStatus> get status =>
      use(() => channel.call(GetReplicatorStatus(
            replicatorObjectId: objectId,
          )));

  @override
  Future<void> start({bool reset = false}) =>
      use(() => channel.call(StartReplicator(
            replicatorObjectId: objectId,
            reset: reset,
          )));

  @override
  Future<void> stop() => use(_stop);

  Future<void> _stop() =>
      channel.call(StopReplicator(replicatorObjectId: objectId));

  @override
  Stream<ReplicatorChange> changes() => useSync(() => channel
      .stream(ReplicatorChanges(replicatorObjectId: objectId))
      .map((status) => ReplicatorChangeImpl(this, status))
      .toClosableResourceStream(this));

  @override
  Stream<DocumentReplication> documentReplications() => useSync(() => channel
      .stream(ReplicatorDocumentReplications(replicatorObjectId: objectId))
      .map((event) =>
          DocumentReplicationImpl(this, event.isPush, event.documents))
      .toClosableResourceStream(this));

  @override
  Future<bool> isDocumentPending(String documentId) =>
      use(() => channel.call(ReplicatorIsDocumentPending(
            replicatorObjectId: objectId,
            id: documentId,
          )));

  @override
  Future<Set<String>> get pendingDocumentIds => use(() => channel
      .call(ReplicatorPendingDocumentIds(replicatorObjectId: objectId))
      .then((value) => value.toSet()));

  @override
  Future<void> performClose() async {
    await _stop();
    _unregisterCallbacks();
    finalizeEarly();
  }
}

CblServiceReplicationFilter _wrapReplicationFilter(
  ReplicationFilter filter,
  ProxyDatabase database,
) =>
    (state, flags) => filter(_documentStateToDocument(database)(state), flags);

CblServiceConflictResolver _wrapConflictResolver(
  ConflictResolver resolver,
  ProxyDatabase database,
) =>
    (documentId, localState, remoteState) async {
      final local = localState?.let(_documentStateToDocument(database));
      final remote = remoteState?.let(_documentStateToDocument(database));
      final conflict = ConflictImpl(documentId, local, remote);

      final result = await resolver.resolve(conflict) as DelegateDocument?;

      if (result != null) {
        final includeProperties = result != local && result != remote;
        final delegate = await database.prepareDocument(
          result,
          syncProperties: includeProperties,
        );
        return delegate.getState(withProperties: includeProperties);
      }
    };

DelegateDocument Function(DocumentState) _documentStateToDocument(
  ProxyDatabase database,
) =>
    (state) => DelegateDocument(
          ProxyDocumentDelegate.fromState(state),
          database: database,
        );
