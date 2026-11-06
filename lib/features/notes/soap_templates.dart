/// Built-in SOAP fill templates for the note editor.
///
/// shortcut: paste text was not available at ship time — section bodies are
/// reconstructed from structural markers (OBGYN→Social, Obs→PERFECT, etc.);
/// re-paste real clinic wording when available.

/// One SOAP template choice (blank = no fill).
class SoapTemplate {
  const SoapTemplate({
    required this.id,
    required this.label,
    this.subjective = '',
    this.objective = '',
    this.assessment = '',
    this.plan = '',
  });

  final String id;
  final String label;
  final String subjective;
  final String objective;
  final String assessment;
  final String plan;

  bool get isBlank => id == blankId;

  bool get hasFill =>
      subjective.isNotEmpty ||
      objective.isNotEmpty ||
      assessment.isNotEmpty ||
      plan.isNotEmpty;
}

const blankId = 'blank';

const soapTemplateBlank = SoapTemplate(
  id: blankId,
  label: 'Blank',
);

/// Postnatal check — S OBGYN…Social; O Obs…PERFECT; A postnatal; P HEP/PF.
const soapTemplatePostnatal = SoapTemplate(
  id: 'postnatal_check',
  label: 'Postnatal Check',
  subjective: '''OBGYN Hx:
Parity / G:
EDD / DOB baby:
Delivery: SVD / instrumental / C-section
Gestation:
Tear / episiotomy / repair:
Feeding: BF / bottle / mixed
Bladder:
Bowel:
Prolapse sx:
PF / incontinence:
Pain / dyspareunia:
Scar / wound:
Mood / sleep:
Social:''',
  objective: '''Obs / posture:
Abdomen / DRAM:
Scar:
PF exam:
  External:
  Internal:
  PERFECT:''',
  assessment: '''1. Postnatal check
2.
3.''',
  plan: '''Home exercise:
PF plan:
Advice:
Follow-up:''',
);

/// Pelvic floor — Subjective skeleton + exam under O when paste lacks S body.
const soapTemplatePelvicFloor = SoapTemplate(
  id: 'pelvic_floor',
  label: 'Pelvic Floor',
  subjective: '''Bladder:
Bowel:
Prolapse:
Intercourse:''',
  objective: '''Obs:
External perineum:
Sensation:
Tone / tenderness:
Cough / bearing down:
Internal exam:
  Strength:
  Endurance:
  Coordination:
  PERFECT:''',
  assessment: '''1.
2.''',
  plan: '''1.
2.
HEP:
Follow-up:''',
);

/// DRAM — blank S; O Obs…C-section; empty A; plan as given.
const soapTemplateDram = SoapTemplate(
  id: 'dram',
  label: 'DRAM',
  subjective: '',
  objective: '''Obs:
Posture / breathing:
Abdomen / DRAM width + depth:
C-section scar / wound:''',
  assessment: '',
  plan: '''Education:
Abdominal / DRAM rehab:
Load / activity advice:
Follow-up:''',
);

const soapTemplates = <SoapTemplate>[
  soapTemplateBlank,
  soapTemplatePostnatal,
  soapTemplatePelvicFloor,
  soapTemplateDram,
];

SoapTemplate soapTemplateById(String id) {
  for (final t in soapTemplates) {
    if (t.id == id) return t;
  }
  return soapTemplateBlank;
}
