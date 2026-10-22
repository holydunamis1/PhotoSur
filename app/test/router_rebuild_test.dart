import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A screen that counts how many times it is created.
int _created = 0;

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
  testWidgets('EXPLORE: a settings change while a pushed screen is open',
      (tester) async {
    final settings = ValueNotifier<int>(0);
    await _pump(tester, settings);
    final before = _created;
    settings.value = 1; // e.g. markHdAutoDownloadTried
    await tester.pumpAndSettle();
    // ignore: avoid_print
    print('ROUTERPROBE created before=$before after-settings-change=$_created');
  });
}
