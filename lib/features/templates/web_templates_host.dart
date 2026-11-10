import 'package:flutter/material.dart';

import '../notes/web_soap_templates_library.dart';
import 'web_template_builder.dart';

/// Desktop Templates destination: library list, or builder when editing a draft.
class WebTemplatesHost extends StatefulWidget {
  const WebTemplatesHost({super.key, this.onEditorActive});

  /// Desktop shell hides its sidebar and top bar while the editor is open.
  final ValueChanged<bool>? onEditorActive;

  @override
  State<WebTemplatesHost> createState() => _WebTemplatesHostState();
}

class _WebTemplatesHostState extends State<WebTemplatesHost> {
  bool _inBuilder = false;
  String _builderName = 'Postnatal Check';
  String _builderDescription = 'Guided prompts for a postnatal review.';
  bool _seedPostnatal = true;

  void _openBuilder({
    required String name,
    String description = '',
    bool seedPostnatal = true,
  }) {
    setState(() {
      _inBuilder = true;
      _builderName = name;
      _builderDescription = description;
      _seedPostnatal = seedPostnatal;
    });
    widget.onEditorActive?.call(true);
  }

  void _closeBuilder() {
    setState(() => _inBuilder = false);
    widget.onEditorActive?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    if (_inBuilder) {
      return WebTemplateBuilder(
        initialName: _builderName,
        initialDescription: _builderDescription,
        seedPostnatal: _seedPostnatal,
        onBackToLibrary: _closeBuilder,
      );
    }
    return WebSoapTemplatesLibrary(
      onOpenBuilder: ({
        required String name,
        String description = '',
        bool seedPostnatal = true,
      }) {
        _openBuilder(
          name: name,
          description: description,
          seedPostnatal: seedPostnatal,
        );
      },
    );
  }
}
