-- SQL Queries to Remove Duplicate News from Supabase
-- Run these queries in Supabase SQL Editor

-- ============================================
-- OPTION 1: Delete duplicates keeping the OLDEST record (lowest id)
-- ============================================

-- Step 1: First, let's see how many duplicates exist
WITH normalized_news AS (
  SELECT 
    id,
    title,
    link,
    date,
    -- Normalize link: lowercase, remove protocol, trailing slashes
    LOWER(TRIM(REGEXP_REPLACE(
      REGEXP_REPLACE(link, '^https?://', ''), 
      '/+$', ''
    ))) AS norm_link,
    -- Normalize title: lowercase, trim whitespace
    LOWER(TRIM(REGEXP_REPLACE(title, '\s+', ' ', 'g'))) AS norm_title
  FROM news
),
duplicates AS (
  SELECT 
    id,
    norm_link,
    norm_title,
    date,
    ROW_NUMBER() OVER (
      PARTITION BY 
        CASE 
          WHEN norm_link != '' THEN norm_link 
          ELSE norm_title || '||' || COALESCE(date, '')
        END
      ORDER BY id ASC  -- Keep oldest (lowest id)
    ) AS rn
  FROM normalized_news
  WHERE norm_link != '' OR (norm_title != '' AND date IS NOT NULL)
)
SELECT 
  COUNT(*) as total_duplicates_to_delete,
  COUNT(DISTINCT 
    CASE 
      WHEN norm_link != '' THEN norm_link 
      ELSE norm_title || '||' || COALESCE(date, '')
    END
  ) as unique_news_items
FROM duplicates
WHERE rn > 1;

-- Step 2: If the count looks correct, delete the duplicates (keeping oldest)
WITH normalized_news AS (
  SELECT 
    id,
    title,
    link,
    date,
    LOWER(TRIM(REGEXP_REPLACE(
      REGEXP_REPLACE(link, '^https?://', ''), 
      '/+$', ''
    ))) AS norm_link,
    LOWER(TRIM(REGEXP_REPLACE(title, '\s+', ' ', 'g'))) AS norm_title
  FROM news
),
duplicates AS (
  SELECT 
    id,
    ROW_NUMBER() OVER (
      PARTITION BY 
        CASE 
          WHEN norm_link != '' THEN norm_link 
          ELSE norm_title || '||' || COALESCE(date, '')
        END
      ORDER BY id ASC
    ) AS rn
  FROM normalized_news
  WHERE norm_link != '' OR (norm_title != '' AND date IS NOT NULL)
)
DELETE FROM news
WHERE id IN (
  SELECT id FROM duplicates WHERE rn > 1
);

-- ============================================
-- OPTION 2: Delete duplicates keeping the NEWEST record (highest id)
-- ============================================

WITH normalized_news AS (
  SELECT 
    id,
    title,
    link,
    date,
    LOWER(TRIM(REGEXP_REPLACE(
      REGEXP_REPLACE(link, '^https?://', ''), 
      '/+$', ''
    ))) AS norm_link,
    LOWER(TRIM(REGEXP_REPLACE(title, '\s+', ' ', 'g'))) AS norm_title
  FROM news
),
duplicates AS (
  SELECT 
    id,
    ROW_NUMBER() OVER (
      PARTITION BY 
        CASE 
          WHEN norm_link != '' THEN norm_link 
          ELSE norm_title || '||' || COALESCE(date, '')
        END
      ORDER BY id DESC  -- Keep newest (highest id)
    ) AS rn
  FROM normalized_news
  WHERE norm_link != '' OR (norm_title != '' AND date IS NOT NULL)
)
DELETE FROM news
WHERE id IN (
  SELECT id FROM duplicates WHERE rn > 1
);

-- ============================================
-- OPTION 3: More aggressive - Remove tracking params and normalize URLs better
-- ============================================

-- This version does more thorough URL normalization
WITH normalized_news AS (
  SELECT 
    id,
    title,
    link,
    date,
    -- Remove protocol
    REGEXP_REPLACE(link, '^https?://', '') AS link_no_proto,
    -- Remove trailing slashes
    REGEXP_REPLACE(REGEXP_REPLACE(link, '^https?://', ''), '/+$', '') AS link_clean,
    LOWER(TRIM(REGEXP_REPLACE(title, '\s+', ' ', 'g'))) AS norm_title
  FROM news
  WHERE link IS NOT NULL AND link != ''
),
link_parts AS (
  SELECT 
    id,
    norm_title,
    date,
    -- Extract hostname + path (before ?)
    SPLIT_PART(link_clean, '?', 1) AS link_base,
    -- Extract query params
    CASE 
      WHEN POSITION('?' IN link_clean) > 0 
      THEN SPLIT_PART(link_clean, '?', 2)
      ELSE ''
    END AS query_params
  FROM normalized_news
),
cleaned_links AS (
  SELECT 
    id,
    norm_title,
    date,
    link_base,
    query_params,
    -- Remove tracking params: utm_*, fbclid, gclid
    REGEXP_REPLACE(
      REGEXP_REPLACE(
        REGEXP_REPLACE(query_params, 'utm_[^&]*&?', '', 'g'),
        'fbclid=[^&]*&?', '', 'g'
      ),
      'gclid=[^&]*&?', '', 'g'
    ) AS clean_params
  FROM link_parts
),
final_norm AS (
  SELECT 
    id,
    norm_title,
    date,
    LOWER(
      link_base || 
      CASE WHEN clean_params != '' AND clean_params != query_params 
           THEN '?' || clean_params 
           ELSE '' 
      END
    ) AS norm_link
  FROM cleaned_links
),
duplicates AS (
  SELECT 
    id,
    ROW_NUMBER() OVER (
      PARTITION BY 
        CASE 
          WHEN norm_link != '' THEN norm_link 
          ELSE norm_title || '||' || COALESCE(date, '')
        END
      ORDER BY id ASC
    ) AS rn
  FROM final_norm
  WHERE norm_link != '' OR (norm_title != '' AND date IS NOT NULL)
)
DELETE FROM news
WHERE id IN (
  SELECT id FROM duplicates WHERE rn > 1
);

-- ============================================
-- SIMPLE OPTION: Delete exact duplicates (same link or same title+date)
-- ============================================

-- Delete duplicates keeping the oldest (simplest approach)
DELETE FROM news
WHERE id NOT IN (
  SELECT MIN(id)
  FROM news
  GROUP BY 
    COALESCE(LOWER(TRIM(link)), ''),
    COALESCE(LOWER(TRIM(title)), ''),
    COALESCE(date, '')
);

-- Or delete duplicates keeping the newest
DELETE FROM news
WHERE id NOT IN (
  SELECT MAX(id)
  FROM news
  GROUP BY 
    COALESCE(LOWER(TRIM(link)), ''),
    COALESCE(LOWER(TRIM(title)), ''),
    COALESCE(date, '')
);
