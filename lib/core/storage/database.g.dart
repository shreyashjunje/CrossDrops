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

  /// PEM certificate; its SHA-256 is the device identity. Null until the
  /// first launch creates it.
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

class $TransferSessionsTable extends TransferSessions
    with TableInfo<$TransferSessionsTable, SessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransferSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _directionMeta = const VerificationMeta(
    'direction',
  );
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerDeviceIdMeta = const VerificationMeta(
    'peerDeviceId',
  );
  @override
  late final GeneratedColumn<String> peerDeviceId = GeneratedColumn<String>(
    'peer_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerNameMeta = const VerificationMeta(
    'peerName',
  );
  @override
  late final GeneratedColumn<String> peerName = GeneratedColumn<String>(
    'peer_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerPlatformMeta = const VerificationMeta(
    'peerPlatform',
  );
  @override
  late final GeneratedColumn<String> peerPlatform = GeneratedColumn<String>(
    'peer_platform',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerHostMeta = const VerificationMeta(
    'peerHost',
  );
  @override
  late final GeneratedColumn<String> peerHost = GeneratedColumn<String>(
    'peer_host',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _peerPortMeta = const VerificationMeta(
    'peerPort',
  );
  @override
  late final GeneratedColumn<int> peerPort = GeneratedColumn<int>(
    'peer_port',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _peerFingerprintMeta = const VerificationMeta(
    'peerFingerprint',
  );
  @override
  late final GeneratedColumn<String> peerFingerprint = GeneratedColumn<String>(
    'peer_fingerprint',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalBytesMeta = const VerificationMeta(
    'totalBytes',
  );
  @override
  late final GeneratedColumn<int> totalBytes = GeneratedColumn<int>(
    'total_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _finishedAtMeta = const VerificationMeta(
    'finishedAt',
  );
  @override
  late final GeneratedColumn<DateTime> finishedAt = GeneratedColumn<DateTime>(
    'finished_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    direction,
    peerDeviceId,
    peerName,
    peerPlatform,
    peerHost,
    peerPort,
    peerFingerprint,
    status,
    reason,
    totalBytes,
    createdAt,
    updatedAt,
    finishedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('peer_device_id')) {
      context.handle(
        _peerDeviceIdMeta,
        peerDeviceId.isAcceptableOrUnknown(
          data['peer_device_id']!,
          _peerDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_peerDeviceIdMeta);
    }
    if (data.containsKey('peer_name')) {
      context.handle(
        _peerNameMeta,
        peerName.isAcceptableOrUnknown(data['peer_name']!, _peerNameMeta),
      );
    } else if (isInserting) {
      context.missing(_peerNameMeta);
    }
    if (data.containsKey('peer_platform')) {
      context.handle(
        _peerPlatformMeta,
        peerPlatform.isAcceptableOrUnknown(
          data['peer_platform']!,
          _peerPlatformMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_peerPlatformMeta);
    }
    if (data.containsKey('peer_host')) {
      context.handle(
        _peerHostMeta,
        peerHost.isAcceptableOrUnknown(data['peer_host']!, _peerHostMeta),
      );
    }
    if (data.containsKey('peer_port')) {
      context.handle(
        _peerPortMeta,
        peerPort.isAcceptableOrUnknown(data['peer_port']!, _peerPortMeta),
      );
    }
    if (data.containsKey('peer_fingerprint')) {
      context.handle(
        _peerFingerprintMeta,
        peerFingerprint.isAcceptableOrUnknown(
          data['peer_fingerprint']!,
          _peerFingerprintMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    }
    if (data.containsKey('total_bytes')) {
      context.handle(
        _totalBytesMeta,
        totalBytes.isAcceptableOrUnknown(data['total_bytes']!, _totalBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_totalBytesMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('finished_at')) {
      context.handle(
        _finishedAtMeta,
        finishedAt.isAcceptableOrUnknown(data['finished_at']!, _finishedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {sessionId, direction},
  ];
  @override
  SessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      direction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction'],
      )!,
      peerDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_device_id'],
      )!,
      peerName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_name'],
      )!,
      peerPlatform: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_platform'],
      )!,
      peerHost: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_host'],
      ),
      peerPort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}peer_port'],
      ),
      peerFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_fingerprint'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      ),
      totalBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_bytes'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      finishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}finished_at'],
      ),
    );
  }

  @override
  $TransferSessionsTable createAlias(String alias) {
    return $TransferSessionsTable(attachedDatabase, alias);
  }
}

class SessionRow extends DataClass implements Insertable<SessionRow> {
  final int id;
  final String sessionId;

  /// `send` or `receive`.
  final String direction;
  final String peerDeviceId;
  final String peerName;
  final String peerPlatform;

  /// Last known address of the receiver (send direction only).
  final String? peerHost;
  final int? peerPort;

  /// The peer's certificate fingerprint: who may continue a received
  /// session, and the pin when a sent session resumes. Null for sessions
  /// stored before Phase 4; those cannot resume.
  final String? peerFingerprint;

  /// A [SessionStatus] name.
  final String status;

  /// Why it was rejected, cancelled or failed.
  final String? reason;
  final int totalBytes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? finishedAt;
  const SessionRow({
    required this.id,
    required this.sessionId,
    required this.direction,
    required this.peerDeviceId,
    required this.peerName,
    required this.peerPlatform,
    this.peerHost,
    this.peerPort,
    this.peerFingerprint,
    required this.status,
    this.reason,
    required this.totalBytes,
    required this.createdAt,
    required this.updatedAt,
    this.finishedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['direction'] = Variable<String>(direction);
    map['peer_device_id'] = Variable<String>(peerDeviceId);
    map['peer_name'] = Variable<String>(peerName);
    map['peer_platform'] = Variable<String>(peerPlatform);
    if (!nullToAbsent || peerHost != null) {
      map['peer_host'] = Variable<String>(peerHost);
    }
    if (!nullToAbsent || peerPort != null) {
      map['peer_port'] = Variable<int>(peerPort);
    }
    if (!nullToAbsent || peerFingerprint != null) {
      map['peer_fingerprint'] = Variable<String>(peerFingerprint);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || reason != null) {
      map['reason'] = Variable<String>(reason);
    }
    map['total_bytes'] = Variable<int>(totalBytes);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || finishedAt != null) {
      map['finished_at'] = Variable<DateTime>(finishedAt);
    }
    return map;
  }

  TransferSessionsCompanion toCompanion(bool nullToAbsent) {
    return TransferSessionsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      direction: Value(direction),
      peerDeviceId: Value(peerDeviceId),
      peerName: Value(peerName),
      peerPlatform: Value(peerPlatform),
      peerHost: peerHost == null && nullToAbsent
          ? const Value.absent()
          : Value(peerHost),
      peerPort: peerPort == null && nullToAbsent
          ? const Value.absent()
          : Value(peerPort),
      peerFingerprint: peerFingerprint == null && nullToAbsent
          ? const Value.absent()
          : Value(peerFingerprint),
      status: Value(status),
      reason: reason == null && nullToAbsent
          ? const Value.absent()
          : Value(reason),
      totalBytes: Value(totalBytes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      finishedAt: finishedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(finishedAt),
    );
  }

  factory SessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionRow(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      direction: serializer.fromJson<String>(json['direction']),
      peerDeviceId: serializer.fromJson<String>(json['peerDeviceId']),
      peerName: serializer.fromJson<String>(json['peerName']),
      peerPlatform: serializer.fromJson<String>(json['peerPlatform']),
      peerHost: serializer.fromJson<String?>(json['peerHost']),
      peerPort: serializer.fromJson<int?>(json['peerPort']),
      peerFingerprint: serializer.fromJson<String?>(json['peerFingerprint']),
      status: serializer.fromJson<String>(json['status']),
      reason: serializer.fromJson<String?>(json['reason']),
      totalBytes: serializer.fromJson<int>(json['totalBytes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      finishedAt: serializer.fromJson<DateTime?>(json['finishedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'direction': serializer.toJson<String>(direction),
      'peerDeviceId': serializer.toJson<String>(peerDeviceId),
      'peerName': serializer.toJson<String>(peerName),
      'peerPlatform': serializer.toJson<String>(peerPlatform),
      'peerHost': serializer.toJson<String?>(peerHost),
      'peerPort': serializer.toJson<int?>(peerPort),
      'peerFingerprint': serializer.toJson<String?>(peerFingerprint),
      'status': serializer.toJson<String>(status),
      'reason': serializer.toJson<String?>(reason),
      'totalBytes': serializer.toJson<int>(totalBytes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'finishedAt': serializer.toJson<DateTime?>(finishedAt),
    };
  }

  SessionRow copyWith({
    int? id,
    String? sessionId,
    String? direction,
    String? peerDeviceId,
    String? peerName,
    String? peerPlatform,
    Value<String?> peerHost = const Value.absent(),
    Value<int?> peerPort = const Value.absent(),
    Value<String?> peerFingerprint = const Value.absent(),
    String? status,
    Value<String?> reason = const Value.absent(),
    int? totalBytes,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> finishedAt = const Value.absent(),
  }) => SessionRow(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    direction: direction ?? this.direction,
    peerDeviceId: peerDeviceId ?? this.peerDeviceId,
    peerName: peerName ?? this.peerName,
    peerPlatform: peerPlatform ?? this.peerPlatform,
    peerHost: peerHost.present ? peerHost.value : this.peerHost,
    peerPort: peerPort.present ? peerPort.value : this.peerPort,
    peerFingerprint: peerFingerprint.present
        ? peerFingerprint.value
        : this.peerFingerprint,
    status: status ?? this.status,
    reason: reason.present ? reason.value : this.reason,
    totalBytes: totalBytes ?? this.totalBytes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    finishedAt: finishedAt.present ? finishedAt.value : this.finishedAt,
  );
  SessionRow copyWithCompanion(TransferSessionsCompanion data) {
    return SessionRow(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      direction: data.direction.present ? data.direction.value : this.direction,
      peerDeviceId: data.peerDeviceId.present
          ? data.peerDeviceId.value
          : this.peerDeviceId,
      peerName: data.peerName.present ? data.peerName.value : this.peerName,
      peerPlatform: data.peerPlatform.present
          ? data.peerPlatform.value
          : this.peerPlatform,
      peerHost: data.peerHost.present ? data.peerHost.value : this.peerHost,
      peerPort: data.peerPort.present ? data.peerPort.value : this.peerPort,
      peerFingerprint: data.peerFingerprint.present
          ? data.peerFingerprint.value
          : this.peerFingerprint,
      status: data.status.present ? data.status.value : this.status,
      reason: data.reason.present ? data.reason.value : this.reason,
      totalBytes: data.totalBytes.present
          ? data.totalBytes.value
          : this.totalBytes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      finishedAt: data.finishedAt.present
          ? data.finishedAt.value
          : this.finishedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionRow(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('direction: $direction, ')
          ..write('peerDeviceId: $peerDeviceId, ')
          ..write('peerName: $peerName, ')
          ..write('peerPlatform: $peerPlatform, ')
          ..write('peerHost: $peerHost, ')
          ..write('peerPort: $peerPort, ')
          ..write('peerFingerprint: $peerFingerprint, ')
          ..write('status: $status, ')
          ..write('reason: $reason, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('finishedAt: $finishedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    direction,
    peerDeviceId,
    peerName,
    peerPlatform,
    peerHost,
    peerPort,
    peerFingerprint,
    status,
    reason,
    totalBytes,
    createdAt,
    updatedAt,
    finishedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionRow &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.direction == this.direction &&
          other.peerDeviceId == this.peerDeviceId &&
          other.peerName == this.peerName &&
          other.peerPlatform == this.peerPlatform &&
          other.peerHost == this.peerHost &&
          other.peerPort == this.peerPort &&
          other.peerFingerprint == this.peerFingerprint &&
          other.status == this.status &&
          other.reason == this.reason &&
          other.totalBytes == this.totalBytes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.finishedAt == this.finishedAt);
}

class TransferSessionsCompanion extends UpdateCompanion<SessionRow> {
  final Value<int> id;
  final Value<String> sessionId;
  final Value<String> direction;
  final Value<String> peerDeviceId;
  final Value<String> peerName;
  final Value<String> peerPlatform;
  final Value<String?> peerHost;
  final Value<int?> peerPort;
  final Value<String?> peerFingerprint;
  final Value<String> status;
  final Value<String?> reason;
  final Value<int> totalBytes;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> finishedAt;
  const TransferSessionsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.direction = const Value.absent(),
    this.peerDeviceId = const Value.absent(),
    this.peerName = const Value.absent(),
    this.peerPlatform = const Value.absent(),
    this.peerHost = const Value.absent(),
    this.peerPort = const Value.absent(),
    this.peerFingerprint = const Value.absent(),
    this.status = const Value.absent(),
    this.reason = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
  });
  TransferSessionsCompanion.insert({
    this.id = const Value.absent(),
    required String sessionId,
    required String direction,
    required String peerDeviceId,
    required String peerName,
    required String peerPlatform,
    this.peerHost = const Value.absent(),
    this.peerPort = const Value.absent(),
    this.peerFingerprint = const Value.absent(),
    required String status,
    this.reason = const Value.absent(),
    required int totalBytes,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.finishedAt = const Value.absent(),
  }) : sessionId = Value(sessionId),
       direction = Value(direction),
       peerDeviceId = Value(peerDeviceId),
       peerName = Value(peerName),
       peerPlatform = Value(peerPlatform),
       status = Value(status),
       totalBytes = Value(totalBytes),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SessionRow> custom({
    Expression<int>? id,
    Expression<String>? sessionId,
    Expression<String>? direction,
    Expression<String>? peerDeviceId,
    Expression<String>? peerName,
    Expression<String>? peerPlatform,
    Expression<String>? peerHost,
    Expression<int>? peerPort,
    Expression<String>? peerFingerprint,
    Expression<String>? status,
    Expression<String>? reason,
    Expression<int>? totalBytes,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? finishedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (direction != null) 'direction': direction,
      if (peerDeviceId != null) 'peer_device_id': peerDeviceId,
      if (peerName != null) 'peer_name': peerName,
      if (peerPlatform != null) 'peer_platform': peerPlatform,
      if (peerHost != null) 'peer_host': peerHost,
      if (peerPort != null) 'peer_port': peerPort,
      if (peerFingerprint != null) 'peer_fingerprint': peerFingerprint,
      if (status != null) 'status': status,
      if (reason != null) 'reason': reason,
      if (totalBytes != null) 'total_bytes': totalBytes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (finishedAt != null) 'finished_at': finishedAt,
    });
  }

  TransferSessionsCompanion copyWith({
    Value<int>? id,
    Value<String>? sessionId,
    Value<String>? direction,
    Value<String>? peerDeviceId,
    Value<String>? peerName,
    Value<String>? peerPlatform,
    Value<String?>? peerHost,
    Value<int?>? peerPort,
    Value<String?>? peerFingerprint,
    Value<String>? status,
    Value<String?>? reason,
    Value<int>? totalBytes,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? finishedAt,
  }) {
    return TransferSessionsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      direction: direction ?? this.direction,
      peerDeviceId: peerDeviceId ?? this.peerDeviceId,
      peerName: peerName ?? this.peerName,
      peerPlatform: peerPlatform ?? this.peerPlatform,
      peerHost: peerHost ?? this.peerHost,
      peerPort: peerPort ?? this.peerPort,
      peerFingerprint: peerFingerprint ?? this.peerFingerprint,
      status: status ?? this.status,
      reason: reason ?? this.reason,
      totalBytes: totalBytes ?? this.totalBytes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      finishedAt: finishedAt ?? this.finishedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (peerDeviceId.present) {
      map['peer_device_id'] = Variable<String>(peerDeviceId.value);
    }
    if (peerName.present) {
      map['peer_name'] = Variable<String>(peerName.value);
    }
    if (peerPlatform.present) {
      map['peer_platform'] = Variable<String>(peerPlatform.value);
    }
    if (peerHost.present) {
      map['peer_host'] = Variable<String>(peerHost.value);
    }
    if (peerPort.present) {
      map['peer_port'] = Variable<int>(peerPort.value);
    }
    if (peerFingerprint.present) {
      map['peer_fingerprint'] = Variable<String>(peerFingerprint.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (totalBytes.present) {
      map['total_bytes'] = Variable<int>(totalBytes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (finishedAt.present) {
      map['finished_at'] = Variable<DateTime>(finishedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransferSessionsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('direction: $direction, ')
          ..write('peerDeviceId: $peerDeviceId, ')
          ..write('peerName: $peerName, ')
          ..write('peerPlatform: $peerPlatform, ')
          ..write('peerHost: $peerHost, ')
          ..write('peerPort: $peerPort, ')
          ..write('peerFingerprint: $peerFingerprint, ')
          ..write('status: $status, ')
          ..write('reason: $reason, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('finishedAt: $finishedAt')
          ..write(')'))
        .toString();
  }
}

class $SessionFilesTable extends SessionFiles
    with TableInfo<$SessionFilesTable, SessionFileRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionFilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionRowIdMeta = const VerificationMeta(
    'sessionRowId',
  );
  @override
  late final GeneratedColumn<int> sessionRowId = GeneratedColumn<int>(
    'session_row_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _fileIdMeta = const VerificationMeta('fileId');
  @override
  late final GeneratedColumn<String> fileId = GeneratedColumn<String>(
    'file_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeMeta = const VerificationMeta('mime');
  @override
  late final GeneratedColumn<String> mime = GeneratedColumn<String>(
    'mime',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdMeta = const VerificationMeta(
    'created',
  );
  @override
  late final GeneratedColumn<DateTime> created = GeneratedColumn<DateTime>(
    'created',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _livePhotoGroupMeta = const VerificationMeta(
    'livePhotoGroup',
  );
  @override
  late final GeneratedColumn<String> livePhotoGroup = GeneratedColumn<String>(
    'live_photo_group',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _transferredBytesMeta = const VerificationMeta(
    'transferredBytes',
  );
  @override
  late final GeneratedColumn<int> transferredBytes = GeneratedColumn<int>(
    'transferred_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _tempPathMeta = const VerificationMeta(
    'tempPath',
  );
  @override
  late final GeneratedColumn<String> tempPath = GeneratedColumn<String>(
    'temp_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourcePathMeta = const VerificationMeta(
    'sourcePath',
  );
  @override
  late final GeneratedColumn<String> sourcePath = GeneratedColumn<String>(
    'source_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _finalLocationMeta = const VerificationMeta(
    'finalLocation',
  );
  @override
  late final GeneratedColumn<String> finalLocation = GeneratedColumn<String>(
    'final_location',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hashAttemptsMeta = const VerificationMeta(
    'hashAttempts',
  );
  @override
  late final GeneratedColumn<int> hashAttempts = GeneratedColumn<int>(
    'hash_attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _errorCodeMeta = const VerificationMeta(
    'errorCode',
  );
  @override
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
    'error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionRowId,
    fileId,
    position,
    name,
    size,
    mime,
    kind,
    created,
    livePhotoGroup,
    sha256,
    transferredBytes,
    tempPath,
    sourcePath,
    finalLocation,
    status,
    hashAttempts,
    errorCode,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'session_files';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionFileRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_row_id')) {
      context.handle(
        _sessionRowIdMeta,
        sessionRowId.isAcceptableOrUnknown(
          data['session_row_id']!,
          _sessionRowIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sessionRowIdMeta);
    }
    if (data.containsKey('file_id')) {
      context.handle(
        _fileIdMeta,
        fileId.isAcceptableOrUnknown(data['file_id']!, _fileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_fileIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    if (data.containsKey('mime')) {
      context.handle(
        _mimeMeta,
        mime.isAcceptableOrUnknown(data['mime']!, _mimeMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('created')) {
      context.handle(
        _createdMeta,
        created.isAcceptableOrUnknown(data['created']!, _createdMeta),
      );
    }
    if (data.containsKey('live_photo_group')) {
      context.handle(
        _livePhotoGroupMeta,
        livePhotoGroup.isAcceptableOrUnknown(
          data['live_photo_group']!,
          _livePhotoGroupMeta,
        ),
      );
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    }
    if (data.containsKey('transferred_bytes')) {
      context.handle(
        _transferredBytesMeta,
        transferredBytes.isAcceptableOrUnknown(
          data['transferred_bytes']!,
          _transferredBytesMeta,
        ),
      );
    }
    if (data.containsKey('temp_path')) {
      context.handle(
        _tempPathMeta,
        tempPath.isAcceptableOrUnknown(data['temp_path']!, _tempPathMeta),
      );
    }
    if (data.containsKey('source_path')) {
      context.handle(
        _sourcePathMeta,
        sourcePath.isAcceptableOrUnknown(data['source_path']!, _sourcePathMeta),
      );
    }
    if (data.containsKey('final_location')) {
      context.handle(
        _finalLocationMeta,
        finalLocation.isAcceptableOrUnknown(
          data['final_location']!,
          _finalLocationMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('hash_attempts')) {
      context.handle(
        _hashAttemptsMeta,
        hashAttempts.isAcceptableOrUnknown(
          data['hash_attempts']!,
          _hashAttemptsMeta,
        ),
      );
    }
    if (data.containsKey('error_code')) {
      context.handle(
        _errorCodeMeta,
        errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionRowId, fileId};
  @override
  SessionFileRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionFileRow(
      sessionRowId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_row_id'],
      )!,
      fileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      mime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      created: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created'],
      ),
      livePhotoGroup: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}live_photo_group'],
      ),
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      ),
      transferredBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}transferred_bytes'],
      )!,
      tempPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}temp_path'],
      ),
      sourcePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_path'],
      ),
      finalLocation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}final_location'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      hashAttempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hash_attempts'],
      )!,
      errorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_code'],
      ),
    );
  }

  @override
  $SessionFilesTable createAlias(String alias) {
    return $SessionFilesTable(attachedDatabase, alias);
  }
}

class SessionFileRow extends DataClass implements Insertable<SessionFileRow> {
  final int sessionRowId;
  final String fileId;
  final int position;

  /// As offered (receive) or picked (send). Local only; never logged.
  final String name;
  final int size;
  final String? mime;
  final String kind;
  final DateTime? created;
  final String? livePhotoGroup;
  final String? sha256;

  /// Receive: bytes known to be on disk (checkpoint). Send: bytes the
  /// receiver confirmed.
  final int transferredBytes;
  final String? tempPath;

  /// Send direction: the file being read.
  final String? sourcePath;
  final String? finalLocation;

  /// A [FileTransferStatus] name.
  final String status;

  /// Hash checks that failed; the file fails for good after the second.
  final int hashAttempts;
  final String? errorCode;
  const SessionFileRow({
    required this.sessionRowId,
    required this.fileId,
    required this.position,
    required this.name,
    required this.size,
    this.mime,
    required this.kind,
    this.created,
    this.livePhotoGroup,
    this.sha256,
    required this.transferredBytes,
    this.tempPath,
    this.sourcePath,
    this.finalLocation,
    required this.status,
    required this.hashAttempts,
    this.errorCode,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_row_id'] = Variable<int>(sessionRowId);
    map['file_id'] = Variable<String>(fileId);
    map['position'] = Variable<int>(position);
    map['name'] = Variable<String>(name);
    map['size'] = Variable<int>(size);
    if (!nullToAbsent || mime != null) {
      map['mime'] = Variable<String>(mime);
    }
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || created != null) {
      map['created'] = Variable<DateTime>(created);
    }
    if (!nullToAbsent || livePhotoGroup != null) {
      map['live_photo_group'] = Variable<String>(livePhotoGroup);
    }
    if (!nullToAbsent || sha256 != null) {
      map['sha256'] = Variable<String>(sha256);
    }
    map['transferred_bytes'] = Variable<int>(transferredBytes);
    if (!nullToAbsent || tempPath != null) {
      map['temp_path'] = Variable<String>(tempPath);
    }
    if (!nullToAbsent || sourcePath != null) {
      map['source_path'] = Variable<String>(sourcePath);
    }
    if (!nullToAbsent || finalLocation != null) {
      map['final_location'] = Variable<String>(finalLocation);
    }
    map['status'] = Variable<String>(status);
    map['hash_attempts'] = Variable<int>(hashAttempts);
    if (!nullToAbsent || errorCode != null) {
      map['error_code'] = Variable<String>(errorCode);
    }
    return map;
  }

  SessionFilesCompanion toCompanion(bool nullToAbsent) {
    return SessionFilesCompanion(
      sessionRowId: Value(sessionRowId),
      fileId: Value(fileId),
      position: Value(position),
      name: Value(name),
      size: Value(size),
      mime: mime == null && nullToAbsent ? const Value.absent() : Value(mime),
      kind: Value(kind),
      created: created == null && nullToAbsent
          ? const Value.absent()
          : Value(created),
      livePhotoGroup: livePhotoGroup == null && nullToAbsent
          ? const Value.absent()
          : Value(livePhotoGroup),
      sha256: sha256 == null && nullToAbsent
          ? const Value.absent()
          : Value(sha256),
      transferredBytes: Value(transferredBytes),
      tempPath: tempPath == null && nullToAbsent
          ? const Value.absent()
          : Value(tempPath),
      sourcePath: sourcePath == null && nullToAbsent
          ? const Value.absent()
          : Value(sourcePath),
      finalLocation: finalLocation == null && nullToAbsent
          ? const Value.absent()
          : Value(finalLocation),
      status: Value(status),
      hashAttempts: Value(hashAttempts),
      errorCode: errorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(errorCode),
    );
  }

  factory SessionFileRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionFileRow(
      sessionRowId: serializer.fromJson<int>(json['sessionRowId']),
      fileId: serializer.fromJson<String>(json['fileId']),
      position: serializer.fromJson<int>(json['position']),
      name: serializer.fromJson<String>(json['name']),
      size: serializer.fromJson<int>(json['size']),
      mime: serializer.fromJson<String?>(json['mime']),
      kind: serializer.fromJson<String>(json['kind']),
      created: serializer.fromJson<DateTime?>(json['created']),
      livePhotoGroup: serializer.fromJson<String?>(json['livePhotoGroup']),
      sha256: serializer.fromJson<String?>(json['sha256']),
      transferredBytes: serializer.fromJson<int>(json['transferredBytes']),
      tempPath: serializer.fromJson<String?>(json['tempPath']),
      sourcePath: serializer.fromJson<String?>(json['sourcePath']),
      finalLocation: serializer.fromJson<String?>(json['finalLocation']),
      status: serializer.fromJson<String>(json['status']),
      hashAttempts: serializer.fromJson<int>(json['hashAttempts']),
      errorCode: serializer.fromJson<String?>(json['errorCode']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionRowId': serializer.toJson<int>(sessionRowId),
      'fileId': serializer.toJson<String>(fileId),
      'position': serializer.toJson<int>(position),
      'name': serializer.toJson<String>(name),
      'size': serializer.toJson<int>(size),
      'mime': serializer.toJson<String?>(mime),
      'kind': serializer.toJson<String>(kind),
      'created': serializer.toJson<DateTime?>(created),
      'livePhotoGroup': serializer.toJson<String?>(livePhotoGroup),
      'sha256': serializer.toJson<String?>(sha256),
      'transferredBytes': serializer.toJson<int>(transferredBytes),
      'tempPath': serializer.toJson<String?>(tempPath),
      'sourcePath': serializer.toJson<String?>(sourcePath),
      'finalLocation': serializer.toJson<String?>(finalLocation),
      'status': serializer.toJson<String>(status),
      'hashAttempts': serializer.toJson<int>(hashAttempts),
      'errorCode': serializer.toJson<String?>(errorCode),
    };
  }

  SessionFileRow copyWith({
    int? sessionRowId,
    String? fileId,
    int? position,
    String? name,
    int? size,
    Value<String?> mime = const Value.absent(),
    String? kind,
    Value<DateTime?> created = const Value.absent(),
    Value<String?> livePhotoGroup = const Value.absent(),
    Value<String?> sha256 = const Value.absent(),
    int? transferredBytes,
    Value<String?> tempPath = const Value.absent(),
    Value<String?> sourcePath = const Value.absent(),
    Value<String?> finalLocation = const Value.absent(),
    String? status,
    int? hashAttempts,
    Value<String?> errorCode = const Value.absent(),
  }) => SessionFileRow(
    sessionRowId: sessionRowId ?? this.sessionRowId,
    fileId: fileId ?? this.fileId,
    position: position ?? this.position,
    name: name ?? this.name,
    size: size ?? this.size,
    mime: mime.present ? mime.value : this.mime,
    kind: kind ?? this.kind,
    created: created.present ? created.value : this.created,
    livePhotoGroup: livePhotoGroup.present
        ? livePhotoGroup.value
        : this.livePhotoGroup,
    sha256: sha256.present ? sha256.value : this.sha256,
    transferredBytes: transferredBytes ?? this.transferredBytes,
    tempPath: tempPath.present ? tempPath.value : this.tempPath,
    sourcePath: sourcePath.present ? sourcePath.value : this.sourcePath,
    finalLocation: finalLocation.present
        ? finalLocation.value
        : this.finalLocation,
    status: status ?? this.status,
    hashAttempts: hashAttempts ?? this.hashAttempts,
    errorCode: errorCode.present ? errorCode.value : this.errorCode,
  );
  SessionFileRow copyWithCompanion(SessionFilesCompanion data) {
    return SessionFileRow(
      sessionRowId: data.sessionRowId.present
          ? data.sessionRowId.value
          : this.sessionRowId,
      fileId: data.fileId.present ? data.fileId.value : this.fileId,
      position: data.position.present ? data.position.value : this.position,
      name: data.name.present ? data.name.value : this.name,
      size: data.size.present ? data.size.value : this.size,
      mime: data.mime.present ? data.mime.value : this.mime,
      kind: data.kind.present ? data.kind.value : this.kind,
      created: data.created.present ? data.created.value : this.created,
      livePhotoGroup: data.livePhotoGroup.present
          ? data.livePhotoGroup.value
          : this.livePhotoGroup,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      transferredBytes: data.transferredBytes.present
          ? data.transferredBytes.value
          : this.transferredBytes,
      tempPath: data.tempPath.present ? data.tempPath.value : this.tempPath,
      sourcePath: data.sourcePath.present
          ? data.sourcePath.value
          : this.sourcePath,
      finalLocation: data.finalLocation.present
          ? data.finalLocation.value
          : this.finalLocation,
      status: data.status.present ? data.status.value : this.status,
      hashAttempts: data.hashAttempts.present
          ? data.hashAttempts.value
          : this.hashAttempts,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionFileRow(')
          ..write('sessionRowId: $sessionRowId, ')
          ..write('fileId: $fileId, ')
          ..write('position: $position, ')
          ..write('name: $name, ')
          ..write('size: $size, ')
          ..write('mime: $mime, ')
          ..write('kind: $kind, ')
          ..write('created: $created, ')
          ..write('livePhotoGroup: $livePhotoGroup, ')
          ..write('sha256: $sha256, ')
          ..write('transferredBytes: $transferredBytes, ')
          ..write('tempPath: $tempPath, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('finalLocation: $finalLocation, ')
          ..write('status: $status, ')
          ..write('hashAttempts: $hashAttempts, ')
          ..write('errorCode: $errorCode')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sessionRowId,
    fileId,
    position,
    name,
    size,
    mime,
    kind,
    created,
    livePhotoGroup,
    sha256,
    transferredBytes,
    tempPath,
    sourcePath,
    finalLocation,
    status,
    hashAttempts,
    errorCode,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionFileRow &&
          other.sessionRowId == this.sessionRowId &&
          other.fileId == this.fileId &&
          other.position == this.position &&
          other.name == this.name &&
          other.size == this.size &&
          other.mime == this.mime &&
          other.kind == this.kind &&
          other.created == this.created &&
          other.livePhotoGroup == this.livePhotoGroup &&
          other.sha256 == this.sha256 &&
          other.transferredBytes == this.transferredBytes &&
          other.tempPath == this.tempPath &&
          other.sourcePath == this.sourcePath &&
          other.finalLocation == this.finalLocation &&
          other.status == this.status &&
          other.hashAttempts == this.hashAttempts &&
          other.errorCode == this.errorCode);
}

class SessionFilesCompanion extends UpdateCompanion<SessionFileRow> {
  final Value<int> sessionRowId;
  final Value<String> fileId;
  final Value<int> position;
  final Value<String> name;
  final Value<int> size;
  final Value<String?> mime;
  final Value<String> kind;
  final Value<DateTime?> created;
  final Value<String?> livePhotoGroup;
  final Value<String?> sha256;
  final Value<int> transferredBytes;
  final Value<String?> tempPath;
  final Value<String?> sourcePath;
  final Value<String?> finalLocation;
  final Value<String> status;
  final Value<int> hashAttempts;
  final Value<String?> errorCode;
  final Value<int> rowid;
  const SessionFilesCompanion({
    this.sessionRowId = const Value.absent(),
    this.fileId = const Value.absent(),
    this.position = const Value.absent(),
    this.name = const Value.absent(),
    this.size = const Value.absent(),
    this.mime = const Value.absent(),
    this.kind = const Value.absent(),
    this.created = const Value.absent(),
    this.livePhotoGroup = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.transferredBytes = const Value.absent(),
    this.tempPath = const Value.absent(),
    this.sourcePath = const Value.absent(),
    this.finalLocation = const Value.absent(),
    this.status = const Value.absent(),
    this.hashAttempts = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionFilesCompanion.insert({
    required int sessionRowId,
    required String fileId,
    required int position,
    required String name,
    required int size,
    this.mime = const Value.absent(),
    required String kind,
    this.created = const Value.absent(),
    this.livePhotoGroup = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.transferredBytes = const Value.absent(),
    this.tempPath = const Value.absent(),
    this.sourcePath = const Value.absent(),
    this.finalLocation = const Value.absent(),
    required String status,
    this.hashAttempts = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sessionRowId = Value(sessionRowId),
       fileId = Value(fileId),
       position = Value(position),
       name = Value(name),
       size = Value(size),
       kind = Value(kind),
       status = Value(status);
  static Insertable<SessionFileRow> custom({
    Expression<int>? sessionRowId,
    Expression<String>? fileId,
    Expression<int>? position,
    Expression<String>? name,
    Expression<int>? size,
    Expression<String>? mime,
    Expression<String>? kind,
    Expression<DateTime>? created,
    Expression<String>? livePhotoGroup,
    Expression<String>? sha256,
    Expression<int>? transferredBytes,
    Expression<String>? tempPath,
    Expression<String>? sourcePath,
    Expression<String>? finalLocation,
    Expression<String>? status,
    Expression<int>? hashAttempts,
    Expression<String>? errorCode,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionRowId != null) 'session_row_id': sessionRowId,
      if (fileId != null) 'file_id': fileId,
      if (position != null) 'position': position,
      if (name != null) 'name': name,
      if (size != null) 'size': size,
      if (mime != null) 'mime': mime,
      if (kind != null) 'kind': kind,
      if (created != null) 'created': created,
      if (livePhotoGroup != null) 'live_photo_group': livePhotoGroup,
      if (sha256 != null) 'sha256': sha256,
      if (transferredBytes != null) 'transferred_bytes': transferredBytes,
      if (tempPath != null) 'temp_path': tempPath,
      if (sourcePath != null) 'source_path': sourcePath,
      if (finalLocation != null) 'final_location': finalLocation,
      if (status != null) 'status': status,
      if (hashAttempts != null) 'hash_attempts': hashAttempts,
      if (errorCode != null) 'error_code': errorCode,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionFilesCompanion copyWith({
    Value<int>? sessionRowId,
    Value<String>? fileId,
    Value<int>? position,
    Value<String>? name,
    Value<int>? size,
    Value<String?>? mime,
    Value<String>? kind,
    Value<DateTime?>? created,
    Value<String?>? livePhotoGroup,
    Value<String?>? sha256,
    Value<int>? transferredBytes,
    Value<String?>? tempPath,
    Value<String?>? sourcePath,
    Value<String?>? finalLocation,
    Value<String>? status,
    Value<int>? hashAttempts,
    Value<String?>? errorCode,
    Value<int>? rowid,
  }) {
    return SessionFilesCompanion(
      sessionRowId: sessionRowId ?? this.sessionRowId,
      fileId: fileId ?? this.fileId,
      position: position ?? this.position,
      name: name ?? this.name,
      size: size ?? this.size,
      mime: mime ?? this.mime,
      kind: kind ?? this.kind,
      created: created ?? this.created,
      livePhotoGroup: livePhotoGroup ?? this.livePhotoGroup,
      sha256: sha256 ?? this.sha256,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      tempPath: tempPath ?? this.tempPath,
      sourcePath: sourcePath ?? this.sourcePath,
      finalLocation: finalLocation ?? this.finalLocation,
      status: status ?? this.status,
      hashAttempts: hashAttempts ?? this.hashAttempts,
      errorCode: errorCode ?? this.errorCode,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionRowId.present) {
      map['session_row_id'] = Variable<int>(sessionRowId.value);
    }
    if (fileId.present) {
      map['file_id'] = Variable<String>(fileId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (mime.present) {
      map['mime'] = Variable<String>(mime.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (created.present) {
      map['created'] = Variable<DateTime>(created.value);
    }
    if (livePhotoGroup.present) {
      map['live_photo_group'] = Variable<String>(livePhotoGroup.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (transferredBytes.present) {
      map['transferred_bytes'] = Variable<int>(transferredBytes.value);
    }
    if (tempPath.present) {
      map['temp_path'] = Variable<String>(tempPath.value);
    }
    if (sourcePath.present) {
      map['source_path'] = Variable<String>(sourcePath.value);
    }
    if (finalLocation.present) {
      map['final_location'] = Variable<String>(finalLocation.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (hashAttempts.present) {
      map['hash_attempts'] = Variable<int>(hashAttempts.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionFilesCompanion(')
          ..write('sessionRowId: $sessionRowId, ')
          ..write('fileId: $fileId, ')
          ..write('position: $position, ')
          ..write('name: $name, ')
          ..write('size: $size, ')
          ..write('mime: $mime, ')
          ..write('kind: $kind, ')
          ..write('created: $created, ')
          ..write('livePhotoGroup: $livePhotoGroup, ')
          ..write('sha256: $sha256, ')
          ..write('transferredBytes: $transferredBytes, ')
          ..write('tempPath: $tempPath, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('finalLocation: $finalLocation, ')
          ..write('status: $status, ')
          ..write('hashAttempts: $hashAttempts, ')
          ..write('errorCode: $errorCode, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TrustedDevicesTable extends TrustedDevices
    with TableInfo<$TrustedDevicesTable, TrustedDeviceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrustedDevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _platformMeta = const VerificationMeta(
    'platform',
  );
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _autoAcceptMeta = const VerificationMeta(
    'autoAccept',
  );
  @override
  late final GeneratedColumn<bool> autoAccept = GeneratedColumn<bool>(
    'auto_accept',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_accept" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _firstSeenMeta = const VerificationMeta(
    'firstSeen',
  );
  @override
  late final GeneratedColumn<DateTime> firstSeen = GeneratedColumn<DateTime>(
    'first_seen',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSeenMeta = const VerificationMeta(
    'lastSeen',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeen = GeneratedColumn<DateTime>(
    'last_seen',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    fingerprint,
    deviceId,
    name,
    platform,
    autoAccept,
    firstSeen,
    lastSeen,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trusted_devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrustedDeviceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('platform')) {
      context.handle(
        _platformMeta,
        platform.isAcceptableOrUnknown(data['platform']!, _platformMeta),
      );
    } else if (isInserting) {
      context.missing(_platformMeta);
    }
    if (data.containsKey('auto_accept')) {
      context.handle(
        _autoAcceptMeta,
        autoAccept.isAcceptableOrUnknown(data['auto_accept']!, _autoAcceptMeta),
      );
    }
    if (data.containsKey('first_seen')) {
      context.handle(
        _firstSeenMeta,
        firstSeen.isAcceptableOrUnknown(data['first_seen']!, _firstSeenMeta),
      );
    } else if (isInserting) {
      context.missing(_firstSeenMeta);
    }
    if (data.containsKey('last_seen')) {
      context.handle(
        _lastSeenMeta,
        lastSeen.isAcceptableOrUnknown(data['last_seen']!, _lastSeenMeta),
      );
    } else if (isInserting) {
      context.missing(_lastSeenMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {fingerprint};
  @override
  TrustedDeviceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrustedDeviceRow(
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      platform: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}platform'],
      )!,
      autoAccept: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_accept'],
      )!,
      firstSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}first_seen'],
      )!,
      lastSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen'],
      )!,
    );
  }

  @override
  $TrustedDevicesTable createAlias(String alias) {
    return $TrustedDevicesTable(attachedDatabase, alias);
  }
}

class TrustedDeviceRow extends DataClass
    implements Insertable<TrustedDeviceRow> {
  final String fingerprint;

  /// Last device id seen with this fingerprint, to find it on the network.
  final String deviceId;
  final String name;
  final String platform;

  /// Skip the Accept prompt for offers from this device.
  final bool autoAccept;
  final DateTime firstSeen;
  final DateTime lastSeen;
  const TrustedDeviceRow({
    required this.fingerprint,
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.autoAccept,
    required this.firstSeen,
    required this.lastSeen,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['fingerprint'] = Variable<String>(fingerprint);
    map['device_id'] = Variable<String>(deviceId);
    map['name'] = Variable<String>(name);
    map['platform'] = Variable<String>(platform);
    map['auto_accept'] = Variable<bool>(autoAccept);
    map['first_seen'] = Variable<DateTime>(firstSeen);
    map['last_seen'] = Variable<DateTime>(lastSeen);
    return map;
  }

  TrustedDevicesCompanion toCompanion(bool nullToAbsent) {
    return TrustedDevicesCompanion(
      fingerprint: Value(fingerprint),
      deviceId: Value(deviceId),
      name: Value(name),
      platform: Value(platform),
      autoAccept: Value(autoAccept),
      firstSeen: Value(firstSeen),
      lastSeen: Value(lastSeen),
    );
  }

  factory TrustedDeviceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrustedDeviceRow(
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      name: serializer.fromJson<String>(json['name']),
      platform: serializer.fromJson<String>(json['platform']),
      autoAccept: serializer.fromJson<bool>(json['autoAccept']),
      firstSeen: serializer.fromJson<DateTime>(json['firstSeen']),
      lastSeen: serializer.fromJson<DateTime>(json['lastSeen']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'fingerprint': serializer.toJson<String>(fingerprint),
      'deviceId': serializer.toJson<String>(deviceId),
      'name': serializer.toJson<String>(name),
      'platform': serializer.toJson<String>(platform),
      'autoAccept': serializer.toJson<bool>(autoAccept),
      'firstSeen': serializer.toJson<DateTime>(firstSeen),
      'lastSeen': serializer.toJson<DateTime>(lastSeen),
    };
  }

  TrustedDeviceRow copyWith({
    String? fingerprint,
    String? deviceId,
    String? name,
    String? platform,
    bool? autoAccept,
    DateTime? firstSeen,
    DateTime? lastSeen,
  }) => TrustedDeviceRow(
    fingerprint: fingerprint ?? this.fingerprint,
    deviceId: deviceId ?? this.deviceId,
    name: name ?? this.name,
    platform: platform ?? this.platform,
    autoAccept: autoAccept ?? this.autoAccept,
    firstSeen: firstSeen ?? this.firstSeen,
    lastSeen: lastSeen ?? this.lastSeen,
  );
  TrustedDeviceRow copyWithCompanion(TrustedDevicesCompanion data) {
    return TrustedDeviceRow(
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      name: data.name.present ? data.name.value : this.name,
      platform: data.platform.present ? data.platform.value : this.platform,
      autoAccept: data.autoAccept.present
          ? data.autoAccept.value
          : this.autoAccept,
      firstSeen: data.firstSeen.present ? data.firstSeen.value : this.firstSeen,
      lastSeen: data.lastSeen.present ? data.lastSeen.value : this.lastSeen,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrustedDeviceRow(')
          ..write('fingerprint: $fingerprint, ')
          ..write('deviceId: $deviceId, ')
          ..write('name: $name, ')
          ..write('platform: $platform, ')
          ..write('autoAccept: $autoAccept, ')
          ..write('firstSeen: $firstSeen, ')
          ..write('lastSeen: $lastSeen')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    fingerprint,
    deviceId,
    name,
    platform,
    autoAccept,
    firstSeen,
    lastSeen,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrustedDeviceRow &&
          other.fingerprint == this.fingerprint &&
          other.deviceId == this.deviceId &&
          other.name == this.name &&
          other.platform == this.platform &&
          other.autoAccept == this.autoAccept &&
          other.firstSeen == this.firstSeen &&
          other.lastSeen == this.lastSeen);
}

class TrustedDevicesCompanion extends UpdateCompanion<TrustedDeviceRow> {
  final Value<String> fingerprint;
  final Value<String> deviceId;
  final Value<String> name;
  final Value<String> platform;
  final Value<bool> autoAccept;
  final Value<DateTime> firstSeen;
  final Value<DateTime> lastSeen;
  final Value<int> rowid;
  const TrustedDevicesCompanion({
    this.fingerprint = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.name = const Value.absent(),
    this.platform = const Value.absent(),
    this.autoAccept = const Value.absent(),
    this.firstSeen = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TrustedDevicesCompanion.insert({
    required String fingerprint,
    required String deviceId,
    required String name,
    required String platform,
    this.autoAccept = const Value.absent(),
    required DateTime firstSeen,
    required DateTime lastSeen,
    this.rowid = const Value.absent(),
  }) : fingerprint = Value(fingerprint),
       deviceId = Value(deviceId),
       name = Value(name),
       platform = Value(platform),
       firstSeen = Value(firstSeen),
       lastSeen = Value(lastSeen);
  static Insertable<TrustedDeviceRow> custom({
    Expression<String>? fingerprint,
    Expression<String>? deviceId,
    Expression<String>? name,
    Expression<String>? platform,
    Expression<bool>? autoAccept,
    Expression<DateTime>? firstSeen,
    Expression<DateTime>? lastSeen,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (deviceId != null) 'device_id': deviceId,
      if (name != null) 'name': name,
      if (platform != null) 'platform': platform,
      if (autoAccept != null) 'auto_accept': autoAccept,
      if (firstSeen != null) 'first_seen': firstSeen,
      if (lastSeen != null) 'last_seen': lastSeen,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TrustedDevicesCompanion copyWith({
    Value<String>? fingerprint,
    Value<String>? deviceId,
    Value<String>? name,
    Value<String>? platform,
    Value<bool>? autoAccept,
    Value<DateTime>? firstSeen,
    Value<DateTime>? lastSeen,
    Value<int>? rowid,
  }) {
    return TrustedDevicesCompanion(
      fingerprint: fingerprint ?? this.fingerprint,
      deviceId: deviceId ?? this.deviceId,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      autoAccept: autoAccept ?? this.autoAccept,
      firstSeen: firstSeen ?? this.firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (platform.present) {
      map['platform'] = Variable<String>(platform.value);
    }
    if (autoAccept.present) {
      map['auto_accept'] = Variable<bool>(autoAccept.value);
    }
    if (firstSeen.present) {
      map['first_seen'] = Variable<DateTime>(firstSeen.value);
    }
    if (lastSeen.present) {
      map['last_seen'] = Variable<DateTime>(lastSeen.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrustedDevicesCompanion(')
          ..write('fingerprint: $fingerprint, ')
          ..write('deviceId: $deviceId, ')
          ..write('name: $name, ')
          ..write('platform: $platform, ')
          ..write('autoAccept: $autoAccept, ')
          ..write('firstSeen: $firstSeen, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings
    with TableInfo<$SettingsTable, SettingsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _receivingEnabledMeta = const VerificationMeta(
    'receivingEnabled',
  );
  @override
  late final GeneratedColumn<bool> receivingEnabled = GeneratedColumn<bool>(
    'receiving_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("receiving_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [slot, receivingEnabled];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingsRow> instance, {
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
    if (data.containsKey('receiving_enabled')) {
      context.handle(
        _receivingEnabledMeta,
        receivingEnabled.isAcceptableOrUnknown(
          data['receiving_enabled']!,
          _receivingEnabledMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {slot};
  @override
  SettingsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingsRow(
      slot: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}slot'],
      )!,
      receivingEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}receiving_enabled'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class SettingsRow extends DataClass implements Insertable<SettingsRow> {
  final int slot;

  /// The global "Receiving" switch (D-031).
  final bool receivingEnabled;
  const SettingsRow({required this.slot, required this.receivingEnabled});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['slot'] = Variable<int>(slot);
    map['receiving_enabled'] = Variable<bool>(receivingEnabled);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(
      slot: Value(slot),
      receivingEnabled: Value(receivingEnabled),
    );
  }

  factory SettingsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingsRow(
      slot: serializer.fromJson<int>(json['slot']),
      receivingEnabled: serializer.fromJson<bool>(json['receivingEnabled']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'slot': serializer.toJson<int>(slot),
      'receivingEnabled': serializer.toJson<bool>(receivingEnabled),
    };
  }

  SettingsRow copyWith({int? slot, bool? receivingEnabled}) => SettingsRow(
    slot: slot ?? this.slot,
    receivingEnabled: receivingEnabled ?? this.receivingEnabled,
  );
  SettingsRow copyWithCompanion(SettingsCompanion data) {
    return SettingsRow(
      slot: data.slot.present ? data.slot.value : this.slot,
      receivingEnabled: data.receivingEnabled.present
          ? data.receivingEnabled.value
          : this.receivingEnabled,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingsRow(')
          ..write('slot: $slot, ')
          ..write('receivingEnabled: $receivingEnabled')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(slot, receivingEnabled);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingsRow &&
          other.slot == this.slot &&
          other.receivingEnabled == this.receivingEnabled);
}

class SettingsCompanion extends UpdateCompanion<SettingsRow> {
  final Value<int> slot;
  final Value<bool> receivingEnabled;
  const SettingsCompanion({
    this.slot = const Value.absent(),
    this.receivingEnabled = const Value.absent(),
  });
  SettingsCompanion.insert({
    this.slot = const Value.absent(),
    this.receivingEnabled = const Value.absent(),
  });
  static Insertable<SettingsRow> custom({
    Expression<int>? slot,
    Expression<bool>? receivingEnabled,
  }) {
    return RawValuesInsertable({
      if (slot != null) 'slot': slot,
      if (receivingEnabled != null) 'receiving_enabled': receivingEnabled,
    });
  }

  SettingsCompanion copyWith({
    Value<int>? slot,
    Value<bool>? receivingEnabled,
  }) {
    return SettingsCompanion(
      slot: slot ?? this.slot,
      receivingEnabled: receivingEnabled ?? this.receivingEnabled,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (slot.present) {
      map['slot'] = Variable<int>(slot.value);
    }
    if (receivingEnabled.present) {
      map['receiving_enabled'] = Variable<bool>(receivingEnabled.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('slot: $slot, ')
          ..write('receivingEnabled: $receivingEnabled')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $IdentityTable identity = $IdentityTable(this);
  late final $TransferSessionsTable transferSessions = $TransferSessionsTable(
    this,
  );
  late final $SessionFilesTable sessionFiles = $SessionFilesTable(this);
  late final $TrustedDevicesTable trustedDevices = $TrustedDevicesTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    identity,
    transferSessions,
    sessionFiles,
    trustedDevices,
    settings,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('session_files', kind: UpdateKind.delete)],
    ),
  ]);
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
typedef $$TransferSessionsTableCreateCompanionBuilder =
    TransferSessionsCompanion Function({
      Value<int> id,
      required String sessionId,
      required String direction,
      required String peerDeviceId,
      required String peerName,
      required String peerPlatform,
      Value<String?> peerHost,
      Value<int?> peerPort,
      Value<String?> peerFingerprint,
      required String status,
      Value<String?> reason,
      required int totalBytes,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> finishedAt,
    });
typedef $$TransferSessionsTableUpdateCompanionBuilder =
    TransferSessionsCompanion Function({
      Value<int> id,
      Value<String> sessionId,
      Value<String> direction,
      Value<String> peerDeviceId,
      Value<String> peerName,
      Value<String> peerPlatform,
      Value<String?> peerHost,
      Value<int?> peerPort,
      Value<String?> peerFingerprint,
      Value<String> status,
      Value<String?> reason,
      Value<int> totalBytes,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> finishedAt,
    });

final class $$TransferSessionsTableReferences
    extends BaseReferences<_$AppDatabase, $TransferSessionsTable, SessionRow> {
  $$TransferSessionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$SessionFilesTable, List<SessionFileRow>>
  _sessionFilesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.sessionFiles,
    aliasName: 'sessions__id__session_files__session_row_id',
  );

  $$SessionFilesTableProcessedTableManager get sessionFilesRefs {
    final manager = $$SessionFilesTableTableManager(
      $_db,
      $_db.sessionFiles,
    ).filter((f) => f.sessionRowId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_sessionFilesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TransferSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $TransferSessionsTable> {
  $$TransferSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerDeviceId => $composableBuilder(
    column: $table.peerDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerName => $composableBuilder(
    column: $table.peerName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerPlatform => $composableBuilder(
    column: $table.peerPlatform,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerHost => $composableBuilder(
    column: $table.peerHost,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get peerPort => $composableBuilder(
    column: $table.peerPort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerFingerprint => $composableBuilder(
    column: $table.peerFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> sessionFilesRefs(
    Expression<bool> Function($$SessionFilesTableFilterComposer f) f,
  ) {
    final $$SessionFilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessionFiles,
      getReferencedColumn: (t) => t.sessionRowId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionFilesTableFilterComposer(
            $db: $db,
            $table: $db.sessionFiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TransferSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $TransferSessionsTable> {
  $$TransferSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerDeviceId => $composableBuilder(
    column: $table.peerDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerName => $composableBuilder(
    column: $table.peerName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerPlatform => $composableBuilder(
    column: $table.peerPlatform,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerHost => $composableBuilder(
    column: $table.peerHost,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get peerPort => $composableBuilder(
    column: $table.peerPort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerFingerprint => $composableBuilder(
    column: $table.peerFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TransferSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TransferSessionsTable> {
  $$TransferSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get peerDeviceId => $composableBuilder(
    column: $table.peerDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get peerName =>
      $composableBuilder(column: $table.peerName, builder: (column) => column);

  GeneratedColumn<String> get peerPlatform => $composableBuilder(
    column: $table.peerPlatform,
    builder: (column) => column,
  );

  GeneratedColumn<String> get peerHost =>
      $composableBuilder(column: $table.peerHost, builder: (column) => column);

  GeneratedColumn<int> get peerPort =>
      $composableBuilder(column: $table.peerPort, builder: (column) => column);

  GeneratedColumn<String> get peerFingerprint => $composableBuilder(
    column: $table.peerFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => column,
  );

  Expression<T> sessionFilesRefs<T extends Object>(
    Expression<T> Function($$SessionFilesTableAnnotationComposer a) f,
  ) {
    final $$SessionFilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessionFiles,
      getReferencedColumn: (t) => t.sessionRowId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionFilesTableAnnotationComposer(
            $db: $db,
            $table: $db.sessionFiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TransferSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TransferSessionsTable,
          SessionRow,
          $$TransferSessionsTableFilterComposer,
          $$TransferSessionsTableOrderingComposer,
          $$TransferSessionsTableAnnotationComposer,
          $$TransferSessionsTableCreateCompanionBuilder,
          $$TransferSessionsTableUpdateCompanionBuilder,
          (SessionRow, $$TransferSessionsTableReferences),
          SessionRow,
          PrefetchHooks Function({bool sessionFilesRefs})
        > {
  $$TransferSessionsTableTableManager(
    _$AppDatabase db,
    $TransferSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransferSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransferSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransferSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<String> peerDeviceId = const Value.absent(),
                Value<String> peerName = const Value.absent(),
                Value<String> peerPlatform = const Value.absent(),
                Value<String?> peerHost = const Value.absent(),
                Value<int?> peerPort = const Value.absent(),
                Value<String?> peerFingerprint = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> reason = const Value.absent(),
                Value<int> totalBytes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> finishedAt = const Value.absent(),
              }) => TransferSessionsCompanion(
                id: id,
                sessionId: sessionId,
                direction: direction,
                peerDeviceId: peerDeviceId,
                peerName: peerName,
                peerPlatform: peerPlatform,
                peerHost: peerHost,
                peerPort: peerPort,
                peerFingerprint: peerFingerprint,
                status: status,
                reason: reason,
                totalBytes: totalBytes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                finishedAt: finishedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String sessionId,
                required String direction,
                required String peerDeviceId,
                required String peerName,
                required String peerPlatform,
                Value<String?> peerHost = const Value.absent(),
                Value<int?> peerPort = const Value.absent(),
                Value<String?> peerFingerprint = const Value.absent(),
                required String status,
                Value<String?> reason = const Value.absent(),
                required int totalBytes,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> finishedAt = const Value.absent(),
              }) => TransferSessionsCompanion.insert(
                id: id,
                sessionId: sessionId,
                direction: direction,
                peerDeviceId: peerDeviceId,
                peerName: peerName,
                peerPlatform: peerPlatform,
                peerHost: peerHost,
                peerPort: peerPort,
                peerFingerprint: peerFingerprint,
                status: status,
                reason: reason,
                totalBytes: totalBytes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                finishedAt: finishedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TransferSessionsTable, SessionRow>(table),
                  $$TransferSessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionFilesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (sessionFilesRefs) db.sessionFiles],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (sessionFilesRefs)
                    await $_getPrefetchedDataByColumns<
                      SessionRow,
                      $TransferSessionsTable,
                      SessionFileRow,
                      $SessionFilesTable
                    >(
                      currentTable: table,
                      referencedTable: $$TransferSessionsTableReferences
                          ._sessionFilesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$TransferSessionsTableReferences(
                            db,
                            table,
                            p0,
                          ).sessionFilesRefs,
                      currentColumn: 'id',
                      referencedColumn: 'session_row_id',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$TransferSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TransferSessionsTable,
      SessionRow,
      $$TransferSessionsTableFilterComposer,
      $$TransferSessionsTableOrderingComposer,
      $$TransferSessionsTableAnnotationComposer,
      $$TransferSessionsTableCreateCompanionBuilder,
      $$TransferSessionsTableUpdateCompanionBuilder,
      (SessionRow, $$TransferSessionsTableReferences),
      SessionRow,
      PrefetchHooks Function({bool sessionFilesRefs})
    >;
typedef $$SessionFilesTableCreateCompanionBuilder =
    SessionFilesCompanion Function({
      required int sessionRowId,
      required String fileId,
      required int position,
      required String name,
      required int size,
      Value<String?> mime,
      required String kind,
      Value<DateTime?> created,
      Value<String?> livePhotoGroup,
      Value<String?> sha256,
      Value<int> transferredBytes,
      Value<String?> tempPath,
      Value<String?> sourcePath,
      Value<String?> finalLocation,
      required String status,
      Value<int> hashAttempts,
      Value<String?> errorCode,
      Value<int> rowid,
    });
typedef $$SessionFilesTableUpdateCompanionBuilder =
    SessionFilesCompanion Function({
      Value<int> sessionRowId,
      Value<String> fileId,
      Value<int> position,
      Value<String> name,
      Value<int> size,
      Value<String?> mime,
      Value<String> kind,
      Value<DateTime?> created,
      Value<String?> livePhotoGroup,
      Value<String?> sha256,
      Value<int> transferredBytes,
      Value<String?> tempPath,
      Value<String?> sourcePath,
      Value<String?> finalLocation,
      Value<String> status,
      Value<int> hashAttempts,
      Value<String?> errorCode,
      Value<int> rowid,
    });

final class $$SessionFilesTableReferences
    extends BaseReferences<_$AppDatabase, $SessionFilesTable, SessionFileRow> {
  $$SessionFilesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TransferSessionsTable _sessionRowIdTable(_$AppDatabase db) => db
      .transferSessions
      .createAlias('session_files__session_row_id__sessions__id');

  $$TransferSessionsTableProcessedTableManager get sessionRowId {
    final $_column = $_itemColumn<int>('session_row_id')!;

    final manager = $$TransferSessionsTableTableManager(
      $_db,
      $_db.transferSessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionRowIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SessionFilesTableFilterComposer
    extends Composer<_$AppDatabase, $SessionFilesTable> {
  $$SessionFilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get created => $composableBuilder(
    column: $table.created,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get livePhotoGroup => $composableBuilder(
    column: $table.livePhotoGroup,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get transferredBytes => $composableBuilder(
    column: $table.transferredBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tempPath => $composableBuilder(
    column: $table.tempPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get finalLocation => $composableBuilder(
    column: $table.finalLocation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hashAttempts => $composableBuilder(
    column: $table.hashAttempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnFilters(column),
  );

  $$TransferSessionsTableFilterComposer get sessionRowId {
    final $$TransferSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionRowId,
      referencedTable: $db.transferSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TransferSessionsTableFilterComposer(
            $db: $db,
            $table: $db.transferSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionFilesTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionFilesTable> {
  $$SessionFilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get created => $composableBuilder(
    column: $table.created,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get livePhotoGroup => $composableBuilder(
    column: $table.livePhotoGroup,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get transferredBytes => $composableBuilder(
    column: $table.transferredBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tempPath => $composableBuilder(
    column: $table.tempPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get finalLocation => $composableBuilder(
    column: $table.finalLocation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hashAttempts => $composableBuilder(
    column: $table.hashAttempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnOrderings(column),
  );

  $$TransferSessionsTableOrderingComposer get sessionRowId {
    final $$TransferSessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionRowId,
      referencedTable: $db.transferSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TransferSessionsTableOrderingComposer(
            $db: $db,
            $table: $db.transferSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionFilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionFilesTable> {
  $$SessionFilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get fileId =>
      $composableBuilder(column: $table.fileId, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<String> get mime =>
      $composableBuilder(column: $table.mime, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<DateTime> get created =>
      $composableBuilder(column: $table.created, builder: (column) => column);

  GeneratedColumn<String> get livePhotoGroup => $composableBuilder(
    column: $table.livePhotoGroup,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<int> get transferredBytes => $composableBuilder(
    column: $table.transferredBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tempPath =>
      $composableBuilder(column: $table.tempPath, builder: (column) => column);

  GeneratedColumn<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get finalLocation => $composableBuilder(
    column: $table.finalLocation,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get hashAttempts => $composableBuilder(
    column: $table.hashAttempts,
    builder: (column) => column,
  );

  GeneratedColumn<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => column);

  $$TransferSessionsTableAnnotationComposer get sessionRowId {
    final $$TransferSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionRowId,
      referencedTable: $db.transferSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TransferSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.transferSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionFilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SessionFilesTable,
          SessionFileRow,
          $$SessionFilesTableFilterComposer,
          $$SessionFilesTableOrderingComposer,
          $$SessionFilesTableAnnotationComposer,
          $$SessionFilesTableCreateCompanionBuilder,
          $$SessionFilesTableUpdateCompanionBuilder,
          (SessionFileRow, $$SessionFilesTableReferences),
          SessionFileRow,
          PrefetchHooks Function({bool sessionRowId})
        > {
  $$SessionFilesTableTableManager(_$AppDatabase db, $SessionFilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionFilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionFilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionFilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> sessionRowId = const Value.absent(),
                Value<String> fileId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<String?> mime = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<DateTime?> created = const Value.absent(),
                Value<String?> livePhotoGroup = const Value.absent(),
                Value<String?> sha256 = const Value.absent(),
                Value<int> transferredBytes = const Value.absent(),
                Value<String?> tempPath = const Value.absent(),
                Value<String?> sourcePath = const Value.absent(),
                Value<String?> finalLocation = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> hashAttempts = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionFilesCompanion(
                sessionRowId: sessionRowId,
                fileId: fileId,
                position: position,
                name: name,
                size: size,
                mime: mime,
                kind: kind,
                created: created,
                livePhotoGroup: livePhotoGroup,
                sha256: sha256,
                transferredBytes: transferredBytes,
                tempPath: tempPath,
                sourcePath: sourcePath,
                finalLocation: finalLocation,
                status: status,
                hashAttempts: hashAttempts,
                errorCode: errorCode,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int sessionRowId,
                required String fileId,
                required int position,
                required String name,
                required int size,
                Value<String?> mime = const Value.absent(),
                required String kind,
                Value<DateTime?> created = const Value.absent(),
                Value<String?> livePhotoGroup = const Value.absent(),
                Value<String?> sha256 = const Value.absent(),
                Value<int> transferredBytes = const Value.absent(),
                Value<String?> tempPath = const Value.absent(),
                Value<String?> sourcePath = const Value.absent(),
                Value<String?> finalLocation = const Value.absent(),
                required String status,
                Value<int> hashAttempts = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionFilesCompanion.insert(
                sessionRowId: sessionRowId,
                fileId: fileId,
                position: position,
                name: name,
                size: size,
                mime: mime,
                kind: kind,
                created: created,
                livePhotoGroup: livePhotoGroup,
                sha256: sha256,
                transferredBytes: transferredBytes,
                tempPath: tempPath,
                sourcePath: sourcePath,
                finalLocation: finalLocation,
                status: status,
                hashAttempts: hashAttempts,
                errorCode: errorCode,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SessionFilesTable, SessionFileRow>(table),
                  $$SessionFilesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionRowId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionRowId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.sessionRowId,
                        referencedTable: $$SessionFilesTableReferences
                            ._sessionRowIdTable(db),
                        referencedColumn: $$SessionFilesTableReferences
                            ._sessionRowIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SessionFilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SessionFilesTable,
      SessionFileRow,
      $$SessionFilesTableFilterComposer,
      $$SessionFilesTableOrderingComposer,
      $$SessionFilesTableAnnotationComposer,
      $$SessionFilesTableCreateCompanionBuilder,
      $$SessionFilesTableUpdateCompanionBuilder,
      (SessionFileRow, $$SessionFilesTableReferences),
      SessionFileRow,
      PrefetchHooks Function({bool sessionRowId})
    >;
typedef $$TrustedDevicesTableCreateCompanionBuilder =
    TrustedDevicesCompanion Function({
      required String fingerprint,
      required String deviceId,
      required String name,
      required String platform,
      Value<bool> autoAccept,
      required DateTime firstSeen,
      required DateTime lastSeen,
      Value<int> rowid,
    });
typedef $$TrustedDevicesTableUpdateCompanionBuilder =
    TrustedDevicesCompanion Function({
      Value<String> fingerprint,
      Value<String> deviceId,
      Value<String> name,
      Value<String> platform,
      Value<bool> autoAccept,
      Value<DateTime> firstSeen,
      Value<DateTime> lastSeen,
      Value<int> rowid,
    });

class $$TrustedDevicesTableFilterComposer
    extends Composer<_$AppDatabase, $TrustedDevicesTable> {
  $$TrustedDevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get autoAccept => $composableBuilder(
    column: $table.autoAccept,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get firstSeen => $composableBuilder(
    column: $table.firstSeen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TrustedDevicesTableOrderingComposer
    extends Composer<_$AppDatabase, $TrustedDevicesTable> {
  $$TrustedDevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get autoAccept => $composableBuilder(
    column: $table.autoAccept,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get firstSeen => $composableBuilder(
    column: $table.firstSeen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TrustedDevicesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TrustedDevicesTable> {
  $$TrustedDevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get platform =>
      $composableBuilder(column: $table.platform, builder: (column) => column);

  GeneratedColumn<bool> get autoAccept => $composableBuilder(
    column: $table.autoAccept,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get firstSeen =>
      $composableBuilder(column: $table.firstSeen, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSeen =>
      $composableBuilder(column: $table.lastSeen, builder: (column) => column);
}

class $$TrustedDevicesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TrustedDevicesTable,
          TrustedDeviceRow,
          $$TrustedDevicesTableFilterComposer,
          $$TrustedDevicesTableOrderingComposer,
          $$TrustedDevicesTableAnnotationComposer,
          $$TrustedDevicesTableCreateCompanionBuilder,
          $$TrustedDevicesTableUpdateCompanionBuilder,
          (
            TrustedDeviceRow,
            BaseReferences<
              _$AppDatabase,
              $TrustedDevicesTable,
              TrustedDeviceRow
            >,
          ),
          TrustedDeviceRow,
          PrefetchHooks Function()
        > {
  $$TrustedDevicesTableTableManager(
    _$AppDatabase db,
    $TrustedDevicesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TrustedDevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TrustedDevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TrustedDevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> fingerprint = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> platform = const Value.absent(),
                Value<bool> autoAccept = const Value.absent(),
                Value<DateTime> firstSeen = const Value.absent(),
                Value<DateTime> lastSeen = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TrustedDevicesCompanion(
                fingerprint: fingerprint,
                deviceId: deviceId,
                name: name,
                platform: platform,
                autoAccept: autoAccept,
                firstSeen: firstSeen,
                lastSeen: lastSeen,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String fingerprint,
                required String deviceId,
                required String name,
                required String platform,
                Value<bool> autoAccept = const Value.absent(),
                required DateTime firstSeen,
                required DateTime lastSeen,
                Value<int> rowid = const Value.absent(),
              }) => TrustedDevicesCompanion.insert(
                fingerprint: fingerprint,
                deviceId: deviceId,
                name: name,
                platform: platform,
                autoAccept: autoAccept,
                firstSeen: firstSeen,
                lastSeen: lastSeen,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TrustedDevicesTable, TrustedDeviceRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $TrustedDevicesTable,
                    TrustedDeviceRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TrustedDevicesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TrustedDevicesTable,
      TrustedDeviceRow,
      $$TrustedDevicesTableFilterComposer,
      $$TrustedDevicesTableOrderingComposer,
      $$TrustedDevicesTableAnnotationComposer,
      $$TrustedDevicesTableCreateCompanionBuilder,
      $$TrustedDevicesTableUpdateCompanionBuilder,
      (
        TrustedDeviceRow,
        BaseReferences<_$AppDatabase, $TrustedDevicesTable, TrustedDeviceRow>,
      ),
      TrustedDeviceRow,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  Value<int> slot,
  Value<bool> receivingEnabled,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<int> slot,
  Value<bool> receivingEnabled,
});

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
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

  ColumnFilters<bool> get receivingEnabled => $composableBuilder(
    column: $table.receivingEnabled,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
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

  ColumnOrderings<bool> get receivingEnabled => $composableBuilder(
    column: $table.receivingEnabled,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get slot =>
      $composableBuilder(column: $table.slot, builder: (column) => column);

  GeneratedColumn<bool> get receivingEnabled => $composableBuilder(
    column: $table.receivingEnabled,
    builder: (column) => column,
  );
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          SettingsRow,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (
            SettingsRow,
            BaseReferences<_$AppDatabase, $SettingsTable, SettingsRow>,
          ),
          SettingsRow,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> slot = const Value.absent(),
                Value<bool> receivingEnabled = const Value.absent(),
              }) => SettingsCompanion(
                slot: slot,
                receivingEnabled: receivingEnabled,
              ),
          createCompanionCallback:
              ({
                Value<int> slot = const Value.absent(),
                Value<bool> receivingEnabled = const Value.absent(),
              }) => SettingsCompanion.insert(
                slot: slot,
                receivingEnabled: receivingEnabled,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, SettingsRow>(table),
                  BaseReferences<_$AppDatabase, $SettingsTable, SettingsRow>(
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

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      SettingsRow,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (SettingsRow, BaseReferences<_$AppDatabase, $SettingsTable, SettingsRow>),
      SettingsRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$IdentityTableTableManager get identity =>
      $$IdentityTableTableManager(_db, _db.identity);
  $$TransferSessionsTableTableManager get transferSessions =>
      $$TransferSessionsTableTableManager(_db, _db.transferSessions);
  $$SessionFilesTableTableManager get sessionFiles =>
      $$SessionFilesTableTableManager(_db, _db.sessionFiles);
  $$TrustedDevicesTableTableManager get trustedDevices =>
      $$TrustedDevicesTableTableManager(_db, _db.trustedDevices);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
}
