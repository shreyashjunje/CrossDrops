// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $IdentityTable extends Identity
    with TableInfo<$IdentityTable, IdentityData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IdentityTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _slotMeta = const VerificationMeta('slot');
  @override
  late final GeneratedColumn<int> slot = GeneratedColumn<int>(
    'slot',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceNameMeta = const VerificationMeta(
    'deviceName',
  );
  @override
  late final GeneratedColumn<String> deviceName = GeneratedColumn<String>(
    'device_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _certificateMeta = const VerificationMeta(
    'certificate',
  );
  @override
  late final GeneratedColumn<String> certificate = GeneratedColumn<String>(
    'certificate',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    slot,
    deviceId,
    deviceName,
    certificate,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'identity';
  @override
  VerificationContext validateIntegrity(
    Insertable<IdentityData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('slot')) {
      context.handle(
        _slotMeta,
        slot.isAcceptableOrUnknown(data['slot']!, _slotMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('device_name')) {
      context.handle(
        _deviceNameMeta,
        deviceName.isAcceptableOrUnknown(data['device_name']!, _deviceNameMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceNameMeta);
    }
    if (data.containsKey('certificate')) {
      context.handle(
        _certificateMeta,
        certificate.isAcceptableOrUnknown(
          data['certificate']!,
          _certificateMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {slot};
  @override
  IdentityData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IdentityData(
      slot: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}slot'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      deviceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_name'],
      )!,
      certificate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}certificate'],
      ),
    );
  }

  @override
  $IdentityTable createAlias(String alias) {
    return $IdentityTable(attachedDatabase, alias);
  }
}

class IdentityData extends DataClass implements Insertable<IdentityData> {
  final int slot;
  final String deviceId;
  final String deviceName;

  /// PEM certificate. Null until the persistent identity lands in Phase 4.
  final String? certificate;
  const IdentityData({
    required this.slot,
    required this.deviceId,
    required this.deviceName,
    this.certificate,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['slot'] = Variable<int>(slot);
    map['device_id'] = Variable<String>(deviceId);
    map['device_name'] = Variable<String>(deviceName);
    if (!nullToAbsent || certificate != null) {
      map['certificate'] = Variable<String>(certificate);
    }
    return map;
  }

  IdentityCompanion toCompanion(bool nullToAbsent) {
    return IdentityCompanion(
      slot: Value(slot),
      deviceId: Value(deviceId),
      deviceName: Value(deviceName),
      certificate: certificate == null && nullToAbsent
          ? const Value.absent()
          : Value(certificate),
    );
  }

  factory IdentityData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IdentityData(
      slot: serializer.fromJson<int>(json['slot']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      deviceName: serializer.fromJson<String>(json['deviceName']),
      certificate: serializer.fromJson<String?>(json['certificate']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'slot': serializer.toJson<int>(slot),
      'deviceId': serializer.toJson<String>(deviceId),
      'deviceName': serializer.toJson<String>(deviceName),
      'certificate': serializer.toJson<String?>(certificate),
    };
  }

  IdentityData copyWith({
    int? slot,
    String? deviceId,
    String? deviceName,
    Value<String?> certificate = const Value.absent(),
  }) => IdentityData(
    slot: slot ?? this.slot,
    deviceId: deviceId ?? this.deviceId,
    deviceName: deviceName ?? this.deviceName,
    certificate: certificate.present ? certificate.value : this.certificate,
  );
  IdentityData copyWithCompanion(IdentityCompanion data) {
    return IdentityData(
      slot: data.slot.present ? data.slot.value : this.slot,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      deviceName: data.deviceName.present
          ? data.deviceName.value
          : this.deviceName,
      certificate: data.certificate.present
          ? data.certificate.value
          : this.certificate,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IdentityData(')
          ..write('slot: $slot, ')
          ..write('deviceId: $deviceId, ')
          ..write('deviceName: $deviceName, ')
          ..write('certificate: $certificate')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(slot, deviceId, deviceName, certificate);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IdentityData &&
          other.slot == this.slot &&
          other.deviceId == this.deviceId &&
          other.deviceName == this.deviceName &&
          other.certificate == this.certificate);
}

class IdentityCompanion extends UpdateCompanion<IdentityData> {
  final Value<int> slot;
  final Value<String> deviceId;
  final Value<String> deviceName;
  final Value<String?> certificate;
  const IdentityCompanion({
    this.slot = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.deviceName = const Value.absent(),
    this.certificate = const Value.absent(),
  });
  IdentityCompanion.insert({
    this.slot = const Value.absent(),
    required String deviceId,
    required String deviceName,
    this.certificate = const Value.absent(),
  }) : deviceId = Value(deviceId),
       deviceName = Value(deviceName);
  static Insertable<IdentityData> custom({
    Expression<int>? slot,
    Expression<String>? deviceId,
    Expression<String>? deviceName,
    Expression<String>? certificate,
  }) {
    return RawValuesInsertable({
      if (slot != null) 'slot': slot,
      if (deviceId != null) 'device_id': deviceId,
      if (deviceName != null) 'device_name': deviceName,
      if (certificate != null) 'certificate': certificate,
    });
  }

  IdentityCompanion copyWith({
    Value<int>? slot,
    Value<String>? deviceId,
    Value<String>? deviceName,
    Value<String?>? certificate,
  }) {
    return IdentityCompanion(
      slot: slot ?? this.slot,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      certificate: certificate ?? this.certificate,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (slot.present) {
      map['slot'] = Variable<int>(slot.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (deviceName.present) {
      map['device_name'] = Variable<String>(deviceName.value);
    }
    if (certificate.present) {
      map['certificate'] = Variable<String>(certificate.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IdentityCompanion(')
          ..write('slot: $slot, ')
          ..write('deviceId: $deviceId, ')
          ..write('deviceName: $deviceName, ')
          ..write('certificate: $certificate')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $IdentityTable identity = $IdentityTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [identity];
}

typedef $$IdentityTableCreateCompanionBuilder = IdentityCompanion Function({
  Value<int> slot,
  required String deviceId,
  required String deviceName,
  Value<String?> certificate,
});
typedef $$IdentityTableUpdateCompanionBuilder = IdentityCompanion Function({
  Value<int> slot,
  Value<String> deviceId,
  Value<String> deviceName,
  Value<String?> certificate,
});

class $$IdentityTableFilterComposer
    extends Composer<_$AppDatabase, $IdentityTable> {
  $$IdentityTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get certificate => $composableBuilder(
    column: $table.certificate,
    builder: (column) => ColumnFilters(column),
  );
}

class $$IdentityTableOrderingComposer
    extends Composer<_$AppDatabase, $IdentityTable> {
  $$IdentityTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get certificate => $composableBuilder(
    column: $table.certificate,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$IdentityTableAnnotationComposer
    extends Composer<_$AppDatabase, $IdentityTable> {
  $$IdentityTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get slot =>
      $composableBuilder(column: $table.slot, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get certificate => $composableBuilder(
    column: $table.certificate,
    builder: (column) => column,
  );
}

class $$IdentityTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $IdentityTable,
          IdentityData,
          $$IdentityTableFilterComposer,
          $$IdentityTableOrderingComposer,
          $$IdentityTableAnnotationComposer,
          $$IdentityTableCreateCompanionBuilder,
          $$IdentityTableUpdateCompanionBuilder,
          (
            IdentityData,
            BaseReferences<_$AppDatabase, $IdentityTable, IdentityData>,
          ),
          IdentityData,
          PrefetchHooks Function()
        > {
  $$IdentityTableTableManager(_$AppDatabase db, $IdentityTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IdentityTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IdentityTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IdentityTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> slot = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> deviceName = const Value.absent(),
                Value<String?> certificate = const Value.absent(),
              }) => IdentityCompanion(
                slot: slot,
                deviceId: deviceId,
                deviceName: deviceName,
                certificate: certificate,
              ),
          createCompanionCallback:
              ({
                Value<int> slot = const Value.absent(),
                required String deviceId,
                required String deviceName,
                Value<String?> certificate = const Value.absent(),
              }) => IdentityCompanion.insert(
                slot: slot,
                deviceId: deviceId,
                deviceName: deviceName,
                certificate: certificate,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$IdentityTable, IdentityData>(table),
                  BaseReferences<_$AppDatabase, $IdentityTable, IdentityData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$IdentityTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $IdentityTable,
      IdentityData,
      $$IdentityTableFilterComposer,
      $$IdentityTableOrderingComposer,
      $$IdentityTableAnnotationComposer,
      $$IdentityTableCreateCompanionBuilder,
      $$IdentityTableUpdateCompanionBuilder,
      (
        IdentityData,
        BaseReferences<_$AppDatabase, $IdentityTable, IdentityData>,
      ),
      IdentityData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$IdentityTableTableManager get identity =>
      $$IdentityTableTableManager(_db, _db.identity);
}
