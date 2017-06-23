-- 5 last created contact per company (only for last 2 years)
-- On company having more than 10 contacts
SELECT con_id, con_firstname, con_lastname, comp_name, pos, created
  FROM (
    SELECT con_id, con_firstname, con_lastname, comp_name,
        timezone('Europe/Paris', contact.date_create)::date as created,
        rank() OVER w AS pos

      FROM contact
      INNER JOIN company On company.comp_id = contact.comp_id
      WHERE date_part('year',timezone('Europe/Paris'::text, contact.date_create)) IN (2016,2017)
      AND contact.comp_id IN (
	select comp_id FROM (
		SELECT company.comp_id, count(*) as nb
		 FROM company
		 INNER JOIN contact ON company.comp_id = contact.comp_id
		 GROUP BY company.comp_id
		 HAVING count(*) > 10
	) ss2
      )
      WINDOW w AS (PARTITION BY contact.comp_id ORDER BY contact.date_create DESC)
  ) AS ss1
  WHERE pos < 6
 ORDER BY comp_name, pos;

 