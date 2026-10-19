import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easynote/app/controller.dart';
import 'package:easynote/store/local_store.dart';
import 'package:easynote/sync/fake_remote.dart';
import 'package:easynote/sync/remote_repo.dart';
import 'package:easynote/ui/editor/editor_page.dart';
import 'package:easynote/ui/editor/item_row.dart';
import 'package:easynote/ui/home_page.dart';
import 'package:easynote/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late FakeRemote remote;
  late AppController c;

  Future<void> setUpController() async {
    tmp = Directory.systemTemp.createTempSync('easynote_ui_');
    remote = FakeRemote({
      'lya/p1d.md': utf8.encode('# P1D\n- [ ] window\n- [x] noise\n'),
      'lya/tomo/maps.md': utf8.encode('# Maps\n- Wiener filter\n'),
      'inbox.md': utf8.encode('# Inbox\n- call\n'),
    });
    final store = await LocalStore.open(Directory('${tmp.path}/n'), File('${tmp.path}/s.json'));
    c = AppController(store: store, remoteFactory: () => remote, device: 'laptop');
    await c.sync();
  }

  tearDown(() => tmp.deleteSync(recursive: true));

  // File IO is real: let it run and pump the tree until [ok] holds. Waits
  // on the condition, not a fixed number of cycles, so slow CI machines pass.
  Future<void> waitFor(WidgetTester t, FutureOr<bool> Function() ok, String what) async {
    for (var i = 0; i < 500; i++) {
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
      await t.pump();
      if (await t.runAsync(() async => await ok()) == true) return;
    }
    fail('timed out waiting for $what');
  }

  Future<String?> disk(String path) => c.store.readNote(path);
  String? pushed(String path) =>
      remote.files()[path] == null ? null : utf8.decode(remote.files()[path]!);
  bool editorLoaded() => find.byType(ItemRow).evaluate().isNotEmpty;

  Widget app(Widget home) => MaterialApp(theme: buildTheme(Palette.light, Brightness.light), home: home);

  Future<void> sized(WidgetTester t, double w, double h) async {
    t.view.physicalSize = Size(w, h);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  testWidgets('wide: tree selects a folder and the grid shows its notes', (t) async {
    await t.runAsync(setUpController);
    await sized(t, 1200, 800);
    await t.pumpWidget(app(HomePage(controller: c, onSettings: () {})));
    expect(find.text('Inbox'), findsOneWidget);
    await t.tap(find.text('lya').first);
    await t.pump();
    expect(find.text('P1D'), findsOneWidget);
    expect(find.text('1 of 2 done'), findsOneWidget);
    expect(find.text('Inbox'), findsNothing);
  });

  testWidgets('search filters across folders', (t) async {
    await t.runAsync(setUpController);
    await sized(t, 1200, 800);
    await t.pumpWidget(app(HomePage(controller: c, onSettings: () {})));
    await t.enterText(find.byType(TextField).first, 'wiener');
    await t.pump();
    expect(find.text('Maps'), findsOneWidget);
    expect(find.text('Inbox'), findsNothing);
  });

  testWidgets('narrow: breadcrumbs and FAB, no tree', (t) async {
    await t.runAsync(setUpController);
    await sized(t, 400, 800);
    await t.pumpWidget(app(HomePage(controller: c, onSettings: () {})));
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Folders'), findsNothing);
    await t.tap(find.text('lya'));
    await t.pump();
    expect(find.text('Notes'), findsOneWidget); // breadcrumb back to the top
    expect(find.text('P1D'), findsOneWidget);
  });

  testWidgets('sync badge shows pending when the remote is unreachable', (t) async {
    await t.runAsync(setUpController);
    await sized(t, 1200, 800);
    await t.pumpWidget(app(HomePage(controller: c, onSettings: () {})));
    await t.runAsync(() async {
      remote.failNext = const RemoteException('offline', offline: true);
      await c.store.writeNote('inbox.md', '# Inbox\n- changed\n');
      await c.sync();
    });
    await t.pump();
    expect(find.text('Offline, 1 unsynced'), findsOneWidget);
  });

  testWidgets('editor: typing then Esc saves the note and pushes it', (t) async {
    await t.runAsync(setUpController);
    await sized(t, 1200, 800);
    await t.pumpWidget(app(Builder(
      builder: (ctx) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
            builder: (_) => EditorPage(controller: c, path: 'inbox.md', folder: '', onSettings: () {}),
          )),
          child: const Text('open'),
        ),
      ),
    )));
    await t.tap(find.text('open'));
    await waitFor(t, editorLoaded, 'the editor to load');
    final row = find.byType(ItemRow).first;
    await t.enterText(find.descendant(of: row, matching: find.byType(TextField)), 'call Bob');
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await waitFor(t, () => pushed('inbox.md') == '# Inbox\n- call Bob\n', 'the push');
    await t.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(await t.runAsync(() => disk('inbox.md')), '# Inbox\n- call Bob\n');
  });

  testWidgets('editor: Ctrl+Enter turns a bullet into a checkbox', (t) async {
    await t.runAsync(setUpController);
    await sized(t, 1200, 800);
    await t.pumpWidget(app(EditorPage(controller: c, path: 'inbox.md', folder: '', onSettings: () {})));
    await waitFor(t, editorLoaded, 'the editor to load');
    await t.tap(find.descendant(of: find.byType(ItemRow).first, matching: find.byType(TextField)));
    await t.pump();
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    expect(find.byType(InkBox), findsOneWidget);
  });

  testWidgets('editor: text is on disk after one second without closing', (t) async {
    await t.runAsync(setUpController);
    await sized(t, 1200, 800);
    await t.pumpWidget(app(EditorPage(controller: c, path: 'inbox.md', folder: '', onSettings: () {})));
    await waitFor(t, editorLoaded, 'the editor to load');
    await t.enterText(find.descendant(of: find.byType(ItemRow).first, matching: find.byType(TextField)), 'draft');
    await t.pump(const Duration(milliseconds: 1100));
    await waitFor(t, () async => await disk('inbox.md') == '# Inbox\n- draft\n', 'the autosave');
    expect(utf8.decode(remote.files()['inbox.md']!), '# Inbox\n- call\n'); // not pushed yet
  });
}
