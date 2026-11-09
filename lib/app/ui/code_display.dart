import 'package:flutter/material.dart';

import '../tokens.dart';

/// The 6-digit pairing code: two groups of three, one digit per cell, the
/// same size on both phones so people can hold them side by side (D-069).
/// Screen readers hear "Code 4 8 2 9 1 3".
class CodeDisplay extends StatelessWidget {
  const CodeDisplay({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final c = context.cd;
    final digits = code.split('');
    final half = (digits.length / 2).ceil();
    Widget cell(String d) => Container(
      width: 48,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(CdRadius.tile),
        border: Border.all(color: c.lineStrong),
      ),
      child: Text(
        d,
        textScaler: TextScaler.noScaling,
        style: CdType.displayXL.copyWith(fontSize: 40, color: c.text),
      ),
    );
    return Semantics(
      container: true,
      label: 'Code ${digits.join(' ')}',
      excludeSemantics: true,
      // Scales down instead of overflowing on very narrow screens; the
      // digits are already far above any system text size.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < digits.length; i++) ...[
              if (i == half)
                const SizedBox(width: 14)
              else if (i > 0)
                const SizedBox(width: 6),
              cell(digits[i]),
            ],
          ],
        ),
      ),
    );
  }
}
