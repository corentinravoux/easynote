import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:home_widget/home_widget.dart';

import '../app/controller.dart';

/// Feeds the Android home-screen widget and reports taps on it.
///
/// The widget makes no network calls: it shows the snapshot the app last
/// wrote here, after every save or sync.
class WidgetBridge {
  static const _receiver = 'io.easynote.app.RecentNotesWidgetReceiver';
  static bool get supported => Platform.isAndroid;

  String? _last;

  Future<void> update(List<NoteSummary> recent) async {
    if (!supported) return;
    final data = jsonEncode([
      for (final n in recent.take(10))
        {
          'path': n.path,
          'title': n.title,
          'preview': n.preview.take(2).join('\n'),
        },
    ]);
    if (data == _last) return;
    _last = data;
    await HomeWidget.saveWidgetData<String>('recent', data);
    await HomeWidget.updateWidget(qualifiedAndroidName: _receiver);
  }

  /// URIs the app was opened with from the widget: `easynote://open?path=…`
  /// or `easynote://new`.
  Stream<Uri> launches() async* {
    if (!supported) return;
    final first = await HomeWidget.initiallyLaunchedFromHomeWidget();
    if (first != null) yield first;
    await for (final u in HomeWidget.widgetClicked) {
      if (u != null) yield u;
    }
  }
}
