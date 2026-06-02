import base64
import hashlib
import hmac
import json
import os
import secrets
import uuid
from datetime import datetime, timedelta, timezone

import boto3


dynamodb = boto3.resource("dynamodb")
users_table = dynamodb.Table(os.environ["KEERTHI_TABLE"])
sessions_table = dynamodb.Table(os.environ["KEERTHI_SESSION_TABLE"])

PBKDF2_ITERATIONS = 120000
SESSION_COOKIE_NAME = "keerthi_auth_session"
SESSION_TTL_SECONDS = int(os.environ.get("KEERTHI_SESSION_TTL_SECONDS", "86400"))
COOKIE_SECURE = os.environ.get("KEERTHI_COOKIE_SECURE", "true").lower() == "true"


def get_method(event):
    if event.get("httpMethod"):
        return event["httpMethod"]
    return event.get("requestContext", {}).get("http", {}).get("method", "")


def parse_body(event):
    raw = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8")
    return json.loads(raw)


def get_origin(event):
    headers = event.get("headers") or {}
    return headers.get("origin") or headers.get("Origin") or "*"


def response(body, status=200, origin="*", cookies=None):
    if origin == "*":
        allow_credentials = "false"
    else:
        allow_credentials = "true"

    return {
        "statusCode": status,
        "headers": {
            "Access-Control-Allow-Origin": origin,
            "Access-Control-Allow-Credentials": allow_credentials,
            "Access-Control-Allow-Headers": "*",
            "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
            "Content-Type": "application/json",
            "Vary": "Origin",
        },
        "body": json.dumps(body),
        "cookies": cookies or [],
    }


def hash_password(password, salt):
    key = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, PBKDF2_ITERATIONS)
    return base64.b64encode(key).decode("utf-8")


def is_valid_email(email):
    return isinstance(email, str) and "@" in email and "." in email and len(email.strip()) >= 6


def parse_cookie_header(event):
    headers = event.get("headers") or {}
    cookie_header = headers.get("cookie") or headers.get("Cookie") or ""
    parts = [part.strip() for part in cookie_header.split(";") if "=" in part]
    cookie_map = {}

    for part in parts:
        key, value = part.split("=", 1)
        cookie_map[key.strip()] = value.strip()

    return cookie_map


def cookie_string(value, max_age):
    secure_part = "Secure; " if COOKIE_SECURE else ""
    return (
        f"{SESSION_COOKIE_NAME}={value}; Path=/; HttpOnly; {secure_part}"
        f"SameSite=None; Max-Age={max_age}"
    )


def create_session(user):
    now = datetime.now(timezone.utc)
    expires_at = now + timedelta(seconds=SESSION_TTL_SECONDS)
    session_id = secrets.token_urlsafe(48)

    sessions_table.put_item(
        Item={
            "session_id": session_id,
            "email": user.get("email"),
            "user_id": user.get("user_id"),
            "full_name": user.get("full_name", ""),
            "created_at": now.isoformat(),
            "expires_at": int(expires_at.timestamp()),
        }
    )

    return session_id


def get_session_user(event):
    cookie_map = parse_cookie_header(event)
    session_id = cookie_map.get(SESSION_COOKIE_NAME)
    if not session_id:
        return None

    session = sessions_table.get_item(Key={"session_id": session_id}).get("Item")
    if not session:
        return None

    if int(session.get("expires_at", 0)) <= int(datetime.now(timezone.utc).timestamp()):
        sessions_table.delete_item(Key={"session_id": session_id})
        return None

    return {
        "user_id": session.get("user_id"),
        "email": session.get("email"),
        "full_name": session.get("full_name", ""),
    }


def register_user(payload, origin):
    email = str(payload.get("email", "")).strip().lower()
    password = str(payload.get("password", "")).strip()
    full_name = str(payload.get("full_name", "")).strip()

    if not is_valid_email(email):
        return response({"error": "Valid email is required"}, 400, origin)
    if len(password) < 8:
        return response({"error": "Password must be at least 8 characters"}, 400, origin)
    if len(full_name) < 2:
        return response({"error": "Full name is required"}, 400, origin)

    existing = users_table.get_item(Key={"email": email}).get("Item")
    if existing:
        return response({"error": "User already exists"}, 409, origin)

    salt = os.urandom(16)
    password_hash = hash_password(password, salt)
    created_at = datetime.now(timezone.utc).isoformat()

    users_table.put_item(
        Item={
            "email": email,
            "user_id": str(uuid.uuid4()),
            "full_name": full_name,
            "password_hash": password_hash,
            "password_salt": base64.b64encode(salt).decode("utf-8"),
            "created_at": created_at,
            "last_login": None,
        }
    )

    return response(
        {
            "message": "Registration successful",
            "user": {
                "email": email,
                "full_name": full_name,
            },
        },
        201,
        origin,
    )


def login_user(payload, origin):
    email = str(payload.get("email", "")).strip().lower()
    password = str(payload.get("password", "")).strip()

    if not is_valid_email(email) or not password:
        return response({"error": "Email and password are required"}, 400, origin)

    user = users_table.get_item(Key={"email": email}).get("Item")
    if not user:
        return response({"error": "Invalid credentials"}, 401, origin)

    salt = base64.b64decode(user["password_salt"])
    expected_hash = user["password_hash"]
    provided_hash = hash_password(password, salt)

    if not hmac.compare_digest(expected_hash, provided_hash):
        return response({"error": "Invalid credentials"}, 401, origin)

    users_table.update_item(
        Key={"email": email},
        UpdateExpression="SET last_login = :last_login",
        ExpressionAttributeValues={":last_login": datetime.now(timezone.utc).isoformat()},
    )

    session_id = create_session(user)

    return response(
        {
            "message": "Login successful",
            "user": {
                "user_id": user.get("user_id"),
                "email": user.get("email"),
                "full_name": user.get("full_name", ""),
            },
        },
        200,
        origin,
        [cookie_string(session_id, SESSION_TTL_SECONDS)],
    )


def get_current_user(event, origin):
    user = get_session_user(event)
    if not user:
        return response({"error": "Unauthorized"}, 401, origin)

    return response({"authenticated": True, "user": user}, 200, origin)


def logout_user(event, origin):
    cookie_map = parse_cookie_header(event)
    session_id = cookie_map.get(SESSION_COOKIE_NAME)

    if session_id:
        sessions_table.delete_item(Key={"session_id": session_id})

    return response(
        {"message": "Logged out"},
        200,
        origin,
        [cookie_string("", 0)],
    )


def lambda_handler(event, context):
    try:
        method = get_method(event)
        origin = get_origin(event)
        path = event.get("rawPath") or event.get("path") or ""
        route_key = event.get("routeKey") or ""

        if method == "OPTIONS":
            return response({}, 200, origin)

        if (path.endswith("/auth/me") or route_key == "GET /auth/me") and method == "GET":
            return get_current_user(event, origin)

        if (path.endswith("/auth/logout") or route_key == "POST /auth/logout") and method == "POST":
            return logout_user(event, origin)

        if method != "POST":
            return response({"error": "Method not allowed"}, 405, origin)

        payload = parse_body(event)

        if path.endswith("/auth/register") or route_key == "POST /auth/register":
            return register_user(payload, origin)

        if path.endswith("/auth/login") or route_key == "POST /auth/login":
            return login_user(payload, origin)

        return response({"error": "Invalid auth route"}, 404, origin)
    except Exception as error:
        return response({"error": str(error)}, 500)
