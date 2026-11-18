# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

from collections.abc import Mapping
import hashlib
import logging
import threading
import time
from typing import Any, Optional

from a2a.auth.user import User
from a2a.server.apps.jsonrpc.jsonrpc_app import DefaultCallContextBuilder
from a2a.server.context import ServerCallContext
from google.auth import transport
from google.auth.transport import requests as google_auth_requests
from google.oauth2 import id_token
import requests
from starlette.requests import Request

logger = logging.getLogger(__name__)

_IAP_CERTS_URL = "https://www.gstatic.com/iap/verify/public_key-jwk"
_OAUTH2_TOKENINFO_URL = "https://oauth2.googleapis.com/tokeninfo"
_CERTS_CACHE_TTL_SECONDS = 3600
_TOKEN_CACHE_TTL_SECONDS = 300
_TOKEN_CACHE_MAX_SIZE = 1024


class AuthenticatedUser(User):
  """Authenticated A2A caller principal verified from request credentials."""

  def __init__(self, principal: str):
    if not isinstance(principal, str) or not principal.strip():
      raise ValueError("principal must be a non-empty string.")
    self._principal = principal.strip()

  @property
  def is_authenticated(self) -> bool:
    return True

  @property
  def user_name(self) -> str:
    return self._principal


class _CachedCertsRequest(transport.Request):
  """Caches Google public certificate GET responses in memory."""

  def __init__(self, ttl_seconds: int = _CERTS_CACHE_TTL_SECONDS):
    self._delegate = google_auth_requests.Request()
    self._ttl_seconds = ttl_seconds
    self._cache: dict[str, tuple[float, transport.Response]] = {}
    self._lock = threading.Lock()

  def __call__(self, url: str, method: str = "GET", body: Any = None,
               headers: Optional[Mapping[str, str]] = None,
               timeout: Optional[float] = None,
               **kwargs: Any) -> transport.Response:
    if method.upper() == "GET" and body is None:
      now = time.monotonic()
      with self._lock:
        cached = self._cache.get(url)
        if cached and cached[0] > now:
          return cached[1]
      response = self._delegate(url=url, method=method, body=body,
                                headers=headers, timeout=timeout or 5.0,
                                **kwargs)
      if response.status == 200:
        with self._lock:
          self._cache[url] = (time.monotonic() + self._ttl_seconds, response)
      return response
    return self._delegate(url=url, method=method, body=body, headers=headers,
                          timeout=timeout or 5.0, **kwargs)


_auth_request = _CachedCertsRequest()
_token_cache: dict[str, tuple[str, float]] = {}
_token_cache_lock = threading.Lock()


def _get_cached_principal(token: str) -> Optional[str]:
  key = hashlib.sha256(token.encode("utf-8")).hexdigest()
  now = time.time()
  with _token_cache_lock:
    entry = _token_cache.get(key)
    if entry is None:
      return None
    principal, expires_at = entry
    if expires_at <= now:
      _token_cache.pop(key, None)
      return None
    return principal


def _store_cached_principal(token: str, principal: str,
                            exp: Optional[float] = None) -> None:
  now = time.time()
  expires_at = now + _TOKEN_CACHE_TTL_SECONDS
  if exp is not None:
    expires_at = min(expires_at, float(exp))
  if expires_at <= now:
    return
  key = hashlib.sha256(token.encode("utf-8")).hexdigest()
  with _token_cache_lock:
    if len(_token_cache) >= _TOKEN_CACHE_MAX_SIZE:
      expired_keys = [
          k for k, (_, exp_ts) in _token_cache.items() if exp_ts <= now
      ]
      for k in expired_keys:
        _token_cache.pop(k, None)
      if len(_token_cache) >= _TOKEN_CACHE_MAX_SIZE:
        _token_cache.pop(next(iter(_token_cache)))
    _token_cache[key] = (principal, expires_at)


def _extract_principal_from_claims(claims: Mapping[str, Any]) -> Optional[str]:
  sub = claims.get("sub")
  if isinstance(sub, str) and sub.strip():
    return sub.strip()
  email = claims.get("email")
  email_verified = claims.get("email_verified")
  if (isinstance(email, str) and email.strip() and
      email_verified in (True, "true", "True")):
    return email.strip()
  return None


def _verify_iap_jwt(iap_jwt: str) -> Optional[str]:
  token = iap_jwt.strip()
  if not token:
    return None
  cached = _get_cached_principal(f"iap:{token}")
  if cached:
    return cached
  try:
    claims = id_token.verify_token(token, request=_auth_request,
                                   certs_url=_IAP_CERTS_URL,
                                   clock_skew_in_seconds=10)
  except Exception as exc:  # pylint: disable=broad-exception-caught
    logger.warning("IAP JWT verification failed: %s", type(exc).__name__)
    return None
  principal = _extract_principal_from_claims(claims)
  if principal:
    _store_cached_principal(f"iap:{token}", principal, claims.get("exp"))
  return principal


def _verify_bearer_token(token: str) -> Optional[str]:
  raw = token.strip()
  if not raw:
    return None
  cached = _get_cached_principal(f"bearer:{raw}")
  if cached:
    return cached

  # 1. Google-signed OIDC ID token (JWT), such as the Agent Engine P4SA OIDC
  # token or an end-user Google OIDC ID token.
  if raw.count(".") == 2:
    try:
      claims = id_token.verify_oauth2_token(raw, request=_auth_request,
                                            clock_skew_in_seconds=10)
    except Exception as exc:  # pylint: disable=broad-exception-caught
      logger.warning("OIDC Bearer token verification failed: %s",
                     type(exc).__name__)
      return None
    principal = _extract_principal_from_claims(claims)
    if principal:
      _store_cached_principal(f"bearer:{raw}", principal, claims.get("exp"))
    return principal

  # 2. Opaque Google OAuth 2.0 access token (e.g. passed via
  # X-Goog-Agent-User-Authorization on Agent Engine :invoke).
  try:
    response = requests.post(_OAUTH2_TOKENINFO_URL, data={"access_token": raw},
                             timeout=5.0)
    if response.status_code != 200:
      return None
    claims = response.json()
  except Exception as exc:  # pylint: disable=broad-exception-caught
    logger.warning("OAuth2 access token verification failed: %s",
                   type(exc).__name__)
    return None

  principal = _extract_principal_from_claims(claims)
  if principal:
    exp = claims.get("exp")
    exp_float = float(exp) if exp is not None else None
    _store_cached_principal(f"bearer:{raw}", principal, exp_float)
  return principal


def authenticate_headers(headers: Mapping[str, str]) -> Optional[str]:
  """Extracts and cryptographically verifies the caller principal from headers."""
  lowered = {str(k).lower(): str(v) for k, v in headers.items() if v}

  iap_jwt = lowered.get("x-goog-iap-jwt-assertion")
  if iap_jwt:
    principal = _verify_iap_jwt(iap_jwt)
    if principal:
      return principal

  auth_header = lowered.get("authorization", "").strip()
  if auth_header.lower().startswith("bearer "):
    bearer_token = auth_header[7:].strip()
    if bearer_token and " " not in bearer_token:
      return _verify_bearer_token(bearer_token)

  return None


def resolve_authenticated_user(
    call_context: Optional[ServerCallContext]) -> Optional[str]:
  """Returns the verified caller principal from ServerCallContext, or None."""
  if call_context is None:
    return None
  if (call_context.user and call_context.user.is_authenticated is True and
      isinstance(call_context.user.user_name, str) and
      call_context.user.user_name.strip()):
    return call_context.user.user_name.strip()

  if isinstance(call_context.state, Mapping):
    headers = call_context.state.get("headers")
    if isinstance(headers, Mapping):
      principal = authenticate_headers(headers)
      if principal:
        call_context.user = AuthenticatedUser(principal)
        return principal
  return None


def require_authenticated_user(
    call_context: Optional[ServerCallContext]) -> str:
  """Returns the verified caller principal or raises PermissionError."""
  principal = resolve_authenticated_user(call_context)
  if not principal:
    raise PermissionError("Authenticated caller principal is required.")
  return principal


class AuthenticatedCallContextBuilder(DefaultCallContextBuilder):
  """Builds ServerCallContext with a verified caller principal."""

  def build(self, request: Request) -> ServerCallContext:
    call_context = super().build(request)
    if (call_context.user and call_context.user.is_authenticated is True and
        isinstance(call_context.user.user_name, str) and
        call_context.user.user_name.strip()):
      return call_context
    principal = authenticate_headers(request.headers)
    if principal:
      call_context.user = AuthenticatedUser(principal)
    return call_context
