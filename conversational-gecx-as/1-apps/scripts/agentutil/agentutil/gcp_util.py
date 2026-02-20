# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import logging
import subprocess
import requests
from google.auth.transport.requests import Request

logger = logging.getLogger(__name__)


def get_current_user_email(credentials) -> str:
    """Retrieves the email of the currently authenticated user."""
    # Get token info
    if not credentials.valid:
        credentials.refresh(Request())

    # Try retrieving from token info
    # This works for Google user credentials
    try:
        # simple request to userinfo
        r = requests.get(
            "https://www.googleapis.com/oauth2/v3/userinfo",
            headers={"Authorization": f"Bearer {credentials.token}"})
        if r.status_code == 200:
            return r.json().get('email')
    except:
        pass

    # Fallback to gcloud if available?
    # Reference script uses `gcloud config get-value account`
    try:
        email = subprocess.check_output(
            ["gcloud", "config", "get-value", "account"], text=True).strip()
        if email: return email
    except:
        pass

    logger.warning(
        "Could not determine current user email. Permission check might differ from script."
    )
    return "unknown"


def has_sa_user_role(sa_email: str, user_email: str, project_id: str | None,
                     credentials) -> bool:
    """Checks if the user has Service Account User role on the SA or Project."""
    if not user_email or user_email == "unknown":
        return True  # Can't check

    if not credentials.valid:
        credentials.refresh(Request())

    headers = {
        "Authorization": f"Bearer {credentials.token}",
        "Content-Type": "application/json",
        "X-Goog-User-Project": project_id or ""
    }

    # Use testIamPermissions to check if the caller can 'actAs' the service account.
    # This is more robust than parsing policies manually as it accounts for
    # inherited permissions at project or folder level.
    url = f"https://iam.googleapis.com/v1/projects/-/serviceAccounts/{sa_email}:testIamPermissions"
    payload = {"permissions": ["iam.serviceAccounts.actAs"]}

    try:
        r = requests.post(url, headers=headers, json=payload)
        if r.status_code == 200:
            permissions = r.json().get('permissions', [])
            return "iam.serviceAccounts.actAs" in permissions
        else:
            logger.warning(
                f"Failed to test permissions for {sa_email}: {r.status_code} {r.text}"
            )
    except Exception as e:
        logger.error(f"Error testing permissions for {sa_email}: {e}")

    return False
