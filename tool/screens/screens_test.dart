// Renders the main screens to PNG with the real fonts, for design review.
//   flutter test tool/screens --update-goldens   →  tool/screens/out/*.png
import 'dart:convert';
import 'dart:io';

import 'package:easynote/app/controller.dart';
import 'package:easynote/store/local_store.dart';
import 'package:easynote/sync/fake_remote.dart';
import 'package:easynote/ui/editor/editor_page.dart';
import 'package:easynote/ui/home_page.dart';
import 'package:easynote/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const sample = {
  'inbox.md': '# Inbox\n- ask about the mock catalogue release\n- [ ] book the room for Thursday\n',
  'reading.md': '# Reading list\n- [x] Kaiser 1987\n- [ ] Hamilton 1998 review\n- [ ] Percival & White 2009\n',
  'lya/p1d.md': '# P1D systematics\n- resolution correction vs. redshift\n  - check the window at high k\n- [ ] continuum fitting bias\n- [x] noise power from pipeline\n- [ ] DLA masking threshold\n',
  'lya/metals.md': '# Metal contamination\n- SiIII cross-term near 2.3\n- [ ] fit with free amplitude\n',
  'lya/tomo/maps.md': '# Tomographic maps\n- Wiener filter, σ_g dependence\n- void finder on the reconstructed field\n- compare spherical and watershed voids\n',
  'lya/tomo/voids.md': '# Void profiles\n- stacked profile vs. radius\n- [ ] RSD around voids\n',
  'flip/growth.md': '# Growth rate ideas\n- fσ8 from velocities at z < 0.1\n- [ ] joint density + velocity fit\n- [ ] non-linear damping σ_u prior\n- field-level likelihood speedups\n  - matrix-free solve\n  - stochastic trace\n',
  'flip/sn.md': '# Supernova velocities\n- host mass step and velocity bias\n- [x] Malmquist bias test\n',
  'teaching.md': '# Teaching\n- statistics course, chapter on MCMC\n- [ ] exercises on Fisher matrices\n',
};

Future<void> loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(File(f).readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
    await loader.load();
  }

  var root = File(Platform.resolvedExecutable).parent;
  while (!Directory('${root.path}/artifacts/material_fonts').existsSync()) {
    root = root.parent;
  }
  await load('MaterialIcons', ['${root.path}/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  await load('Literata', ['assets/fonts/Literata.ttf']);
  await load('Atkinson', ['assets/fonts/AtkinsonHyperlegible-Regular.ttf', 'assets/fonts/AtkinsonHyperlegible-Bold.ttf']);
}

void main() {
  late AppController c;
  late Directory tmp;

  setUpAll(() async {
    await loadFonts();
  });

  Future<void> seed() async {
    tmp = Directory.systemTemp.createTempSync('easynote_screens_');
    final remote = FakeRemote({for (final e in sample.entries) e.key: utf8.encode(e.value)});
    final store = await LocalStore.open(Directory('${tmp.path}/n'), File('${tmp.path}/s.json'));
    c = AppController(store: store, remoteFactory: () => remote, device: 'laptop');
    await c.sync();
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 40; i++) {
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 10)));
      await t.pump();
    }
  }

  Future<void> shot(WidgetTester t, String name, Size size, Palette p, Brightness b, Widget Function() home) async {
    await t.runAsync(seed);
    t.view.physicalSize = size * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(p, b),
      home: home(),
    ));
    await settle(t);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));
    tmp.deleteSync(recursive: true);
  }

  const desk = Size(1280, 820), phone = Size(412, 900);

  for (final (name, p, b) in [
    ('light', Palette.light, Brightness.light),
    ('dark', Palette.dark, Brightness.dark),
    ('eink', Palette.eink, Brightness.light),
  ]) {
    testWidgets('desktop home $name', (t) async {
      await shot(t, 'desktop-home-$name', desk, p, b, () {
        c.folder = 'lya';
        return HomePage(controller: c, onSettings: () {});
      });
    });
  }

  testWidgets('desktop editor', (t) async {
    await shot(t, 'desktop-editor-light', desk, Palette.light, Brightness.light,
        () => EditorPage(controller: c, path: 'flip/growth.md', folder: 'flip', onSettings: () {}));
  });

  testWidgets('desktop top level', (t) async {
    await shot(t, 'desktop-top-light', desk, Palette.light, Brightness.light,
        () => HomePage(controller: c, onSettings: () {}));
  });

  testWidgets('phone home', (t) async {
    await shot(t, 'phone-home-light', phone, Palette.light, Brightness.light,
        () => HomePage(controller: c, onSettings: () {}));
  });

  testWidgets('phone editor', (t) async {
    await shot(t, 'phone-editor-light', phone, Palette.light, Brightness.light,
        () => EditorPage(controller: c, path: 'lya/p1d.md', folder: 'lya', onSettings: () {}));
  });

  testWidgets('phone home eink', (t) async {
    await shot(t, 'phone-home-eink', phone, Palette.eink, Brightness.light,
        () => HomePage(controller: c, onSettings: () {}));
  });
}
