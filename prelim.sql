/*--*2019 Data Load
1. Create temp tables, remove select rows, add select columns
        dropped columns: payment_region, organic_status
        dropped data: all year 2019 data, ((land_use = 'EXCL' OR land_use = 'DELETED_LANDUSE') AND (land_use_area = 0 OR land_use_area IS NULL)), 
                      duplicate records from payment_region, NULL hapar_id and land_use = ' ', application_status LIKE 'Wait for Dealine/Inspection' or 'Wait for Land Change'
        recast claim_id column to accept multiple values
        rename claim_id_p/s so no problems with unique ids between tables

2. Fix land_parcel_area IS NULL/0
        infer land_parcel_area from same hapar_id
        infer land_parcel_area from land_use_area in same row
        delete where land_parcel_area IS NULL/0 AND land_use_area = 0

3. Fix land_use_area IS NULL or 0
        copy land_parcel_area for single claims where land_parcel_area = bps_eligible_area
        update NULL/0 land_use_areas with inferred values from other years whre same land_use
        --! adjust land_use_area to match bps_claimed_area -- not sure about this one
        delete remaining NULL land_use_area

4. Find renter records in wrong tables
        finds multiple businesses claiming on same land in same table and marks them as either owner/renter
        moves marked records to respective tables
        finds swapped owner/renters (owners in seasonal table and renters in permanent table that join on hapar_id, year, land_use, land_use_area) 
        move marked records to respective tables
            
5. Combine mutually exclusive       
        move mutually exclusive hapar_ids to separate table
        
6. Joins 
        first join on hapar_id, year, land_use, land_use_area
            delete from original table where join above
        second join on hapar_id, year, land_use 
            delete from original table where join above 
        third join on hapar_id, year, land_use_area 
            delete from original table where join above
        fourth join on hapar_id, year 
            delete from original table where join above

7. Clean up
    move leftover mutually exclusive ones to diff tables 
    find owners based on LLO flag and change them from user to owner from mutually exclusive table
    Assumes land_parcel_area = owner_land_parcel when owner > user
    Assumes land_parcel_area = user_land_parcel when user > owner 
    Assumes bps_eligible_area = owner_bps_eligible_area when owner > user 
    Assumes bps_eligible_area = user_bps_eligible_area when user > owner 
    Assumes verified_exclusion = owner_verified_exclusion when owner > user
    Assumes verified_exclusion = user_verified_exclusion when user > owner
    Assumes user_land_activity is more correct when no match
    Assumes if either owner or renter has application_status = ‘under action/assessment’ then it is  

8. Combine ALL into final table
    Infer NON-SAF renter where LLO yes 
    Infer NON-SAF owner for mutually exclusive users 

*/
DROP TABLE IF EXISTS excl;
CREATE TEMP TABLE excl (land_use VARCHAR(30),
                                 descript VARCHAR(30));


INSERT INTO excl (land_use, descript)
VALUES ('BLU-GLS', 'Blueberries - glasshouse'), 
       ('BRA', 'Bracken'), 
       ('BUI', 'Building'), 
       ('EXCL','Generic exclusion'),
       ('FSE', 'Foreshore'), 
       ('GOR', 'Gorse'), 
       ('LLO', 'Land let out'), 
       ('MAR', 'Marsh'), 
       ('RASP-GLS', 'Raspberries - glasshouse'), 
       ('ROAD', 'Road'), 
       ('ROK', 'Rocks'), 
       ('SCB', 'Scrub'), 
       ('SCE', 'Scree'), 
       ('STRB-GLS', 'Strawberries - glasshouse'), 
       ('TOM-GLS', 'Tomatoes - glasshouse'), 
       ('TREES', 'Trees'), 
       ('WAT', 'Water');

--*Step 1. Create temp tables, remove select rows, add select columns
-- DROPPED COLUMNS: payment_region, organic_status
-- DROPPED DATA: all year 2019 data, ((land_use = 'EXCL' OR land_use = 'DELETED_LANDUSE') AND (land_use_area = 0 OR land_use_area IS NULL)), 
--               duplicate records from payment_region, NULL hapar_id and land_use = ' '

DROP TABLE IF EXISTS temp_permanent CASCADE;
CREATE TEMP TABLE temp_permanent AS 
WITH subq AS
    (SELECT mlc_hahol_id,
            habus_id,
            hahol_id,
            hapar_id,
            land_parcel_area,
            verified_exclusion,
            bps_eligible_area,
            land_activity,
            organic_status,
            land_use,
            land_use_area,
            land_leased_out,
            lfass,
            bps_claimed_area,
            application_status,
            payment_region,
            is_perm_flag,
            year,
            claim_id_p,
            ROW_NUMBER () OVER (PARTITION BY mlc_hahol_id,
                                             habus_id,
                                             hahol_id,
                                             hapar_id,
                                             land_parcel_area,
                                             verified_exclusion,
                                             bps_eligible_area,
                                             land_activity,
                                             organic_status,
                                             land_use,
                                             land_use_area,
                                             lfass,
                                             bps_claimed_area,
                                             application_status,
                                             is_perm_flag,
                                             year
                                ORDER BY mlc_hahol_id,
                                         habus_id,
                                         hahol_id,
                                         hapar_id,
                                         land_parcel_area,
                                         verified_exclusion,
                                         bps_eligible_area,
                                         land_activity,
                                         organic_status,
                                         land_use,
                                         land_use_area,
                                         lfass,
                                         bps_claimed_area,
                                         application_status,
                                         is_perm_flag,
                                         year) row_num
     FROM rpid.saf_permanent_land_parcels_deliv20190911)
SELECT mlc_hahol_id,
       habus_id,
       hahol_id,
       hapar_id,
       land_parcel_area,
       ABS(bps_eligible_area) AS bps_eligible_area, -- fixes 11 rows
       bps_claimed_area,
       verified_exclusion,
       ABS(land_use_area) AS land_use_area, -- fixes 2 rows
       land_use,
       land_activity,
       application_status,
       land_leased_out,
       lfass AS lfass_flag,
       is_perm_flag,
       claim_id_p,
       YEAR
FROM subq
WHERE row_num < 2 -- removes 55,250 rows
    AND hapar_id IS NOT NULL -- removes 609 rows
    AND land_use <> '' -- removes 1,761 rows
    AND year <> 2019 -- removes 681,711 ROWS
    AND application_status NOT LIKE '%Wait%'; --removes 35,966 rows 

DELETE
FROM temp_permanent
WHERE (land_use = 'EXCL'
        OR land_use = 'DELETED_LANDUSE')
       AND (land_use_area = 0
            OR land_use_area IS NULL); -- removes 720,741 rows

ALTER TABLE temp_permanent ADD change_note VARCHAR;
---------------------------------------------------------------------1,898,643 in temp_permanent

DROP TABLE IF EXISTS temp_seasonal CASCADE;
CREATE TEMP TABLE temp_seasonal AS 
WITH subq AS
    (SELECT mlc_hahol_id,
            habus_id,
            hahol_id,
            hapar_id,
            land_parcel_area,
            verified_exclusion,
            bps_eligible_area,
            land_activity,
            organic_status,
            land_use,
            land_use_area,
            land_leased_out,
            lfass,
            bps_claimed_area,
            application_status,
            payment_region,
            is_perm_flag,
            year,
            claim_id_s,
            ROW_NUMBER () OVER (PARTITION BY mlc_hahol_id,
                                             habus_id,
                                             hahol_id,
                                             hapar_id,
                                             land_parcel_area,
                                             verified_exclusion,
                                             bps_eligible_area,
                                             land_activity,
                                             organic_status,
                                             land_use,
                                             land_use_area,
                                             land_leased_out,
                                             lfass,
                                             bps_claimed_area,
                                             application_status,
                                             is_perm_flag,
                                             year
                                ORDER BY mlc_hahol_id,
                                         habus_id,
                                         hahol_id,
                                         hapar_id,
                                         land_parcel_area,
                                         verified_exclusion,
                                         bps_eligible_area,
                                         land_activity,
                                         organic_status,
                                         land_use,
                                         land_use_area,
                                         land_leased_out,
                                         lfass,
                                         bps_claimed_area,
                                         application_status,
                                         is_perm_flag,
                                         year) row_num
     FROM rpid.saf_seasonal_land_parcels_deliv20190911)
SELECT mlc_hahol_id,
       habus_id,
       hahol_id,
       hapar_id,
       land_parcel_area,
       ABS(bps_eligible_area) AS bps_eligible_area, -- fixes 1 row
       bps_claimed_area,
       verified_exclusion,
       ABS(land_use_area) AS land_use_area, -- fixes 0 rows
       land_use,
       land_activity,
       application_status,
       land_leased_out,
       lfass AS lfass_flag,
       is_perm_flag,
       claim_id_s,
       YEAR
FROM subq
WHERE row_num < 2 -- removes 4,362 rows
    AND hapar_id IS NOT NULL -- removes 35 rows
    AND land_use <> '' -- removes 707 rows
    AND year <> 2019 -- removes 30,403 rows
    AND application_status NOT LIKE '%Wait%'; -- removes 2,939 rows

DELETE
FROM temp_seasonal
WHERE (land_use = 'EXCL'
        OR land_use = 'DELETED_LANDUSE')
       AND (land_use_area = 0
            OR land_use_area IS NULL); -- removes 76,649 rows

ALTER TABLE temp_seasonal ADD change_note VARCHAR;
---------------------------------------------------------------------173,252 in temp_seasonal

--recast claim_id column to accept multiple values
ALTER TABLE temp_permanent 
ALTER COLUMN claim_id_p TYPE VARCHAR;

ALTER TABLE temp_seasonal
ALTER COLUMN claim_id_s TYPE VARCHAR;

--rename claim_id_p/s so no problems with unique ids between tables
UPDATE temp_permanent 
SET claim_id_p = 'P' || claim_id_p
WHERE claim_id_p NOT LIKE '%P%';

UPDATE temp_seasonal 
SET claim_id_s = 'S' || claim_id_s
WHERE claim_id_s NOT LIKE '%S%';

--*Step 2. Fix land_parcel_area IS NULL or 0
--infer land_parcel_area where same hapar_id
UPDATE temp_permanent AS t
SET land_parcel_area = sub.land_parcel_area,
    change_note = CONCAT(t.change_note, 'land_parcel_area inferred from same hapar_id; ')
FROM
    (SELECT *
     FROM temp_permanent
     WHERE land_parcel_area IS NOT NULL
         OR land_parcel_area <> 0) sub
WHERE t.hapar_id = sub.hapar_id
    AND t.land_parcel_area IS NULL; -- updates 3 rows

UPDATE temp_seasonal AS t
SET land_parcel_area = sub.land_parcel_area,
    change_note = CONCAT(t.change_note, 'land_parcel_area inferred from same hapar_id; ')
FROM
    (SELECT *
     FROM temp_seasonal
     WHERE land_parcel_area IS NOT NULL
         OR land_parcel_area <> 0) sub
WHERE t.hapar_id = sub.hapar_id
    AND t.land_parcel_area IS NULL; -- updates 5 rows

--infer land_parcel_area from land_use_area in same row
UPDATE temp_permanent
SET land_parcel_area = land_use_area,
    change_note = CONCAT(change_note, 'land_parcel_area inferred from land_use_area in single claim row; ')
WHERE land_parcel_area IS NULL; -- updates 13 rows

UPDATE temp_seasonal
SET land_parcel_area = land_use_area,
    change_note = CONCAT(change_note, 'land_parcel_area inferred from land_use_area in single claim row; ')
WHERE land_parcel_area IS NULL; -- updates 1 rows

--delete where land_parcel_area IS NULL/0 AND land_use_area = 0
DELETE
FROM temp_permanent
WHERE (land_parcel_area IS NULL
       AND land_use_area = 0)
    OR (land_parcel_area = 0
        AND land_use_area =0); -- deletes 19 rows

DELETE
FROM temp_seasonal
WHERE (land_parcel_area IS NULL
       AND land_use_area = 0)
    OR (land_parcel_area = 0
        AND land_use_area =0); -- deletes 1 rows

--*Step 3. Fix land_use_area IS NULL or 0 
--copy land_parcel_area for single claims where land_parcel_area = bps_eligible_area
WITH sub AS
    (SELECT hapar_id,
            year
     FROM
         (SELECT hapar_id,
                 year,
                 COUNT(land_use) as lu_count,
                 SUM(land_use_area) as sum_lu
          FROM temp_permanent AS tp
          GROUP BY hapar_id,
                   year) foo
     WHERE lu_count = 1
         AND (sum_lu = 0 OR sum_lu IS NULL))
UPDATE temp_permanent
SET land_use_area = p.land_parcel_area,
    change_note = CONCAT(p.change_note, 'land_use_area inferred where land_parcel_area = bps_eligible_area for single claims; ')
FROM sub
JOIN temp_permanent AS p USING (hapar_id,
                                year)
WHERE temp_permanent.hapar_id = sub.hapar_id
    AND temp_permanent.year = sub.year
    AND temp_permanent.land_parcel_area = temp_permanent.bps_eligible_area; -- updates 688 rows

WITH sub AS
    (SELECT hapar_id,
            year
     FROM
         (SELECT hapar_id,
                 year,
                 COUNT(land_use) as lu_count,
                 SUM(land_use_area) as sum_lu
          FROM temp_seasonal AS ts
          GROUP BY hapar_id,
                   year) foo
     WHERE lu_count = 1
         AND (sum_lu = 0 OR sum_lu IS NULL))
UPDATE temp_seasonal
SET land_use_area = s.land_parcel_area,
    change_note = CONCAT(s.change_note, 'land_use_area inferred where land_parcel_area = bps_eligible_area for single claims; ')
FROM sub
JOIN temp_seasonal AS s USING (hapar_id,
                                year)
WHERE temp_seasonal.hapar_id = sub.hapar_id
    AND temp_seasonal.year = sub.year
    AND temp_seasonal.land_parcel_area = temp_seasonal.bps_eligible_area; -- updates 842 rows 

-- update NULL/0 land_use_areas with inferred values from other years whre same land_use
WITH sub1 AS
    (SELECT *
     FROM
         (SELECT hapar_id,
                 sum(land_use_area) OVER(PARTITION BY hapar_id, year) AS sum_lua,
                 land_use,
                 year
          FROM temp_permanent) foo
     WHERE sum_lua IS NULL),
     sub2 AS
    (SELECT hapar_id,
            land_use,
            p.land_use_area AS fix_lu
     FROM sub1
     JOIN temp_permanent AS p USING (hapar_id,
                                     land_use)
     WHERE p.land_use_area IS NOT NULL
     GROUP BY hapar_id,
              land_use,
              p.land_use_area
     ORDER BY hapar_id)
UPDATE temp_permanent AS p
SET land_use_area = fix_lu,
    change_note = CONCAT(p.change_note, 'land_use_area inferred from other year where same land_use; ')
FROM temp_permanent
JOIN sub2 USING (hapar_id,
                 land_use)
WHERE p.hapar_id = sub2.hapar_id
    AND p.land_use = sub2.land_use
    AND (p.land_use_area IS NULL
         OR p.land_use_area = 0); -- updates 73 rows

WITH sub1 AS
    (SELECT *
     FROM
         (SELECT hapar_id,
                 sum(land_use_area) OVER(PARTITION BY hapar_id, year) AS sum_lua,
                 land_use,
                 year
          FROM temp_seasonal) foo
     WHERE sum_lua IS NULL),
     sub2 AS
    (SELECT hapar_id,
            land_use,
            s.land_use_area AS fix_lu
     FROM sub1
     JOIN temp_seasonal AS s USING (hapar_id,
                                    land_use)
     WHERE s.land_use_area IS NOT NULL
     GROUP BY hapar_id,
              land_use,
              s.land_use_area
     ORDER BY hapar_id)
UPDATE temp_seasonal AS s
SET land_use_area = fix_lu,
    change_note = CONCAT(s.change_note, 'land_use_area inferred from other year where same land_use; ')
FROM temp_seasonal
JOIN sub2 USING (hapar_id,
                 land_use)
WHERE s.hapar_id = sub2.hapar_id
    AND s.land_use = sub2.land_use
    AND (s.land_use_area IS NULL
         OR s.land_use_area = 0); -- updates 113 rows 

--adjust land_use_area to match bps_claimed_area
UPDATE temp_permanent
SET land_use_area = bps_claimed_area,
    change_note = CONCAT(change_note, 'adjust land_use_area to match bps_claimed_area; ')
WHERE bps_claimed_area <> land_use_area
    AND bps_claimed_area <> 0
    AND bps_claimed_area < land_parcel_area; -- updates 183,590 rows

UPDATE temp_seasonal
SET land_use_area = bps_claimed_area,
    change_note = CONCAT(change_note, 'adjust land_use_area to match bps_claimed_area; ')
WHERE bps_claimed_area <> land_use_area
    AND bps_claimed_area <> 0
    AND bps_claimed_area < land_parcel_area;; -- updates 21,194 rows

--delete remaining NULL land_use_area
DELETE FROM 
temp_permanent 
WHERE land_use_area IS NULL; --deletes 349 rows 

DELETE FROM 
temp_seasonal
WHERE land_use_area IS NULL; --deletes 1,168 rows

--*STEP 4. Find renter records in wrong tables 
--finds multiple businesses claiming on same land in same table and marks them as either owner/renter
WITH mult_busses AS
    (SELECT *
     FROM
         (SELECT mlc_hahol_id,
                 habus_id,
                 hahol_id,
                 hapar_id,
                 YEAR,
                 ROW_NUMBER () OVER (PARTITION BY hapar_id,
                                                  YEAR)
          FROM temp_permanent
          GROUP BY mlc_hahol_id,
                   habus_id,
                   hahol_id,
                   hapar_id,
                   YEAR) foo
     WHERE ROW_NUMBER > 1),
     bps_claim AS
    (SELECT mlc_hahol_id,
            habus_id,
            hahol_id,
            hapar_id,
            year,
            SUM(bps_claimed_area) AS sum_bps
     FROM temp_permanent
     GROUP BY mlc_hahol_id,
              habus_id,
              hahol_id,
              hapar_id,
              year)
UPDATE temp_permanent AS t
SET claim_id_p = 'S' || TRIM('P'
                             FROM t.claim_id_p) || '-01',
    is_perm_flag = 'N',
    change_note = CONCAT(t.change_note, 'S record moved from permanent to seasonal sheet; ')
FROM temp_permanent AS a
JOIN mult_busses USING (mlc_hahol_id,
                        habus_id,
                        hahol_id,
                        hapar_id,
                        year)
JOIN bps_claim USING (mlc_hahol_id,
                      habus_id,
                      hahol_id,
                      hapar_id,
                      year)
WHERE sum_bps <> 0
    AND t.land_leased_out = 'N'
    AND t.mlc_hahol_id = a.mlc_hahol_id
    AND t.habus_id = a.habus_id
    AND t.hahol_id = a.hahol_id
    AND t.hapar_id = a.hapar_id
    AND t.year = a.year; --updates 49 rows

WITH mult_busses AS
    (SELECT *
     FROM
         (SELECT mlc_hahol_id,
                 habus_id,
                 hahol_id,
                 hapar_id,
                 YEAR,
                 ROW_NUMBER () OVER (PARTITION BY hapar_id,
                                                  YEAR)
          FROM temp_seasonal
          GROUP BY mlc_hahol_id,
                   habus_id,
                   hahol_id,
                   hapar_id,
                   YEAR) foo
     WHERE ROW_NUMBER > 1),
     bps_claim AS
    (SELECT mlc_hahol_id,
            habus_id,
            hahol_id,
            hapar_id,
            year,
            SUM(bps_claimed_area) AS sum_bps
     FROM temp_seasonal
     GROUP BY mlc_hahol_id,
              habus_id,
              hahol_id,
              hapar_id,
              year)
UPDATE temp_seasonal AS t
SET land_leased_out = (CASE
                           WHEN t.land_use <> 'EXCL' THEN 'Y'
                           ELSE t.land_leased_out
                       END),
    claim_id_s = 'P' || TRIM('S'
                                  from t.claim_id_s) || '-01',
    is_perm_flag = 'Y',
    change_note = CONCAT(t.change_note, 'P record moved from seasonal to permanent sheet; ')
FROM temp_seasonal AS a
JOIN mult_busses USING (mlc_hahol_id,
                        habus_id,
                        hahol_id,
                        hapar_id,
                        year)
JOIN bps_claim USING (mlc_hahol_id,
                      habus_id,
                      hahol_id,
                      hapar_id,
                      year)
WHERE sum_bps = 0
    AND t.mlc_hahol_id = a.mlc_hahol_id
    AND t.habus_id = a.habus_id
    AND t.hahol_id = a.hahol_id
    AND t.hapar_id = a.hapar_id
    AND t.year = a.year; --updates 1,134 rows

--moves marked records to respective tables
INSERT INTO temp_permanent 
SELECT * 
FROM temp_seasonal 
WHERE claim_id_s LIKE '%P%';
DELETE FROM temp_seasonal 
WHERE claim_id_s LIKE '%P%'; --moves 1,134 rows

INSERT INTO temp_seasonal 
SELECT * 
FROM temp_permanent 
WHERE claim_id_p LIKE '%S%';
DELETE FROM temp_permanent 
WHERE claim_id_p LIKE '%S%'; -- moves 49 rows

--finds swapped owner/renters (owners in seasonal table and renters in permanent table that join on hapar_id, year, land_use, land_use_area) 
WITH find_switches AS
    (SELECT hapar_id,
            YEAR
     FROM
         (SELECT hapar_id,
                 YEAR,
                 SUM(owner_bps_claimed_area) AS owner_bps,
                 SUM(user_bps_claimed_area) AS user_bps
          FROM
              (SELECT hapar_id,
                      p.bps_claimed_area AS owner_bps_claimed_area,
                      s.bps_claimed_area AS user_bps_claimed_area,
                      year
               FROM temp_permanent AS p
               JOIN temp_seasonal AS s USING (hapar_id,
                                              year,
                                              land_use,
                                              land_use_area)) foo
          GROUP BY hapar_id,
                   YEAR) foo2
     WHERE owner_bps <> 0
         AND user_bps = 0)
UPDATE temp_permanent AS t
SET land_leased_out = (CASE
                           WHEN t.land_use <> 'EXCL' THEN 'Y'
                           ELSE t.land_leased_out
                       END),
    claim_id_p = 'S' || TRIM('P'
                             FROM t.claim_id_p) || '-01',
    is_perm_flag = 'N',
    change_note = CONCAT(t.change_note, 'S record moved from permanent to seasonal sheet; ')
FROM find_switches AS a
JOIN temp_permanent AS b USING (hapar_id,
                                year)
WHERE t.hapar_id = a.hapar_id
    AND t.land_leased_out = 'N'
    AND t.year = a.year; --updates 4,929 rows

WITH find_switches AS
    (SELECT hapar_id,
            YEAR
     FROM
         (SELECT hapar_id,
                 YEAR,
                 sum(owner_bps_claimed_area) AS owner_bps,
                 sum(user_bps_claimed_area) AS user_bps
          FROM
              (SELECT hapar_id,
                      p.bps_claimed_area AS owner_bps_claimed_area,
                      s.bps_claimed_area AS user_bps_claimed_area,
                      year
               FROM temp_permanent AS p
               JOIN temp_seasonal AS s USING (hapar_id,
                                              year,
                                              land_use,
                                              land_use_area)) foo
          GROUP BY hapar_id,
                   YEAR) foo2
     WHERE owner_bps <> 0
         AND user_bps = 0)
UPDATE temp_seasonal AS t
SET land_leased_out = (CASE
                           WHEN t.land_use <> 'EXCL' THEN 'Y'
                           ELSE t.land_leased_out
                       END),
    claim_id_s = 'P' || TRIM('S'
                             from t.claim_id_s) || '-01',
    is_perm_flag = 'Y',
    change_note = CONCAT(t.change_note, 'P record moved from seasonal to permanent sheet; ')
FROM find_switches AS a
JOIN temp_seasonal AS b USING (hapar_id,
                               year)
WHERE t.hapar_id = a.hapar_id
    AND t.year = a.year; -- updates 4,924 rows  

--moves marked records to respective tables
INSERT INTO temp_permanent 
SELECT * 
FROM temp_seasonal 
WHERE claim_id_s LIKE '%P%';
DELETE FROM temp_seasonal 
WHERE claim_id_s LIKE '%P%'; --moves 4,924 rows

INSERT INTO temp_seasonal 
SELECT * 
FROM temp_permanent 
WHERE claim_id_p LIKE '%S%';
DELETE FROM temp_permanent 
WHERE claim_id_p LIKE '%S%'; -- moves 4,929 rows 

--*STEP 5. Combine mutually exclusive
--move mutually exclusive hapar_ids to separate table 
DROP TABLE IF EXISTS combine; 
SELECT mlc_hahol_id AS owner_mlc_hahol_id,
       NULL :: BIGINT AS user_mlc_hahol_id,
       habus_id AS owner_habus_id,
       NULL :: BIGINT AS user_habus_id,
       hahol_id AS owner_hahol_id,
       NULL :: BIGINT AS user_hahol_id,
       hapar_id,
       land_parcel_area AS owner_land_parcel_area,
       NULL :: BIGINT AS user_land_parcel_area,
       bps_eligible_area AS owner_bps_eligible_area,
       NULL :: BIGINT AS user_bps_eligible_area,
       bps_claimed_area AS owner_bps_claimed_area,
       NULL :: BIGINT AS user_bps_claimed_area,
       verified_exclusion AS owner_verified_exclusion,
       NULL :: BIGINT AS user_verified_exclusion,
       land_use_area AS owner_land_use_area,
       NULL :: BIGINT AS user_land_use_area,
       land_use AS owner_land_use,
       NULL :: VARCHAR AS user_land_use,
       land_activity AS owner_land_activity,
       NULL :: VARCHAR AS user_land_activity,
       application_status AS owner_application_status,
       NULL :: VARCHAR AS user_application_status,
       land_leased_out,
       lfass_flag AS owner_lfass_flag,
       NULL :: VARCHAR AS user_lfass_flag,
       claim_id_p AS claim_id,
       year,
       change_note INTO TEMP TABLE combine
FROM temp_permanent
WHERE hapar_id NOT IN
        (SELECT DISTINCT hapar_id
         FROM temp_seasonal); 
DELETE
FROM temp_permanent AS t USING combine
WHERE t.hapar_id = combine.hapar_id; --moves 1,802,432 rows

INSERT INTO combine 
SELECT NULL :: BIGINT AS owner_mlc_hahol_id,
       mlc_hahol_id AS user_mlc_hahol_id,
       NULL :: BIGINT AS owner_habus_id,
       habus_id AS user_habus_id,
       NULL :: BIGINT AS owner_hahol_id,
       hahol_id AS user_hahol_id,
       hapar_id,
       NULL :: BIGINT AS owner_land_parcel_area, 
       land_parcel_area AS user_land_parcel_area,
       NULL :: BIGINT AS owner_bps_eligible_area,
       bps_eligible_area AS user_bps_eligible_area,
       NULL :: BIGINT AS owner_bps_claimed_area,
       bps_claimed_area AS user_bps_claimed_area,
       NULL :: BIGINT AS owner_verified_exclusion,
       verified_exclusion AS user_verified_exclusion,
       NULL :: BIGINT AS owner_land_use_area,
       land_use_area AS user_land_use_area,
       NULL :: VARCHAR AS owner_land_use,
       land_use AS user_land_use,
       NULL :: VARCHAR AS owner_land_activity,
       land_activity AS user_land_activity,
       NULL :: VARCHAR AS owner_application_status,
       application_status AS user_application_status,
       land_leased_out,
       NULL :: VARCHAR AS owner_lfass_flag,
       lfass_flag AS user_lfass_flag,
       claim_id_s AS claim_id,
       year,
       change_note
FROM temp_seasonal 
WHERE hapar_id NOT IN
        (SELECT DISTINCT hapar_id
         FROM temp_permanent); 
DELETE
FROM temp_seasonal AS t USING combine
WHERE t.hapar_id = combine.hapar_id; --move 93,752 rows

--*Step 6. Join
--first join on hapar_id, year, land_use, land_use_area
DROP TABLE IF EXISTS joined; 
SELECT p.mlc_hahol_id AS owner_mlc_hahol_id,
       s.mlc_hahol_id AS user_mlc_hahol_id,
       p.habus_id AS owner_habus_id,
       s.habus_id AS user_habus_id,
       p.hahol_id AS owner_hahol_id,
       s.hahol_id AS user_hahol_id,
       hapar_id,
       p.land_parcel_area AS owner_land_parcel_area,
       s.land_parcel_area AS user_land_parcel_area,
       p.bps_eligible_area AS owner_bps_eligible_area,
       s.bps_eligible_area AS user_bps_eligible_area,
       p.bps_claimed_area AS owner_bps_claimed_area,
       s.bps_claimed_area AS user_bps_claimed_area,
       p.verified_exclusion AS owner_verified_exclusion,
       s.verified_exclusion AS user_verified_exclusion,
       p.land_use_area AS owner_land_use_area,
       s.land_use_area AS user_land_use_area,
       p.land_use AS owner_land_use,
       s.land_use AS user_land_use,
       p.land_activity AS owner_land_activity,
       s.land_activity AS user_land_activity,
       p.application_status AS owner_application_status,
       s.application_status AS user_application_status,
       'Y' AS land_leased_out,
       p.lfass_flag AS owner_lfass_flag,
       s.lfass_flag AS user_lfass_flag,
       CONCAT(claim_id_p, ', ', claim_id_s) AS claim_id,
       year,
       CASE
           WHEN p.change_note IS NOT NULL
                AND s.change_note IS NOT NULL THEN CONCAT(p.change_note, s.change_note, 'first join; ')
           WHEN p.change_note IS NULL
                AND s.change_note IS NOT NULL THEN CONCAT(s.change_note, 'first join; ')
           WHEN s.change_note IS NULL
                AND p.change_note IS NOT NULL THEN CONCAT(p.change_note, 'first join; ')
           WHEN p.change_note IS NULL
                AND s.change_note IS NULL THEN 'first join; '
       END AS change_note INTO TEMP TABLE joined
FROM temp_permanent AS p
JOIN temp_seasonal AS s USING (hapar_id,
                               year,
                               land_use,
                               land_use_area); --38,629 rows

--delete from original table where join above
WITH joined_ids AS (
SELECT SPLIT_PART(claim_id, ', ', 1) AS claim_id_p,
       SPLIT_PART(claim_id, ', ', 2) AS claim_id_s
FROM joined)
DELETE 
FROM temp_permanent AS t USING joined_ids AS a  
WHERE t.claim_id_p = a.claim_id_p; -- 38,341 rows 

WITH joined_ids AS (
SELECT SPLIT_PART(claim_id, ', ', 1) AS claim_id_p,
       SPLIT_PART(claim_id, ', ', 2) AS claim_id_s
FROM joined)
DELETE 
FROM temp_seasonal AS t USING joined_ids AS a  
WHERE t.claim_id_s = a.claim_id_s; --38,234 rows 

--second join on hapar_id, year, land_use 
INSERT INTO joined 
SELECT p.mlc_hahol_id AS owner_mlc_hahol_id,
       s.mlc_hahol_id AS user_mlc_hahol_id,
       p.habus_id AS owner_habus_id,
       s.habus_id AS user_habus_id,
       p.hahol_id AS owner_hahol_id,
       s.hahol_id AS user_hahol_id,
       hapar_id,
       p.land_parcel_area AS owner_land_parcel_area,
       s.land_parcel_area AS user_land_parcel_area,
       p.bps_eligible_area AS owner_bps_eligible_area,
       s.bps_eligible_area AS user_bps_eligible_area,
       p.bps_claimed_area AS owner_bps_claimed_area,
       s.bps_claimed_area AS user_bps_claimed_area,
       p.verified_exclusion AS owner_verified_exclusion,
       s.verified_exclusion AS user_verified_exclusion,
       p.land_use_area AS owner_land_use_area,
       s.land_use_area AS user_land_use_area,
       p.land_use AS owner_land_use,
       s.land_use AS user_land_use,
       p.land_activity AS owner_land_activity,
       s.land_activity AS user_land_activity,
       p.application_status AS owner_application_status,
       s.application_status AS user_application_status,
       p.land_leased_out,
       p.lfass_flag AS owner_lfass_flag,
       s.lfass_flag AS user_lfass_flag,
       CONCAT(claim_id_p, ', ', claim_id_s) AS claim_id,
       year,
       CASE
           WHEN p.change_note IS NOT NULL
                AND s.change_note IS NOT NULL THEN CONCAT(p.change_note, s.change_note, 'second join; ')
           WHEN p.change_note IS NULL
                AND s.change_note IS NOT NULL THEN CONCAT(s.change_note, 'second join; ')
           WHEN s.change_note IS NULL
                AND p.change_note IS NOT NULL THEN CONCAT(p.change_note, 'second join; ')
           WHEN p.change_note IS NULL
                AND s.change_note IS NULL THEN 'second join; '
       END AS change_note 
FROM temp_permanent AS p
JOIN temp_seasonal AS s USING (hapar_id,
                               year,
                               land_use); --12,266 rows

--delete from original table where join above
WITH joined_ids AS (
SELECT SPLIT_PART(claim_id, ', ', 1) AS claim_id_p,
       SPLIT_PART(claim_id, ', ', 2) AS claim_id_s
FROM joined)
DELETE 
FROM temp_permanent AS t USING joined_ids AS a  
WHERE t.claim_id_p = a.claim_id_p; -- 12,056 rows 

WITH joined_ids AS (
SELECT SPLIT_PART(claim_id, ', ', 1) AS claim_id_p,
       SPLIT_PART(claim_id, ', ', 2) AS claim_id_s
FROM joined)
DELETE 
FROM temp_seasonal AS t USING joined_ids AS a  
WHERE t.claim_id_s = a.claim_id_s; --12,068 rows 

--third join on hapar_id, year, land_use_area
INSERT INTO joined 
SELECT p.mlc_hahol_id AS owner_mlc_hahol_id,
       s.mlc_hahol_id AS user_mlc_hahol_id,
       p.habus_id AS owner_habus_id,
       s.habus_id AS user_habus_id,
       p.hahol_id AS owner_hahol_id,
       s.hahol_id AS user_hahol_id,
       hapar_id,
       p.land_parcel_area AS owner_land_parcel_area,
       s.land_parcel_area AS user_land_parcel_area,
       p.bps_eligible_area AS owner_bps_eligible_area,
       s.bps_eligible_area AS user_bps_eligible_area,
       p.bps_claimed_area AS owner_bps_claimed_area,
       s.bps_claimed_area AS user_bps_claimed_area,
       p.verified_exclusion AS owner_verified_exclusion,
       s.verified_exclusion AS user_verified_exclusion,
       p.land_use_area AS owner_land_use_area,
       s.land_use_area AS user_land_use_area,
       p.land_use AS owner_land_use,
       s.land_use AS user_land_use,
       p.land_activity AS owner_land_activity,
       s.land_activity AS user_land_activity,
       p.application_status AS owner_application_status,
       s.application_status AS user_application_status,
       p.land_leased_out,
       p.lfass_flag AS owner_lfass_flag,
       s.lfass_flag AS user_lfass_flag,
       CONCAT(claim_id_p, ', ', claim_id_s) AS claim_id,
       year,
       CASE
           WHEN p.change_note IS NOT NULL
                AND s.change_note IS NOT NULL THEN CONCAT(p.change_note, s.change_note, 'third join; ')
           WHEN p.change_note IS NULL
                AND s.change_note IS NOT NULL THEN CONCAT(s.change_note, 'third join; ')
           WHEN s.change_note IS NULL
                AND p.change_note IS NOT NULL THEN CONCAT(p.change_note, 'third join; ')
           WHEN p.change_note IS NULL
                AND s.change_note IS NULL THEN 'third join; '
       END AS change_note 
FROM temp_permanent AS p
JOIN temp_seasonal AS s USING (hapar_id,
                               year,
                               land_use_area); --3,401 rows

--delete from original table where join above
WITH joined_ids AS (
SELECT SPLIT_PART(claim_id, ', ', 1) AS claim_id_p,
       SPLIT_PART(claim_id, ', ', 2) AS claim_id_s
FROM joined)
DELETE 
FROM temp_permanent AS t USING joined_ids AS a  
WHERE t.claim_id_p = a.claim_id_p; -- 3,398 rows

WITH joined_ids AS (
SELECT SPLIT_PART(claim_id, ', ', 1) AS claim_id_p,
       SPLIT_PART(claim_id, ', ', 2) AS claim_id_s
FROM joined)
DELETE 
FROM temp_seasonal AS t USING joined_ids AS a  
WHERE t.claim_id_s = a.claim_id_s; --3,400 rows 

--fourth join on hapar_id, year (but not on EXCL land_uses and only on p.land_leased_out = 'Y')
INSERT INTO joined 
SELECT p.mlc_hahol_id AS owner_mlc_hahol_id,
       s.mlc_hahol_id AS user_mlc_hahol_id,
       p.habus_id AS owner_habus_id,
       s.habus_id AS user_habus_id,
       p.hahol_id AS owner_hahol_id,
       s.hahol_id AS user_hahol_id,
       hapar_id,
       p.land_parcel_area AS owner_land_parcel_area,
       s.land_parcel_area AS user_land_parcel_area,
       p.bps_eligible_area AS owner_bps_eligible_area,
       s.bps_eligible_area AS user_bps_eligible_area,
       p.bps_claimed_area AS owner_bps_claimed_area,
       s.bps_claimed_area AS user_bps_claimed_area,
       p.verified_exclusion AS owner_verified_exclusion,
       s.verified_exclusion AS user_verified_exclusion,
       p.land_use_area AS owner_land_use_area,
       s.land_use_area AS user_land_use_area,
       p.land_use AS owner_land_use,
       s.land_use AS user_land_use,
       p.land_activity AS owner_land_activity,
       s.land_activity AS user_land_activity,
       p.application_status AS owner_application_status,
       s.application_status AS user_application_status,
       p.land_leased_out,
       p.lfass_flag AS owner_lfass_flag,
       s.lfass_flag AS user_lfass_flag,
       CONCAT(claim_id_p, ', ', claim_id_s) AS claim_id,
       year,
       CASE
           WHEN p.change_note IS NOT NULL
                AND s.change_note IS NOT NULL THEN CONCAT(p.change_note, s.change_note, 'fourth join; ')
           WHEN p.change_note IS NULL
                AND s.change_note IS NOT NULL THEN CONCAT(s.change_note, 'fourth join; ')
           WHEN s.change_note IS NULL
                AND p.change_note IS NOT NULL THEN CONCAT(p.change_note, 'fourth join; ')
           WHEN p.change_note IS NULL
                AND s.change_note IS NULL THEN 'fourth join; '
       END AS change_note
FROM temp_permanent AS p
JOIN temp_seasonal AS s USING (hapar_id,
                               year)
WHERE p.land_use NOT IN
        (SELECT land_use
         FROM excl)
    AND s.land_use NOT IN
        (SELECT land_use
         FROM excl)
    AND p.land_leased_out = 'Y'; --1,341 rows

--delete from original table where join above
WITH joined_ids AS (
SELECT SPLIT_PART(claim_id, ', ', 1) AS claim_id_p,
       SPLIT_PART(claim_id, ', ', 2) AS claim_id_s
FROM joined)
DELETE 
FROM temp_permanent AS t USING joined_ids AS a  
WHERE t.claim_id_p = a.claim_id_p; -- 1,807 rows 

WITH joined_ids AS (
SELECT SPLIT_PART(claim_id, ', ', 1) AS claim_id_p,
       SPLIT_PART(claim_id, ', ', 2) AS claim_id_s
FROM joined)
DELETE 
FROM temp_seasonal AS t USING joined_ids AS a  
WHERE t.claim_id_s = a.claim_id_s; --1,972 rows 

--*STEP 7. Clean up 
--move leftover mutually exclusive ones to diff tables 
INSERT INTO combine
SELECT mlc_hahol_id AS owner_mlc_hahol_id,
       NULL :: BIGINT AS user_mlc_hahol_id,
       habus_id AS owner_habus_id,
       NULL :: BIGINT AS user_habus_id,
       hahol_id AS owner_hahol_id,
       NULL :: BIGINT AS user_hahol_id,
       hapar_id,
       land_parcel_area AS owner_land_parcel_area,
       NULL :: BIGINT AS user_land_parcel_area,
       bps_eligible_area AS owner_bps_eligible_area,
       NULL :: BIGINT AS user_bps_eligible_area,
       bps_claimed_area AS owner_bps_claimed_area,
       NULL :: BIGINT AS user_bps_claimed_area,
       verified_exclusion AS owner_verified_exclusion,
       NULL :: BIGINT AS user_verified_exclusion,
       land_use_area AS owner_land_use_area,
       NULL :: BIGINT AS user_land_use_area,
       land_use AS owner_land_use,
       NULL :: VARCHAR AS user_land_use,
       land_activity AS owner_land_activity,
       NULL :: VARCHAR AS user_land_activity,
       application_status AS owner_application_status,
       NULL :: VARCHAR AS user_application_status,
       land_leased_out,
       lfass_flag AS owner_lfass_flag,
       NULL :: VARCHAR AS user_lfass_flag,
       claim_id_p AS claim_id,
       year,
       change_note
FROM temp_permanent;  --last 41,321 rows 

INSERT INTO combine 
SELECT NULL :: BIGINT AS owner_mlc_hahol_id,
       mlc_hahol_id AS user_mlc_hahol_id,
       NULL :: BIGINT AS owner_habus_id,
       habus_id AS user_habus_id,
       NULL :: BIGINT AS owner_hahol_id,
       hahol_id AS user_hahol_id,
       hapar_id,
       NULL :: BIGINT AS owner_land_parcel_area, 
       land_parcel_area AS user_land_parcel_area,
       NULL :: BIGINT AS owner_bps_eligible_area,
       bps_eligible_area AS user_bps_eligible_area,
       NULL :: BIGINT AS owner_bps_claimed_area,
       bps_claimed_area AS user_bps_claimed_area,
       NULL :: BIGINT AS owner_verified_exclusion,
       verified_exclusion AS user_verified_exclusion,
       NULL :: BIGINT AS owner_land_use_area,
       land_use_area AS user_land_use_area,
       NULL :: VARCHAR AS owner_land_use,
       land_use AS user_land_use,
       NULL :: VARCHAR AS owner_land_activity,
       land_activity AS user_land_activity,
       NULL :: VARCHAR AS owner_application_status,
       application_status AS user_application_status,
       land_leased_out,
       NULL :: VARCHAR AS owner_lfass_flag,
       lfass_flag AS user_lfass_flag,
       claim_id_s AS claim_id,
       year,
       change_note
FROM temp_seasonal; --last 21,577 rows

DROP TABLE temp_permanent; 
DROP TABLE temp_seasonal;

--find owners based on LLO flag and bps_claimed_area and changes them from user to owner from mutually exclusive table
UPDATE combine
SET owner_mlc_hahol_id = user_mlc_hahol_id,
    user_mlc_hahol_id = NULL,
    owner_habus_id = user_habus_id,
    user_habus_id = NULL,
    owner_hahol_id = user_hahol_id,
    user_hahol_id = NULL,
    owner_land_parcel_area = user_land_parcel_area,
    user_land_parcel_area = NULL,
    owner_bps_eligible_area = user_bps_eligible_area,
    user_bps_eligible_area = NULL,
    owner_bps_claimed_area = user_bps_claimed_area,
    user_bps_claimed_area = NULL,
    owner_verified_exclusion = user_verified_exclusion,
    user_verified_exclusion = NULL,
    owner_land_use_area = user_land_use_area,
    user_land_use_area = NULL,
    owner_land_use = user_land_use,
    user_land_use = NULL,
    owner_land_activity = user_land_activity,
    user_land_activity = NULL,
    owner_application_status = user_application_status,
    user_application_status = NULL,
    owner_lfass_flag = user_lfass_flag,
    user_lfass_flag = NULL,
    claim_id = (CASE
                    WHEN claim_id LIKE '%-01' THEN 'P' || TRIM('S'
                                                               from claim_id) || TRIM(TRAILING '-01') || '-01'
                    ELSE 'P' || TRIM('S'
                                     from claim_id) || '-01'
                END),
    change_note = (CASE
                       WHEN change_note LIKE '%record%' THEN 'S record moved from seasonal to permanent sheet based on LLO yes; '
                       ELSE CONCAT(change_note, 'S record moved from seasonal to permanent sheet based on LLO yes and bps_claimed_area = 0; ')
                   END)
WHERE land_leased_out = 'Y'
    AND user_land_use IS NOT NULL
    AND user_bps_claimed_area = 0; --updates 378 records

--*Step 8. Combine ALL rows into final table
DROP TABLE IF EXISTS final;
CREATE TEMP TABLE final AS
SELECT owner_mlc_hahol_id,
       user_mlc_hahol_id,
       owner_habus_id,
       user_habus_id,
       owner_hahol_id,
       user_hahol_id,
       hapar_id,
       CASE
           WHEN owner_land_parcel_area IS NULL THEN user_land_parcel_area
           WHEN user_land_parcel_area IS NULL THEN owner_land_parcel_area
       END AS land_parcel_area,
       CASE
           WHEN owner_bps_eligible_area IS NULL THEN user_bps_eligible_area
           WHEN user_bps_eligible_area IS NULL THEN owner_bps_eligible_area
       END AS bps_eligible_area,
       owner_bps_claimed_area,
       user_bps_claimed_area,
       CASE
           WHEN owner_verified_exclusion IS NULL THEN user_verified_exclusion
           WHEN user_verified_exclusion IS NULL THEN owner_verified_exclusion
       END AS verified_exclusion,
       owner_land_use_area,
       user_land_use_area,
       owner_land_use,
       user_land_use,
       CASE
           WHEN owner_land_activity IS NULL THEN user_land_activity
           WHEN user_land_activity IS NULL THEN owner_land_activity
       END AS land_activity,
       CASE
           WHEN owner_application_status IS NULL THEN user_application_status
           WHEN user_application_status IS NULL THEN owner_application_status
       END AS application_status,
       land_leased_out,
       owner_lfass_flag,
       user_lfass_flag,
       claim_id,
       year,
       change_note
FROM combine; -- moves 1,959,082 rows

--mark rows in joined where owner_land_parcel_area <> user_land_parcel_area
UPDATE joined 
SET change_note = CONCAT(change_note, 'assume land_parcel_area = owner_land_parcel_area when owner > user; ')
WHERE owner_land_parcel_area > user_land_parcel_area; -- updates 152 rows

UPDATE joined 
SET change_note = CONCAT(change_note, 'assume land_parcel_area = user_land_parcel_area when user > owner; ')
WHERE owner_land_parcel_area < user_land_parcel_area; -- updates 165 rows

--mark rows in joined where owner_bps_eligible_area <> user_bps_eligible_area
UPDATE joined 
SET change_note = CONCAT(change_note, 'assume bps_eligible_area = owner_bps_eligible_area when owner > user; ')
WHERE owner_bps_eligible_area > user_bps_eligible_area; -- updates 162 rows

UPDATE joined 
SET change_note = CONCAT(change_note, 'assume bps_eligible_area = user_bps_eligible_area when user > owner; ')
WHERE owner_bps_eligible_area < user_bps_eligible_area; -- updates 229 rows

--mark rows in joined where owner_verified_exclusion <> user_verified_exclusion
UPDATE joined 
SET change_note = CONCAT(change_note, 'assume verified_exclusion = owner_verified_exclusion when owner > user; ')
WHERE owner_verified_exclusion > user_verified_exclusion; -- updates 1,699 rows

UPDATE joined 
SET change_note = CONCAT(change_note, 'assume verified_exclusion = user_verified_exclusion WHEN user > owner; ')
WHERE owner_verified_exclusion < user_verified_exclusion; -- updates 2,111 rows

--mark rows in joined where owner_land_activity <> user_land_activity 
UPDATE joined 
SET change_note = CONCAT(change_note, 'owner and user land_activity choice based on assumption user knows best; ')
WHERE owner_land_activity <> user_land_activity; -- updates 38,804 rows

--mark rows in joined where owner_application_status <> user_application_status
UPDATE joined
SET change_note = CONCAT(change_note, 'application status assumed under action/assessment if either owner or user; ')
WHERE (owner_application_status LIKE '%Action%'
       OR user_application_status LIKE '%Action')
    AND owner_application_status <> user_application_status; -- updates 1,048 rows

-- move joined data into last table
INSERT INTO final 
SELECT owner_mlc_hahol_id,
       user_mlc_hahol_id,
       owner_habus_id,
       user_habus_id,
       owner_hahol_id,
       user_hahol_id,
       hapar_id,
       CASE
           WHEN owner_land_parcel_area > user_land_parcel_area THEN owner_land_parcel_area
           WHEN user_land_parcel_area > owner_land_parcel_area THEN user_land_parcel_area
           ELSE owner_land_parcel_area
       END AS land_parcel_area, --changes 321 rows with than 5.77 ha change
       CASE 
            WHEN owner_bps_eligible_area > user_bps_eligible_area THEN owner_bps_eligible_area 
            WHEN user_bps_eligible_area > owner_bps_eligible_area THEN user_bps_eligible_area
            ELSE owner_bps_eligible_area
        END AS bps_eligible_area, --changes 398 rows with than 273.3 ha change
       owner_bps_claimed_area,
       user_bps_claimed_area,
       CASE 
            WHEN owner_verified_exclusion > user_verified_exclusion THEN owner_verified_exclusion
            WHEN user_verified_exclusion > owner_verified_exclusion THEN user_verified_exclusion
            ELSE owner_verified_exclusion
        END AS verified_exclusion, --changes 3,810 rows with 4,208.76 ha change
       owner_land_use_area,
       user_land_use_area,
       owner_land_use,
       user_land_use,
       CASE 
            WHEN owner_land_activity = '' THEN user_land_activity
            WHEN user_land_activity = '' THEN owner_land_activity 
            WHEN (user_land_activity = 'No Activity' OR user_land_activity = 'Unspecified') AND owner_land_activity <> '' THEN owner_land_activity
            ELSE user_land_activity
        END AS land_activity, --changes 38,804 rows 
       CASE 
            WHEN owner_application_status = user_application_status THEN owner_application_status
            WHEN owner_application_status LIKE '%Action%' AND owner_application_status <> user_application_status THEN owner_application_status
            WHEN user_application_status LIKE '%Action%' AND owner_application_status <> user_application_status THEN user_application_status 
            ELSE owner_application_status
        END AS application_status, --changes 1,048 rows
       land_leased_out,
       owner_lfass_flag,
       user_lfass_flag,
       claim_id,
       year,
       change_note
FROM joined; -- moves 56,525 rows 

--infer NON-SAF renter where LLO yes 
UPDATE final 
SET user_land_use = 'NON_SAF',
change_note = CONCAT(change_note, 'infer non-SAF renter; ')
WHERE user_habus_id IS NULL AND land_leased_out = 'Y'; --updates 7,589 rows

--infer NON-SAF owner for mutually exclusive users
UPDATE final 
SET owner_land_use = 'NON_SAF',
change_note = CONCAT(change_note, 'infer non-SAF owner; ')
WHERE owner_habus_id IS NULL; --updates 114,951 rows


