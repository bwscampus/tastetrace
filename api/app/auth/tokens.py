"""Session tokens are stored hashed, never as the bearer value itself.

The client (cookie or iOS bearer header) holds the raw token; access_tokens
holds only its SHA-256. Someone who reads the database, a backup, or a leaked
read-only credential gets hashes, which cannot be presented as a session.

A token is 32 random bytes, so a plain unsalted SHA-256 is enough: there is
nothing to brute-force, unlike a password. base64url without padding is 43
characters, exactly the width of the existing access_tokens.token column, so
the schema doesn't change. Migration 0004 applies the same transform in SQL
to rows that predate this module.

Production Standard: DB-8.
"""

import base64
import hashlib


def hash_token(raw: str) -> str:
    digest = hashlib.sha256(raw.encode("utf-8")).digest()
    return base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
