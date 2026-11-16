import 'package:flutter/material.dart';

import '../notes/web_soap_templates_library.dart';
import 'web_template_builder.dart';

/// Desktop Templates destination: library root; builder is pushed so chrome
/// Templates nav can pop back to the list (same as Clients → profile).
class WebTemplatesHost extends StatelessWidget {
  const WebTemplatesHost({super.key});

  void _openBuilder(
    BuildContext context, {
    required String name,
    String description = '',
    bool seedPostnatal = true,
    String? remoteId,
    String? fieldsJson,
    bool published = false,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => WebTemplateBuilder(
          initialName: name,
          initialDescription: description,
          seedPostnatal: seedPostnatal,
          remoteId: remoteId,
          fieldsJson: fieldsJson,
          initialPublished: published,
          onBackToLibrary: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WebSoapTemplatesLibrary(
      onOpenBuilder:
          ({
            required String name,
            String description = '',
            bool seedPostnatal = true,
            String? remoteId,
            String? fieldsJson,
            bool published = false,
          }) {
            _openBuilder(
              context,
              name: name,
              description: description,
              seedPostnatal: seedPostnatal,
              remoteId: remoteId,
              fieldsJson: fieldsJson,
              published: published,
            );
          },
    );
  }
}
