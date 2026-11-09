import 'package:flutter/material.dart';

import '../../app/tokens.dart';

/// Instructions as numbered steps. Each step is one screen-reader node:
/// "Step 2 of 4. Join ...".
class NumberedSteps extends StatelessWidget {
  const NumberedSteps({super.key, required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    return Container(
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: BorderRadius.circular(CdRadius.button),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, step) in steps.indexed)
            Semantics(
              container: true,
              label: 'Step ${i + 1} of ${steps.length}. $step',
              excludeSemantics: true,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  border: i == 0
                      ? null
                      : Border(top: BorderSide(color: c.line)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.surface3,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        textScaler: TextScaler.noScaling,
                        style: CdType.titleS.copyWith(
                          fontSize: 13,
                          color: c.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        step,
                        style: CdType.bodyM.copyWith(color: c.text),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
