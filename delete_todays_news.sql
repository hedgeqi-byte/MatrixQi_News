-- SQL Queries to Delete Today's News (January 30, 2026)
-- Run these queries in Supabase SQL Editor

-- ============================================
-- OPTION 1: Delete by date string match (for "Fri, 30 Jan 2026" format)
-- ============================================

-- Step 1: First, check how many records will be deleted
SELECT COUNT(*) as records_to_delete
FROM news
WHERE date LIKE '%30 Jan 2026%'
   OR date LIKE '%Fri, 30 Jan 2026%'
   OR date LIKE '%2026-01-30%';

-- Step 2: Preview the records that will be deleted
SELECT id, title, link, date
FROM news
WHERE date LIKE '%30 Jan 2026%'
   OR date LIKE '%Fri, 30 Jan 2026%'
   OR date LIKE '%2026-01-30%'
ORDER BY id;

-- Step 3: If the preview looks correct, DELETE the records
DELETE FROM news
WHERE date LIKE '%30 Jan 2026%'
   OR date LIKE '%Fri, 30 Jan 2026%'
   OR date LIKE '%2026-01-30%';

-- ============================================
-- OPTION 2: More precise - Parse the date and match exactly
-- ============================================

-- Check records to delete (parsing RFC 2822 date format)
SELECT COUNT(*) as records_to_delete
FROM news
WHERE (
  -- Match "Fri, 30 Jan 2026" or "30 Jan 2026" anywhere in date string
  date ~ '30\s+Jan\s+2026'
  OR date ~ '2026-01-30'
  OR TO_DATE(SUBSTRING(date FROM '[0-9]{1,2}\s+[A-Za-z]{3}\s+[0-9]{4}'), 'DD Mon YYYY') = '2026-01-30'::date
);

-- Delete records (parsing RFC 2822 date format)
DELETE FROM news
WHERE (
  date ~ '30\s+Jan\s+2026'
  OR date ~ '2026-01-30'
  OR TO_DATE(SUBSTRING(date FROM '[0-9]{1,2}\s+[A-Za-z]{3}\s+[0-9]{4}'), 'DD Mon YYYY') = '2026-01-30'::date
);

-- ============================================
-- OPTION 3: Simple and safe - Match exact date string pattern
-- ============================================

-- Check records
SELECT COUNT(*) as records_to_delete, 
       MIN(id) as min_id, 
       MAX(id) as max_id
FROM news
WHERE date LIKE '%30 Jan 2026%';

-- Delete records
DELETE FROM news
WHERE date LIKE '%30 Jan 2026%';

-- ============================================
-- OPTION 4: Using date extraction (most reliable)
-- ============================================

-- Check records (extracts date part and compares)
WITH parsed_dates AS (
  SELECT 
    id,
    date,
    -- Try to extract date in format "DD Mon YYYY"
    CASE 
      WHEN date ~ '[0-9]{1,2}\s+[A-Za-z]{3}\s+[0-9]{4}' THEN
        TO_DATE(SUBSTRING(date FROM '[0-9]{1,2}\s+[A-Za-z]{3}\s+[0-9]{4}'), 'DD Mon YYYY')
      WHEN date ~ '[0-9]{4}-[0-9]{2}-[0-9]{2}' THEN
        TO_DATE(SUBSTRING(date FROM '[0-9]{4}-[0-9]{2}-[0-9]{2}'), 'YYYY-MM-DD')
      ELSE NULL
    END AS parsed_date
  FROM news
)
SELECT COUNT(*) as records_to_delete
FROM parsed_dates
WHERE parsed_date = '2026-01-30'::date;

-- Delete records using date extraction
WITH parsed_dates AS (
  SELECT 
    id,
    CASE 
      WHEN date ~ '[0-9]{1,2}\s+[A-Za-z]{3}\s+[0-9]{4}' THEN
        TO_DATE(SUBSTRING(date FROM '[0-9]{1,2}\s+[A-Za-z]{3}\s+[0-9]{4}'), 'DD Mon YYYY')
      WHEN date ~ '[0-9]{4}-[0-9]{2}-[0-9]{2}' THEN
        TO_DATE(SUBSTRING(date FROM '[0-9]{4}-[0-9]{2}-[0-9]{2}'), 'YYYY-MM-DD')
      ELSE NULL
    END AS parsed_date
  FROM news
)
DELETE FROM news
WHERE id IN (
  SELECT id FROM parsed_dates WHERE parsed_date = '2026-01-30'::date
);
