import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A screen that counts how many times it is created.
int _created = 0;

ValueNotifier<int>? _writeFromInit;
bool _deferWrite = false;

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _created++;
    final n = _writeFromInit;
    if (n != null) {
      if (_deferWrite) {
        WidgetsBinding.instance.addPostFrameCallback((_) => n.value++);
      } else {
        n.value++; // a settings write straight from initState
      }
    }
  }

  @override
  Widget build(BuildContext context) => const Text('probe');
}

Future<GoRouter> _pump(WidgetTester tester, Listenable refresh) async {
  _created = 0;
  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) => null,
    routes: [
      GoRoute(path: '/', builder: (c, s) => const Text('home')),
      GoRoute(
        path: '/editor',
        builder: (c, s) => const _Probe(),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  router.push('/editor', extra: 'x');
  await tester.pumpAndSettle();
  return router;
}

void main() {
  tearDown(() {
    _writeFromInit = null;
    _deferWrite = false;
  });

  testWidgets('a settings write deferred from initState builds the screen once',
      (tester) async {
    final settings = ValueNotifier<int>(0);
    _writeFromInit = settings;
    _deferWrite = true;
    await _pump(tester, settings);
    expect(_created, 1, reason: 'DEFERRED created=$_created');
  });

  testWidgets('a settings change while a pushed screen is open keeps it',
      (tester) async {
    final settings = ValueNotifier<int>(0);
    await _pump(tester, settings);
    final before = _created;
    settings.value = 1; // e.g. setHdRemovedByUser
    await tester.pumpAndSettle();
    expect(_created, before);
  });
}
