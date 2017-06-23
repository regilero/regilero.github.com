-- http://sqlfiddle.com/#!17/25d75/1

DROP TABLE IF EXISTS contact
;
DROP TABLE IF EXISTS company
;
DROP TYPE IF EXISTS contact_type
;

CREATE TYPE contact_type AS ENUM
 ('unknown',
  'direction',
  'commercial',
  'production',
  'support',
  'external',
  '#err'
 )
;

CREATE OR REPLACE FUNCTION update_date_alter()
  RETURNS trigger AS
$BODY$
  BEGIN
    NEW.date_alter = NOW();
    RETURN NEW;
  END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100
;

CREATE TABLE company
(
 comp_id bigserial,
 comp_name character varying(255) NOT NULL,
 comp_active boolean NOT NULL DEFAULT true,
 date_create timestamp with time zone DEFAULT now(),
 date_alter timestamp with time zone DEFAULT now(),
  CONSTRAINT "company_PRIMARY_KEY" PRIMARY KEY (comp_id)
)
;

CREATE UNIQUE INDEX company_unique_name
  ON company (comp_name)
  WHERE comp_active
;

CREATE TRIGGER comp_update_date_alter
  BEFORE UPDATE
  ON company
  FOR EACH ROW
  EXECUTE PROCEDURE update_date_alter()
;

CREATE TABLE contact
(
 con_id bigserial,
 con_lastname character varying(100) NULL,
 con_firstname character varying(50) NULL,
 con_mail character varying(255) NOT NULL default 'unknown@example.com'::character varying,
 con_active boolean NOT NULL DEFAULT true,
 comp_id bigint NOT NULL DEFAULT 1,
 con_comment text NULL,
 con_status contact_type NOT NULL default 'unknown'::contact_type,
 con_date_first_interaction timestamp with time zone NULL,
 con_date_last_interaction timestamp with time zone NULL,
 date_create timestamp with time zone DEFAULT now(),
 date_alter timestamp with time zone DEFAULT now(),
  CONSTRAINT "contact_PRIMARY_KEY" PRIMARY KEY (con_id),
  CONSTRAINT "contact_has_company" FOREIGN KEY (comp_id)
      REFERENCES company (comp_id) MATCH SIMPLE
      ON UPDATE CASCADE ON DELETE SET DEFAULT DEFERRABLE INITIALLY DEFERRED,
  CONSTRAINT contact_first_interaction_cannot_be_in_future CHECK (con_date_first_interaction IS NULL OR con_date_first_interaction <= now()),
  CONSTRAINT contact_last_interaction_cannot_be_in_future CHECK (con_date_last_interaction IS NULL OR con_date_last_interaction <= now()),
  CONSTRAINT contact_first_interaction_imply_last_interaction CHECK (con_date_first_interaction IS NULL OR con_date_last_interaction IS NOT NULL),
  CONSTRAINT contact_last_interaction_imply_first_interaction CHECK (con_date_last_interaction IS NULL OR con_date_first_interaction IS NOT NULL),
  CONSTRAINT contact_last_interaction_cannot_be_lower_than_first_one CHECK (con_date_last_interaction IS NULL OR con_date_last_interaction >= con_date_first_interaction)
)
;

CREATE UNIQUE INDEX contact_unique_active_email
  ON contact (con_mail)
  WHERE con_active
;
CREATE INDEX contact_upplastname_firstname
  ON contact (upper(con_lastname), con_firstname)
  WHERE con_active
;

CREATE INDEX contact_last_interaction_year_month_idx
ON contact (
  date_part('year',timezone('Europe/Paris'::text, con_date_last_interaction)) DESC,
  date_part('month',timezone('Europe/Paris'::text, con_date_last_interaction)) DESC
)
;

-- fk
CREATE INDEX contact_comp_id_idx
ON contact (comp_id)
;

CREATE INDEX contact_created_idx
ON contact
  ((timezone('Europe/Paris'::text, date_create)::date) DESC)
;

CREATE INDEX contact_year_create_idx
ON contact (
  date_part('year', timezone('Europe/Paris'::text, date_create))
)
;

CREATE TRIGGER contact_update_date_alter
  BEFORE UPDATE
  ON contact
  FOR EACH ROW
  EXECUTE PROCEDURE update_date_alter()
;

-- Data sample

INSERT INTO company (comp_name)
VALUES
('COMPANY1'),
('COMPANY2'),
('COMPANY3')
;

INSERT INTO contact (
  con_firstname,
  con_lastname,
  con_mail,
  comp_id,
  con_status,
  con_date_first_interaction,
  con_date_last_interaction
) VALUES
('Bob', 'Foo', 'bob.foo@example.com', 1, 'production', CURRENT_TIMESTAMP - INTERVAL '2 days', CURRENT_TIMESTAMP),
('John', 'Bar', 'john.bar@example.com', 2, 'production', CURRENT_TIMESTAMP - INTERVAL '1 day', CURRENT_TIMESTAMP  - INTERVAL '1 day'),
(NULL, NULL, 'null@example.com', 1, 'direction', NULL, NULL)
;

-- Check sample with this simple query:
-- select comp.*, con.*
-- FROM contact con
-- INNER JOIN company comp ON comp.comp_id = con.comp_id;