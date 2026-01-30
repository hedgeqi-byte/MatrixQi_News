-- Simple SQL to delete duplicate news keeping the oldest record
-- Run this in Supabase SQL Editor

-- First, check how many duplicates you have:
WITH duplicates AS (
  SELECT 
    id,
    LOWER(TRIM(REGEXP_REPLACE(link, '^https?://', ''))) AS clean_link,
    LOWER(TRIM(REGEXP_REPLACE(title, '\s+', ' ', 'g'))) AS clean_title,
    date,
    ROW_NUMBER() OVER (
      PARTITION BY 
        CASE 
          WHEN link IS NOT NULL AND link != '' 
          THEN LOWER(TRIM(REGEXP_REPLACE(link, '^https?://', '')))
          ELSE LOWER(TRIM(REGEXP_REPLACE(title, '\s+', ' ', 'g'))) || '||' || COALESCE(date::text, '')
        END
      ORDER BY id ASC
    ) AS rn
  FROM news
)
SELECT COUNT(*) as duplicates_to_delete
FROM duplicates
WHERE rn > 1;

-- If the count looks good, run this to DELETE duplicates (keeps oldest):
WITH duplicates AS (
  SELECT 
    id,
    ROW_NUMBER() OVER (
      PARTITION BY 
        CASE 
          WHEN link IS NOT NULL AND link != '' 
          THEN LOWER(TRIM(REGEXP_REPLACE(link, '^https?://', '')))
          ELSE LOWER(TRIM(REGEXP_REPLACE(title, '\s+', ' ', 'g'))) || '||' || COALESCE(date::text, '')
        END
      ORDER BY id ASC
    ) AS rn
  FROM news
)
DELETE FROM news
WHERE id IN (
  SELECT id FROM duplicates WHERE rn > 1
);
