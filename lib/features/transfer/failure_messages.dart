import '../../core/engine/send_session.dart';
import '../../core/protocol/models.dart';
import '../../core/storage/partial_cleanup.dart';
import 'transfer_format.dart';
import 'transfer_view.dart';

/// The button a failure screen offers for its next step.
enum NextAction {
  /// Sender: continue from the last confirmed byte.
  resume,

  /// Start over: pick files and send again.
  sendAgain,

  /// Connect with the other phone's QR code instead.
  scanQr,

  /// Open "Can't find the other phone?" (QR, then hotspot).
  findHelp,
  none,
}

/// What went wrong, in plain words, and what to do next. Built from the
/// failure table in ARCHITECTURE.md, "Failure handling" (D-049).
class FailureMessage {
  const FailureMessage({
    required this.title,
    required this.reason,
    required this.next,
    this.action = NextAction.none,
  });

  final String title;
  final String reason;
  final String next;
  final NextAction action;

  @override
  String toString() => '$title: $reason $next';
}

/// The message for a finished transfer that did not fully succeed, or null
/// when every file arrived.
FailureMessage? describeOutcome(TransferView v) => switch (v.stage) {
  TransferStage.done when v.failedCount > 0 => _partial(v),
  TransferStage.rejected => _rejected(v),
  TransferStage.cancelled => _cancelled(v),
  TransferStage.failed =>
    v.sending ? _sendFailed(v.reason, v.neededBytes) : _receiveFailed(v),
  _ => null,
};

FailureMessage _partial(TransferView v) {
  final n = v.files.length;
  return FailureMessage(
    title: 'Some files did not arrive',
    reason:
        '${v.savedCount} of $n files arrived. The others failed their '
        'integrity check twice, so they were not saved.',
    next: v.sending
        ? 'Send the missing files again.'
        : 'Ask ${v.peerName} to send the missing files again.',
    action: v.sending ? NextAction.sendAgain : NextAction.none,
  );
}

FailureMessage _rejected(TransferView v) {
  if (!v.sending) {
    return switch (v.reason) {
      RejectReasons.timeout => FailureMessage(
        title: 'Not answered in time',
        reason: 'The request expired after 60 seconds, so nothing arrived.',
        next: 'Ask ${v.peerName} to send again, then tap Accept.',
      ),
      RejectReasons.noSpace => FailureMessage(
        title: 'Not enough space',
        reason: 'This phone does not have room for these files.',
        next: 'Free some space, then ask ${v.peerName} to send again.',
      ),
      _ => const FailureMessage(
        title: 'You declined',
        reason: 'Nothing was received.',
        next: 'Nothing else to do.',
      ),
    };
  }
  return switch (v.reason) {
    RejectReasons.timeout => const FailureMessage(
      title: 'Not answered',
      reason: 'Nobody tapped Accept on the other phone within 60 seconds.',
      next: 'Ask the other person to watch their screen, then send again.',
      action: NextAction.sendAgain,
    ),
    RejectReasons.noSpace => FailureMessage(
      title: 'Not enough space on the other phone',
      reason: v.neededBytes == null
          ? 'The other phone does not have room for these files.'
          : 'The other phone needs ${formatSize(v.neededBytes!)} free.',
      next: 'Free some space there, or send fewer files.',
      action: NextAction.sendAgain,
    ),
    ErrorCodes.receivingOff => const FailureMessage(
      title: 'The other phone is not receiving',
      reason: 'Receiving is turned off on it.',
      next:
          'Ask its owner to turn Receiving on, on the CrossDrop home '
          'screen, then send again.',
      action: NextAction.sendAgain,
    ),
    RejectReasons.senderBusy => const FailureMessage(
      title: 'Unfinished transfer',
      reason:
          'The other phone still has an unfinished transfer from this '
          'phone.',
      next:
          'Resume it from History, or wait until it expires, then send '
          'again.',
    ),
    _ => const FailureMessage(
      title: 'Declined',
      reason: 'The other phone declined the files. Nothing was sent.',
      next: 'Ask its owner to tap Accept if you send again.',
      action: NextAction.sendAgain,
    ),
  };
}

FailureMessage _cancelled(TransferView v) {
  final byOther = v.sending ? v.reason == 'receiver' : v.reason == 'sender';
  if (byOther) {
    return FailureMessage(
      title: 'Cancelled by ${v.peerName}',
      reason: v.sending
          ? 'The other phone stopped the transfer and deleted the '
                'unfinished files.'
          : 'The sender stopped the transfer. Unfinished files were '
                'deleted.',
      next: v.sending
          ? 'Send again if you still need to.'
          : 'Files that already arrived are kept.',
      action: v.sending ? NextAction.sendAgain : NextAction.none,
    );
  }
  return FailureMessage(
    title: 'Cancelled',
    reason: v.sending
        ? 'You stopped the transfer. The other phone deleted the '
              'unfinished files.'
        : 'You stopped the transfer. Unfinished files were deleted.',
    next: 'Files that already arrived are kept.',
  );
}

FailureMessage _receiveFailed(TransferView v) => switch (v.reason) {
  ErrorCodes.fileFailed || ErrorCodes.hashMismatch => FailureMessage(
    title: 'Nothing could be saved',
    reason:
        'Every file arrived damaged twice, so none was saved. Weak Wi-Fi '
        'can cause this.',
    next:
        'Ask ${v.peerName} to send again, closer to the router, or use '
        'hotspot mode.',
    action: NextAction.findHelp,
  ),
  expiredReason => FailureMessage(
    title: 'Transfer expired',
    reason:
        'It stayed unfinished for more than 24 hours, so the partial '
        'files were deleted.',
    next: 'Ask ${v.peerName} to send again.',
  ),
  _ => FailureMessage(
    title: 'Could not save the files',
    reason: 'This phone could not write the files.',
    next:
        'Check that this phone has free space, then ask ${v.peerName} to '
        'send again.',
  ),
};

/// A send that stopped with [reason] ([SendReasons], [ErrorCodes] or an
/// upload error code).
FailureMessage _sendFailed(
  String? reason,
  int? neededBytes,
) => switch (reason) {
  SendReasons.network || 'stalled' => const FailureMessage(
    title: 'Connection lost',
    reason: 'The phones could not reach each other for 2 minutes.',
    next:
        'Check that both phones are on the same Wi-Fi with CrossDrop '
        'open, then tap Resume. If it keeps failing, use hotspot mode.',
    action: NextAction.resume,
  ),
  ErrorCodes.noSpace => const FailureMessage(
    title: 'The other phone is full',
    reason:
        'It ran out of storage during the transfer. What arrived so far '
        'is kept.',
    next: 'Free some space on the other phone, then tap Resume.',
    action: NextAction.resume,
  ),
  SendReasons.version || ErrorCodes.unsupportedVersion => const FailureMessage(
    title: 'Update needed',
    reason:
        'The two phones run versions of CrossDrop that cannot talk '
        'to each other.',
    next: 'Update CrossDrop on the other phone, then send again.',
    action: NextAction.sendAgain,
  ),
  SendReasons.identityMismatch => const FailureMessage(
    title: 'A different phone answered',
    reason: 'Another device is now using that address.',
    next: 'Search again in the nearby list and pick the phone again.',
    action: NextAction.sendAgain,
  ),
  SendReasons.pinMismatch => const FailureMessage(
    title: 'Not the expected phone',
    reason:
        'Its security key is different from the one this phone knows, '
        'so nothing more was sent.',
    next:
        'Check that you picked the right phone. If CrossDrop was '
        'reinstalled on it, forget it in Settings > Trusted devices and '
        'pair again.',
  ),
  SendReasons.timeout => const FailureMessage(
    title: 'No answer',
    reason: 'The other phone did not answer the request.',
    next:
        'Make sure CrossDrop is open on the other phone, then send '
        'again.',
    action: NextAction.sendAgain,
  ),
  SendReasons.sourceUnreadable => const FailureMessage(
    title: 'A file could not be read',
    reason:
        'A file was moved, deleted or changed while sending, or the app '
        'that shared it no longer allows reading it.',
    next: 'Pick or share the files again, then send.',
    action: NextAction.sendAgain,
  ),
  SendReasons.sessionLost || ErrorCodes.sessionClosed => const FailureMessage(
    title: 'The other phone ended this transfer',
    reason: 'It no longer has this transfer.',
    next: 'Send the files again.',
    action: NextAction.sendAgain,
  ),
  ErrorCodes.rateLimited => const FailureMessage(
    title: 'Too many attempts',
    reason: 'The other phone is refusing new requests for a moment.',
    next: 'Wait a minute, then send again.',
    action: NextAction.sendAgain,
  ),
  ErrorCodes.busy => const FailureMessage(
    title: 'The other phone is busy',
    reason: 'It has too many transfers open.',
    next: 'Wait until they finish, then send again.',
    action: NextAction.sendAgain,
  ),
  ErrorCodes.fileFailed || ErrorCodes.hashMismatch => const FailureMessage(
    title: 'Files arrived damaged',
    reason:
        'Every file failed its integrity check twice, so none was '
        'saved. Weak Wi-Fi can cause this.',
    next: 'Send again closer to the router, or use hotspot mode.',
    action: NextAction.findHelp,
  ),
  ErrorCodes.authFailed => const FailureMessage(
    title: 'The phones could not verify each other',
    reason: 'The security check between the phones failed.',
    next:
        'Send again. If it keeps failing, restart CrossDrop on both '
        'phones.',
    action: NextAction.sendAgain,
  ),
  _ => FailureMessage(
    title: 'Transfer failed',
    reason:
        'Something unexpected happened'
        '${reason == null ? '' : ' ($reason)'}.',
    next:
        'Send again. If it keeps failing, restart CrossDrop on both '
        'phones.',
    action: NextAction.sendAgain,
  ),
};

/// Connecting from the Nearby screen failed with an [UploadException]
/// code.
FailureMessage describeConnectError(String code, {required bool fromQr}) =>
    switch (code) {
      'network' when fromQr => const FailureMessage(
        title: 'Could not connect',
        reason:
            'This Wi-Fi may block phone-to-phone traffic (common on guest '
            'and public Wi-Fi), or a VPN is on.',
        next: 'Pause any VPN, or use hotspot mode.',
        action: NextAction.findHelp,
      ),
      'network' => const FailureMessage(
        title: 'Could not reach that phone',
        reason: 'It did not answer.',
        next:
            'Check that CrossDrop is open on it and both phones are on the '
            'same Wi-Fi. Or scan its QR code.',
        action: NextAction.scanQr,
      ),
      'pin_mismatch' when fromQr => const FailureMessage(
        title: "This isn't the device you scanned",
        reason: 'Its security key is different. Nothing was sent.',
        next: 'Scan the code on the other phone again.',
        action: NextAction.scanQr,
      ),
      'pin_mismatch' => const FailureMessage(
        title: 'Not the expected phone',
        reason: 'Its security key is different. Nothing was sent.',
        next: 'Check that you picked the right phone.',
      ),
      'identity_mismatch' when fromQr => const FailureMessage(
        title: "This isn't the device you scanned",
        reason: 'A different device answered at that address.',
        next: 'Scan the code on the other phone again.',
        action: NextAction.scanQr,
      ),
      'identity_mismatch' => const FailureMessage(
        title: 'A different phone answered',
        reason: 'The list was out of date.',
        next: 'Pull down to refresh the list.',
      ),
      'version' => const FailureMessage(
        title: 'Update needed',
        reason:
            'The other phone runs a version of CrossDrop this one cannot '
            'talk to.',
        next: 'Update CrossDrop on the other phone.',
      ),
      _ => const FailureMessage(
        title: 'Could not connect',
        reason: 'The other phone gave an unexpected answer.',
        next: 'Try again, or scan its QR code.',
        action: NextAction.scanQr,
      ),
    };

/// Why one file failed, in a few words.
String describeFileError(String? code) => switch (code) {
  ErrorCodes.hashMismatch ||
  ErrorCodes.fileFailed => 'arrived damaged twice, not saved',
  ErrorCodes.tooManyBytes => 'bigger than announced, not saved',
  ErrorCodes.ioError || ErrorCodes.noSpace => 'could not be written',
  SendReasons.sourceUnreadable => 'could not be read',
  _ => 'not saved',
};
