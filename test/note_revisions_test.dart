import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelvi_crm/data/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<Note> seedNote() async {
    final clientId = await db.insertClient(
      firstName: 'Ada',
      lastName: 'Lovelace',
    );
    final apptId = await db.insertAppointment(
      clientId: clientId,
      startsAt: DateTime(2026, 11, 15, 10),
      practitionerUid: 'uid-test',
    );
    return db.getOrCreateNoteForAppointment(
      appointmentId: apptId,
      clientId: clientId,
    );
  }

  test('autosave does not create revisions; save draft and publish do', () async {
    final note = await seedNote();

    await db.updateNoteSoap(
      id: note.id,
      subjective: 'S1',
      objective: '',
      assessment: '',
      plan: '',
    );
    expect(await db.listNoteRevisions(note.id), isEmpty);

    final drafted = await db.saveDraftWithRevision(
      id: note.id,
      subjective: 'S1',
      objective: '',
      assessment: '',
      plan: '',
    );
    expect(drafted, isTrue);
    expect(await db.listNoteRevisions(note.id), hasLength(1));

    // Dedup: same body again skips revision.
    final again = await db.saveDraftWithRevision(
      id: note.id,
      subjective: 'S1',
      objective: '',
      assessment: '',
      plan: '',
    );
    expect(again, isFalse);
    expect(await db.listNoteRevisions(note.id), hasLength(1));

    final published = await db.publishNote(
      id: note.id,
      subjective: 'S2',
      objective: '',
      assessment: '',
      plan: '',
    );
    expect(published, PublishNoteResult.published);
    final fresh = await db.getNote(note.id);
    expect(fresh!.status, NoteStatus.published);
    expect(await db.listNoteRevisions(note.id), hasLength(2));

    final noop = await db.publishNote(
      id: note.id,
      subjective: 'S2',
      objective: '',
      assessment: '',
      plan: '',
    );
    expect(noop, PublishNoteResult.noop);
  });

  test('cap of 5 soft-deletes oldest; restore forces draft without new row',
      () async {
    final note = await seedNote();
    for (var i = 0; i < 6; i++) {
      await db.saveDraftWithRevision(
        id: note.id,
        subjective: 'body-$i',
        objective: '',
        assessment: '',
        plan: '',
      );
    }
    final live = await db.listNoteRevisions(note.id);
    expect(live, hasLength(5));
    expect(live.first.subjective, 'body-5');
    expect(live.last.subjective, 'body-1');

    await db.publishNote(
      id: note.id,
      subjective: 'body-5',
      objective: '',
      assessment: '',
      plan: '',
    );
    // body-5 already snapshotted as draft — publish without new revision.
    expect(await db.listNoteRevisions(note.id), hasLength(5));
    expect((await db.getNote(note.id))!.status, NoteStatus.published);

    final oldestKept = live.last;
    final ok = await db.restoreNoteRevision(
      noteId: note.id,
      revisionId: oldestKept.id,
    );
    expect(ok, isTrue);
    final after = await db.getNote(note.id);
    expect(after!.status, NoteStatus.draft);
    expect(after.subjective, 'body-1');
    expect(await db.listNoteRevisions(note.id), hasLength(5));
  });

  test('editing a published note via autosave flips status to draft', () async {
    final note = await seedNote();
    await db.publishNote(
      id: note.id,
      subjective: 'done',
      objective: '',
      assessment: '',
      plan: '',
    );
    await db.updateNoteSoap(
      id: note.id,
      subjective: 'done edited',
      objective: '',
      assessment: '',
      plan: '',
    );
    expect((await db.getNote(note.id))!.status, NoteStatus.draft);
  });
}
