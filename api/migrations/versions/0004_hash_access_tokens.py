"""Store session tokens hashed.

Revision ID: 0004_hash_access_tokens
Revises: 0003_onboarding

Rewrites every existing access_tokens.token as base64url(sha256(token)),
without padding: the same transform as app.auth.tokens.hash_token. Live
sessions and iOS bearer tokens keep working, because from now on the app
hashes whatever the client presents before looking it up. Alembic runs this
once, so rows are never hashed twice.

Downgrade can't recover raw tokens from hashes, so it deletes every session
and everyone signs in again.
"""

from typing import Sequence, Union

from alembic import op

revision: str = "0004_hash_access_tokens"
down_revision: Union[str, None] = "0003_onboarding"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Kept in one place so the test suite can check it against hash_token().
HASH_SQL = (
    "rtrim(translate(encode(sha256(convert_to({col}, 'UTF8')), 'base64'),"
    " '+/', '-_'), '=')"
)


def upgrade() -> None:
    op.execute(
        f"UPDATE access_tokens SET token = {HASH_SQL.format(col='token')}"
    )


def downgrade() -> None:
    op.execute("DELETE FROM access_tokens")
