import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shebbak/data/prefs.dart';
import 'package:shebbak/services/follow_film.dart';
import 'package:shebbak/services/push.dart';
import 'package:shebbak/util/i18n.dart';

class _Alerts implements FilmAlerts {
  @override
  bool supported = true;
  FollowAlertResult result = FollowAlertResult.enabled;
  Completer<FollowAlertResult>? pending;
  int enables = 0;
  int syncs = 0;
  bool syncResult = true;
  @override
  Future<FollowAlertResult> enableForFollow() async {
    enables++;
    return pending?.future ?? result;
  }

  @override
  Future<bool> syncPreferences() async {
    syncs++;
    return syncResult;
  }
}

Future<void> _mount(WidgetTester tester, Prefs prefs, _Alerts alerts) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FilmFollowAction(
            prefs: prefs,
            movieId: 'film',
            alerts: alerts,
            builder: (onPressed, busy) => FilledButton(
              onPressed: onPressed,
              child: Text(busy ? 'Working' : 'Follow'),
            ),
          ),
        ),
      ),
    );

void main() {
  setUp(() => Lang.english = true);
  tearDown(() => Lang.english = false);

  testWidgets('double tap cannot undo following while permission is pending', (
    tester,
  ) async {
    final prefs = Prefs.memory();
    final alerts = _Alerts()..pending = Completer();
    await _mount(tester, prefs, alerts);
    await tester.tap(find.text('Follow'));
    await tester.tap(find.text('Follow'));
    await tester.pump();
    expect(prefs.isFollowing('film'), isTrue);
    expect(alerts.enables, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    alerts.pending!.complete(FollowAlertResult.enabled);
    await tester.pumpAndSettle();
    expect(find.textContaining('selected cinemas'), findsOneWidget);
  });

  testWidgets('denied permission keeps the follow and offers phone settings', (
    tester,
  ) async {
    final prefs = Prefs.memory();
    await _mount(tester, prefs, _Alerts()..result = FollowAlertResult.denied);
    await tester.tap(find.text('Follow'));
    await tester.pumpAndSettle();
    expect(prefs.isFollowing('film'), isTrue);
    expect(find.textContaining('permission is off'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets(
    'registration failure retries without unfollowing or claiming success',
    (tester) async {
      final prefs = Prefs.memory();
      final alerts = _Alerts()..result = FollowAlertResult.failed;
      await _mount(tester, prefs, alerts);
      await tester.tap(find.text('Follow'));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be activated'), findsOneWidget);
      expect(find.textContaining('You’ll get an alert'), findsNothing);
      alerts.result = FollowAlertResult.enabled;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(alerts.enables, 2);
      expect(prefs.isFollowing('film'), isTrue);
      expect(find.text('Film alerts enabled'), findsOneWidget);
    },
  );

  testWidgets('unfollow syncs immediately without requesting permission', (
    tester,
  ) async {
    final prefs = Prefs.memory(following: {'film'});
    final alerts = _Alerts();
    await _mount(tester, prefs, alerts);
    await tester.tap(find.text('Follow'));
    await tester.pumpAndSettle();
    expect(prefs.isFollowing('film'), isFalse);
    expect(alerts.syncs, 1);
    expect(alerts.enables, 0);
  });

  testWidgets('no cinema selection accurately describes all-cinema alerts', (
    tester,
  ) async {
    await _mount(tester, Prefs.memory(cinemas: {}), _Alerts());
    await tester.tap(find.text('Follow'));
    await tester.pumpAndSettle();
    expect(find.textContaining('any cinema'), findsOneWidget);
  });

  testWidgets('failed unfollow sync retries without following the film again', (
    tester,
  ) async {
    final prefs = Prefs.memory(following: {'film'});
    final alerts = _Alerts()..syncResult = false;
    await _mount(tester, prefs, alerts);
    await tester.tap(find.text('Follow'));
    await tester.pumpAndSettle();
    expect(find.textContaining('syncing failed'), findsOneWidget);
    alerts.syncResult = true;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(prefs.isFollowing('film'), isFalse);
    expect(alerts.syncs, 2);
    expect(alerts.enables, 0);
  });

  testWidgets(
    'unsupported platforms retain follows without promising notifications',
    (tester) async {
      final prefs = Prefs.memory();
      final alerts = _Alerts()..supported = false;
      await _mount(tester, prefs, alerts);
      await tester.tap(find.text('Follow'));
      await tester.pumpAndSettle();
      expect(prefs.isFollowing('film'), isTrue);
      expect(alerts.enables, 0);
      expect(
        find.textContaining('unavailable on this platform'),
        findsOneWidget,
      );
    },
  );
}
