/* Remaining problems
1. Same land_use_claims in seasonal table associated with different businesses - only one with bps_claimed_area 0 and another with LLO yes          381266, 591113, 99299, 590132
2. These might be different owners/rents Different land_use claims in seasonal table associated with different businesses - only with bps_claimed_area 0 and another with LLO yes         590224, 388042, 39194, 39273
3. sum_bpc_claimed_area > land_parcel_area

*/

WITH sclaims AS
    (SELECT claim_id_s
     FROM
         (SELECT claim_id_s,
                 join_no,
                 ROW_NUMBER() OVER (PARTITION BY claim_id_s
                                    ORDER BY join_no)
          FROM
              (SELECT SPLIT_PART(claim_id, ', ', 2) AS claim_id_s,
                      LEFT(change_note, 1) AS join_no
               FROM joined) foo) bar
     WHERE ROW_NUMBER > 1
     ORDER BY ROW_NUMBER DESC)
DELETE
FROM joined
WHERE owner_land_leased_out = 'N'
    AND SPLIT_PART(claim_id, ', ', 2) IN
        (SELECT *
         FROM sclaims) AND change_note NOT LIKE '%1%'; -- removes 494 rows



SELECT * 
FROM joined 
WHERE owner_land_use IN (SELECT land_use FROM excl) AND user_bps_claimed_area <> 0         



WITH joined_ids AS (
SELECT SPLIT_PART(claim_id, ', ', 2) AS claim_id_s
FROM joined)
DELETE 
FROM temp_seasonal AS t USING joined_ids AS a  
WHERE t.claim_id_s = a.claim_id_s;

--TODO where second join exists but third join is actually real (based on owner_land_use_area = user_land_use_area) hapar_id= 13916, 18209, 18785
WITH sclaims AS
    (SELECT *
     FROM
         (SELECT claim_id_s,
                 COUNT(*)
          FROM
              (SELECT SPLIT_PART(claim_id, ', ', 2) AS claim_id_s,
                      LEFT(change_note, 1) AS join_no
               FROM joined) foo
          GROUP BY claim_id_s) bar
     WHERE COUNT > 1)
SELECT *
FROM joined
WHERE SPLIT_PART(claim_id, ', ', 2) IN
        (SELECT claim_id_s
         FROM sclaims)
    AND change_note NOT LIKE '%1%'
    AND change_note NOT LIKE '%2%'
ORDER BY hapar_id,
         year



--! these ones act good but some are owner_land_use_area + user_land_use_area = land_parcel_area 
--! need to find a way to split these up 
SELECT *
FROM joined
WHERE change_note LIKE '%4%'
    AND (owner_land_use <> 'RGR'
         AND user_land_use <> 'PGRS')
    AND (owner_land_use <> 'PGRS'
         AND user_land_use <> 'RGR')
    AND (owner_land_use NOT LIKE '%TGRS%'
         AND user_land_use NOT LIKE '%TGRS%')
    AND (owner_land_use NOT IN
             (SELECT land_use
              FROM excl)
         AND user_land_use NOT IN
             (SELECT land_use
              FROM excl))
--    AND owner_land_use <> 'OVEG'
--    AND owner_land_use <> 'ASSF'
--    AND owner_land_use <> 'BSP'
--    AND owner_land_use <> 'FALW'
--    AND owner_land_use <> 'SB'
    ORDER BY owner_land_use, user_land_use, hapar_id

--TODO   should I make all excl land_use match verified exclusion unless where separated? (about 7k in perm)
--TODO   look at LFASS flag where claim = 0

--* finds and sums difference in overclaims where bps_claimed_area > land_parcel_area for perm and seas table 
SELECT sum(land_parcel_area - bps_claimed_area)
FROM
    (SELECT hapar_id,
            year
     FROM
         (SELECT hapar_id,
                 YEAR,
                 sum_bps,
                 land_parcel_area
          FROM
              (SELECT hapar_id,
                      YEAR,
                      sum(bps_claimed_area) AS sum_bps
               FROM temp_seasonal
               GROUP BY hapar_id,
                        YEAR) foo
          JOIN temp_seasonal USING (hapar_id,
                                     YEAR)) bar
     WHERE sum_bps > land_parcel_area
     GROUP BY hapar_id,
              year) foobar
JOIN temp_seasonal USING (hapar_id,
                           year);

--* finds and sums difference in SINGLE overclaims where bps_claimed_area > land_parcel_area for joined table
SELECT hapar_id, YEAR, total_claimed_area - owner_land_parcel_area AS diff
FROM
    (SELECT hapar_id,
            YEAR,
            owner_land_parcel_area,
            user_land_parcel_area,
            owner_bps_claimed_area + user_bps_claimed_area AS total_claimed_area
     FROM joined) foo
WHERE total_claimed_area > owner_land_parcel_area
    OR total_claimed_area > user_land_parcel_area
    ORDER BY diff DESC;

SELECT * 
FROM temp_permanent
WHERE hapar_id = 40016
ORDER BY year
--* finds multiple businesses for same hapar, year
SELECT *
FROM
    (SELECT habus_id,
            hapar_id,
            YEAR,
            ROW_NUMBER() OVER (PARTITION BY hapar_id,
                                            YEAR)
     FROM temp_seasonal
     GROUP BY habus_id,
              hapar_id,
              YEAR) foo
WHERE ROW_NUMBER > 1

--! need to combine same land_use year hapar_id -- no i dont because they're separated for a reason !
WITH same_lu AS (
    SELECT *
    FROM
        ( SELECT mlc_hahol_id,
                habus_id,
                hahol_id,
                hapar_id,
                land_parcel_area,
                bps_eligible_area,
                bps_claimed_area,
                verified_exclusion,
                land_use_area,
                land_use,
                land_activity,
                application_status,
                land_leased_out,
                lfass_flag,
                is_perm_flag,
                claim_id_p,
                year,
                change_note,
                ROW_NUMBER() OVER (PARTITION BY hapar_id,
                                                land_use,
                                                year, 
                                                land_leased_out)
        FROM temp_permanent ) foo
    WHERE ROW_NUMBER > 1
)

-- run all the way up to join 
-- check hapars 1135,1144,1146,1725,1728
    SELECT mlc_hahol_id, 
           habus_id, 
           hahol_id, 
           hapar_id, 
           land_parcel_area, 
           bps_eligible_area,
           bps_claimed_area, 
           verified_exclusion, 
           land_use_area, 
           land_use, 
           land_activity, 
           application_status, 
           land_leased_out, 
           lfass_flag, 
           is_perm_flag, 
           claim_id_p, 
           year, 
           change_note, 
           ROW_NUMBER() OVER (PARTITION BY hapar_id, land_use, year)
    FROM temp_permanent
    WHERE hapar_id > 1100
ORDER BY hapar_id, year



SELECT * 
FROM temp_seasonal
WHERE verified_exclusion <> land_use_area AND land_use IN (SELECT land_use FROM excl)
ORDER BY hapar_id, year

--! Ask Doug
SELECT *
FROM FINAL
WHERE owner_land_use IN
        (SELECT land_use
         FROM excl)
    AND user_land_use IN
        (SELECT land_use
         FROM excl)
    AND user_land_use_area <> 0
    AND user_land_use <> 'EXCL'
    -- especially hapar_id = 369777 -- this one has matching hahol id
    -- with 369777 owner PGRS needs to be subdivided into PGRS and RGR
    -- the problem happens when I do second join and then delete all joined from original. I need to be able to join something again but how
    -- SO THE TRICK IS NOT TO DELETE BUT DO JOINS ANYWAY AND DELETE DUPLICATES AFTERWARD


--! Do everything by FID and not claim
--! FID level analysis, no claim level
--TODO      compare owner_bps_eligible_area and user_bps_eligible_area

--TODO check claimed_area vs land_parcel-area

--!weird case with 36 ha of BUILDING and no matching land_uses
SELECT * 
FROM rpid.saf_permanent_land_parcels_deliv20190911 splpd
WHERE hapar_id = 212811  AND YEAR = 2017
UNION 
SELECT * 
FROM rpid.saf_seasonal_land_parcels_deliv20190911 sslpd
WHERE hapar_id = 212811 AND YEAR = 2017
ORDER BY YEAR, is_perm_flag

--!last checks 
SELECT hapar_id,
owner_verified_exclusion,
user_verified_exclusion,
       CASE
           WHEN owner_verified_exclusion > user_verified_exclusion THEN owner_verified_exclusion - user_verified_exclusion
           WHEN user_verified_exclusion > owner_verified_exclusion THEN user_verified_exclusion - owner_verified_exclusion
           WHEN owner_verified_exclusion = owner_land_use_area THEN 0 
           WHEN user_verified_exclusion = user_land_use_area THEN 0 
           ELSE 9999999999           
       END AS verified_exclusion_diff,
       change_note
FROM joined
WHERE owner_verified_exclusion <> user_verified_exclusion
ORDER BY verified_exclusion_diff DESC

--!! DO THE stuff above this line

-- This code compares owner_land_parcel_area and user_land_parcel_area
--TODO
SELECT hapar_id,
       sum_owner,
       sum_user,
       CASE
           WHEN sum_owner > sum_user THEN sum_owner - sum_user
           WHEN sum_user > sum_owner THEN sum_user - sum_owner
       END AS diff,
       year
FROM
    (SELECT hapar_id,
            year,
            sum(owner_land_parcel_area) AS sum_owner,
            sum(user_land_parcel_area) AS sum_user
     FROM joined
     GROUP BY hapar_id, year) foo
WHERE sum_owner <> sum_user
ORDER BY diff DESC

-- This code compares owner_bps_eligible_area and user_bps_eligible_area
-- not a problem
SELECT hapar_id,
       sum_owner,
       sum_user,
       CASE
           WHEN sum_owner > sum_user THEN sum_owner - sum_user
           WHEN sum_user > sum_owner THEN sum_user - sum_owner
       END AS diff,
       year
FROM
    (SELECT hapar_id,
            year,
            sum(owner_bps_eligible_area) AS sum_owner,
            sum(user_bps_eligible_area) AS sum_user
     FROM joined
     GROUP BY hapar_id, year) foo
WHERE sum_owner <> sum_user
ORDER BY diff DESC

-- This code finds overclaims // sum_bpc_claimed_area > land_parcel_area
SELECT *
FROM
    (SELECT mlc_hahol_id,
            habus_id,
            hapar_id,
            year,
            land_parcel_area,
            sum(bps_claimed_area) AS sum_bps
     FROM temp_permanent
     GROUP BY mlc_hahol_id,
              habus_id,
              hapar_id,
              land_parcel_area,
              year) foo
WHERE land_parcel_area < sum_bps 

-- this code checks for instances where land_parcel_area is different from land_use_area
SELECT *
FROM
    (SELECT hapar_id,
            year,
            (owner_land_parcel_area/owner_land_use_area) AS percent_right
     FROM joined
     WHERE owner_land_use_area > owner_land_parcel_area) foo
ORDER BY percent_right 

SELECT *
FROM
    (SELECT hapar_id,
            year,
            (user_land_parcel_area/user_land_use_area) AS percent_right
     FROM joined
     WHERE user_land_use_area > user_land_parcel_area) foo
ORDER BY percent_right 

--This code checks to see if land_parcel_area is the same for each year
SELECT *
FROM
    (SELECT hapar_id,
            YEAR,
            row_number() OVER (PARTITION BY hapar_id,
                                            YEAR,
                                            user_land_parcel_area)
     FROM
         (SELECT hapar_id,
                 YEAR,
                 user_land_parcel_area
          FROM joined
          GROUP BY hapar_id,
                   YEAR,
                   user_land_parcel_area) foo) foo2
WHERE ROW_NUMBER > 1

-- This code finds duplicate land use codes  
-- not a problem
SELECT *
FROM 
    (SELECT hapar_id, 
            year, 
            COUNT(Distinct land_use) as dupes, 
            COUNT(land_use) as lu_count, 
            SUM(land_use_area) as sum_lu 
     FROM temp_seasonal 
     GROUP BY hapar_id, 
              year) foo 
WHERE dupes <> lu_count 
ORDER BY lu_count DESC, 
         dupes DESC 

--! Look at these Doug
SELECT * 
FROM temp_seasonal 
WHERE hapar_id = 85859 -- so many claims? so many businesses? also these: 83863, 242798

