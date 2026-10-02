import os
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv
from supabase import create_client, Client

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SECRET_KEY = os.getenv("SUPABASE_SECRET_KEY")
RESULTS_BUCKET = "cad-results"


def get_supabase_client() -> Client:
    """Create a Supabase client for backend storage operations."""
    if not SUPABASE_URL or not SUPABASE_SECRET_KEY:
        raise RuntimeError(
            "SUPABASE_URL or SUPABASE_SECRET_KEY is not configured."
        )

    return create_client(SUPABASE_URL, SUPABASE_SECRET_KEY)


def upload_result_csv(
    local_file_path: str,
    job_id: str,
    user_identifier: Optional[str] = None,
) -> str:
    """Upload a generated result CSV to Supabase Storage."""

    client = get_supabase_client()

    filename = f"{job_id}_results.csv"

    if user_identifier:
        safe_user = (
            user_identifier
            .replace("@", "_at_")
            .replace(".", "_")
            .replace("/", "_")
            .replace("\\", "_")
        )
        cloud_path = f"{safe_user}/{filename}"
    else:
        cloud_path = f"{job_id}/{filename}"

    file_path = Path(local_file_path)

    if not file_path.exists():
        raise FileNotFoundError(
            f"Result CSV does not exist: {local_file_path}"
        )

    with file_path.open("rb") as file:
        client.storage.from_(RESULTS_BUCKET).upload(
            cloud_path,
            file,
            {
                "content-type": "text/csv",
                "upsert": "true",
            },
        )

    print(f"[CLOUD] Result uploaded to Supabase: {cloud_path}")

    return cloud_path