-- http://sqlfiddle.com/#!17/93004/7
-- http://sqlfiddle.com/#!17/93004/8
-- http://sqlfiddle.com/#!17/93004/6
WITH dates1083 as (
-- 1083 dates, with 2 other dates following (date_up_to_7_days and date_up_to_3_months)
-- dates are more frequent on last year, then on previous 5 years, then on previous 10 years
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
)

INSERT INTO contact(
  con_id,
  con_active,
  con_firstname,
  con_lastname,
  con_mail,
  date_create,
  con_date_first_interaction,
  con_date_last_interaction,
  date_alter,
  con_status,
  comp_id
)
SELECT
  id,
  con_active,
  CASE WHEN show_first_name THEN name_first ELSE NULL END as con_first_name,
  CASE WHEN show_last_name THEN name_last ELSE NULL END as con_last_name,
  -- con_mail
  concat_ws('@',concat_ws('.',
                          replace(lower(name_first),'ï','i'),
                          replace(replace(replace(replace(replace(replace(lower(name_last),'ï','i'),'ü','u'),'é','e'),'á','a'),'ó','o'),'''','-')),
               concat_ws('.',replace(replace(replace(lower(company.comp_name),' ','-'),'&',''),'--','-'),'com')
           ) as mail,
  -- date_create
  dates1083.base_date as date_create,
  -- con_date_first_interaction
  CASE WHEN (has_1st_interact=true) THEN dates1083.date_up_to_7_days ELSE NULL END as date_1st_interact,
  -- con_date_last_interaction
  CASE WHEN (has_2nd_interact=true AND has_1st_interact=true) THEN dates1083.date_up_to_3_months
       WHEN (has_2nd_interact=false AND has_1st_interact=true) THEN dates1083.date_up_to_7_days
       ELSE NULL END as date_2nd_interact,
  -- date_alter
  CASE WHEN (has_2nd_interact=true AND has_1st_interact=true) THEN dates1083.date_up_to_3_months 
       WHEN (has_1st_interact=true) THEN dates1083.date_up_to_7_days ELSE dates1083.base_date END as date_alter,
  -- con_status
  con_status,
  -- company link
  main_sub.comp_id
FROM (
   -- name_first
  SELECT(
	SELECT initcap(string_agg(x,''))  as name_first
	FROM (
		select start_arr[ 1 + ( (random() * 25)::int) % 31 ]
		FROM
		(
		    select '{ro,re,pi,co,jho,bo,ba,ja,mi,pe,da,an,en,sy,vir,nath,so,mo,aï,che,cha,dia,n,nn,hn,b,t,gh,ri,hen,ng}'::text[] as start_arr
		) syllarr,
		-- need 3 syllabes, and force generator interpretation with the '*0' (else 3 same syllabes)
		generate_series(1, 3 + (generator*0))
	) AS con_name_first(x)
    ),
    -- name_last
    (
	SELECT initcap(string_agg(x,''))  as name_last
	FROM (
		select start_arr[ 1 + ( (random() * 25)::int) % 65 ]
		FROM
		(
		    select '{le,la,jac,butch,son,er,er,er,roy,king,o'',mc,ibn,ill,san,vur,cht,stein,klein,chen,taka,oto,ata,für,dur,dup,and,ont,tru,kloug,ing,mam,gul,haj,bab,oru,isma,gnon,wil,son,mar,lam,mur,smi,phy,th,thier,tin,iaz,ales,iguez,iérrez,ález,ópe;wink,brun;lech,qign,outer,imon,p,d,t,r,n,bert,h}'::text[] as start_arr
		) syllarr,
		-- need 4 syllabes, and force generator interpretation with the '*0' (else 3 same syllabes)
		generate_series(1, 4 + (generator*0))
	) AS con_name_last(x)
    ),
    -- con_status
    (
        select status_arr[ (generator*0) + 1 + ( (random() * 12)::int) % 6 ] as con_status
        FROM (
            select '{unknown,direction,commercial,production,support,external}'::contact_type[] as status_arr
        ) AS sub_enum
        
    ),
    -- comp_id (used for joining company table, adding comp_name on email
    (
        select  (random() * 10000)::int + (generator*0) as comp_id
    ),
    -- base_date_num (used for joining dates1083 pseudo-table, and computing others dates from that
    (
        select  (random() * 1083)::int + (generator*0) as base_date_num
    ),
    -- con_active, something like 10% of false (inactive)
    (
        select ((random() * 10 + (generator*0)) > 1)::boolean as con_active
    ),
    -- has_1st interaction something like 95%
    (
        select ((random() * 100 + (generator*0)) > 5)::boolean as has_1st_interact
    ),
    -- has_2nd interaction something like 65%
    (
        select ((random() * 100 + (generator*0)) > 35)::boolean as has_2nd_interact
    ),
    -- let's hide some non required fields sometimes
    -- hiding 5 % of last_names
    (
        select ((random() * 100 + (generator*0)) > 5)::boolean as show_last_name
    ),
    -- hiding 5 % of first_names
    (
        select ((random() * 100 + (generator*0)) > 5)::boolean as show_first_name
    ),
    -- id
    generator as id
  FROM generate_series(1,100) as generator
 ) main_sub
 INNER JOIN company ON company.comp_id = main_sub.comp_id
 INNER JOIN dates1083 ON dates1083.rownum = main_sub.base_date_num
-- ignore conflicts of ids, but not any checks constraint failure (on dates for example)
ON CONFLICT DO NOTHING;

