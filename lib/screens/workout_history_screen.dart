import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../l10n/l10n.dart';
import '../models/history_metrics.dart';
import '../models/workout.dart';
import '../services/health_store.dart';
import '../state/fit_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/ui_kit.dart';
import 'start_sheet.dart';

typedef LoggedExerciseEditor =
    void Function(BuildContext context, LoggedSession session, LoggedExercise exercise);

class WorkoutHistoryScreen extends StatelessWidget {
  const WorkoutHistoryScreen({super.key, required this.date, required this.onEdit});

  final DateTime date;
  final LoggedExerciseEditor onEdit;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return Scaffold(
      backgroundColor: gc.pageBg,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: fit,
          builder: (context, _) {
            final sessions = fit.sessionsOn(date);
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _header(context, gc)),
                if (sessions.isEmpty)
                  SliverFillRemaining(hasScrollBody: false, child: _empty(context, gc))
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
                    sliver: SliverList.list(
                      children: [
                        for (var i = 0; i < sessions.length; i++) ...[
                          _session(context, gc, sessions[i]),
                          if (i < sessions.length - 1) const SizedBox(height: 18),
                        ],
                        if (!fit.isSessionActive && !_isFuture) ...[
                          const SizedBox(height: 18),
                          GhostButton(
                            label: t.logWorkoutAction,
                            icon: PhosphorIconsRegular.plus,
                            onTap: () {
                              Navigator.of(context).pop();
                              showStartSheet(context, day: date);
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context, GymColors gc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: gc.bgRaised, shape: BoxShape.circle),
              child: Icon(PhosphorIconsRegular.caretLeft, size: 18, color: gc.text),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.history,
                  style: AppTheme.f(10, weight: FontWeight.w700, color: gc.textTertiary, letterSpacing: 1.4),
                ),
                const SizedBox(height: 3),
                Text(
                  t.longDate(date),
                  style: AppTheme.f(23, weight: FontWeight.w800, color: gc.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, GymColors gc) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(PhosphorIconsRegular.clockCounterClockwise, size: 42, color: gc.textTertiary),
          const SizedBox(height: 14),
          Text(
            t.restDay,
            textAlign: TextAlign.center,
            style: AppTheme.f(14, color: gc.textSecondary),
          ),
          if (!fit.isSessionActive && !_isFuture) ...[
            const SizedBox(height: 20),
            GhostButton(
              label: t.logWorkoutAction,
              icon: PhosphorIconsRegular.plus,
              onTap: () {
                Navigator.of(context).pop();
                showStartSheet(context, day: date);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _session(BuildContext context, GymColors gc, LoggedSession session) {
    return FutureBuilder<SessionHistoryMetrics>(
      future: HealthStore.instance.historyMetricsForSession(session),
      builder: (context, snapshot) {
        final metrics = snapshot.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sessionHero(context, gc, session, metrics),
            const SizedBox(height: 12),
            for (var i = 0; i < session.exercises.length; i++) ...[
              _exerciseCard(
                context,
                gc,
                session,
                session.exercises[i],
                metrics?.exercises[session.exercises[i].id],
              ),
              if (i < session.exercises.length - 1) const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }

  Widget _sessionHero(
    BuildContext context,
    GymColors gc,
    LoggedSession session,
    SessionHistoryMetrics? metrics,
  ) {
    final kcal = metrics?.estimatedKcal;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: gc.bgRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: gc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${session.exercises.length} ${t.exercisesCaps.toLowerCase()} · ${t.setCount(session.setCount)}',
                  style: AppTheme.f(12, weight: FontWeight.w600, color: gc.textSecondary),
                ),
              ),
              if (!fit.isSessionActive)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _confirmResume(context, session),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(color: gc.emberSoft, borderRadius: BorderRadius.circular(100)),
                    child: Row(
                      children: [
                        Icon(PhosphorIconsFill.play, size: 11, color: gc.ember),
                        const SizedBox(width: 6),
                        Text(
                          t.continueWorkout,
                          style: AppTheme.f(10, weight: FontWeight.w700, color: gc.ember),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _heroValue(gc, t.duration, _time(session.durationSec), PhosphorIconsRegular.timer),
              ),
              Expanded(
                child: _heroValue(
                  gc,
                  t.volume,
                  fit.volumeLabel(session.volume),
                  PhosphorIconsRegular.barbell,
                ),
              ),
              Expanded(
                child: _heroValue(
                  gc,
                  'KCAL',
                  kcal == null ? '—' : '≈${kcal.round()}',
                  PhosphorIconsFill.fire,
                  accent: kcal != null,
                ),
              ),
            ],
          ),
          if (metrics != null && (metrics.averageHeartRate != null || metrics.activeSeconds > 0)) ...[
            const SizedBox(height: 16),
            Container(height: 1, color: gc.border),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _smallMetric(
                    gc,
                    t.averageHeartRate,
                    metrics.averageHeartRate == null ? '—' : '${metrics.averageHeartRate!.round()} bpm',
                  ),
                ),
                Expanded(
                  child: _smallMetric(
                    gc,
                    t.maxHeartRate,
                    metrics.maxHeartRate == null ? '—' : '${metrics.maxHeartRate!.round()} bpm',
                  ),
                ),
                Expanded(
                  child: _smallMetric(
                    gc,
                    t.workRest,
                    '${_time(metrics.activeSeconds)} / ${_time(metrics.restSeconds)}',
                  ),
                ),
              ],
            ),
            if (metrics.sensorCoverage > 0) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 5,
                  value: metrics.sensorCoverage,
                  backgroundColor: gc.bgRaised2,
                  valueColor: AlwaysStoppedAnimation(gc.brass),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${t.sensorCoverage} ${(metrics.sensorCoverage * 100).round()}%',
                style: AppTheme.f(9.5, weight: FontWeight.w600, color: gc.textTertiary, letterSpacing: 0.5),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _heroValue(GymColors gc, String label, String value, IconData icon, {bool accent = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: accent ? gc.brass : gc.textTertiary),
        const SizedBox(height: 7),
        Text(
          value,
          maxLines: 1,
          style: AppTheme.f(19, weight: FontWeight.w800, color: accent ? gc.brass : gc.text),
        ),
        const SizedBox(height: 3),
        Text(
          label.toUpperCase(),
          maxLines: 1,
          style: AppTheme.f(9, weight: FontWeight.w700, color: gc.textTertiary, letterSpacing: 0.8),
        ),
      ],
    );
  }

  Widget _smallMetric(GymColors gc, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          style: AppTheme.f(12.5, weight: FontWeight.w700, color: gc.text),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.f(8.5, weight: FontWeight.w600, color: gc.textTertiary, letterSpacing: 0.5),
        ),
      ],
    );
  }

  Widget _exerciseCard(
    BuildContext context,
    GymColors gc,
    LoggedSession session,
    LoggedExercise exercise,
    ExerciseHistoryMetrics? metrics,
  ) {
    final work = metrics?.activeSeconds ?? 0;
    final rest = metrics?.restSeconds ?? 0;
    final total = work + rest;
    final workRatio = total <= 0 ? 0.0 : work / total;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showExerciseDetails(context, session, exercise, metrics),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: gc.bgRaised, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: gc.bgRaised2, borderRadius: BorderRadius.circular(13)),
                  child: Icon(PhosphorIconsRegular.barbell, size: 18, color: gc.brass),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.catalogName(exercise.id, exercise.name),
                        maxLines: 2,
                        style: AppTheme.f(15, weight: FontWeight.w700, color: gc.text),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${t.setCount(exercise.workingSets.length)} · ${fit.volumeLabel(exercise.volume)}',
                        style: AppTheme.f(11.5, weight: FontWeight.w500, color: gc.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (metrics?.estimatedKcal != null)
                  Text(
                    '≈${metrics!.estimatedKcal!.round()} kcal',
                    style: AppTheme.f(12, weight: FontWeight.w700, color: gc.brass),
                  ),
                const SizedBox(width: 7),
                Icon(PhosphorIconsRegular.caretRight, size: 14, color: gc.textTertiary),
              ],
            ),
            if (metrics != null && (metrics.activeSeconds > 0 || metrics.averageHeartRate != null)) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  _inlineMetric(gc, PhosphorIconsRegular.timer, _time(metrics.activeSeconds)),
                  const SizedBox(width: 14),
                  _inlineMetric(
                    gc,
                    PhosphorIconsRegular.heart,
                    metrics.averageHeartRate == null ? '— bpm' : '${metrics.averageHeartRate!.round()} bpm',
                  ),
                  const SizedBox(width: 14),
                  _inlineMetric(gc, PhosphorIconsRegular.pause, _time(metrics.restSeconds)),
                ],
              ),
              if (total > 0) ...[
                const SizedBox(height: 11),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    value: workRatio,
                    backgroundColor: gc.bgRaised2,
                    valueColor: AlwaysStoppedAnimation(gc.brass),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _inlineMetric(GymColors gc, IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: gc.textTertiary),
        const SizedBox(width: 5),
        Text(
          value,
          style: AppTheme.f(10.5, weight: FontWeight.w600, color: gc.textSecondary),
        ),
      ],
    );
  }

  Future<void> _showExerciseDetails(
    BuildContext context,
    LoggedSession session,
    LoggedExercise exercise,
    ExerciseHistoryMetrics? metrics,
  ) async {
    final gc = context.gc;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.82),
        decoration: BoxDecoration(
          color: gc.bgRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetHandle(),
                const SizedBox(height: 16),
                Text(
                  t.exerciseDetails,
                  style: AppTheme.f(10, weight: FontWeight.w700, color: gc.textTertiary, letterSpacing: 1.2),
                ),
                const SizedBox(height: 5),
                Text(
                  t.catalogName(exercise.id, exercise.name),
                  style: AppTheme.f(22, weight: FontWeight.w800, color: gc.text),
                ),
                if (metrics != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _detailTile(gc, t.actActive, _time(metrics.activeSeconds))),
                      const SizedBox(width: 8),
                      Expanded(child: _detailTile(gc, t.rest, _time(metrics.restSeconds))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _detailTile(
                          gc,
                          'KCAL',
                          metrics.estimatedKcal == null ? '—' : '≈${metrics.estimatedKcal!.round()}',
                        ),
                      ),
                    ],
                  ),
                  if (metrics.averageHeartRate != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _detailTile(
                            gc,
                            t.averageHeartRate,
                            '${metrics.averageHeartRate!.round()} bpm',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _detailTile(gc, t.maxHeartRate, '${metrics.maxHeartRate!.round()} bpm'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _detailTile(
                            gc,
                            t.sensorCoverage,
                            '${(metrics.sensorCoverage * 100).round()}%',
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
                const SizedBox(height: 18),
                for (var i = 0; i < exercise.sets.length; i++) ...[
                  _setRow(gc, i, exercise.sets[i]),
                  if (i < exercise.sets.length - 1) const SizedBox(height: 7),
                ],
                const SizedBox(height: 16),
                GhostButton(
                  label: t.editEntry,
                  icon: PhosphorIconsRegular.pencilSimple,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onEdit(context, session, exercise);
                  },
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    final ok = await askConfirm(
                      sheetContext,
                      title: t.deleteEntry,
                      body: t.deleteEntryBody(t.catalogName(exercise.id, exercise.name)),
                      confirmLabel: t.delete,
                    );
                    if (!ok) return;
                    fit.deleteLoggedExercise(session, exercise);
                    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      t.deleteEntry,
                      textAlign: TextAlign.center,
                      style: AppTheme.f(12, weight: FontWeight.w600, color: gc.danger),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailTile(GymColors gc, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
      decoration: BoxDecoration(color: gc.bgRaised2, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            style: AppTheme.f(14, weight: FontWeight.w800, color: gc.text),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.f(8, weight: FontWeight.w700, color: gc.textTertiary, letterSpacing: 0.7),
          ),
        ],
      ),
    );
  }

  Widget _setRow(GymColors gc, int index, LoggedSet set) {
    final duration = set.startedAt == null || set.completedAt == null
        ? null
        : set.completedAt!.difference(set.startedAt!).inSeconds.clamp(0, 3600);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(color: gc.bgRaised2, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: gc.emberSoft, shape: BoxShape.circle),
            child: Text(
              '${index + 1}',
              style: AppTheme.f(11, weight: FontWeight.w800, color: gc.text),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${fit.weightLabel(set.weight)} × ${set.reps}',
              style: AppTheme.f(14, weight: FontWeight.w700, color: gc.text),
            ),
          ),
          if (set.rpe != null)
            Text(
              'RPE ${set.rpe!.toStringAsFixed(set.rpe! % 1 == 0 ? 0 : 1)}',
              style: AppTheme.f(11, weight: FontWeight.w600, color: gc.brass),
            ),
          if (duration != null) ...[
            const SizedBox(width: 10),
            Text(
              _time(duration),
              style: AppTheme.f(11, weight: FontWeight.w600, color: gc.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmResume(BuildContext context, LoggedSession session) async {
    final ok = await askConfirm(
      context,
      title: t.continueWorkout,
      body: t.continueWorkoutBody,
      confirmLabel: t.continueWorkout,
    );
    if (!ok || !context.mounted) return;
    Navigator.of(context).pop();
    fit.resumeLoggedSession(session);
  }

  bool get _isFuture {
    final now = DateTime.now();
    return date.isAfter(DateTime(now.year, now.month, now.day, 23, 59));
  }

  static String _time(int seconds) {
    if (seconds <= 0) return '—';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    if (minutes > 0) return '${minutes}m ${secs.toString().padLeft(2, '0')}s';
    return '${secs}s';
  }
}
