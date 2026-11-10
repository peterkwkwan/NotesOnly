import 'package:flutter/material.dart';

import '../notes/web_soap_templates_library.dart';
import 'web_template_builder.dart';

/// Desktop Templates destination: library list, or builder when editing a draft.
class WebTemplatesHost extends StatefulWidget {
  const WebTemplatesHost({super.key});

  @override
  State<WebTemplatesHost> createState() => _WebTemplatesHostState();
}

class _WebTemplatesHostState extends State<WebTemplatesHost> {
  bool _inBuilder = false;
  String _builderName = 'Postnatal Check';
  String _builderDescription = 'Guided prompts for a postnatal review.';
  bool _seedPostnatal = true;
  String? _remoteId;
  String? _fieldsJson;
  int _openGen = 0;

  void _openBuilder({
    required String name,
    String description = '',
    bool seedPostnatal = true,
    String? remoteId,
    String? fieldsJson,
  }) {
    setState(() {
      _openGen += 1;
      _inBuilder = true;
      _builderName = name;
      _builderDescription = description;
      _seedPostnatal = seedPostnatal;
      _remoteId = remoteId;
      _fieldsJson = fieldsJson;
    });
  }

  void _closeBuilder() {
    setState(() => _inBuilder = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_inBuilder) {
      return WebTemplateBuilder(
        key: ValueKey(_openGen),
        initialName: _builderName,
        initialDescription: _builderDescription,
        seedPostnatal: _seedPostnatal,
        remoteId: _remoteId,
        fieldsJson: _fieldsJson,
        onBackToLibrary: _closeBuilder,
      );
    }
    return WebSoapTemplatesLibrary(
      onOpenBuilder:
          ({
            required String name,
            String description = '',
            bool seedPostnatal = true,
            String? remoteId,
            String? fieldsJson,
          }) {
            _openBuilder(
              name: name,
              description: description,
              seedPostnatal: seedPostnatal,
              remoteId: remoteId,
              fieldsJson: fieldsJson,
            );
          },
    );
  }
}
