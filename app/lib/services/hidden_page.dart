import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// A cinema's website open in a web view nobody sees, for reading showtimes
/// the way a visitor's browser would (premiere_live.dart, vox_live.dart).
/// Phones only. Calls run one at a time, since a page script may click.
class HiddenPage {
  HiddenPage._(this._view, this._controller);

  static bool get available =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  final HeadlessInAppWebView _view;
  final InAppWebViewController _controller;
  Future<void> _turn = Future.value();

  /// Loads [url], with [script] run at the start of every page load.
  static Future<HiddenPage> open(String url, {String? script}) async {
    InAppWebViewController? controller;
    final loaded = Completer<void>();
    final view = HeadlessInAppWebView(
      // Wide enough for the sites' desktop layouts, which the scripts read.
      initialSize: const Size(1280, 900),
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialUserScripts: UnmodifiableListView([
        if (script != null)
          UserScript(
            source: script,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
      ]),
      initialSettings: InAppWebViewSettings(
        // Text and scripts are all a reader needs.
        blockNetworkImage: true,
        mediaPlaybackRequiresUserGesture: true,
      ),
      onWebViewCreated: (c) => controller = c,
      onLoadStop: (_, _) {
        if (!loaded.isCompleted) loaded.complete();
      },
    );
    await view.run();
    try {
      await loaded.future.timeout(const Duration(seconds: 45));
    } catch (_) {
      await view.dispose();
      rethrow;
    }
    return HiddenPage._(view, controller!);
  }

  /// Runs [body] (an async function body) in the page; its `return` value
  /// comes back. [args] are its variables.
  Future<Object?> call(
    String body, {
    Map<String, dynamic> args = const {},
    Duration timeout = const Duration(minutes: 2),
  }) {
    final run = _turn.then((_) async {
      final result = await _controller
          .callAsyncJavaScript(functionBody: body, arguments: args)
          .timeout(timeout);
      if (result?.error != null) throw Exception(result!.error);
      return result?.value;
    });
    _turn = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Lets the page send messages: `window.flutter_inappwebview.callHandler(name, …)`.
  void listen(String name, void Function(List<dynamic> args) handler) =>
      _controller.addJavaScriptHandler(handlerName: name, callback: handler);

  void stopListening(String name) =>
      _controller.removeJavaScriptHandler(handlerName: name);

  Future<void> close() => _view.dispose();
}
