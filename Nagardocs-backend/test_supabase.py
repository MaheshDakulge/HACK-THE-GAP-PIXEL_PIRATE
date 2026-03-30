import asyncio
from app.core.database import get_supabase_sync

def test():
    sb = get_supabase_sync()
    res = sb.table("documents").select("id, doc_type").execute()
    print("Documents count:", len(res.data) if res.data else 0)

if __name__ == "__main__":
    test()
