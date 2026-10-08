import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/models/live_session.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/state/fit_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    fit.saveAndExit();
    fit.sessions.clear();
  });

  tearDown(() {
    fit.saveAndExit();
    fit.sessions.clear();
  });

  void startAndLog() {
    fit.startWorkout();
    fit.toggleMuscle('chest');
    fit.trainContinue();
    fit.startSession();
    fit.setSessionReps(0, 0, 8);
    fit.setSessionWeight(0, 0, 72.5);
    fit.toggleSet(0, 0);
    fit.nextExercise();
  }

  void killAndReopen() {
    fit.persistNow();
    fit.session = null;
    fit.route = 'home';
    fit.loadFromStore();
  }

  test('a workout in progress survives the app being killed', () {
    startAndLog();
    killAndReopen();

    expect(fit.session, isNotNull, reason: 'el entreno no puede evaporarse');
    expect(fit.route, 'session', reason: 'vuelves justo donde estabas');
    expect(fit.session!.currentIndex, 1, reason: 'y en el ejercicio en el que ibas');

    final firstSet = fit.session!.exercises[0].sets[0];
    expect(firstSet.reps, 8);
    expect(firstSet.weight, 72.5);
    expect(firstSet.done, true, reason: 'la serie marcada sigue marcada');
  });

  test('you can jump directly to any exercise without completing the previous one', () {
    startAndLog();
    final target = fit.session!.exercises.length - 1;

    fit.goToSessionExercise(target);

    expect(fit.session!.currentIndex, target);
    expect(fit.session!.exercises[1].sets.every((set) => !set.done), true,
        reason: 'cambiar de máquina no marca el ejercicio intermedio como terminado');
  });

  test('the clock keeps counting real time while the app is dead', () {
    startAndLog();

    fit.persistNow();
    final raw = Store.instance.load();
    raw['liveStart'] = DateTime.now().subtract(const Duration(minutes: 10)).toIso8601String();
    Store.instance.save(raw);

    fit.session = null;
    fit.loadFromStore();

    expect(fit.sessionElapsed, greaterThanOrEqualTo(600),
        reason: 'los 10 minutos pasaron aunque la app estuviera muerta');
    expect(fit.sessionPaused, false);
  });

  test('a paused workout comes back paused, not silently running', () {
    startAndLog();
    fit.toggleSessionPause();
    final frozen = fit.sessionElapsed;

    killAndReopen();

    expect(fit.sessionPaused, true);
    expect(fit.sessionElapsed, frozen, reason: 'en pausa el reloj no corre ni estando muerta');
  });

  test('a rest still running comes back with the time it really has left', () {
    startAndLog();
    fit.startRest();
    final left = fit.session!.restRemaining!;

    killAndReopen();

    expect(fit.session!.restRemaining, isNotNull,
        reason: 'la alarma sigue programada, así que la cuenta tiene que seguir en pantalla');
    expect(fit.session!.restRemaining, lessThanOrEqualTo(left),
        reason: 'el descanso cuenta por reloj, no se reinicia');
  });

  test('a rest whose time already passed is not resurrected', () {
    startAndLog();
    fit.startRest();
    fit.session!.restEndsAt = DateTime.now().subtract(const Duration(seconds: 1));

    killAndReopen();
    expect(fit.session!.restRemaining, isNull);
  });

  test('finishing clears the rescue copy so it does not reappear', () {
    startAndLog();
    fit.finishSession();
    fit.saveAndExit();

    expect(Store.instance.load().containsKey('live'), false);
    fit.loadFromStore();
    expect(fit.session, isNull);
    expect(fit.route, 'home');
  });

  test('discarding a workout leaves nothing to come back to', () {
    startAndLog();
    fit.discardSession();
    expect(Store.instance.load().containsKey('live'), false);
    fit.loadFromStore();
    expect(fit.session, isNull);
  });

  test('a finished-but-unsaved summary is not treated as live', () {
    startAndLog();
    fit.finishSession();
    fit.persistNow();
    expect(Store.instance.load().containsKey('live'), false,
        reason: 'la sesión completa ya está en el historial');
  });

  test('a timed set has one active interval and finishes with timestamps', () {
    fit.startWorkout();
    fit.toggleMuscle('chest');
    fit.trainContinue();
    fit.startSession();

    expect(fit.startSessionSet(0, 0), true);
    final first = fit.session!.exercises[0].sets[0];
    expect(first.status, SessionSetStatus.active);
    expect(first.startedAt, isNotNull);
    expect(fit.startSessionSet(0, 1), false,
        reason: 'dos series no pueden compartir el mismo intervalo activo');

    fit.finishSessionSet(0, 0);
    expect(first.status, SessionSetStatus.completed);
    expect(first.completedAt, isNotNull);
    expect(first.durationSec, isNotNull);
    expect(fit.activeSetLocation, isNull);
  });

  test('a set can be removed while the workout is in progress', () {
    fit.startWorkout();
    fit.toggleMuscle('chest');
    fit.trainContinue();
    fit.startSession();
    final original = fit.session!.exercises[0].sets.length;

    fit.removeSessionSet(0, original - 1);

    expect(fit.session!.exercises[0].sets.length, original - 1);
  });

  test('removing the active set clears the active-set lock', () {
    fit.startWorkout();
    fit.toggleMuscle('chest');
    fit.trainContinue();
    fit.startSession();

    expect(fit.startSessionSet(0, 0), true);
    fit.removeSessionSet(0, 0);

    expect(fit.activeSetLocation, isNull);
    expect(fit.startSessionSet(0, 0), true,
        reason: 'la serie siguiente debe poder iniciarse inmediatamente');
  });

  test('old live JSON remains readable and receives stable ids', () {
    final old = WorkoutSession.fromJson({
      'ex': [
        {
          'id': 'bench',
          'n': 'Bench press',
          'p': 'chest',
          's': [
            {'r': 8, 'w': 40, 'd': true}
          ]
        }
      ],
      'i': 0,
      'c': false,
    });

    expect(old.id, isNotEmpty);
    expect(old.exercises.single.sets.single.id, isNotEmpty);
    expect(old.exercises.single.sets.single.status, SessionSetStatus.completed);
  });
}
