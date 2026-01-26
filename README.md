# MatrixQi News API

Flask API server for fetching and storing news from RSS feeds.

## Endpoints

### GET /api/storenews
Fetches RSS feed from Zerodha Pulse, normalizes links and titles, deduplicates, and stores new items in Supabase.

### GET /api/fetchnews
Returns news from Supabase filtered by today's date (Asia/Kolkata timezone).

**Query Parameters:**
- `limit` (optional): Maximum number of items to return
- `offset` (optional): Number of items to skip

## Environment Variables

- `SUPABASE_URL`: Your Supabase project URL
- `SUPABASE_KEY`: Your Supabase API key
- `PORT`: Server port (default: 5000)

## Local Development

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Set environment variables:
```bash
export SUPABASE_URL=your_supabase_url
export SUPABASE_KEY=your_supabase_key
```

3. Run the server:
```bash
python app.py
```

## Deployment on Render

1. Connect your repository to Render
2. Set the environment variables in Render dashboard:
   - `SUPABASE_URL`
   - `SUPABASE_KEY`
3. Render will automatically detect `render.yaml` and deploy
