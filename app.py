from flask import Flask, jsonify, request
from supabase import create_client, Client
import requests
import feedparser
from urllib.parse import urlparse, urlunparse, parse_qs, urlencode
from datetime import datetime, timedelta
import pytz
import os
import re
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

app = Flask(__name__)

# Initialize Supabase client
SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_KEY = os.getenv('SUPABASE_KEY')

if not SUPABASE_URL or not SUPABASE_KEY:
    raise ValueError("SUPABASE_URL and SUPABASE_KEY environment variables must be set")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)


def normalize_link(raw):
    """Normalize a URL by removing tracking params and standardizing format."""
    if not raw or not isinstance(raw, str):
        return ''
    
    url_str = raw.strip()
    
    # Fix protocol-less links like //example.com/path
    if url_str.startswith('//'):
        url_str = 'https:' + url_str
    
    # Attempt to parse
    try:
        parsed = urlparse(url_str)
        
        # Remove tracking params like utm_*, fbclid, gclid
        query_params = parse_qs(parsed.query, keep_blank_values=True)
        to_remove = []
        
        for key in query_params.keys():
            key_lower = key.lower()
            if key_lower.startswith('utm_') or key_lower in ['fbclid', 'gclid']:
                to_remove.append(key)
        
        for key in to_remove:
            del query_params[key]
        
        # Rebuild query string
        new_query = urlencode(query_params, doseq=True)
        
        # Build normalized URL: hostname + pathname + (remaining search)
        norm = parsed.hostname or ''
        if parsed.path:
            norm += parsed.path
        
        if new_query:
            norm += '?' + new_query
        
        # Remove trailing slash (but keep single slash if pathname is '/')
        if norm.endswith('/') and len(norm) > 1:
            norm = norm.rstrip('/')
        
        return norm.lower()
    except Exception:
        # Fallback: strip whitespace and lower-case, remove trailing slashes
        import re
        return re.sub(r'/+$', '', url_str).lower()


def normalize_title(raw):
    """Normalize a title by collapsing whitespace and lowercasing."""
    if not raw or not isinstance(raw, str):
        return ''
    
    return ' '.join(raw.split()).strip().lower()


@app.route('/api/storenews', methods=['GET'])
def store_news():
    """Fetch RSS feed, normalize items, deduplicate, and store new items in Supabase."""
    try:
        RSS_URL = 'https://pulse.zerodha.com/feed.php'
        
        # Fetch RSS feed with timeout
        response = requests.get(RSS_URL, timeout=10)
        if not response.ok:
            return jsonify({
                'error': f'Failed to fetch feed ({response.status_code})'
            }), 502
        
        # Parse RSS feed
        feed = feedparser.parse(response.text)
        
        # Get feed items
        items = feed.entries if feed.entries else []
        
        # Debug: Print first item structure to understand feed format
        if items and len(items) > 0:
            first_item = items[0]
            print(f"Sample feed item keys: {list(first_item.keys())}")
            print(f"Has 'summary': {first_item.get('summary') is not None}")
            print(f"Has 'description': {first_item.get('description') is not None}")
            if first_item.get('summary'):
                print(f"Summary value (first 150 chars): {str(first_item.get('summary'))[:150]}")
            if first_item.get('description'):
                print(f"Description value (first 150 chars): {str(first_item.get('description'))[:150]}")
        
        if len(items) == 0:
            return jsonify({
                'message': 'No items parsed from feed',
                'fetched': 0,
                'inserted': 0
            })
        
        # Normalize parsed items to our DB shape plus dedupe keys
        normalized = []
        for it in items:
            title = it.get('title', '') or ''
            link = it.get('link', '') or ''
            
            # Extract description - RSS 2.0 maps <description> to 'summary' in feedparser
            # Try summary first (RSS 2.0 standard)
            description = ''
            if it.get('summary'):
                summary_val = it.get('summary')
                if isinstance(summary_val, str):
                    description = summary_val
                elif isinstance(summary_val, dict):
                    description = summary_val.get('value', '') or summary_val.get('content', '')
            
            # Try description field (some feeds use this)
            if not description and it.get('description'):
                desc_val = it.get('description')
                if isinstance(desc_val, str):
                    description = desc_val
                elif isinstance(desc_val, dict):
                    description = desc_val.get('value', '') or desc_val.get('content', '')
            
            # Try content field (Atom feeds, can be list or dict)
            if not description and it.get('content'):
                content_val = it.get('content')
                if isinstance(content_val, list) and len(content_val) > 0:
                    # Try first content item
                    first_content = content_val[0]
                    if isinstance(first_content, dict):
                        description = first_content.get('value', '') or first_content.get('content', '')
                elif isinstance(content_val, dict):
                    description = content_val.get('value', '') or content_val.get('content', '')
            
            # Try subtitle as fallback
            if not description and it.get('subtitle'):
                subtitle_val = it.get('subtitle')
                if isinstance(subtitle_val, str):
                    description = subtitle_val
            
            pub_date = it.get('published', '') or it.get('updated', '') or ''
            
            norm_link = normalize_link(link)
            norm_title = normalize_title(title)
            title_date_key = f"{norm_title}||{pub_date.strip()}" if pub_date else ''
            
            # Need at least title or link
            if title or link:
                normalized.append({
                    'title': title.strip() if isinstance(title, str) else '',
                    'link': link.strip() if isinstance(link, str) else '',
                    'description': description.strip() if isinstance(description, str) else '',
                    'date': pub_date.strip() if isinstance(pub_date, str) else '',
                    'norm_link': norm_link,
                    'title_date_key': title_date_key
                })
        
        if len(normalized) == 0:
            return jsonify({
                'message': 'No items parsed from feed',
                'fetched': 0,
                'inserted': 0
            })
        
        # Fetch existing rows from DB (fetch all to ensure proper deduplication)
        try:
            # Fetch all existing rows - Supabase default limit is 1000, but we'll fetch more if needed
            existing_rows = []
            page_size = 1000
            offset = 0
            
            while True:
                response = supabase.table('news').select('link, title, date').range(offset, offset + page_size - 1).execute()
                batch = response.data if response.data else []
                if not batch:
                    break
                existing_rows.extend(batch)
                if len(batch) < page_size:
                    break
                offset += page_size
        except Exception as select_err:
            print(f'Supabase select warning: {select_err}')
            existing_rows = []
        
        # Build sets for deduplication
        existing_links_set = set()
        existing_title_date_set = set()
        
        for r in existing_rows:
            l = r.get('link', '') or ''
            t = r.get('title', '') or ''
            d = r.get('date', '') or ''
            n_l = normalize_link(l)
            n_t = normalize_title(t)
            if n_l:
                existing_links_set.add(n_l)
            if n_t or d:
                existing_title_date_set.add(f"{n_t}||{d}")
        
        print(f'Deduplication sets: {len(existing_links_set)} unique links, {len(existing_title_date_set)} unique title+date combinations')
        
        # Decide which to insert
        to_insert = []
        skipped = {
            'duplicateLink': 0,
            'duplicateTitleDate': 0,
            'noLinkNoTitle': 0
        }
        
        for it in normalized:
            # Prefer link-based deduplication if link exists
            if it['norm_link']:
                if it['norm_link'] not in existing_links_set:
                    to_insert.append({
                        'title': it['title'],
                        'link': it['link'],
                        'description': it['description'],
                        'date': it['date']
                    })
                    # Add to set to avoid inserting duplicates within this run
                    existing_links_set.add(it['norm_link'])
                else:
                    skipped['duplicateLink'] += 1
            elif it['title_date_key'] and it['title_date_key'] not in existing_title_date_set:
                # Fallback: dedupe by title+date if link missing
                to_insert.append({
                    'title': it['title'],
                    'link': it['link'],
                    'description': it['description'],
                    'date': it['date']
                })
                existing_title_date_set.add(it['title_date_key'])
            else:
                if not it['norm_link']:
                    skipped['duplicateTitleDate'] += 1
        
        print(f'Deduplication results: {len(to_insert)} to insert, {skipped}')
        
        if len(to_insert) == 0:
            return jsonify({
                'message': 'No new items to insert',
                'fetchedCount': len(normalized),
                'skipped': skipped,
                'insertedCount': 0
            })
        
        # Insert new rows
        try:
            insert_response = supabase.table('news').insert(to_insert).execute()
            inserted = insert_response.data if insert_response.data else []
        except Exception as insert_err:
            print(f'Supabase insert error: {insert_err}')
            return jsonify({
                'error': 'Failed to insert into DB',
                'detail': str(insert_err)
            }), 500
        
        return jsonify({
            'message': 'Fetched feed and stored new items',
            'fetchedCount': len(normalized),
            'insertedCount': len(inserted),
            'inserted': inserted,
            'skipped': skipped
        })
    
    except Exception as err:
        print(f'storenews error: {err}')
        return jsonify({'error': str(err)}), 500


@app.route('/api/fetchnews', methods=['GET'])
def fetch_news():
    """Returns news from Supabase filtered by today's date (Asia/Kolkata timezone)."""
    try:
        limit = int(request.args.get('limit', 0)) or None
        offset = int(request.args.get('offset', 0)) or 0
        
        # How many recent rows to fetch from DB to allow server-side filtering
        FETCH_ROWS = 1000
        
        # Fetch recent rows (newest first)
        try:
            response = supabase.table('news')\
                .select('id, title, link, description, date')\
                .order('id', desc=True)\
                .limit(FETCH_ROWS)\
                .execute()
            rows = response.data if response.data else []
        except Exception as error:
            print(f'Supabase select error: {error}')
            return jsonify({
                'error': 'Failed to fetch news from DB',
                'detail': str(error)
            }), 500
        
        tz = pytz.timezone('Asia/Kolkata')
        
        # Helper: get YYYY-MM-DD in Asia/Kolkata for any datetime
        def to_kolkata_date_str(dt):
            try:
                if dt.tzinfo is None:
                    dt = pytz.utc.localize(dt)
                kolkata_dt = dt.astimezone(tz)
                return kolkata_dt.strftime('%Y-%m-%d')
            except Exception:
                return None
        
        # Today's and yesterday's date strings in Asia/Kolkata
        now = datetime.now(tz)
        today_str = to_kolkata_date_str(now)
        yesterday = now.replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(days=1)
        yesterday_str = to_kolkata_date_str(yesterday)
        
        # parse_row_date: attempts to parse the stored date string into a datetime
        def parse_row_date(date_str):
            if not date_str or not isinstance(date_str, str):
                return None
            
            # Try parsing with feedparser (handles RFC-2822 and other formats)
            try:
                # feedparser can parse dates - create a dummy entry to use its parser
                test_feed = feedparser.parse(f'<?xml version="1.0"?><rss><channel><item><pubDate>{date_str}</pubDate></item></channel></rss>')
                if test_feed.entries and test_feed.entries[0].get('published_parsed'):
                    parsed_tuple = test_feed.entries[0]['published_parsed']
                    return datetime(*parsed_tuple[:6], tzinfo=pytz.utc)
            except Exception:
                pass
            
            # Try standard date parsing
            try:
                parsed = datetime.fromisoformat(date_str.replace('Z', '+00:00'))
                if parsed.tzinfo is None:
                    parsed = pytz.utc.localize(parsed)
                return parsed
            except Exception:
                pass
            
            # Try dateutil parser (handles many formats)
            try:
                from dateutil import parser as date_parser
                parsed = date_parser.parse(date_str)
                if parsed.tzinfo is None:
                    parsed = pytz.utc.localize(parsed)
                return parsed
            except Exception:
                pass
            
            return None
        
        # Annotate rows with kolkata_date
        annotated = []
        for r in rows:
            parsed = parse_row_date(r.get('date', ''))
            kolkata_date = to_kolkata_date_str(parsed) if parsed else None
            annotated.append({**r, 'kolkata_date': kolkata_date})
        
        # Filter for today's news
        todays = [r for r in annotated if r.get('kolkata_date') == today_str]
        
        # If none found, fallback to yesterday's news
        used_day = 'today'
        if not todays or len(todays) == 0:
            todays = [r for r in annotated if r.get('kolkata_date') == yesterday_str]
            used_day = 'yesterday'
        
        # Apply offset & limit to the filtered array
        result = todays if todays else []
        if offset:
            result = result[offset:]
        if limit:
            result = result[:limit]
        
        # Format response (remove kolkata_date from output)
        news_list = []
        for item in result:
            news_list.append({
                'id': item.get('id'),
                'title': item.get('title'),
                'link': item.get('link'),
                'description': item.get('description'),
                'date': item.get('date')
            })
        
        return jsonify({
            'requested_day': used_day,
            'day_date': today_str if used_day == 'today' else yesterday_str,
            'count': len(news_list),
            'news': news_list
        })
    
    except Exception as err:
        print(f'get news error: {err}')
        return jsonify({'error': str(err)}), 500


if __name__ == '__main__':
    port = int(os.getenv('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)
