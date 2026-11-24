import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'database.dart';
import 'online.dart';
import 'org.dart';

const clientSummaryNoteLimit = 5;
const clientSummaryApptLimit = 5;

/// Local Settings key for a cached AI summary for [clientRemoteId].
String clientSummaryCacheKey(String clientRemoteId) =>
    'client_summary_cache__$clientRemoteId';

class ClientSummaryCache {
  const ClientSummaryCache({
    required this.summary,
    required this.inputHash,
    required this.generatedAt,
  });

  final String summary;
  final String inputHash;
  final String generatedAt;

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'inputHash': inputHash,
        'generatedAt': generatedAt,
      };

  static ClientSummaryCache? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final summary = '${map['summary'] ?? ''}'.trim();
      final inputHash = '${map['inputHash'] ?? ''}'.trim();
      if (summary.isEmpty || inputHash.isEmpty) return null;
      return ClientSummaryCache(
        summary: summary,
        inputHash: inputHash,
        generatedAt: '${map['generatedAt'] ?? ''}',
      );
    } catch (_) {
      return null;
    }
  }
}

class ClientSummaryPayload {
  const ClientSummaryPayload({
    required this.orgId,
    required this.clientId,
    required this.diagnosisCurrent,
    required this.diagnosisPast,
    required this.notes,
    required this.appointments,
    required this.inputHash,
  });

  final String orgId;
  final String clientId;
  final String diagnosisCurrent;
  final String diagnosisPast;
  final List<Map<String, dynamic>> notes;
  final List<Map<String, dynamic>> appointments;
  final String inputHash;

  Map<String, dynamic> toCallableMap({bool force = false}) => {
        'orgId': orgId,
        'clientId': clientId,
        'diagnosisCurrent': diagnosisCurrent,
        'diagnosisPast': diagnosisPast,
        'notes': notes,
        'appointments': appointments,
        if (force) 'force': true,
      };
}

/// Owner or Practitioner may generate SOAP-based AI summaries.
bool canViewClientSummary(Iterable<OrgRole> roles) {
  return roles.contains(OrgRole.owner) ||
      roles.contains(OrgRole.practitioner);
}

/// Admin-only (no owner/practitioner) must not see SOAP-derived summaries.
bool isAdminBlockedFromSummary(Iterable<OrgRole> roles) {
  return roles.contains(OrgRole.admin) && !canViewClientSummary(roles);
}

String _iso(DateTime dt) => dt.toUtc().toIso8601String();

String _apptStatusLabel(AppointmentStatus status) => switch (status) {
      AppointmentStatus.scheduled => 'scheduled',
      AppointmentStatus.completed => 'completed',
      AppointmentStatus.cancelled => 'cancelled',
      AppointmentStatus.noShow => 'noShow',
    };

/// FNV-1a 32-bit hex — stable cache fingerprint without a crypto package.
String fingerprintClientSummaryInput(String material) {
  var hash = 0x811c9dc5;
  for (final unit in material.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

Future<ClientSummaryPayload?> buildClientSummaryPayload(
  AppDatabase db, {
  required Client client,
}) async {
  final orgId = (await db.getSetting(AppDatabase.activeOrgIdKey))?.trim() ?? '';
  if (orgId.isEmpty) return null;

  final roles = parseOrgRoles(await db.getSetting(AppDatabase.activeOrgRolesKey));
  if (!canViewClientSummary(roles)) return null;

  final selfUid =
      (await db.getSetting(AppDatabase.syncBoundUidKey))?.trim() ?? '';
  final isOwner = roles.contains(OrgRole.owner);

  final allNotes = await db.watchNotesForClient(client.id).first;
  final published = <Note>[];
  for (final n in allNotes) {
    if (n.status != NoteStatus.published) continue;
    if (!isOwner) {
      final ownerUid = n.practitionerUid.isEmpty ? selfUid : n.practitionerUid;
      if (selfUid.isEmpty || ownerUid != selfUid) continue;
    }
    published.add(n);
    if (published.length >= clientSummaryNoteLimit) break;
  }

  final allAppts = await db.watchAppointmentsForClient(client.id).first;
  final appts = <Appointment>[];
  for (final a in allAppts) {
    if (a.status == AppointmentStatus.cancelled) continue;
    appts.add(a);
    if (appts.length >= clientSummaryApptLimit) break;
  }

  final clientRemoteId =
      client.remoteId.trim().isEmpty ? 'local_${client.id}' : client.remoteId;
  final diagnosisCurrent = (client.diagnosisCurrent ?? '').trim();
  final diagnosisPast = (client.diagnosisPast ?? '').trim();

  final noteMaps = [
    for (final n in published)
      <String, dynamic>{
        'noteDate': _iso(n.noteDate),
        'subjective': n.subjective,
        'objective': n.objective,
        'assessment': n.assessment,
        'plan': n.plan,
        'practitionerUid': n.practitionerUid,
        'remoteId': n.remoteId,
        'updatedAt': _iso(n.updatedAt),
      },
  ];
  final apptMaps = [
    for (final a in appts)
      <String, dynamic>{
        'startsAt': _iso(a.startsAt),
        'status': _apptStatusLabel(a.status),
      },
  ];

  final material = jsonEncode({
    'orgId': orgId,
    'clientId': clientRemoteId,
    'diagnosisCurrent': diagnosisCurrent,
    'diagnosisPast': diagnosisPast,
    'notes': [
      for (final n in noteMaps)
        {
          'remoteId': n['remoteId'],
          'updatedAt': n['updatedAt'],
          'noteDate': n['noteDate'],
          'subjective': n['subjective'],
          'objective': n['objective'],
          'assessment': n['assessment'],
          'plan': n['plan'],
        },
    ],
    'appointments': apptMaps,
  });

  return ClientSummaryPayload(
    orgId: orgId,
    clientId: clientRemoteId,
    diagnosisCurrent: diagnosisCurrent,
    diagnosisPast: diagnosisPast,
    notes: noteMaps,
    appointments: apptMaps,
    inputHash: fingerprintClientSummaryInput(material),
  );
}

class ClientSummaryApi {
  ClientSummaryApi({FirebaseFunctions? functions}) : _functions = functions;

  final FirebaseFunctions? _functions;

  FirebaseFunctions get _fn =>
      _functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  Future<ClientSummaryCache> generate(
    ClientSummaryPayload payload, {
    bool force = false,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw StateError('Sign in required');
    }
    final callable = _fn.httpsCallable('generateClientSummary');
    final result = await callable.call(payload.toCallableMap(force: force));
    final map = Map<String, dynamic>.from(result.data as Map);
    final summary = '${map['summary'] ?? ''}'.trim();
    if (summary.isEmpty) throw StateError('Empty summary');
    // Prefer local fingerprint so cache matches our Drift-side key.
    return ClientSummaryCache(
      summary: summary,
      inputHash: payload.inputHash,
      generatedAt: '${map['generatedAt'] ?? DateTime.now().toUtc().toIso8601String()}',
    );
  }
}

Future<ClientSummaryCache?> loadClientSummaryCache(
  AppDatabase db,
  String clientRemoteId,
) async {
  final raw = await db.getSetting(clientSummaryCacheKey(clientRemoteId));
  return ClientSummaryCache.tryParse(raw);
}

Future<void> saveClientSummaryCache(
  AppDatabase db,
  String clientRemoteId,
  ClientSummaryCache cache,
) {
  return db.setSetting(
    clientSummaryCacheKey(clientRemoteId),
    jsonEncode(cache.toJson()),
  );
}

/// Auto-generate when cache miss / hash changed; otherwise return cache.
Future<({ClientSummaryCache? cache, String? error, bool offline})>
    ensureClientSummary({
  required AppDatabase db,
  required Client client,
  required ClientSummaryApi api,
  bool force = false,
}) async {
  final roles = parseOrgRoles(await db.getSetting(AppDatabase.activeOrgRolesKey));
  if (isAdminBlockedFromSummary(roles)) {
    return (cache: null, error: 'admin_blocked', offline: false);
  }
  if (!canViewClientSummary(roles)) {
    return (cache: null, error: 'no_org', offline: false);
  }

  final payload = await buildClientSummaryPayload(db, client: client);
  if (payload == null) {
    return (cache: null, error: 'no_org', offline: false);
  }

  try {
    if (FirebaseAuth.instance.currentUser == null) {
      final existing = await loadClientSummaryCache(db, payload.clientId);
      return (cache: existing, error: 'signed_out', offline: false);
    }
  } catch (_) {
    final existing = await loadClientSummaryCache(db, payload.clientId);
    return (cache: existing, error: 'signed_out', offline: false);
  }

  final remoteId = payload.clientId;
  final existing = await loadClientSummaryCache(db, remoteId);
  if (!force &&
      existing != null &&
      existing.inputHash == payload.inputHash) {
    return (cache: existing, error: null, offline: false);
  }

  final online = await deviceLooksOnline();
  if (!online) {
    return (
      cache: existing,
      error: existing == null ? 'offline' : 'offline_stale',
      offline: true,
    );
  }

  if (payload.notes.isEmpty &&
      payload.diagnosisCurrent.isEmpty &&
      payload.diagnosisPast.isEmpty) {
    final empty = ClientSummaryCache(
      summary: 'Not enough published notes to summarize yet.',
      inputHash: payload.inputHash,
      generatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    await saveClientSummaryCache(db, remoteId, empty);
    return (cache: empty, error: null, offline: false);
  }

  try {
    final generated = await api.generate(payload, force: force);
    await saveClientSummaryCache(db, remoteId, generated);
    return (cache: generated, error: null, offline: false);
  } on FirebaseFunctionsException catch (e) {
    return (
      cache: existing,
      error: e.message ?? e.code,
      offline: false,
    );
  } catch (e) {
    return (cache: existing, error: '$e', offline: false);
  }
}
