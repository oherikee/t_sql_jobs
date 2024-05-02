-- Structure explanation:
-- Throughout the project, there was the monitoring of the project analyst and the mathematician who made the calculations, 
-- both employees of the client. For this, it was necessary to separate the processes in an extended way, repeating the 
-- calculations several times for a simplified presentation (both had a basic understanding of SQL).
--
-- Table purpose explanation:
-- The "tb_first_trend_period" table is the first of three tables and will be consumed by the system for a separate 
-- presentation, where each period will be analyzed and also consumed for future calculations. The entire set of calculations
-- aims to estimate the progress of the civil project, considering seasonality, previous results, etc.
--
-- Comments explanation:
-- Comments are named with the following code: "XXC".
-- Since the calculations are complex, sometimes it will be necessary to mention other comments to avoid repetitions and, 
-- mainly, to facilitate understanding.

CREATE TRIGGER trg_first_trend_period
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
	-- In case of deletions, the snippet below declares the project's PK as the variable "@id_deleted";
	DECLARE @id_deleted INTEGER =  (SELECT tb_schedule.id_civil_work FROM inserted JOIN 
																				tb_qualitative_activity
																				ON tb_qualitative_activity.id_qualitative_activity = inserted.id_qualitative_activity
																		   JOIN
																				tb_schedule
																				ON tb_qualitative_activity.id_schedule = tb_schedule.id_schedule)
	-- 03C
	-- As it is a replacement, following the business rule, the previously calculated period is disregarded/excluded;
	DELETE FROM tb_first_trend_period WHERE @id = tb_first_trend_period.id_civil_work;
	-- 04C
	-- The "WITH" clause below aims to return a table (cte_accumulated) containing the expected and actual advances 
	-- (both achieved individually in the period and accumulated over the development of the project), along with the 
	-- structured calendar for this period as well;
	WITH cte_accumulated (
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
		cte_accumulated.id_civil_work,
		cte_accumulated.id_schedule,
		cte_accumulated.id_term,
		cte_accumulated.period,
		cte_accumulated.foreseen_progress AS foreseen_progress,
		CASE
			WHEN SUM(cte_accumulated.foreseen_progress) OVER (PARTITION BY cte_accumulated.id_civil_work ORDER BY cte_accumulated.period) > 100
			THEN 100
			ELSE SUM(cte_accumulated.foreseen_progress) OVER (PARTITION BY cte_accumulated.id_civil_work ORDER BY cte_accumulated.period)
		END AS foreseen_progress_accumulated,
		cte_accumulated.accomplished_progress AS accomplished_progress,
		CASE
			WHEN cte_accumulated.period> sq_sd.status_date
				THEN NULL
				ELSE SUM(cte_accumulated.accomplished_progress) OVER (PARTITION BY cte_accumulated.id_civil_work ORDER BY tde_accumulated.period) 
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
			JOIN (SELECT TOP 1
						*
					FROM
						tb_term 
					WHERE
						@id = id_civil_work
					ORDER BY 
						id_schedule DESC) tb_term ON tb_civil_work.id_civil_work = tb_term.id_civil_work
			JOIN (SELECT TOP 1
						*
					FROM
						tb_schedule 
					WHERE
						@id = id_civil_work
					ORDER BY 
						id_schedule DESC)tb_schedule ON tb_term.id_schedule = tb_schedule.id_schedule
			JOIN tb_term_input_data ON tb_term_input_data.id_term = tb_term.id_term
			JOIN tb_calendar ON tb_calendar.id_input_data = tb_term_input_data.id_input_data
			JOIN tb_qualitative_activity ON tb_schedule.id_schedule = tb_qualitative_activity.id_schedule AND tb_qualitative_activity.outline_lvl = 1
			JOIN tb_activty_foreseen_progress ON tb_qualitative_activity.id_qualitative_activity = tb_activty_foreseen_progress.id_qualitative_activity AND calendar_period = CAST(id_term_date AS DATE)
			LEFT JOIN tb_activity_real_progress ON tb_qualitative_activity.id_qualitative_activity = tb_activity_real_progress.id_qualitative_activity AND calendar_period = CAST(progress_date AS DATE)
		GROUP BY
			tb_civil_work.id_civil_work,
			tb_schedule.id_schedule,
			tb_term.id_term,
			id_term_date) cte_accumulated
	-- 06C
	-- The snippet below is responsible for fetching the status date (point where the project stands);
	JOIN
		(SELECT 
			cw.id_civil_work,
			MAX(avr.progress_date) AS sq_status_date
		FROM
			tb_civil_work cw
		-- 07C
		-- Following the client's business rules, the status date must be calculated based on the latest deadline monitoring, 
		-- which is filtered in the snippet below;
		LEFT JOIN
			(SELECT TOP 1
						*
					FROM
						tb_term 
					WHERE
						@id = id_civil_work
					ORDER BY 
						id_term DESC) mpr
			ON mpr.id_civil_work = cw.id_civil_work
		LEFT JOIN
			tb_term_activity mpa
			ON mpa.id_term = mpr.id_term
		LEFT JOIN
			tb_activity_real_progress avr
			ON avr.id_term_activity = mpa.id_term_activity
		GROUP BY
			cw.id_civil_work) sq_sd
		ON sq_sd.id_civil_work = cte_accumulated.id_civil_work
	GROUP BY
		cte_accumulated.id_civil_work,
		cte_accumulated.id_schedule,
		cte_accumulated.id_term,
		cte_accumulated.period,
		cte_accumulated.foreseen_progress,
		cte_accumulated.accomplished_progress,
		sq_sd.sq_status_date)
	-- 08C
	-- In case of insertions or updates, the snippet below inserts the latest version of the first period of the trend;
	INSERT INTO tb_first_trend_period
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
	-- Using the table present in the "WITH" clause (cte_accumulated), the structure of the "tb_first_trend_period" 
	-- table is calculated in the snippet below;
	SELECT
		cte_accumulated.period,
		sq_first_period.initial_deviation,
		sq_first_period.mobile_deviation,
		sq_first_period.previous_estimate,
		sq_first_period.current_estimate,
		sq_first_period.seasonal_estimate,
		sq_first_period.trend_period,
		cte_accumulated.id_civil_work,
		cte_accumulated.id_schedule,
		cte_accumulated.id_term
	FROM
		cte_accumulated
	JOIN
		-- 10C
		-- Once the periods are already calculated and attached with the accomplished and foreseen physical advances, in the 
		-- snippet below, everything is structured with the necessary information to assemble the first period of the 
		-- trend (described from comments 11C to 18C);
		(SELECT
			sq_initial_deviation.period,
			sq_initial_deviation.initial_deviation AS initial_deviation,
			sq_mobile_deviation.deviation AS mobile_deviation,
			sq_previous_seasonal_estimate.deviation AS previous_estimate,
			sq_current_seasonal_estimate.deviation AS current_estimate,
			sq_post_calculation_average.seasonal_estimate,
			-- 11C
			-- Below, the decision-making of the trend period calculation is shown:
			-- 1st Rule = If there is an actual advance in this period, then the value equals the actual advance (this logic 
			-- is to fill in the previous periods, since there is already an actual advance, so there is no need for the trend period);
			-- 2nd Rule = If there is a calculated trend period in the previous period, then the following multiplication is made:
			-- seasonal average (explained in comment 15C) * foreseen progress;
			CASE
				WHEN sq_initial_deviation.accomplished_progress IS NOT NULL
				THEN sq_initial_deviation.accomplished_progress
				ELSE CASE 
						WHEN LAG(sq_initial_deviation.initial_deviation,1) OVER (PARTITION BY sq_initial_deviation.id_civil_work ORDER BY sq_initial_deviation.period) IS NOT NULL
						THEN sq_post_calculation_average.seasonal_estimate * sq_initial_deviation.foreseen_progress
			END END AS trend_period,
			sq_initial_deviation.id_civil_work
		FROM
			-- 12C
			-- As a basis, a table is used to return the initial deviation only.
			-- The calculation is done in all periods containing an actual physical advance. See the calculation below:
			-- Calculation: (accomplished progress / foreseen progress);
			(SELECT
				cte_accumulated.id_civil_work,
				cte_accumulated.period,
				cte_accumulated.accomplished_progress,
				cte_accumulated.foreseen_progress,
				cte_accumulated.accomplished_progress / cte_accumulated.foreseen_progress AS initial_deviation 
			FROM
				cte_accumulated) sq_initial_deviation
		LEFT JOIN
			-- 13C
			-- Support table to calculate the moving deviation, specifically for the last 3 periods (number of periods defined by the client).
			-- The calculation itself is the same as the initial deviation (see comment 12C), but it is brought only from the last 3 periods;
			(SELECT TOP 3
				cte_accumulated.id_civil_work,
				cte_accumulated.period,
				cte_accumulated.accomplished_progress / cte_accumulated.foreseen_progress AS deviation
			FROM 
				cte_accumulated
			-- 14C
			-- The snippet below filters only the most recent monitoring analysis;
			JOIN
				(SELECT TOP 1
						*
					FROM
						tb_term 
					WHERE
						@id = id_civil_work
					ORDER BY 
						id_term DESC) tb_term
				ON tb_term.id_civil_work = cte_accumulated.id_civil_work
			WHERE
				cte_accumulated.accomplished_progress IS NOT NULL
			ORDER BY
				cte_accumulated.period DESC) sq_mobile_deviation
			ON sq_initial_deviation.id_civil_work = sq_mobile_deviation.id_civil_work
			AND sq_mobile_deviation.period = sq_initial_deviation.period
		-- 15C
		-- Based on the moving deviation, we need to calculate the estimate to reach the seasonal average.
		-- The snippets below are responsible for calculating the previous periods of the moving deviation, which uses the 
		-- following logic:
		-- To have the seasonal average, we need to estimate within the moving deviation the average of the previous months, and 
		-- to bring the seasonal concept, we need
		-- to consider mainly the most recent month. In this case, as we use 3 periods for the analysis (explained in comment 13C), then
		-- we will separate into two values: the average of the first 2 periods divided by the most recent period.
		-- To specify better, if we were analyzing 5 periods, we would average the first 4 and divide by the most recent period.
		-- See the example below, following the premise that we will be analyzing 3 periods to calculate the seasonal average:
		-- |  Period | Moving Deviation | Reference Period |
		-- | 01/2023 |        -         |        -         |
		-- | 02/2023 |        -         |        -         |
		-- | 03/2023 |      11.1%       |     Previous     |
		-- | 04/2023 |      12.4%       |     Previous     |
		-- | 05/2023 |      10.3%       |      Current     |
		--
		-- Understanding the logic above, the calculation would be like this:
		-- Previous period = (11.1 + 12.4) / 2
		-- Current period = 10.3
		-- Seasonal average = (previous period + current period) / 2;
		LEFT JOIN
			-- 16C
			-- Below, the previous moving averages will be calculated (value explained in comment 15C);
			(SELECT TOP 2
				sq_mobile_deviation.id_civil_work,
				sq_mobile_deviation.period,
				sq_mobile_deviation.accomplished_progress / sq_mobile_deviation.foreseen_progress AS deviation 
			FROM 
				(SELECT TOP 3
					cte_accumulated.id_civil_work,
					cte_accumulated.period,
					cte_accumulated.accomplished_progress,
					cte_accumulated.foreseen_progress,
					cte_accumulated.accomplished_progress / cte_accumulated.foreseen_progress AS deviation
				FROM 
					cte_accumulated
				JOIN
					(SELECT TOP 1
						*
					FROM
						tb_term 
					WHERE
						@id = id_civil_work
					ORDER BY 
						id_term DESC) tb_term
					ON tb_term.id_civil_work = cte_accumulated.id_civil_work
				WHERE
					cte_accumulated.accomplished_progress IS NOT NULL
				ORDER BY
					cte_accumulated.period DESC) sq_mobile_deviation
			ORDER BY
				sq_mobile_deviation.period ASC) sq_previous_seasonal_estimate
			ON sq_mobile_deviation.id_civil_work = sq_previous_seasonal_estimate.id_civil_work
			AND sq_mobile_deviation.period = sq_previous_seasonal_estimate.period
		
		LEFT JOIN
			-- 17C
			-- Below, the current moving average will be calculated (value explained in comment 15C);
			(SELECT TOP 1
				sq_mobile_deviation.id_civil_work,
				sq_mobile_deviation.period,
				sq_mobile_deviation.accomplished_progress / sq_mobile_deviation.foreseen_progress AS deviation
			FROM 
				(SELECT TOP 3
					cte_accumulated.id_civil_work,
					cte_accumulated.period,
					cte_accumulated.accomplished_progress,
					cte_accumulated.foreseen_progress,
					cte_accumulated.accomplished_progress / cte_accumulated.foreseen_progress AS deviation
				FROM 
					cte_accumulated
				JOIN
					(SELECT TOP 1
						*
					FROM
						tb_term 
					WHERE
						@id = id_civil_work
					ORDER BY 
						id_term DESC) tb_term
					ON tb_term.id_civil_work = cte_accumulated.id_civil_work
				WHERE
					cte_accumulated.accomplished_progress IS NOT NULL
				ORDER BY
					cte_accumulated.period DESC) sq_mobile_deviation
			JOIN
				(SELECT TOP 1
						*
					FROM
						tb_term 
					WHERE
						@id = id_civil_work
					ORDER BY 
						id_term DESC) tb_term
				ON tb_term.id_civil_work = sq_mobile_deviation.id_civil_work
			ORDER BY
				sq_mobile_deviation.period DESC) sq_current_seasonal_estimate
			ON sq_mobile_deviation.id_civil_work = sq_current_seasonal_estimate.id_civil_work
			AND sq_mobile_deviation.period = sq_current_seasonal_estimate.period
		LEFT JOIN
			(SELECT
				sq_pre_calculation_average.id_civil_work,
				-- 18C
				-- Below, is the point where the seasonal average, explained in comment 15C, is effected.
				-- Even though the average has already been explained, it is also worth noting the decision-making:
				-- 1st Rule = If the average of the previous moving deviations equals 100%, then it will only present the current moving 
				-- deviation, without calculation;
				-- 2nd Rule = If the above rule is not met, then the calculation will be performed.
				CASE
					WHEN sq_pre_calculation_average.average_previous_seasonal_deviation = 1
					THEN sq_pre_calculation_average.average_mobile_deviation
					ELSE (sq_pre_calculation_average.average_previous_seasonal_deviation + sq_pre_calculation_average.average_current_seasonal_deviation)/2
				END AS seasonal_estimate
			FROM
				-- 19C
				-- As the calculations need to be presented individually in the final result, but also need to be calculated separately 
				-- to reach the first period of the trend, several calculations already performed above will be repeated in the following snippets;
				(SELECT
					sq_initial_deviation.id_civil_work,
					AVG(sq_mobile_deviation.deviation) AS average_mobile_deviation,
					AVG(sq_previous_seasonal_estimate.deviation) AS average_previous_seasonal_deviation,
					AVG(sq_current_seasonal_estimate.deviation) AS average_current_seasonal_deviation
				FROM
					(SELECT
						cte_accumulated.id_civil_work,
						cte_accumulated.period,
						cte_accumulated.accomplished_progress / cte_accumulated.foreseen_progress AS initial_deviation
					FROM
						cte_accumulated) sq_initial_deviation
				-- 20C
				-- Below, is the calculation of the moving deviation (explained in comment 13C);
				LEFT JOIN
					(SELECT TOP 3
						cte_accumulated.id_civil_work,
						cte_accumulated.period,
						cte_accumulated.accomplished_progress / cte_accumulated.foreseen_progress AS deviation
					FROM 
						cte_accumulated
					WHERE 
						cte_accumulated.accomplished_progress IS NOT NULL
					ORDER BY
						cte_accumulated.period DESC) sq_mobile_deviation
					ON sq_initial_deviation.id_civil_work = sq_mobile_deviation.id_civil_work
					AND sq_mobile_deviation.period = sq_initial_deviation.period
				-- 21C
				-- Below, is the calculation of the previous moving deviations (explained in comment 15C);
				LEFT JOIN
					(SELECT TOP 2
						sq_mobile_deviation.id_civil_work,
						sq_mobile_deviation.period,
						sq_mobile_deviation.accomplished_progress / sq_mobile_deviation.foreseen_progress AS deviation 
					FROM 
						(SELECT TOP 3
							cte_accumulated.id_civil_work,
							cte_accumulated.period,
							cte_accumulated.accomplished_progress,
							cte_accumulated.foreseen_progress,
							cte_accumulated.accomplished_progress / cte_accumulated.foreseen_progress AS deviation
						FROM 
							cte_accumulated
						JOIN
							(SELECT TOP 1
						*
					FROM
						tb_term 
					WHERE
						@id = id_civil_work
					ORDER BY 
						id_term DESC) tb_term
							ON tb_term.id_civil_work = cte_accumulated.id_civil_work
						WHERE
							cte_accumulated.accomplished_progress IS NOT NULL
						ORDER BY
							cte_accumulated.period DESC) sq_mobile_deviation
					ORDER BY
						sq_mobile_deviation.period ASC) sq_previous_seasonal_estimate
					ON sq_mobile_deviation.id_civil_work = sq_previous_seasonal_estimate.id_civil_work
					AND sq_mobile_deviation.period = sq_previous_seasonal_estimate.period
				-- 22C
				-- Below, is the calculation of the current moving deviation (explained in comment 15C);
				LEFT JOIN
					(SELECT TOP 1
						sq_mobile_deviation.id_civil_work,
						sq_mobile_deviation.period,
						sq_mobile_deviation.accomplished_progress / sq_mobile_deviation.foreseen_progress AS deviation
					FROM 
						(SELECT TOP 3
							cte_accumulated.id_civil_work,
							cte_accumulated.period,
							cte_accumulated.accomplished_progress,
							cte_accumulated.foreseen_progress,
							cte_accumulated.accomplished_progress / cte_accumulated.foreseen_progress AS deviation
						FROM 
							cte_accumulated
						JOIN
							(SELECT TOP 1
						*
					FROM
						tb_term 
					WHERE
						@id = id_civil_work
					ORDER BY 
						id_term DESC) tb_term
							ON tb_term.id_civil_work = cte_accumulated.id_civil_work
						WHERE
							cte_accumulated.accomplished_progress IS NOT NULL
						ORDER BY
							cte_accumulated.period DESC) sq_mobile_deviation
					JOIN
						tb_term
						ON tb_term.id_civil_work = sq_mobile_deviation.id_civil_work
					ORDER BY
						sq_mobile_deviation.period DESC) sq_current_seasonal_estimate
					ON sq_mobile_deviation.id_civil_work = sq_current_seasonal_estimate.id_civil_work
					AND sq_mobile_deviation.period = sq_current_seasonal_estimate.period
				GROUP BY
					sq_initial_deviation.id_civil_work) sq_pre_calculation_average) sq_post_calculation_average
			ON sq_post_calculation_average.id_civil_work = sq_initial_deviation.id_civil_work
		) sq_first_period
		ON sq_first_period.id_civil_work = cte_accumulated.id_civil_work
		AND cte_accumulated.period = sq_first_period.period
	WHERE
		@id = cte_accumulated.id_civil_work OR @id_deleted = cte_accumulated.id_civil_work
END;
GO

ALTER TABLE [dbo].[tb_activity_real_progress] ENABLE TRIGGER [trg_first_trend_period];
GO