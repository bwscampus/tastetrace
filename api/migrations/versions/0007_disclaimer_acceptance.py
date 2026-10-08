"""Project: record which disclaimer wording each account accepted.

Revision ID: 0007_disclaimer_acceptance
Revises: 0006_shorter_window

Onboarding now shows a medical disclaimer and will not complete without it.
Storing the version alongside the timestamp is the point: "they agreed on this
date" is worth little if nobody can say what they agreed to.

Existing accounts are left null deliberately. Backfilling an acceptance for
someone who was never shown the text would be inventing a record, so they are
asked the next time onboarding runs.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0007_disclaimer_acceptance"
down_revision: Union[str, None] = "0006_shorter_window"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("users", sa.Column("disclaimer_version", sa.String(length=32), nullable=True))
    op.add_column(
        "users", sa.Column("disclaimer_accepted_at", sa.DateTime(timezone=True), nullable=True)
    )


def downgrade() -> None:
    op.drop_column("users", "disclaimer_accepted_at")
    op.drop_column("users", "disclaimer_version")
