"""Project: first-run onboarding answers.

Revision ID: 0003_onboarding
Revises: 0002_tastetrace_schema

Adds the data-sharing choice and onboarding timestamp to users, and the usual
meal times to user_settings. Accounts that already exist are marked as
onboarded so only new sign-ups see the questions.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0003_onboarding"
down_revision: Union[str, None] = "0002_tastetrace_schema"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("users", sa.Column("data_sharing", sa.String(length=20), nullable=True))
    op.add_column(
        "users", sa.Column("onboarding_completed_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.execute("UPDATE users SET onboarding_completed_at = created_at")

    op.add_column(
        "user_settings",
        sa.Column("breakfast_time", sa.Text(), nullable=False, server_default="09:00"),
    )
    op.add_column(
        "user_settings", sa.Column("lunch_time", sa.Text(), nullable=False, server_default="13:00")
    )
    op.add_column(
        "user_settings", sa.Column("dinner_time", sa.Text(), nullable=False, server_default="19:00")
    )


def downgrade() -> None:
    op.drop_column("user_settings", "dinner_time")
    op.drop_column("user_settings", "lunch_time")
    op.drop_column("user_settings", "breakfast_time")
    op.drop_column("users", "onboarding_completed_at")
    op.drop_column("users", "data_sharing")
