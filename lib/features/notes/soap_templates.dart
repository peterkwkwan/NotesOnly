/// Built-in SOAP fill templates for the note editor.

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

/// Postnatal check — clinic paste; P empty.
const soapTemplatePostnatal = SoapTemplate(
  id: 'postnatal_check',
  label: 'Postnatal Check',
  subjective: '''OBGYN: 

 weeks PN

Presenting Condition (why here today) / Patient Goals -



Pregnancy History:

G P

Birth weight - 

Sex - 

Type of delivery -  

Instruments -  

Length of pushing stage - 

Tearing/episiotomy - 

Complications -

Recovery journey - 



Feeding:

Breast/bottle - 
Feeding/breast issues - 


Musculoskeletal problems/pain:  

Neck -
Back - 
Wrist - 
LL - 


Exercise: 

Current -  

Pre-pregnancy -

How active during pregnancy - 

Goals for exercise - 

 

Pelvic Floor:

Bladder/OAB: 

Fluid intake - 
Voiding frequency - 
Leaking - 
Activities - 
Volume -
Frequency - 
Pad use ( # / volume) - 
Urgency incontinence -  
Triggers -
Volume - 
Frequency - 
Nocturia - 
Sensation - 
Flow - 
Fully empty -  
Pre-pregnancy - 


Bowel: 

Frequency -  
Straining -  
Incontinence (faecal or flatus) -   
Urgency - 
Pre-pregnancy - 


Prolapse: 

Pain -  
Prolapse symptoms:
Heaviness -  
Pressure -  
Time of day/activity -
Any previous/current PF exs - 


Intercourse: 

Sexually active -  
Any difficulty/pain - 
Entrance - 
Deep pain - 
Positional - 
Incontinence - 
Orgasm - 
 

Menstrual status:

Returned - 
Choice of protection - 
Contraception - 


Lochia - finished at week 



Abdomen:  

Aware of any separation - 
Having any issues -  
Strength - 
Aesthetic - 
 

General health/Medical History - 

Cancer Hx - 

Medications -  

Social History - 

Coping/mood -  
''',
  objective: '''Obs / posture -  

Breathing pattern - 

Abdominal appearance in standing - 

Ability to transfer load in standing - use UL to create pressure

Down - 
Left - 
Right -


Linea alba:

Integrity -  
Tension -  


DRAM Manual (head lift):

4cm above umbilicus - 
2cm above umbilicus - 
2cm below umbilicus - 


C-section scar -



VE: Informed valid verbal consent gained, signed consent form

EXTERNAL:

Observation

Skin colour - 
Introitus held open -
Swelling - 
GH+PB - 


Sensation

Thighs -  
Glutes -  
Labia - 
Perineum -  


PF Contraction

Perineum movement relative to ischial tuberosities - yes 
How much does introitus closes - minimal
External anal sphincter - elevates
Compensatory/accessory strategies:
Breathing - 
Adductors - 
Glutes - 
Core - 


Cough/bear down

Level of descent - 


INTERNAL: 

Palpation 

Superficial -  
Deep - 


PF PERFECT Contraction (global - levator + bulbo):

P - 
E - 
R - 
F -
T 
''',
  assessment: '''1. Postnatal check:

2. Home exercise program:
''',
  plan: '',
);

/// Pelvic floor — clinic paste; S/A/P empty.
const soapTemplatePelvicFloor = SoapTemplate(
  id: 'pelvic_floor',
  label: 'Pelvic Floor',
  subjective: '',
  objective: '''Obs / posture - 

Breathing pattern - 

Abdominal appearance in standing -

Ability to transfer load in standing - use UL to create pressure

Down - 
Left - 
Right -


Linea alba:

Integrity - good 
Tension -  moderate 


DRAM Manual (head lift)l:

4cm above umbilicus -
2cm above umbilicus -
2cm below umbilicus - 


VE: Informed valid verbal consent gained, signed consent form

EXTERNAL:

Observation

Skin colour - 
Introitus held open -
Swelling - 
GH+PB - 


Sensation

Thighs -  
Glutes -  
Labia - 
Perineum -  


PF Contraction

Perineum movement relative to ischial tuberosities - yes 
How much does introitus closes - minimal
External anal sphincter - elevates
Compensatory/accessory strategies:
Breathing - 
Adductors - 
Glutes - 
Core - 


Cough/bear down

Level of descent - 


INTERNAL: 

Palpation 

Superficial -  
Deep - 


PF PERFECT Contraction (global - levator + bulbo):

P - 
E - 
R - 
F -
T 
''',
  assessment: '',
  plan: '',
);

/// DRAM — empty S/A/P; O from clinic paste (dram-template-source).
const soapTemplateDram = SoapTemplate(
  id: 'dram',
  label: 'DRAM',
  subjective: '',
  objective: '''Obs / posture -  

Breathing pattern - 

Abdominal appearance in standing - 

Ability to transfer load in standing - use UL to create pressure

Down - 
Left - 
Right -


Linea alba:

Integrity -  
Tension -  


DRAM Manual (head lift)l:

4cm above umbilicus - 
2cm above umbilicus - 
2cm below umbilicus - 


C-section scar -''',
  assessment: '',
  plan: '',
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
