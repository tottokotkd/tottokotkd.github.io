SET SEARCH_PATH TO hinapedia;

CREATE OR REPLACE VIEW units_of_idol AS
SELECT
  characters.id AS character_id,
  characters.name AS character_name,
  count(units.name) AS count,
  array_agg(units.name)
FROM characters
  JOIN yomi_of_character ON characters.id = yomi_of_character.character_id
  JOIN idol_type_of_character ON characters.id = idol_type_of_character.character_id
  JOIN characters_of_unit ON characters.id = characters_of_unit.character_id
  JOIN units ON characters_of_unit.unit_id = units.id
GROUP BY characters.id, characters.name, idol_type_of_character.idol_type, yomi_of_character.yomi
ORDER BY count DESC NULLS LAST;

SELECT avg(count)
FROM units_of_idol
  LEFT JOIN actor_of_character ON units_of_idol.character_id = actor_of_character.character_id
WHERE actor_id IS NULL;

CREATE OR REPLACE VIEW support_power AS
  WITH status_of_units AS (
    SELECT
      units.id as unit_id,
      count(characters.id) as members_count,
      count(actors.id) as actors_count
    FROM units
      LEFT JOIN characters_of_unit ON units.id = characters_of_unit.unit_id
      LEFT JOIN characters ON characters_of_unit.character_id = characters.id
      LEFT JOIN actor_of_character ON characters.id = actor_of_character.character_id
      LEFT JOIN actors ON actor_of_character.actor_id = actors.id
    GROUP BY units.id
  ), voting_params AS (
    SELECT
      unit_id,
      1.0 / (members_count - actors_count) AS param
    FROM status_of_units
    WHERE members_count <> actors_count
  ), idol_with_actors AS (
    SELECT DISTINCT characters.id AS character_id
    FROM characters
      JOIN idol_type_of_character ON characters.id = idol_type_of_character.character_id
      JOIN actor_of_character ON characters.id = actor_of_character.character_id
  ), support_targets AS (
    SELECT
      idol_with_actors.character_id,
      count(voting_params.param) as param
    FROM idol_with_actors
      LEFT JOIN characters_of_unit ON idol_with_actors.character_id = characters_of_unit.character_id
      LEFT JOIN voting_params ON characters_of_unit.unit_id = voting_params.unit_id
    GROUP BY idol_with_actors.character_id
  ), support_power AS (
    SELECT
      idol_with_actors.character_id,
      voting_params.unit_id,
      voting_params.param::FLOAT / support_targets.param AS param
    FROM idol_with_actors
      JOIN characters_of_unit ON idol_with_actors.character_id = characters_of_unit.character_id
      JOIN voting_params ON characters_of_unit.unit_id = voting_params.unit_id
      JOIN support_targets ON idol_with_actors.character_id = support_targets.character_id
  )

  SELECT *
  FROM support_power;

CREATE OR REPLACE VIEW support_by_unit AS
  WITH supporting_idols AS (
    SELECT
      support_power.unit_id,
      support_power.character_id,
      characters.name,
      support_power.param
    FROM support_power
      JOIN characters ON support_power.character_id = characters.id
  ), src AS (
    SELECT
      units.id as unit_id,
      units.name AS unit_name,
      CASE
      WHEN count(supporting_idols) = 0 THEN NULL
      ELSE jsonb_agg(to_jsonb(supporting_idols) - 'unit_id'  - 'character_id')
      END
       AS supporters,
      sum(param) as param
    FROM units
      LEFT JOIN supporting_idols ON units.id = supporting_idols.unit_id
    GROUP BY  units.id, units.name
  )
  SELECT *
  FROM src
  ORDER BY param DESC NULLS LAST;

CREATE OR REPLACE VIEW voting_support_for_idols AS
WITH supported_members AS (
  SELECT
    characters_of_unit.character_id,
    characters_of_unit.unit_id,
    units.name as unit_name,
    support_by_unit.supporters,
    support_by_unit.param
  FROM characters_of_unit
    LEFT JOIN actor_of_character ON characters_of_unit.character_id = actor_of_character.character_id
    JOIN support_by_unit ON characters_of_unit.unit_id = support_by_unit.unit_id
    JOIN units ON characters_of_unit.unit_id = units.id
  WHERE actor_of_character.actor_id IS NULL AND supporters IS NOT NULL
  ORDER BY support_by_unit.param DESC
), src AS (
  SELECT
    character_id,
    jsonb_agg(to_jsonb(supported_members) - 'unit_id') as supporters,
    sum(param) as param
  FROM supported_members
  GROUP BY character_id
)
SELECT
  characters.id AS character_id,
  characters.name AS  character_name,
  src.param,
  src.supporters
FROM characters
  JOIN src ON characters.id = src.character_id
ORDER BY param DESC NULLS LAST
