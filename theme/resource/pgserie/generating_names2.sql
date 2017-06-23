-- http://sqlfiddle.com/#!17/9eecb/189
SELECT *
FROM (
  SELECT(
	SELECT initcap(string_agg(x,''))  as name_first
	FROM (
		select start_arr[ 1 + ( (random() * 25)::int) % 31 ]
		FROM
		(
		    select '{ro,re,pi,co,jho,bo,ba,ja,mi,pe,da,an,en,sy,vir,nath,so,mo,aï,che,cha,dia,n,nn,hn,b,t,gh,ri,hen,ng}'::text[] as start_arr
		) syllarr,
		-- here without the reference to the generator -- FAIL
		generate_series(1, 3 )
	) AS con_name_first(x)
    ),
    generator as id
  FROM generate_series(1,100) as generator
 ) main_sub