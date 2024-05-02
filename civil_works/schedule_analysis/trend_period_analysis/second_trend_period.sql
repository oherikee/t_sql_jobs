-- Structure explanation:
-- Throughout the project, there was the monitoring of the project analyst and the mathematician who made the calculations, 
-- both employees of the client. For this, it was necessary to separate the processes in an extended way, repeating the 
-- calculations several times for a simplified presentation (both had a basic understanding of SQL).
--
-- Table purpose explanation:
-- The "tb_second_trend_period" table is the second of three tables and will be consumed by the system for a separate 
-- presentation, where each period will be analyzed and also consumed for future calculations. The entire set of calculations
-- aims to estimate the progress of the civil project, considering seasonality, previous results, etc.
--
-- Comments explanation:
-- Comments are named with the following code: "XXC".
-- Since the calculations are complex, sometimes it will be necessary to mention other comments to avoid repetitions and, 
-- mainly, to facilitate understanding.

ALTER TRIGGER trg_second_trend_period
ON tb_activity_real_progress
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
	SET NOCOUNT ON;
	-- 01C
	-- In case of insertions or updates, the snippet below declares the project's PK as the variable "@id";
	DECLARE @id INTEGER = (SELECT tb_schedule.id_civil_work FROM inserted  JOIN 
																			tb_qualitative_activity
																			ON tb_qualitative_activity.id_qualitative_activity = inserted.id_qualitative_activity
																		JOIN
																			tb_schedule
																			ON tb_qualitative_activity.id_schedule = tb_schedule.id_schedule)
	-- 02C
	-- In case of deletions, the snippet below declares the project's PK as the variable "@idDeleted";
	DECLARE @idDeleted INTEGER =  (SELECT tb_schedule.id_civil_work FROM inserted JOIN 
																				tb_qualitative_activity
																				ON tb_qualitative_activity.id_qualitative_activity = inserted.id_qualitative_activity
																		   JOIN
																				tb_schedule
																				ON tb_qualitative_activity.id_schedule = tb_schedule.id_schedule)
	-- 03C
	-- As it is a replacement, following the business rule, the previously calculated period is disregarded/excluded;	
	DELETE FROM tb_second_trend_period WHERE @id = tb_second_trend_period.id_civil_work;
	-- 04C
	-- The "WITH" clause below aims to return a table (cte_accumulated) containing the expected and actual advances 
	-- (both achieved individually in the period and accumulated over the development of the project), along with the 
	-- structured calendar for this period as well;	
	WITH tde_accumulated (
		id_civil_work,
		id_schedule,
		id_term,
		period,
		foreseen_progress,
		foreseen_progress_accumulated,
		accomplished_progress,
		accomplished_progress_accumulated
		) AS (
	SELECT
		tde_accumulated.id_civil_work,
		tde_accumulated.id_schedule,
		tde_accumulated.id_term,
		tde_accumulated.period,
		tde_accumulated.foreseen_progress AS foreseen_progress,
		CASE
			WHEN SUM(tde_accumulated.foreseen_progress) OVER (PARTITION BY tde_accumulated.id_civil_work ORDER BY tde_accumulated.period) > 100
			THEN 100
			ELSE SUM(tde_accumulated.foreseen_progress) OVER (PARTITION BY tde_accumulated.id_civil_work ORDER BY tde_accumulated.period)
		END AS foreseen_progress_accumulated,
		tde_accumulated.accomplished_progress AS accomplished_progress,
		CASE
			WHEN tde_accumulated.period> sq_sd.data_status
				THEN NULL
				ELSE SUM(tde_accumulated.accomplished_progress) OVER (PARTITION BY tde_accumulated.id_civil_work ORDER BY tde_accumulated.period) 
		END AS accomplished_progress_accumulated
	FROM
		-- 05C
		-- Below, a subquery (cte_accumulated) aims to return in a single table the individual expected and actual values 
		-- per period, attached to the structured periods in the calendar (period);
		(SELECT
			tb_civil_work.id_civil_work,
			tb_schedule.id_schedule,
			tb_term.id_term,
			id_term_date period,
			SUM(tb_activity_real_progress.progress_percentage) AS accomplished_progress,
			CAST(SUM(tb_activty_foreseen_progress.id_foreseen_progress)*100 AS NUMERIC(9,2)) AS foreseen_progress
		FROM
			tb_civil_work
			JOIN
				(SELECT TOP 1
						*
					FROM
						tb_term 
					WHERE
						@id = id_civil_work
					ORDER BY 
						id_term DESC) tb_term ON tb_term.id_civil_work = tb_civil_work.id_civil_work
			JOIN (SELECT TOP 1
						*
					FROM
						tb_schedule 
					WHERE
						@id = id_civil_work
					ORDER BY 
						id_schedule DESC) tb_schedule ON tb_term.id_schedule = tb_schedule.id_schedule
			JOIN tb_term_input_data ON tb_term_input_data.id_term = tb_term.id_term
			JOIN tb_calendar ON tb_calendar.id_input_data = tb_term_input_data.id_input_data
			JOIN tb_qualitative_activity ON tb_schedule.id_schedule = tb_qualitative_activity.id_schedule AND tb_qualitative_activity.outline_lvl = 1
			JOIN tb_activty_foreseen_progress ON tb_qualitative_activity.id_qualitative_activity = tb_activty_foreseen_progress.id_qualitative_activity AND calendar_period = CAST(id_term_date AS DATE)
			LEFT JOIN tb_activity_real_progress ON tb_qualitative_activity.id_qualitative_activity = tb_activity_real_progress.id_qualitative_activity AND calendar_period = CAST(date AS DATE)
		GROUP BY
			tb_civil_work.id_civil_work,
			tb_schedule.id_schedule,
			tb_term.id_term,
			id_term_date) tde_accumulated
	JOIN
		-- 06C
		-- The snippet below is responsible for fetching the status date (point where the project stands);
		(SELECT 
			sq_cw.id_civil_work,
			MAX(sq_activity_real_progress.date) AS sq_status_date
		FROM
			tb_civil_work sq_cw
		LEFT JOIN
			-- 07C
			-- Following the client's business rules, the status date must be calculated based on the latest deadline monitoring, 
			-- which is filtered in the snippet below;
			(SELECT TOP 1
						*
					FROM
						tb_term 
					WHERE
						@id = id_civil_work
					ORDER BY 
						id_term DESC) sq_term
			ON sq_term.id_civil_work = sq_cw.id_civil_work
		LEFT JOIN
			tb_term_activity sq_term_activity
			ON sq_term_activity.id_term = sq_term.id_term
		LEFT JOIN
			tb_activity_real_progress sq_activity_real_progress
			ON sq_activity_real_progress.id_term_activity = sq_term_activity.id_term_activity
		GROUP BY
			sq_cw.id_civil_work) sq_sd
		ON sq_sd.id_civil_work = tde_accumulated.id_civil_work
	GROUP BY
		tde_accumulated.id_civil_work,
		tde_accumulated.id_schedule,
		tde_accumulated.id_term,
		tde_accumulated.period,
		tde_accumulated.foreseen_progress,
		tde_accumulated.accomplished_progress,
		sq_sd.sq_status_date)
	-- 08C
	-- In case of insertions or updates, the snippet below inserts the latest version of the first period of the trend;
	INSERT INTO tb_second_trend_period
			   (period
			   ,initial_deviation
			   ,mobile_deviation
			   ,previous_estimate
			   ,current_estimate
			   ,seasonal_estimate
			   ,trend_period
			   ,id_civil_work
			   ,id_schedule
			   ,id_term)
	-- 09C
	-- Using the table present in the "WITH" clause (cte_accumulated), the structure of the "tb_second_trend_period" 
	-- table is calculated in the snippet below;
	SELECT
		tde_accumulated.period,
		sq_second_period.initial_deviation,
		sq_second_period.mobile_deviation,
		sq_second_period.previous_estimate,
		sq_second_period.current_estimate,
		sq_second_period.seasonal_estimate,
		sq_second_period.trend_period,
		tde_accumulated.id_civil_work,
		tde_accumulated.id_schedule,
		tde_accumulated.id_term
	FROM
		tde_accumulated
	JOIN
		-- 10C
		-- Once the periods are already calculated and attached with the accomplished and foreseen physical advances, in the 
		-- snippet below, everything is structured with the necessary information to assemble the second period of the 
		-- trend (described from comments 11C to 18C);
		(SELECT
			sq_initial_deviation.id_civil_work,
			sq_initial_deviation.period,
			sq_initial_deviation.initial_deviation AS initial_deviation,
			sq_mobile_deviation.deviation AS mobile_deviation,
			sq_previous_seasonal_estimate.deviation AS previous_estimate,
			sq_current_seasonal_estimate.deviation AS current_estimate,
			sq_post_calculation_average.seasonal_estimate,
			CASE
				WHEN sq_initial_deviation.accomplished_progress IS NOT NULL
				THEN sq_initial_deviation.accomplished_progress
				WHEN sq_initial_deviation.trend_period IS NOT NULL
				THEN sq_initial_deviation.trend_period
				ELSE CASE 
						WHEN LAG(sq_initial_deviation.initial_deviation,1) OVER (PARTITION BY sq_initial_deviation.id_civil_work ORDER BY sq_initial_deviation.period) IS NOT NULL
						THEN sq_post_calculation_average.seasonal_estimate * sq_initial_deviation.foreseen_progress
			END END AS trend_period
		FROM
			(SELECT
				tde_accumulated.id_civil_work,
				tde_accumulated.period,
				tde_accumulated.accomplished_progress,
				tde_accumulated.foreseen_progress,
				CASE
					WHEN tb_first_trend_period.initial_deviation IS NOT NULL
					THEN tb_first_trend_period.initial_deviation
					ELSE tb_first_trend_period.trend_period / tde_accumulated.foreseen_progress
				END AS initial_deviation,
				tb_first_trend_period.trend_period
			FROM
				tde_accumulated
			JOIN
				tb_first_trend_period
				ON tb_first_trend_period.id_civil_work = tde_accumulated.id_civil_work
				AND tb_first_trend_period.period = CAST(tde_accumulated.period AS DATE)) sq_initial_deviation
		LEFT JOIN
			(SELECT TOP 3
				tde_accumulated.id_civil_work,
				tde_accumulated.period,
				tde_accumulated.accomplished_progress,
				tde_accumulated.foreseen_progress,
				CASE
					WHEN tb_first_trend_period.initial_deviation IS NOT NULL
					THEN tb_first_trend_period.initial_deviation
					ELSE tb_first_trend_period.trend_period / tde_accumulated.foreseen_progress
				END AS deviation
			FROM
				tde_accumulated
			JOIN
				tb_first_trend_period
				ON tb_first_trend_period.id_civil_work = tde_accumulated.id_civil_work
				AND tb_first_trend_period.period = CAST(tde_accumulated.period AS DATE)
			WHERE
				tb_first_trend_period.trend_period / tde_accumulated.foreseen_progress IS NOT NULL
			ORDER BY
				tde_accumulated.period DESC) sq_mobile_deviation
			ON sq_initial_deviation.id_civil_work = sq_mobile_deviation.id_civil_work
			AND CAST(sq_mobile_deviation.period AS DATE) = CAST(sq_initial_deviation.period AS DATE)
		LEFT JOIN
			(SELECT TOP 2
				sq_mobile_deviation.id_civil_work,
				sq_mobile_deviation.period,
				sq_mobile_deviation.deviation AS deviation
			FROM 
				(SELECT TOP 3
					tde_accumulated.id_civil_work,
					tde_accumulated.period,
					tde_accumulated.accomplished_progress,
					tde_accumulated.foreseen_progress,
					CASE
						WHEN tb_first_trend_period.initial_deviation IS NOT NULL
						THEN tb_first_trend_period.initial_deviation
						ELSE tb_first_trend_period.trend_period / tde_accumulated.foreseen_progress
					END AS deviation
				FROM
					tde_accumulated
				JOIN
					tb_first_trend_period
					ON tb_first_trend_period.id_civil_work = tde_accumulated.id_civil_work
					AND tb_first_trend_period.period = CAST(tde_accumulated.period AS DATE)
				WHERE
					tb_first_trend_period.trend_period / tde_accumulated.foreseen_progress IS NOT NULL
				ORDER BY
					tde_accumulated.period DESC) sq_mobile_deviation
			ORDER BY
				sq_mobile_deviation.period ASC) sq_previous_seasonal_estimate
			ON sq_mobile_deviation.id_civil_work = sq_previous_seasonal_estimate.id_civil_work
			AND sq_mobile_deviation.period = sq_previous_seasonal_estimate.period
		LEFT JOIN
			(SELECT TOP 1
				sq_mobile_deviation.id_civil_work,
				sq_mobile_deviation.period,
				sq_mobile_deviation.deviation AS deviation
			FROM 
				(SELECT TOP 3
					tde_accumulated.id_civil_work,
					tde_accumulated.period,
					tde_accumulated.accomplished_progress,
					tde_accumulated.foreseen_progress,
					CASE
						WHEN tb_first_trend_period.initial_deviation IS NOT NULL
						THEN tb_first_trend_period.initial_deviation
						ELSE tb_first_trend_period.trend_period / tde_accumulated.foreseen_progress
					END AS deviation
				FROM
					tde_accumulated
				JOIN
					tb_first_trend_period
					ON tb_first_trend_period.id_civil_work = tde_accumulated.id_civil_work
					AND tb_first_trend_period.period = CAST(tde_accumulated.period AS DATE)
				WHERE
					tb_first_trend_period.trend_period / tde_accumulated.foreseen_progress IS NOT NULL
				ORDER BY
					tde_accumulated.period DESC) sq_mobile_deviation
			ORDER BY
				sq_mobile_deviation.period DESC) sq_current_seasonal_estimate
			ON sq_mobile_deviation.id_civil_work = sq_current_seasonal_estimate.id_civil_work
			AND sq_mobile_deviation.period = sq_current_seasonal_estimate.period
		LEFT JOIN
			(SELECT
				sq_pre_calculation_average.id_civil_work,
				CASE
					WHEN sq_pre_calculation_average.avg_previous_estimate = 1
					THEN sq_pre_calculation_average.avg_mobile_deviation
					ELSE (sq_pre_calculation_average.avg_previous_estimate + sq_pre_calculation_average.avg_current_estimate)/2
				END AS seasonal_estimate
			FROM
				(SELECT
					sq_initial_deviation.id_civil_work,
					AVG(sq_mobile_deviation.deviation) AS avg_mobile_deviation,
					AVG(sq_previous_seasonal_estimate.deviation) AS avg_previous_estimate,
					AVG(sq_current_seasonal_estimate.deviation) AS avg_current_estimate
				FROM
					(SELECT
						tde_accumulated.id_civil_work,
						tde_accumulated.period,
						tde_accumulated.accomplished_progress,
						tde_accumulated.foreseen_progress,
						CASE
							WHEN tb_first_trend_period.initial_deviation IS NOT NULL
							THEN tb_first_trend_period.initial_deviation
							ELSE tb_first_trend_period.trend_period / tde_accumulated.foreseen_progress
						END AS initial_deviation
					FROM
						tde_accumulated
					JOIN
						tb_first_trend_period
						ON tb_first_trend_period.id_civil_work = tde_accumulated.id_civil_work
						AND tb_first_trend_period.period = CAST(tde_accumulated.period AS DATE)) sq_initial_deviation
				LEFT JOIN
					(SELECT TOP 3
						tde_accumulated.id_civil_work,
						tde_accumulated.period,
						tde_accumulated.accomplished_progress,
						tde_accumulated.foreseen_progress,
						CASE
							WHEN tb_first_trend_period.initial_deviation IS NOT NULL
							THEN tb_first_trend_period.initial_deviation
							ELSE tb_first_trend_period.trend_period / tde_accumulated.foreseen_progress
						END AS deviation
					FROM
						tde_accumulated
					JOIN
						tb_first_trend_period
						ON tb_first_trend_period.id_civil_work = tde_accumulated.id_civil_work
						AND tb_first_trend_period.period = CAST(tde_accumulated.period AS DATE)
					WHERE
						tb_first_trend_period.trend_period / tde_accumulated.foreseen_progress IS NOT NULL
					ORDER BY
						tde_accumulated.period DESC) sq_mobile_deviation
					ON sq_initial_deviation.id_civil_work = sq_mobile_deviation.id_civil_work
					AND CAST(sq_mobile_deviation.period AS DATE) = CAST(sq_initial_deviation.period AS DATE)
				LEFT JOIN
					(SELECT TOP 2
						sq_mobile_deviation.id_civil_work,
						sq_mobile_deviation.period,
						sq_mobile_deviation.deviation AS deviation
					FROM 
						(SELECT TOP 3
							tde_accumulated.id_civil_work,
							tde_accumulated.period,
							tde_accumulated.accomplished_progress,
							tde_accumulated.foreseen_progress,
							CASE
								WHEN tb_first_trend_period.initial_deviation IS NOT NULL
								THEN tb_first_trend_period.initial_deviation
								ELSE tb_first_trend_period.trend_period / tde_accumulated.foreseen_progress
							END AS deviation
						FROM
							tde_accumulated
						JOIN
							tb_first_trend_period
							ON tb_first_trend_period.id_civil_work = tde_accumulated.id_civil_work
							AND tb_first_trend_period.period = CAST(tde_accumulated.period AS DATE)
						WHERE
							tb_first_trend_period.trend_period / tde_accumulated.foreseen_progress IS NOT NULL
						ORDER BY
							tde_accumulated.period DESC) sq_mobile_deviation
					ORDER BY
						sq_mobile_deviation.period ASC) sq_previous_seasonal_estimate
					ON sq_mobile_deviation.id_civil_work = sq_previous_seasonal_estimate.id_civil_work
					AND sq_mobile_deviation.period = sq_previous_seasonal_estimate.period
				LEFT JOIN
					(SELECT TOP 1
						sq_mobile_deviation.id_civil_work,
						sq_mobile_deviation.period,
						sq_mobile_deviation.deviation AS deviation
					FROM 
						(SELECT TOP 3
							tde_accumulated.id_civil_work,
							tde_accumulated.period,
							tde_accumulated.accomplished_progress,
							tde_accumulated.foreseen_progress,
							CASE
								WHEN tb_first_trend_period.initial_deviation IS NOT NULL
								THEN tb_first_trend_period.initial_deviation
								ELSE tb_first_trend_period.trend_period / tde_accumulated.foreseen_progress
							END AS deviation
						FROM
							tde_accumulated
						JOIN
							tb_first_trend_period
							ON tb_first_trend_period.id_civil_work = tde_accumulated.id_civil_work
							AND tb_first_trend_period.period = CAST(tde_accumulated.period AS DATE)
						WHERE
							tb_first_trend_period.trend_period / tde_accumulated.foreseen_progress IS NOT NULL
						ORDER BY
							tde_accumulated.period DESC) sq_mobile_deviation
					ORDER BY
						sq_mobile_deviation.period DESC) sq_current_seasonal_estimate
					ON sq_mobile_deviation.id_civil_work = sq_current_seasonal_estimate.id_civil_work
					AND sq_mobile_deviation.period = sq_current_seasonal_estimate.period
				GROUP BY
					sq_initial_deviation.id_civil_work) sq_pre_calculation_average) sq_post_calculation_average
			ON sq_post_calculation_average.id_civil_work = sq_initial_deviation.id_civil_work
		) sq_second_period
		ON sq_second_period.id_civil_work = tde_accumulated.id_civil_work
		AND tde_accumulated.period = sq_second_period.period
	WHERE
		@id = tde_accumulated.id_civil_work OR @idDeleted = tde_accumulated.id_civil_work
END;
