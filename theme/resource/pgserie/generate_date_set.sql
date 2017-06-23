-- http://sqlfiddle.com/#!17/9eecb/193
SELECT
   row_number() OVER () as rownum,
   day_with_hour_decay as base_date,
   -- least will protect us from dates in future
   least( day_with_hour_decay + concat( ceil(random()*10080 )::text,' minutes')::interval, CURRENT_TIMESTAMP) as date_up_to_7_days,
   least( day_with_hour_decay + concat( (10080 + ceil(random()*1119520 ))::text,' minutes')::interval, CURRENT_TIMESTAMP) as date_up_to_3_months
  FROM (
      SELECT *
 
	 FROM
	 (
	   select  base_day_dates + concat( ceil(random()*1440 )::text,' minutes')::interval as day_with_hour_decay
		  FROM
		   (
			(
			   select 
			   -- 4 years of 1/3 dates (not the last year)
			   generate_series(current_timestamp - interval '5 years', current_timestamp - interval '1 year', '3 day') as base_day_dates
			) UNION ALL (
			   select
			   -- 5 more ancien years with less dates
			   generate_series(current_timestamp - interval '10 years', current_timestamp - interval '5 years', '8 days') as base_day_dates
			) UNION ALL (
			   select
			   -- 1 last year with each day
			   generate_series(current_timestamp - interval '1 year', current_timestamp, '1 day') as base_day_dates
			)
		    ) sub1
	) sub2
	ORDER BY RANDOM()
    ) sub3