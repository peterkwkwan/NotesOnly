import 'package:flutter_test/flutter_test.dart';
import 'package:pelvi_crm/features/notes/note_format.dart';

void main() {
  test('preview falls back to first non-empty without previous', () {
    expect(
      soapRevisionPreview(
        subjective: 'Patient reports pain.',
        objective: 'Tone reduced.',
        assessment: '',
        plan: '',
      ),
      'Patient reports pain.',
    );
  });

  test('preview prefers changed sentence over unchanged Subjective', () {
    expect(
      soapRevisionPreview(
        subjective: 'Patient reports pain.',
        objective: 'Tone reduced. The word was changed.',
        assessment: '',
        plan: '',
        previousSubjective: 'Patient reports pain.',
        previousObjective: 'Tone reduced. Sleep is ok.',
        previousAssessment: '',
        previousPlan: '',
      ),
      'The word was changed.',
    );
  });

  test('preview prefers last changed SOAP section', () {
    expect(
      soapRevisionPreview(
        subjective: 'S updated',
        objective: 'O same',
        assessment: 'A same',
        plan: 'Plan now says rest.',
        previousSubjective: 'S old',
        previousObjective: 'O same',
        previousAssessment: 'A same',
        previousPlan: 'Plan was walk.',
      ),
      'Plan now says rest.',
    );
  });

  test('preview truncates long one-line chunks', () {
    final long = 'A' * 80;
    final out = soapRevisionPreview(
      subjective: long,
      objective: '',
      assessment: '',
      plan: '',
    );
    expect(out.endsWith('…'), isTrue);
    expect(out.length, 73);
  });
}
