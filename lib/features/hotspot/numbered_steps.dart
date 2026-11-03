import 'package:flutter/material.dart';

/// Instructions as numbered steps. Each step is one screen-reader node:
/// "Step 2 of 4. Join ...".
class NumberedSteps extends StatelessWidget {
  const NumberedSteps({super.key, required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, step) in steps.indexed)
          Semantics(
            container: true,
            label: 'Step ${i + 1} of ${steps.length}. $step',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    child: Text(
                      '${i + 1}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(step, style: theme.textTheme.bodyLarge)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
