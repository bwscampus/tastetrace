"""Project: waitlist signups move off the retired Express backend.

Revision ID: 0005_waitlist_signups
Revises: 0004_hash_access_tokens

The landing page's signup form used to post to the Express app, which owned
this table in its own database. That service is being retired, so the table
comes here and the existing rows are loaded in alongside.

The unique constraint on email is what makes a repeat signup a no-op rather
than an error, so the endpoint can answer the same way every time.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0005_waitlist_signups"
down_revision: Union[str, None] = "0004_hash_access_tokens"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "waitlist_signups",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("email", sa.Text(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("email", name="uq_waitlist_signups_email"),
    )


def downgrade() -> None:
    op.drop_table("waitlist_signups")
