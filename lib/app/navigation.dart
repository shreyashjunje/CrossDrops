import 'package:flutter/material.dart';

/// The app's navigator and snack bars, for events that start outside any
/// screen (an incoming offer, a share from another app).
final navigatorKey = GlobalKey<NavigatorState>();
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Route names (docs/features/ui-navigation.md). Used so a share or an
/// offer does not open a screen that is already on top.
abstract final class Routes {
  static const nearby = 'nearby';
  static const send = 'send';
  static const incoming = 'incoming';
  static const transfer = 'transfer';
  static const myQr = 'my-qr';
  static const history = 'history';
  static const settings = 'settings';
  static const findHelp = 'find-help';
  static const hotspot = 'hotspot';
}

/// Tracks the names of the routes on the stack.
class TopRouteObserver extends NavigatorObserver {
  final List<String?> _stack = [];

  String? get top => _stack.isEmpty ? null : _stack.last;

  bool contains(String name) => _stack.contains(name);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _stack.add(route.settings.name);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_stack.isNotEmpty) _stack.removeLast();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final i = _stack.lastIndexOf(route.settings.name);
    if (i >= 0) _stack.removeAt(i);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (_stack.isNotEmpty) _stack.removeLast();
    _stack.add(newRoute?.settings.name);
  }
}

final topRouteObserver = TopRouteObserver();

/// Pushes [screen] as a named route.
Future<T?> pushScreen<T>(BuildContext context, String name, Widget screen) =>
    Navigator.of(context).push<T>(
      MaterialPageRoute<T>(
        settings: RouteSettings(name: name),
        builder: (_) => screen,
      ),
    );
