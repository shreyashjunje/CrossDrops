import 'package:flutter/material.dart';

import '../../app/tokens.dart';
import '../../app/ui/ui.dart';
import '../../core/client/peer_check.dart';

/// Warns when [target] uses the name or id of a trusted device but has a
/// different security key (ARCHITECTURE.md, "Pairing"). Returns true to go
/// on, as an untrusted device that must pass the code check.
Future<bool> confirmLookalike(
  BuildContext context,
  ConnectTarget target,
) async {
  final lookalike = target.trust.lookalike;
  if (lookalike == null) return true;
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: context.cd.dangerSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.cd.dangerLine),
        ),
        child: Icon(Icons.gpp_maybe_outlined, color: context.cd.danger),
      ),
      title: Text('Not the "${lookalike.name}" you trusted'),
      content: const Text(
        'This device has the same name, but a different security key. It '
        'may have been reinstalled, or someone may be pretending to be it.\n\n'
        'If you go on, compare the 6-digit code on both phones before the '
        'other phone accepts.',
      ),
      actions: [
        FilledButton(
          style: CdButtonStyles.secondary(context),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Stop'),
        ),
        OutlinedButton(
          style: CdButtonStyles.danger(context),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Continue anyway'),
        ),
      ],
    ),
  );
  return go ?? false;
}
