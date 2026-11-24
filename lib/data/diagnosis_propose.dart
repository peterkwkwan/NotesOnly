import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'client_summary.dart';
import 'database.dart';
import 'online.dart';
import 'org.dart';

class DiagnosisProposal {
  const DiagnosisProposal({
    required this.majorDiagnoses,
    required this.caveats,
    required this.generatedAt,
    required this.inputHash,
  });

  /// Ranked major diagnosis labels (typically 3–5) for single-select pills.
  final List<String> majorDiagnoses;
  final String caveats;
  final String generatedAt;
  final String inputHash;

  bool get isEmpty => majorDiagnoses.isEmpty;
}

class DiagnosisProposeApi {
  DiagnosisProposeApi({FirebaseFunctions? functions}) : _functions = functions;

  final FirebaseFunctions? _functions;

  FirebaseFunctions get _fn =>
      _functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  Future<DiagnosisProposal> propose(ClientSummaryPayload payload) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw StateError('Sign in required');
    }
    final callable = _fn.httpsCallable('proposeDiagnosis');
    final result = await callable.call(payload.toCallableMap());
    final map = Map<String, dynamic>.from(result.data as Map);
    final rawList = map['majorDiagnoses'];
    final majorDiagnoses = <String>[];
    if (rawList is List) {
      for (final item in rawList) {
        final label = '$item'.trim();
        if (label.isEmpty) continue;
        majorDiagnoses.add(label);
        if (majorDiagnoses.length >= 5) break;
      }
    }
    return DiagnosisProposal(
      majorDiagnoses: majorDiagnoses,
      caveats: '${map['caveats'] ?? ''}'.trim(),
      generatedAt:
          '${map['generatedAt'] ?? DateTime.now().toUtc().toIso8601String()}',
      inputHash: '${map['inputHash'] ?? payload.inputHash}',
    );
  }
}

/// Owner/Practitioner only; Admin blocked — same ACL as client summary.
Future<({DiagnosisProposal? proposal, String? error, bool offline})>
    proposeClientDiagnosis({
  required AppDatabase db,
  required Client client,
  required DiagnosisProposeApi api,
}) async {
  final roles =
      parseOrgRoles(await db.getSetting(AppDatabase.activeOrgRolesKey));
  if (isAdminBlockedFromSummary(roles)) {
    return (proposal: null, error: 'admin_blocked', offline: false);
  }
  if (!canViewClientSummary(roles)) {
    return (proposal: null, error: 'no_org', offline: false);
  }

  final payload = await buildClientSummaryPayload(db, client: client);
  if (payload == null) {
    return (proposal: null, error: 'no_org', offline: false);
  }

  try {
    if (FirebaseAuth.instance.currentUser == null) {
      return (proposal: null, error: 'signed_out', offline: false);
    }
  } catch (_) {
    return (proposal: null, error: 'signed_out', offline: false);
  }

  final online = await deviceLooksOnline();
  if (!online) {
    return (proposal: null, error: 'offline', offline: true);
  }

  try {
    final proposal = await api.propose(payload);
    return (proposal: proposal, error: null, offline: false);
  } on FirebaseFunctionsException catch (e) {
    return (proposal: null, error: e.message ?? e.code, offline: false);
  } catch (e) {
    return (proposal: null, error: '$e', offline: false);
  }
}

/// Persist one selected major diagnosis onto diagnosisCurrent (past unchanged).
Future<bool> applySelectedDiagnosis(
  AppDatabase db,
  Client client,
  String diagnosisCurrent,
) {
  return db.updateClient(
    id: client.id,
    firstName: client.firstName,
    lastName: client.lastName,
    phone: client.phone,
    email: client.email,
    emergencyContact: client.emergencyContact,
    emergencyContactPhone: client.emergencyContactPhone,
    notes: client.notes,
    diagnosisCurrent: diagnosisCurrent,
    diagnosisPast: client.diagnosisPast,
  );
}
