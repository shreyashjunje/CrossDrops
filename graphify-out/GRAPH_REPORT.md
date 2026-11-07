# Graph Report - CrossDrops  (2026-11-08)

## Corpus Check
- 333 files · ~221,294 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 58 file(s) not represented in the graph (top: .xml 9, (none) 8, .plist 8)

## Summary
- 5335 nodes · 8038 edges · 221 communities (192 shown, 29 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 185 edges (avg confidence: 0.86)
- Token cost: 596,962 input · 0 output

## Community Hubs (Navigation)
- Community 0
- Community 1
- Community 2
- Community 3
- Community 4
- Community 5
- Community 6
- Community 7
- Community 8
- Community 9
- Community 10
- Community 11
- Community 12
- Community 13
- Community 14
- Community 15
- Community 16
- Community 17
- Community 18
- Community 19
- Community 20
- Community 21
- Community 22
- Community 23
- Community 24
- Community 25
- Community 26
- Community 27
- Community 28
- Community 29
- Community 30
- Community 31
- Community 32
- Community 33
- Community 34
- Community 35
- Community 36
- Community 37
- Community 38
- Community 39
- Community 40
- Community 41
- Community 42
- Community 43
- Community 44
- Community 45
- Community 46
- Community 47
- Community 48
- Community 49
- Community 50
- Community 51
- Community 52
- Community 53
- Community 54
- Community 55
- Community 56
- Community 57
- Community 58
- Community 59
- Community 60
- Community 61
- Community 62
- Community 63
- Community 64
- Community 65
- Community 66
- Community 67
- Community 68
- Community 69
- Community 70
- Community 71
- Community 72
- Community 73
- Community 74
- Community 75
- Community 76
- Community 77
- Community 78
- Community 79
- Community 80
- Community 81
- Community 82
- Community 83
- Community 84
- Community 85
- Community 86
- Community 87
- Community 88
- Community 89
- Community 90
- Community 91
- Community 92
- Community 93
- Community 94
- Community 95
- Community 96
- Community 97
- Community 98
- Community 99
- Community 100
- Community 101
- Community 102
- Community 103
- Community 104
- Community 105
- Community 106
- Community 107
- Community 108
- Community 109
- Community 110
- Community 111
- Community 112
- Community 113
- Community 114
- Community 115
- Community 116
- Community 117
- Community 118
- Community 119
- Community 120
- Community 121
- Community 122
- Community 123
- Community 124
- Community 125
- Community 126
- Community 127
- Community 128
- Community 129
- Community 130
- Community 131
- Community 132
- Community 133
- Community 134
- Community 135
- Community 136
- Community 137
- Community 138
- Community 139
- Community 140
- Community 141
- Community 142
- Community 143
- Community 144
- Community 145
- Community 146
- Community 147
- Community 148
- Community 149
- Community 150
- Community 151
- Community 152
- Community 153
- Community 154
- Community 155
- Community 156
- Community 157
- Community 158
- Community 159
- Community 160
- Community 161
- Community 162
- Community 163
- Community 165
- Community 166
- Community 167
- Community 168
- Community 169
- Community 170
- Community 171
- Community 172
- Community 173
- Community 174
- Community 175
- Community 176
- Community 177
- Community 178
- Community 179
- Community 180
- Community 181
- Community 182
- Community 183
- Community 184
- Community 185
- Community 186
- Community 187
- Community 188
- Community 189
- Community 190
- Community 191
- Community 192
- Community 194
- Community 195
- Community 196
- Community 197
- Community 198
- Community 199
- Community 200
- Community 203
- Community 204
- Community 205
- Community 206
- Community 207
- Community 208
- Community 210

## God Nodes (most connected - your core abstractions)
1. `Decisions log (DECISIONS.md)` - 68 edges
2. `CrossDrop Architecture (ARCHITECTURE.md)` - 30 edges
3. `ExportJob` - 26 edges
4. `dependencies` - 23 edges
5. `Win32Window` - 21 edges
6. `Device Tests (DEVICE_TESTS.md)` - 21 edges
7. `Code Review 2026-11-03` - 19 edges
8. `HotspotChannel` - 17 edges
9. `identityProvider` - 16 edges
10. `DevicePlatform` - 16 edges

## Surprising Connections (you probably didn't know these)
- `Rule 2: No File Bytes Through Platform Channels` --semantically_similar_to--> `Platform Channels (paths and file descriptors only)`  [INFERRED] [semantically similar]
  CLAUDE.md → docs/ARCHITECTURE.md
- `Rule 6: Check Free Space; Never Trust Declared Sizes` --semantically_similar_to--> `Free-Space Check (offer + open sessions + 64 MB reserve)`  [INFERRED] [semantically similar]
  CLAUDE.md → docs/ARCHITECTURE.md
- `Rule 1: Never Load Whole File; Stream ~1 MB Buffers` --semantically_similar_to--> `Principle: Stream, Never Buffer`  [INFERRED] [semantically similar]
  CLAUDE.md → docs/ARCHITECTURE.md
- `Rule 5: Sanitize Every Received File Name` --semantically_similar_to--> `File Name Sanitization (review L8)`  [INFERRED] [semantically similar]
  CLAUDE.md → docs/ARCHITECTURE.md
- `Rule 7: Never Log Contents, Names, Keys or QR Payloads` --semantically_similar_to--> `Privacy (no accounts, no analytics, 8-char fingerprint logs)`  [INFERRED] [semantically similar]
  CLAUDE.md → docs/ARCHITECTURE.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Code Review 2026-11-03 Speed Changes** — docs_changelog_socket_read_ahead, docs_changelog_checkpoint_pace, docs_changelog_sender_read_ahead, docs_changelog_native_buffer_reuse, docs_changelog_measure_this_phone [EXTRACTED 1.00]
- **Connection Mode Fallback Chain** — docs_architecture_bonjour_advertisement, docs_architecture_qr_payload, docs_architecture_android_localonlyhotspot, docs_architecture_iphone_personal_hotspot, docs_architecture_connection_flow [EXTRACTED 1.00]
- **Pairing and trust model: identity, code check, trust list, lookalike and tampered-QR refusal** — docs_device_tests_device_identity_security_key, docs_device_tests_six_digit_pairing_code, docs_device_tests_trusted_devices, docs_device_tests_lookalike_warning, docs_device_tests_tampered_qr, docs_device_tests_pairing_commitment [EXTRACTED 1.00]
- **Phase 7 Benchmark Protocol Steps** — docs_benchmarks_step_0_phone_limits, docs_benchmarks_step_a_buffer_size, docs_benchmarks_step_b_full_matrix, docs_benchmarks_localsend_comparison, docs_benchmarks_parallel_streams [EXTRACTED 1.00]
- **Resumable Streamed File Transfer** — docs_architecture_endpoint_put_file, docs_architecture_endpoint_file_status, docs_architecture_received_file_store, docs_architecture_checkpointing, docs_architecture_retry_backoff, docs_architecture_sha256_verification, docs_architecture_endpoint_complete [EXTRACTED 1.00]
- **Sender Authentication and Pairing Flow** — docs_architecture_commitment, docs_architecture_endpoint_auth_challenge, docs_architecture_endpoint_auth, docs_architecture_bearer_token, docs_architecture_pairing_code, docs_architecture_pinned_http_client, docs_architecture_certificate_fingerprint [EXTRACTED 1.00]
- **Sender pinning and authentication flow** — docs_features_pairing_and_trust_pinned_tls, docs_features_pairing_and_trust_probefingerprint, docs_features_pairing_and_trust_checkpeer, docs_features_pairing_and_trust_commitment, docs_features_pairing_and_trust_signed_challenge, docs_features_pairing_and_trust_pairing_code, docs_features_pairing_and_trust_bearer_token [EXTRACTED 1.00]
- **Android hotspot to iPhone join flow (scenario 4)** — docs_features_android_hotspot_localonlyhotspot, docs_features_android_hotspot_qr_wifi_fields, docs_features_iphone_join_hotspot_hotspotjoinflow, docs_features_iphone_join_hotspot_joinedhotspot, docs_features_android_hotspot_idle_stop [INFERRED 0.85]
- **Android in-place MediaStore and file-descriptor I/O** — docs_decisions_d_035, docs_decisions_d_036, docs_decisions_d_037, docs_decisions_d_040, docs_decisions_d_041, docs_decisions_d_067 [INFERRED 0.85]
- **Connection fallbacks when discovery or the Wi-Fi fails** — docs_device_tests_mdns_discovery, docs_device_tests_qr_connect, docs_device_tests_p2_7_manual_address, docs_device_tests_android_local_only_hotspot, docs_device_tests_iphone_personal_hotspot_guide, docs_device_tests_hotspot_suggestion [INFERRED 0.85]
- **Resilient transfer: resume, retry, rediscovery, keep-alive and restore** — docs_device_tests_offset_resume, docs_device_tests_auto_retry_backoff, docs_device_tests_receiver_moved, docs_device_tests_keep_alive, docs_device_tests_unfinished_transfers_restore [INFERRED 0.85]
- **Measurement-driven transfer speed tuning** — docs_decisions_d_058, docs_decisions_d_059, docs_decisions_d_064, docs_decisions_d_065, docs_decisions_d_066, docs_benchmarks [INFERRED 0.85]
- **Phase 7 Hotspot Connection Modes** — docs_changelog_android_hotspot, docs_changelog_iphone_join_hotspot, docs_changelog_android_network_binding, docs_changelog_iphone_personal_hotspot_guide, docs_changelog_qr_wifi_fields [INFERRED 0.85]
- **Platform code behind a Dart interface (hard rule 9)** — docs_features_device_identity_secretstore, docs_features_keep_alive_keepaliveplatform, docs_features_android_network_binding_networkplatform, docs_features_android_hotspot_hotspotservice, docs_features_discovery_mdnsbackend [INFERRED 0.85]
- **Receiver partial-file and save pipeline** — docs_features_transfer_engine_receiveserver, docs_features_resume_receiver_checkpoint, docs_features_saving_received_files_receivedfilestore, docs_features_saving_received_files_mediastorefilestore, docs_features_saving_received_files_folderstore, docs_features_saving_received_files_iosphotossaver [INFERRED 0.85]
- **Send pipeline from pick to verified upload** — docs_features_media_picking_preparer, docs_features_media_picking_sourceopener, docs_features_transfer_engine_sendsession, docs_features_resume_backoff, docs_features_transfer_engine_hash_verification [INFERRED 0.85]
- **Sender authentication, pinning and pairing-code security model** — docs_decisions_d_027, docs_decisions_d_028, docs_decisions_d_029, docs_decisions_d_030, docs_decisions_d_033, docs_decisions_d_061 [INFERRED 0.85]
- **Streamed, resumable, verified transfer** — docs_features_file_transfer_poc_uploadclient, docs_features_file_transfer_poc_receive_server, docs_features_file_transfer_poc_sha256isolate, docs_features_file_transfer_poc_part_file_resume, docs_features_keep_alive_checkpointall [INFERRED 0.85]

## Communities (221 total, 29 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.01
Nodes (145): accepted, _acceptTimeout, acceptTimer, _afterFile, anyBusy, _auth, authBurst, _authenticate (+137 more)

### Community 1 - "Community 1"
Cohesion: 0.02
Nodes (106): acceptTimeout, bytesPerSecond, cancel, _cancelRemote, canResume, _checkStop, client, ClientFactory (+98 more)

### Community 2 - "Community 2"
Cohesion: 0.02
Nodes (88): _, actualTableName, aliasedName, allSchemaEntities, allTables, _autoAcceptMeta, _certificateMeta, _convertHeicToJpegMeta (+80 more)

### Community 3 - "Community 3"
Cohesion: 0.02
Nodes (72): _alias, attachedDatabase, _deviceNameMeta, _directionMeta, _finalLocationMeta, _finishedAtMeta, _firstSeenMeta, fromJson (+64 more)

### Community 4 - "Community 4"
Cohesion: 0.02
Nodes (82): addresses, advertiseError, _advertiser, advertising, answer, _ask, _beginKeepAlive, _busy (+74 more)

### Community 5 - "Community 5"
Cohesion: 0.03
Nodes (75): all, alreadySaved, authFailed, authRequired, badRequest, best, bodyTooLarge, busy (+67 more)

### Community 6 - "Community 6"
Cohesion: 0.04
Nodes (47): DevicePlatform, AcceptDecision, files, main, screens, view, contrast, la (+39 more)

### Community 7 - "Community 7"
Cohesion: 0.03
Nodes (65): _abort, _active, _authenticate, _authenticating, bytesPerSecond, cancel, _cancelled, cancelSession (+57 more)

### Community 8 - "Community 8"
Cohesion: 0.03
Nodes (57): anyInGrace, clear, defaultGrace, grace, _held, isHeld, _paused, update (+49 more)

### Community 9 - "Community 9"
Cohesion: 0.03
Nodes (44): DeviceCredentials, identity, main, me, r, runner, src, main (+36 more)

### Community 10 - "Community 10"
Cohesion: 0.06
Nodes (11): ImageIO, ExportChannel, ExportError, ExportJob, .isCancelled, .sawDownload, .stalled, OnceFlag (+3 more)

### Community 11 - "Community 11"
Cohesion: 0.05
Nodes (12): Android 10 Minimum (D-035), Descriptor I/O via dart:ffi (D-036), H1: Auth Commitment Covers Both Fingerprints (Protocol v2, D-061), Media Picking (photo_manager gallery, SAF, document picker), Android Descriptor I/O Native Buffer Reuse, crossdrop/open Channel (D-051), Receiver Keeps Hash Across Drops (D-021), Decisions log (DECISIONS.md) (+4 more)

### Community 12 - "Community 12"
Cohesion: 0.03
Nodes (59): asset, cancel, _cancelled, cleanStaging, code, converted, copyIntoStaging, count (+51 more)

### Community 13 - "Community 13"
Cohesion: 0.04
Nodes (55): BenchDiscardingStore, append, close, code, collection, delete, fallback, FolderStore (+47 more)

### Community 14 - "Community 14"
Cohesion: 0.05
Nodes (37): SettingsRepository, TrustRepository, main, screens, main, main, db, main (+29 more)

### Community 15 - "Community 15"
Cohesion: 0.03
Nodes (57): add, bucket, buildCameraRoll, CameraObject, CameraRoll, collection, compareNewestFirst, current (+49 more)

### Community 16 - "Community 16"
Cohesion: 0.04
Nodes (54): OfferDecider, ReceiveServer, ServerLimits, TrustLookup, acceptsUntrusted, add, authenticateRaw, checkpointInterval (+46 more)

### Community 17 - "Community 17"
Cohesion: 0.04
Nodes (51): RollItem, ImportProgress, ImportSummary, _Busy, _Choice, _HotspotIdle, HotspotModeScreen, HotspotSuggestion (+43 more)

### Community 18 - "Community 18"
Cohesion: 0.05
Nodes (34): IllegalTransition, SourceUnavailable, main, bytes, dir, main, data, dir (+26 more)

### Community 19 - "Community 19"
Cohesion: 0.04
Nodes (52): backToPhotos, build, camera, cancelImport, clearSelection, connect, _copy, copyWith (+44 more)

### Community 20 - "Community 20"
Cohesion: 0.04
Nodes (43): AppDatabase, _db, formatSettings, receivingEnabled, setConvertHeicToJpeg, setOnboardingDone, setReceivingEnabled, setSendLivePhotoVideo (+35 more)

### Community 21 - "Community 21"
Cohesion: 0.05
Nodes (30): FormatError, _fp, _id, main, _valid, main, all, heic (+22 more)

### Community 22 - "Community 22"
Cohesion: 0.04
Nodes (47): documentPickerProvider, SendSnapshot, PrepareControl, PrepareProgress, addMedia, addShared, cancel, canResume (+39 more)

### Community 23 - "Community 23"
Cohesion: 0.05
Nodes (43): busy, bytes, CameraPage, cancelCurrent, cancelled, _channel, ChannelUsbCamera, close (+35 more)

### Community 24 - "Community 24"
Cohesion: 0.04
Nodes (42): add, bytes, chunk, chunkSize, close, context, csvHeader, defaultBenchChunk (+34 more)

### Community 25 - "Community 25"
Cohesion: 0.04
Nodes (42): bytes, bytesDone, bytesTotal, cancel, _cancelled, code, _Copied, copiedFiles (+34 more)

### Community 26 - "Community 26"
Cohesion: 0.07
Nodes (40): build, _Unfinished, ActiveTransfers, build, ReceiveStatusCard, hotspotControllerProvider, transfersActiveProvider, AndroidHotspotScreen (+32 more)

### Community 27 - "Community 27"
Cohesion: 0.04
Nodes (35): atLeast, _buf, _c, close, _eintr, errno, _error, _espipe (+27 more)

### Community 28 - "Community 28"
Cohesion: 0.05
Nodes (21): onboardingDoneProvider, _askedAboutUnfinished, build, createState, onPressed, _SendButton, build, child (+13 more)

### Community 29 - "Community 29"
Cohesion: 0.05
Nodes (38): UploadClient, main, make, now, complete, _CorruptingClient, expectSavedMatches, failAfter (+30 more)

### Community 30 - "Community 30"
Cohesion: 0.05
Nodes (41): SenderInfo, created, createdAt, createSession, _db, deleteSession, direction, errorCode (+33 more)

### Community 31 - "Community 31"
Cohesion: 0.05
Nodes (37): _Access, _album, _albums, asset, _assets, build, capacity, createState (+29 more)

### Community 32 - "Community 32"
Cohesion: 0.05
Nodes (37): abort, _aborted, add, addFilePrefix, addSourcePrefix, BackgroundFileHash, _checkUsable, close (+29 more)

### Community 33 - "Community 33"
Cohesion: 0.05
Nodes (40): add, appVersion, avgMBps, BenchResult, BenchRole, bestBuffer, bufferBytes, buffers (+32 more)

### Community 34 - "Community 34"
Cohesion: 0.05
Nodes (40): dependencies, basic_utils, bonsoir, connectivity_plus, crypto, cupertino_icons, drift, drift_flutter (+32 more)

### Community 35 - "Community 35"
Cohesion: 0.05
Nodes (38): FileTransferStatus, TransferDirection, bytesPerSecond, canResume, collectionOfLocation, direction, doneBytes, error (+30 more)

### Community 36 - "Community 36"
Cohesion: 0.05
Nodes (36): _FilePart, PartFile, FdPart, actAs, append, auth, authLine, close (+28 more)

### Community 37 - "Community 37"
Cohesion: 0.06
Nodes (30): UploadException, check, _id, identity, main, me, other, root (+22 more)

### Community 38 - "Community 38"
Cohesion: 0.05
Nodes (35): api, append, cleanupPending, close, collection, delete, deleted, dir (+27 more)

### Community 39 - "Community 39"
Cohesion: 0.06
Nodes (32): _armSearchTimer, _browser, build, _changesSub, checkLocalNetworkPermissionProvider, connectToAddress, connectToPeer, connectToQr (+24 more)

### Community 40 - "Community 40"
Cohesion: 0.06
Nodes (29): benchNetworks, _buffers, _chooseReceiver, _copyCsv, createState, _csvPath, dispose, initState (+21 more)

### Community 41 - "Community 41"
Cohesion: 0.06
Nodes (34): any, _badPercent, code, ConnectPayload, ConnectPayloadError, detail, deviceId, encode (+26 more)

### Community 42 - "Community 42"
Cohesion: 0.06
Nodes (31): body, build, _controller, count, createState, current, dispose, _Dots (+23 more)

### Community 43 - "Community 43"
Cohesion: 0.06
Nodes (30): at, _cameraQr, _confirmLeave, createState, dispose, error, flow, hotspotErrorMessage (+22 more)

### Community 44 - "Community 44"
Cohesion: 0.07
Nodes (22): fileOpenerProvider, StoredSession, TrustedDevice, build, _Empty, HistoryDetailScreen, historyProvider, HistoryScreen (+14 more)

### Community 45 - "Community 45"
Cohesion: 0.09
Nodes (30): Bench Builds (CI bench input), crossdrop-bench.csv Columns, Benchmark Matrix (sizes x networks x directions), LocalSend, Fair LocalSend Comparison Protocol, Phase 1 Proof-of-Concept Benchmarks, Phase 7 Benchmarks (buffer sizes, network modes, LocalSend), Step A: Choose the Buffer Size (256 KB / 1 MB / 4 MB) (+22 more)

### Community 46 - "Community 46"
Cohesion: 0.06
Nodes (30): _added, addedNetwork, _answers, _current, dispose, _disposed, error, _generation (+22 more)

### Community 47 - "Community 47"
Cohesion: 0.06
Nodes (30): add, cell, client, close, dir, _fakeQr, fingerprint, hash (+22 more)

### Community 48 - "Community 48"
Cohesion: 0.06
Nodes (31): assetId, base, convertedToJpeg, convertHeicToJpeg, convertToJpeg, dot, exported, exportedFileName (+23 more)

### Community 49 - "Community 49"
Cohesion: 0.06
Nodes (31): AndroidShareInbox, arrivals, capped, _channel, _copyTree, decoded, _delete, failed (+23 more)

### Community 50 - "Community 50"
Cohesion: 0.07
Nodes (18): build, fraction, onTap, _Tile, title, onShowQr, _status, _close (+10 more)

### Community 51 - "Community 51"
Cohesion: 0.07
Nodes (20): NotEnoughSpace, main, names, _next, obj, file, main, camera (+12 more)

### Community 52 - "Community 52"
Cohesion: 0.06
Nodes (31): candidates, _changes, _check, connectivityEvents, _current, debounce, _debounceTimer, dispose (+23 more)

### Community 53 - "Community 53"
Cohesion: 0.07
Nodes (31): WifiCredentials, address, addressPoll, addressWait, build, error, esc, HotspotController (+23 more)

### Community 54 - "Community 54"
Cohesion: 0.07
Nodes (17): build, c, _databaseDirectory, databaseProvider, db, documents, IdentityNotifier, lifecycle (+9 more)

### Community 55 - "Community 55"
Cohesion: 0.10
Nodes (22): crossdrop-limits.csv, iperf3 Baseline, Parallel Streams (not built, D-059), Step 0: Measure This Phone (per-phone limits), Android Release Signing (key.properties / CI secrets), App Id io.github.shreyashjunje.crossdrop (D-063), Measure This Phone (D-066), Sender Reads Next 1 MB While Sending (+14 more)

### Community 56 - "Community 56"
Cohesion: 0.08
Nodes (14): fl_register_plugins(), main(), first_frame_cb(), my_application_activate(), my_application_class_init(), my_application_dispose(), my_application_init(), my_application_local_command_line() (+6 more)

### Community 57 - "Community 57"
Cohesion: 0.07
Nodes (20): _addressUnreachable, _Banner, _connect, _connecting, connectionHint, _controller, createState, _EmptyState (+12 more)

### Community 58 - "Community 58"
Cohesion: 0.08
Nodes (20): _channel, ChannelFreeSpace, freeBytes, FreeSpace, _channel, requestAccess, saveToGallery, beginBackgroundTask (+12 more)

### Community 59 - "Community 59"
Cohesion: 0.07
Nodes (29): busy, cancelled, capability, _channel, ChannelHotspotService, code, disallowed, failed (+21 more)

### Community 60 - "Community 60"
Cohesion: 0.07
Nodes (26): _api, append, _channel, ChannelMediaStore, cleanupOrphans, cleanupPending, close, delete (+18 more)

### Community 61 - "Community 61"
Cohesion: 0.07
Nodes (26): _accept, blackhole, client, close, connections, _countUp, _dead, destroy (+18 more)

### Community 62 - "Community 62"
Cohesion: 0.07
Nodes (25): cancelCopy, cancelled, _channel, ContentInfo, copy, copyIntoStaging, created, describe (+17 more)

### Community 63 - "Community 63"
Cohesion: 0.08
Nodes (23): IncomingOffer, _StopCountdown, _StopCountdownState, accept, _answer, build, code, createState (+15 more)

### Community 65 - "Community 65"
Cohesion: 0.08
Nodes (19): build, NumberedSteps, steps, build, skipped, SkippedNotice, why, dirs (+11 more)

### Community 66 - "Community 66"
Cohesion: 0.07
Nodes (21): android, b, CredentialRepository, current, _db, defaultDeviceName, deviceId, deviceName (+13 more)

### Community 67 - "Community 67"
Cohesion: 0.08
Nodes (27): Network Setup Labels (Router 2.4/5 GHz, Android hotspot, iPhone hotspot), Android In-app Hotspot (LocalOnlyHotspot), Android Network Binding (D-056), M5/L4: Cancel While Connecting or Checking Address, Checkpoints Every 2 s or 64 MB (D-065), Code Review 2026-11-03, L2: /complete Rechecks Session After Body, File-name Sanitizer (+19 more)

### Community 68 - "Community 68"
Cohesion: 0.09
Nodes (18): formatSettingsProvider, receivingEnabledProvider, settingsRepositoryProvider, _finish, build, build, createState, dispose (+10 more)

### Community 69 - "Community 69"
Cohesion: 0.08
Nodes (13): build, CrossDropApp, buildTheme, minButton, padding, scheme, _seed, build (+5 more)

### Community 70 - "Community 70"
Cohesion: 0.08
Nodes (22): appVersion, BenchCase, BenchRunner, BenchSessionFactory, bufferBytes, cancel, _cancelled, _current (+14 more)

### Community 71 - "Community 71"
Cohesion: 0.08
Nodes (24): addresses, _ap, build, c, _cancel, _client, containerFor, failWith (+16 more)

### Community 72 - "Community 72"
Cohesion: 0.18
Nodes (25): appDirsProvider, mediaPlatformProvider, receivedFileStoreProvider, sourceOpenerProvider, connectivityEventsProvider, credentialsProvider, freeSpaceProvider, identityProvider (+17 more)

### Community 73 - "Community 73"
Cohesion: 0.08
Nodes (19): certificateFingerprint, diff, fingerprintLength, _fingerprintPattern, fingerprintsEqual, head, isValidFingerprint, shortFingerprint (+11 more)

### Community 74 - "Community 74"
Cohesion: 0.10
Nodes (5): attached(), detached(), emit(), onIntent(), onListen()

### Community 76 - "Community 76"
Cohesion: 0.08
Nodes (19): build, _CheckPage, createState, dispose, initState, link, _LinkStatus, _me (+11 more)

### Community 77 - "Community 77"
Cohesion: 0.11
Nodes (23): Onboarding (three pages), Phase 6 UI Screens and Navigation, Receiving Runs Whenever App Is Open (D-046), Transfer History screen, Phase 6: UI and onboarding, Receiving on/off switch, VoiceOver and TalkBack accessibility, Screen review checklist (small, large, large text, dark) (+15 more)

### Community 78 - "Community 78"
Cohesion: 0.14
Nodes (24): Feature: Pairing and trust, Auto-accept per trusted fingerprint, Bearer token on /v1/sessions requests, checkPeer (peer check before Send), crossdrop-commit-v2 commitment (D-061), Lookalike device warning, 6-digit pairing code (derivePairingCode), pin_mismatch error (+16 more)

### Community 79 - "Community 79"
Cohesion: 0.08
Nodes (21): contains, didPop, didPush, didRemove, didReplace, findHelp, history, hotspot (+13 more)

### Community 80 - "Community 80"
Cohesion: 0.12
Nodes (22): localNetworkProvider, BenchScreen, HomeScreen, _HomeScreenState, PersonalHotspotGuide, _PersonalHotspotGuideState, build, FindHelpScreen (+14 more)

### Community 81 - "Community 81"
Cohesion: 0.08
Nodes (20): certificateDer, certificatePem, der, fingerprint, fromPem, generate, _generatePem, _hexBytes (+12 more)

### Community 82 - "Community 82"
Cohesion: 0.09
Nodes (20): _apply, binder, _bound, build, child, createState, _drain, _draining (+12 more)

### Community 83 - "Community 83"
Cohesion: 0.08
Nodes (21): addressSharingSubnet, fresh, hashCode, _hotspotInterface, InterfaceAddress, ip, looksLikeIphoneHotspot, mask (+13 more)

### Community 84 - "Community 84"
Cohesion: 0.08
Nodes (22): authenticate, AuthenticatedSender, _Challenge, _challenges, challengeTtl, commit, created, _expire (+14 more)

### Community 85 - "Community 85"
Cohesion: 0.08
Nodes (23): attached, cancelCurrent, cancels, close, closes, copied, copyErrors, copyGates (+15 more)

### Community 86 - "Community 86"
Cohesion: 0.09
Nodes (10): AppDirs, incomingTemp, outgoingStaging, received, resolve, androidSourcesProvider, dirs, iosShareInboxProvider (+2 more)

### Community 87 - "Community 87"
Cohesion: 0.09
Nodes (21): _active, activeCount, appBackgrounded, appResumed, _askedPermission, backgroundBudget, begin, end (+13 more)

### Community 88 - "Community 88"
Cohesion: 0.09
Nodes (17): _checked, checkPeer, client, deviceId, fingerprint, fingerprintHint, host, name (+9 more)

### Community 89 - "Community 89"
Cohesion: 0.09
Nodes (21): clear, _detach, deviceId, fingerprintHint, hashCode, host, _idByService, isSupported (+13 more)

### Community 90 - "Community 90"
Cohesion: 0.12
Nodes (22): Receiver Accept prompt (60 s timeout), App id change to io.github.shreyashjunje.crossdrop, Benchmark build (bench flag) and CSV output, GitHub Actions Build workflow (build.yml), Code review fixes device checks (2026-11-03, R-1 to R-9), PC CLI third device (tool/crossdrop_cli.dart), Debug-signed APK fallback, Device identity and security key (fingerprint) (+14 more)

### Community 91 - "Community 91"
Cohesion: 0.13
Nodes (21): Cable import from iPhone (D-067, U-1 to U-9), Cancel from either side with partial-file cleanup, Creation date preservation, D-035 Android 10 or newer required, D-037 Request unredacted Android original (location kept), D-042 PNG screenshot date known limit, Saving to gallery (MediaStore / Photos) with pending items, HEIC to JPEG and Live Photo video settings (+13 more)

### Community 92 - "Community 92"
Cohesion: 0.10
Nodes (19): ByteSource, chunkSize, defaultChunkSize, fd, FdSource, io, path, PathSource (+11 more)

### Community 93 - "Community 93"
Cohesion: 0.09
Nodes (21): Advertiser, _backend, _changes, _current, dispose, _emit, isAdvertising, isRunning (+13 more)

### Community 94 - "Community 94"
Cohesion: 0.10
Nodes (16): AuthFailure, code, _fpR, _fpS, _fpX, _knownCode, main, nr (+8 more)

### Community 96 - "Community 96"
Cohesion: 0.17
Nodes (18): Feature: Android hotspot from the app, Standard Wi-Fi QR for iPhone Camera (D-055), Hotspot error codes (permission, location_off, tethering_on, no_channel, ...), HotspotChannel.kt (crossdrop/hotspot), HotspotController, HotspotService / ChannelHotspotService, LocalOnlyHotspot (WifiManager.startLocalOnlyHotspot), NEARBY_WIFI_DEVICES permission (neverForLocation) (+10 more)

### Community 97 - "Community 97"
Cohesion: 0.11
Nodes (8): Flutter, SceneDelegate, Notification.Name, RunnerTests, RunnerTests, QuickLook, UIKit, XCTest

### Community 99 - "Community 99"
Cohesion: 0.10
Nodes (16): appVersion, clock, _finished, isBenchSession, linkMbps, me, network, platformShort (+8 more)

### Community 100 - "Community 100"
Cohesion: 0.10
Nodes (18): day, describeSaveLocations, diff, formatDay, formatDuration, formatMegabytes, formatSavedTo, formatSize (+10 more)

### Community 101 - "Community 101"
Cohesion: 0.11
Nodes (15): bytesOf, bytesPerSecond, _done, _doneBytes, drop, fraction, _meter, sizeOf (+7 more)

### Community 102 - "Community 102"
Cohesion: 0.18
Nodes (17): Feature: Resume, Backoff and 2-minute deadline (D-019), flaky_proxy test support, locatePeer (find receiver by device id), 24-hour partial file cleanup, Stall detection (15 s), Unfinished transfers launch prompt, Feature: Transfer engine (+9 more)

### Community 103 - "Community 103"
Cohesion: 0.15
Nodes (8): EnableNonClientDpiScaling, Scale(), Win32Window::Win32Window(), WindowClassRegistrar, class_registered_, WindowClassRegistrar::GetWindowClass(), instance_, WindowClassRegistrar::UnregisterWindowClass()

### Community 104 - "Community 104"
Cohesion: 0.15
Nodes (4): Foundation, HotspotJoinChannel, NetworkInfoChannel, NetworkExtension

### Community 105 - "Community 105"
Cohesion: 0.12
Nodes (16): _active, afterTransfer, _arm, build, capability, forget, hotspotJoinerProvider, join (+8 more)

### Community 106 - "Community 106"
Cohesion: 0.10
Nodes (19): answerAfter, capability, capable, check, checks, done, FakeNetwork, flowWith (+11 more)

### Community 107 - "Community 107"
Cohesion: 0.12
Nodes (13): bonsoir_darwin, Cocoa, connectivity_plus, file_picker_darwin, flutter_secure_storage_darwin, FlutterMacOS, RegisterGeneratedPlugins(), MainFlutterWindow (+5 more)

### Community 108 - "Community 108"
Cohesion: 0.14
Nodes (18): Known Risks (Local Network permission, screen lock, routing, OEM killers, client isolation, dart:io TLS), Android Network Binding (bindProcessToNetwork, D-056), Android SEND/SEND_MULTIPLE Share Intents (D-044), Guest/Public Wi-Fi Client Isolation Card, Connectivity Scenarios (10-row table), Android fd Streaming via pread / dart:ffi (D-036), iCloud-Only Originals Download While Preparing (D-038), iOS Documents Folder in Files (D-034) (+10 more)

### Community 109 - "Community 109"
Cohesion: 0.11
Nodes (17): band, bindToWifi, bound, _changes, _channel, ChannelNetworkPlatform, connected, frequencyMhz (+9 more)

### Community 110 - "Community 110"
Cohesion: 0.11
Nodes (18): default, description, type, concurrency, cancel-in-progress, group, env, BENCH_DEFINE (+10 more)

### Community 112 - "Community 112"
Cohesion: 0.11
Nodes (12): addresses, failWith, h, main, pump, pumpWidget, start, stop (+4 more)

### Community 113 - "Community 113"
Cohesion: 0.14
Nodes (16): AcceptedEvent, by, CancelledEvent, code, ErrorEvent, FileDoneEvent, fileId, fromJson (+8 more)

### Community 114 - "Community 114"
Cohesion: 0.11
Nodes (17): cached, cancel, capacity, close, _closed, _done, has, load (+9 more)

### Community 115 - "Community 115"
Cohesion: 0.14
Nodes (16): CrossDrop CLAUDE.md Project Instructions, Definition of Done per Phase, Tech Stack (Flutter, Riverpod, drift, shelf, bonsoir...), Per-Task Workflow (plan, small steps, analyze/test, commit), CrossDrop Architecture (ARCHITECTURE.md), Code Structure (lib/app, features, core, platform), Device Identity (ECDSA P-256 self-signed cert, D-028, D-030), Local Database Schema v5 (identity, trusted_devices, sessions, session_files, settings) (+8 more)

### Community 116 - "Community 116"
Cohesion: 0.12
Nodes (4): FlutterWindow, flutter_controller_, FlutterWindow::FlutterWindow(), project_

### Community 117 - "Community 117"
Cohesion: 0.11
Nodes (17): bare, base, detectFileType, dot, extensionOf, fromName, guessFileType, kind (+9 more)

### Community 118 - "Community 118"
Cohesion: 0.11
Nodes (17): availablePath, base, candidate, claimPath, dot, ext, _fallbackName, _forbiddenChars (+9 more)

### Community 119 - "Community 119"
Cohesion: 0.12
Nodes (13): KeepAliveCoordinator, keepAliveProvider, createState, dispose, initState, _keepAlive, _Message, MyQrScreen (+5 more)

### Community 120 - "Community 120"
Cohesion: 0.21
Nodes (5): AppDelegate, BackgroundTaskChannel, LocalNetworkChannel, StorageChannel, Network

### Community 122 - "Community 122"
Cohesion: 0.12
Nodes (16): benchBuffers, benchBuild, benchFileName, _benchName, benchSizes, ensureBenchFile, file, isBenchFileName (+8 more)

### Community 123 - "Community 123"
Cohesion: 0.14
Nodes (16): BonsoirBackend, attributes, crossDropServiceType, hostAddresses, MdnsAdvertisement, MdnsBackend, MdnsEvent, MdnsServiceLost (+8 more)

### Community 124 - "Community 124"
Cohesion: 0.12
Nodes (14): AuthChallenge, AuthChallengeRequest, AuthGranted, AuthRequest, certificate, commit, expiresIn, fromJson (+6 more)

### Community 125 - "Community 125"
Cohesion: 0.12
Nodes (14): WifiState, bindGate, binds, bindToWifi, bindWorks, changes, _home, initial (+6 more)

### Community 126 - "Community 126"
Cohesion: 0.12
Nodes (10): build, child, createState, didChangeAppLifecycleState, dispose, initState, null, _snack (+2 more)

### Community 127 - "Community 127"
Cohesion: 0.12
Nodes (13): decode, deviceId, encode, fingerprintHint, fingerprintHintLength, forDevice, _hintPattern, isSupported (+5 more)

### Community 128 - "Community 128"
Cohesion: 0.12
Nodes (14): beginBackgroundTask, calls, endBackgroundTask, ensureNotificationPermission, grant, hold, main, onBackground (+6 more)

### Community 129 - "Community 129"
Cohesion: 0.13
Nodes (13): build, createState, dispose, _form, _host, ManualAddressDialog, _ManualAddressDialogState, null (+5 more)

### Community 130 - "Community 130"
Cohesion: 0.19
Nodes (14): Bearer Token (32 bytes, 1 h idle expiry), POST /v1/auth (bearer token), POST /v1/sessions/{id}/files/{fileId}/complete, DELETE /v1/sessions/{id}, WS /v1/sessions/{id}/events, GET /v1/sessions/{id}/files/{fileId} (receivedBytes), GET /v1/info, POST /v1/sessions (offer) (+6 more)

### Community 131 - "Community 131"
Cohesion: 0.22
Nodes (15): Feature: Media and file picking, Android SourceChannel (crossdrop/source), iOS ExportChannel (crossdrop/export), FdFile / FdWorker descriptor I/O, GalleryPickerScreen (photo grid), Preparer (prepare picks before offer), SkipReason (prepare skips), SourceOpener (+7 more)

### Community 133 - "Community 133"
Cohesion: 0.15
Nodes (11): AndroidSources, AndroidDocumentPicker, DocumentPicker, _id, IosDocumentPicker, _length, _modified, pick (+3 more)

### Community 134 - "Community 134"
Cohesion: 0.13
Nodes (10): _broadcast, _discovery, _events, _onEvent, _resolved, startAdvertising, startBrowsing, stopAdvertising (+2 more)

### Community 135 - "Community 135"
Cohesion: 0.14
Nodes (13): close, _closed, FileSourceOpener, length, open, OpenedSource, reason, source (+5 more)

### Community 136 - "Community 136"
Cohesion: 0.15
Nodes (13): buildCameraRoll (tiles grouped by day), Cable Import iPhone -> Android (D-067), PUT /v1/sessions/{id}/files/{fileId}?offset=N, Failure Handling Table, failure_messages.dart Message Table (D-049), Free-Space Check (offer + open sessions + 64 MB reserve), MediaStore Pending Item as Partial File (D-040), android.mtp.MtpDevice PTP Camera Interface (+5 more)

### Community 137 - "Community 137"
Cohesion: 0.13
Nodes (9): _cpuStart, _peakRss, processCpuTime, ProcessSampler, sample, start, stop, _wall (+1 more)

### Community 138 - "Community 138"
Cohesion: 0.13
Nodes (9): ConnectTarget, beginBackgroundTask, endBackgroundTask, ensureNotificationPermission, main, setScreenOn, startService, stopService (+1 more)

### Community 139 - "Community 139"
Cohesion: 0.13
Nodes (12): advertisements, browseStarts, browseStops, current, emit, _events, failNextBrowse, isBrowsing (+4 more)

### Community 140 - "Community 140"
Cohesion: 0.15
Nodes (8): main, mib, sent, bench, main, _sender, session, tracker

### Community 142 - "Community 142"
Cohesion: 0.20
Nodes (13): L1: Exclusive File Creation to Claim Save Name, Keep a Changelog, ReceivedFileStore, Saving Received Files (MediaStore / Photos / Files), Import from iPhone by Cable (D-067), Feature: Saving received files, Database moved to Application Support (D-034), FolderStore (iOS Documents) (+5 more)

### Community 143 - "Community 143"
Cohesion: 0.19
Nodes (12): Abuse Limits (Receiving switch, rate limits, 429/431/413), Receiver Resource Limits (M1, M2, L3), Feature doc template, Feature doc structure (Summary, Scope, Design, Code, Protocol, Tests, Limits, Open questions), Feature: Abuse limits and server hygiene, Abuse error codes (403 receiving_off, 413 body_too_large, 429 rate_limited, 431 headers_too_large), Server memory caps (challenges, tokens), RateLimiter (token bucket per remote IP) (+4 more)

### Community 144 - "Community 144"
Cohesion: 0.14
Nodes (13): authCommitment, authSigningInput, bytes, derivePairingCode, digest, encode, formatPairingCode, isValidNonce (+5 more)

### Community 145 - "Community 145"
Cohesion: 0.18
Nodes (5): RegisterPlugins(), Win32Window, child_content_, quit_on_close_, window_handle_

### Community 146 - "Community 146"
Cohesion: 0.26
Nodes (11): DataClass, IdentityCompanion, IdentityData, SessionFileRow, SessionFilesCompanion, SessionRow, SettingsCompanion, SettingsRow (+3 more)

### Community 147 - "Community 147"
Cohesion: 0.15
Nodes (10): MediaPlatform, AndroidMedia, _channel, copyIntoStaging, describe, IosMedia, _onNative, resolveAsset (+2 more)

### Community 148 - "Community 148"
Cohesion: 0.22
Nodes (12): Android LocalOnlyHotspot Mode (D-054, D-055), Certificate SHA-256 Fingerprint as Identity, Sender Commitment crossdrop-commit-v2 (D-061), Connection Flow (Wi-Fi -> QR -> Hotspot), POST /v1/auth/challenge, Where the Receiver's Fingerprint Comes From (QR, trusted, probeFingerprint), 6-Digit Pairing Code crossdrop-code-v1 (D-029), probeFingerprint (handshake without request) (+4 more)

### Community 149 - "Community 149"
Cohesion: 0.26
Nodes (12): iPhone Personal Hotspot Guide, Feature: Android network binding, ConnectivityManager.bindProcessToNetwork, NetworkBinder, NetworkChannel.kt (crossdrop/network), NetworkPlatform / WifiState, Feature: iPhone Personal Hotspot guide, Maximize Compatibility advice (+4 more)

### Community 150 - "Community 150"
Cohesion: 0.27
Nodes (10): BenchDiscardingStore, Feature: File transfer proof of concept, ChunkedReader (1 MB reads), .part file resume (offset=N), Receive server (shelf HTTPS, receive_server.dart), sanitizeFileName / availablePath, Sha256Isolate, SpeedMeter (3 s moving average) (+2 more)

### Community 151 - "Community 151"
Cohesion: 0.19
Nodes (4): wWinMain(), CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16()

### Community 152 - "Community 152"
Cohesion: 0.15
Nodes (10): _attempt, attempts, Backoff, giveUpAfter, jitter, next, _random, reset (+2 more)

### Community 153 - "Community 153"
Cohesion: 0.18
Nodes (12): PeerAdded, PeerChange, PeerList, PeerRemoved, PeerUpdated, _a, _b, list (+4 more)

### Community 155 - "Community 155"
Cohesion: 0.18
Nodes (3): File Name Sanitization (review L8), pinnedHttpClient (leaf pinning), Privacy (no accounts, no analytics, 8-char fingerprint logs)

### Community 156 - "Community 156"
Cohesion: 0.17
Nodes (10): _Bucket, _buckets, burst, maxKeys, RateLimiter, refillEvery, take, tokens (+2 more)

### Community 157 - "Community 157"
Cohesion: 0.23
Nodes (11): Bonjour/mDNS Discovery (_crossdrop._tcp), iOS Local Network Probe, Feature: Discovery on the local network, checkPeer (GET /v1/info), iOS LocalNetworkProbe (D-015), MdnsBackend / BonsoirBackend, Android Wi-Fi multicast lock, NetworkMonitor (+3 more)

### Community 158 - "Community 158"
Cohesion: 0.18
Nodes (7): ProgressTracker, main, now, t, main, meter, now

### Community 159 - "Community 159"
Cohesion: 0.17
Nodes (9): _clientContext, connectTimeout, matches, PinMismatchException, pinnedHttpClient, probeFingerprint, socket, timeout (+1 more)

### Community 160 - "Community 160"
Cohesion: 0.17
Nodes (9): canMoveTo, from, moveTo, SessionStateMachine, sessionTransitions, _state, to, tryMoveTo (+1 more)

### Community 161 - "Community 161"
Cohesion: 0.17
Nodes (9): _CameraError, _controller, createState, dispose, _done, error, _message, _onDetect (+1 more)

### Community 162 - "Community 162"
Cohesion: 0.18
Nodes (7): delete, discarded, initialLocation, inner, length, restore, save

### Community 163 - "Community 163"
Cohesion: 0.18
Nodes (3): browser, timeout, main

### Community 165 - "Community 165"
Cohesion: 0.18
Nodes (11): Benchmark Builds CROSSDROP_BENCH (D-058, D-059), HEIC/Live Photo Format Settings (D-039), LocalSend (comparison baseline, D-060), Open Decisions, Performance Design, Receiver 8 MB Read-Ahead Write Queue (D-064), Trusted Devices and Auto-Accept, Per-Feature Docs Index (Phases 1-7, usb-import) (+3 more)

### Community 166 - "Community 166"
Cohesion: 0.24
Nodes (9): Format Handling (originals, HEIC to JPEG, D-042), Feature: Format handling between iPhone and Android, detectFileType / mimeForName / kindForMime, ExportChannel.swift, exportedFileName / pairedVideoName, FormatSettings (HEIC to JPEG, Live Photo video), livePhotoGroup field, planExport (+1 more)

### Community 167 - "Community 167"
Cohesion: 0.27
Nodes (10): Feature: Device identity, Certificate SHA-256 fingerprint (device identity), CredentialRepository.loadOrCreate, credentialsProvider, DeviceCredentials (ECDSA P-256 key, self-signed cert), Android no-backup rules (data_extraction_rules.xml), SecretStore interface / MemorySecretStore, SecureSecretStore (flutter_secure_storage, D-030) (+2 more)

### Community 168 - "Community 168"
Cohesion: 0.18
Nodes (11): if, name, needs, runs-on, timeout-minutes, jobs, android, test (+3 more)

### Community 169 - "Community 169"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 170 - "Community 170"
Cohesion: 0.29
Nodes (8): Bonjour/mDNS Advertisement _crossdrop._tcp, Lookalike Warning (trusted name, different key), Memory and Database Hygiene (review M1, M2, L3), Per-IP Rate Limits and Request Limits (D-031, D-032), Receiving Switch, Security Model, Server Lifetime (D-046, D-050, D-062, review M6), Threats and Defenses Table

### Community 171 - "Community 171"
Cohesion: 0.27
Nodes (10): Android local-only hotspot started by app, Android network binding to Wi-Fi without internet, Wi-Fi client isolation / blocked phone-to-phone traffic, Hotspot suggestion when phones can't reach each other, iPhone manual hotspot join (free Apple ID build), iPhone Personal Hotspot guide, In-app join via NEHotspotConfiguration (paid account), Phase 7: hotspot mode and benchmarks (+2 more)

### Community 172 - "Community 172"
Cohesion: 0.33
Nodes (10): Session pruning (ReceiveServer.prune), Feature: Keep-alive during transfers, crossdrop/background channel, checkpointAll (receiver fsync), Android dataSync foreground service, iOS beginBackgroundTask (20 s budget), KeepAliveCoordinator, KeepAlivePlatform / PlatformKeepAlive (+2 more)

### Community 173 - "Community 173"
Cohesion: 0.20
Nodes (7): accepted, _androidNotInGallery, _iosPhotos, kind, mime, SaveCollection, saveCollectionFor

### Community 174 - "Community 174"
Cohesion: 0.20
Nodes (8): bytes, cleaned, _control, maxDeviceNameBytes, out, sanitizeDeviceName, _spaces, toString

### Community 175 - "Community 175"
Cohesion: 0.20
Nodes (7): expiredReason, incomingTemp, maxAge, _newestChange, PartialCleanup, _repo, run

### Community 177 - "Community 177"
Cohesion: 0.22
Nodes (5): delete, read, SecureSecretStore, _storage, write

### Community 178 - "Community 178"
Cohesion: 0.33
Nodes (7): Feature: Benchmark mode, BenchResult CSV columns, BenchRunner, Parallel streams (D-059, not built), Phone limits measurement (D-066), Process stats (CPU via getrusage, peak RSS), ReceiverBenchTracker

### Community 179 - "Community 179"
Cohesion: 0.22
Nodes (9): with, cache, channel, distribution, flutter-version, java-version, name, path (+1 more)

### Community 180 - "Community 180"
Cohesion: 0.22
Nodes (5): main, _mobile, _wifi, _wifi2, main

### Community 181 - "Community 181"
Cohesion: 0.22
Nodes (5): arrivals, main, pump, takePending, takes

### Community 182 - "Community 182"
Cohesion: 0.39
Nodes (7): steps, steps, if, name, run, uses, steps

### Community 183 - "Community 183"
Cohesion: 0.25
Nodes (4): main, own, peerId, resolved

### Community 184 - "Community 184"
Cohesion: 0.25
Nodes (6): ConnectPayloadException, _fp, _id, main, _query, _uri

### Community 185 - "Community 185"
Cohesion: 0.29
Nodes (6): delete, MemorySecretStore, read, SecretStore, values, write

### Community 186 - "Community 186"
Cohesion: 0.29
Nodes (7): _channel, ChannelLocalNetwork, LocalNetwork, LocalNetworkStatus, openSettings, probe, _FakeLocalNetwork

### Community 187 - "Community 187"
Cohesion: 0.25
Nodes (4): _a, main, _own, _resolved

### Community 188 - "Community 188"
Cohesion: 0.43
Nodes (5): Identity, SessionFiles, Settings, TransferSessions, TrustedDevices

### Community 189 - "Community 189"
Cohesion: 0.33
Nodes (7): iOS Local Network permission and probe, mDNS/Bonjour nearby discovery, Android multicast lock (bonsoirMulticastLock), Onboarding and just-in-time permission prompts, P2-5 Wi-Fi switched mid-session, P2-7 Manual address entry, Phase 2: discovery and QR connect

### Community 190 - "Community 190"
Cohesion: 0.29
Nodes (7): FileFailed, FileProgress, FileSaved, OfferRefused, ReceiveEvent, SessionOffered, SessionStateChanged

### Community 191 - "Community 191"
Cohesion: 0.29
Nodes (4): SessionKeepAlive, k, log, main

### Community 192 - "Community 192"
Cohesion: 0.33
Nodes (5): analyzer, exclude, include, linter, rules

### Community 195 - "Community 195"
Cohesion: 0.33
Nodes (6): if, name, needs, runs-on, timeout-minutes, ios

### Community 197 - "Community 197"
Cohesion: 0.40
Nodes (4): skip, timeout, tags, large

### Community 198 - "Community 198"
Cohesion: 0.40
Nodes (5): CROSSDROP_KEY_ALIAS, CROSSDROP_KEY_PASSWORD, CROSSDROP_KEYSTORE_PASSWORD, KEYSTORE_BASE64, env

### Community 199 - "Community 199"
Cohesion: 0.50
Nodes (5): trustedDevicesProvider, trustRepositoryProvider, _lookupTrust, build, TrustedDevicesScreen

### Community 200 - "Community 200"
Cohesion: 0.40
Nodes (4): _DigestSink, _DigestSink, DigestSink, _Sink

### Community 203 - "Community 203"
Cohesion: 0.67
Nodes (4): build, UsbImportCard, usbDevicesProvider, usbImportAvailableProvider

### Community 204 - "Community 204"
Cohesion: 0.50
Nodes (4): KeepAlivePlatform, PlatformKeepAlive, FakePlatform, _NoKeepAlive

### Community 205 - "Community 205"
Cohesion: 0.50
Nodes (3): Point, x, y

### Community 206 - "Community 206"
Cohesion: 0.50
Nodes (3): Size, height, width

### Community 208 - "Community 208"
Cohesion: 0.67
Nodes (3): BackgroundAware, _ServerKeepAlive, FakeTransfer

## Knowledge Gaps
- **3034 isolated node(s):** `Network`, `ImageIO`, `.isCancelled`, `.sawDownload`, `.stalled` (+3029 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 3582 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **29 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Feature: Settings` connect `Community 78` to `Community 98`, `Community 77`, `Community 142`?**
  _High betweenness centrality (0.179) - this node is a cross-community bridge._
- **What connects `Network`, `ImageIO`, `.isCancelled` to the rest of the system?**
  _3034 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.012738853503184714 - nodes in this community are weakly interconnected._
- **Why does `Phase 6: UI and onboarding` connect `Community 77` to `Community 171`, `Community 45`, `Community 78`, `Community 90`, `Community 189`?**
  _High betweenness centrality (0.128) - this node is a cross-community bridge._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.017543859649122806 - nodes in this community are weakly interconnected._
- **Why does `Device Tests (DEVICE_TESTS.md)` connect `Community 45` to `Community 11`, `Community 171`, `Community 77`, `Community 55`, `Community 90`, `Community 91`, `Community 189`?**
  _High betweenness centrality (0.113) - this node is a cross-community bridge._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.02247191011235955 - nodes in this community are weakly interconnected._