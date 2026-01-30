-- Simple SQL to Delete Today's News (January 30, 2026)
-- Run in Supabase SQL Editor

-- STEP 1: Check how many records will be deleted
SELECT COUNT(*) as records_to_delete
FROM news
WHERE date LIKE '%30 Jan 2026%';

-- STEP 2: Preview what will be deleted (optional - review before deleting)
SELECT id, title, date
FROM news
WHERE date LIKE '%30 Jan 2026%'
ORDER BY id
LIMIT 20;

-- STEP 3: Delete all news from January 30, 2026
DELETE FROM news
WHERE date LIKE '%30 Jan 2026%';
