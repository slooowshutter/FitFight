-- More private Apple Health collection. Still not used for Fight scoring.
-- Older apps that omit resting energy and workout active minutes stay valid.

alter table private.healthkit_activity_days
    drop constraint healthkit_activity_days_metric,
    add constraint healthkit_activity_days_metric check (
        metric in (
            'active_energy',
            'resting_energy',
            'walking_running_distance',
            'exercise_minutes',
            'stand_minutes',
            'stand_hours',
            'flights_climbed',
            'cycling_distance',
            'swimming_distance',
            'move_time_minutes',
            'wheelchair_distance',
            'wheelchair_pushes',
            'swimming_strokes',
            'rowing_distance',
            'paddle_distance',
            'skating_distance',
            'cross_country_ski_distance',
            'downhill_snow_distance',
            'workout_count',
            'workout_time',
            'walk_run_workout_distance'
        )
    );

alter table private.healthkit_activity_days
    drop constraint healthkit_activity_days_unit,
    add constraint healthkit_activity_days_unit check (
        (metric in ('active_energy', 'resting_energy') and unit = 'kcal')
        or (metric in (
            'walking_running_distance',
            'cycling_distance',
            'swimming_distance',
            'wheelchair_distance',
            'rowing_distance',
            'paddle_distance',
            'skating_distance',
            'cross_country_ski_distance',
            'downhill_snow_distance',
            'walk_run_workout_distance'
        ) and unit = 'm')
        or (metric in ('exercise_minutes', 'stand_minutes', 'move_time_minutes') and unit = 'min')
        or (metric in (
            'stand_hours',
            'flights_climbed',
            'wheelchair_pushes',
            'swimming_strokes',
            'workout_count'
        ) and unit = 'count')
        or (metric = 'workout_time' and unit = 's')
    );

alter table private.healthkit_workouts
    add column active_minutes numeric,
    add constraint healthkit_workouts_active_minutes check (
        active_minutes is null or active_minutes >= 0
    );
