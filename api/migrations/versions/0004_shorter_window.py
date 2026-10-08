"""Project: 6-hour default correlation window.

Revision ID: 0004_shorter_window
Revises: 0003_onboarding

The default window was 24 hours, which ties a symptom to every meal of the
previous day. New accounts now start at 6 hours. Accounts still on 24 never
had a way to tell a chosen 24 from the default, so they move to 6 as well;
anyone who wants a day-long window can pick it again in Tracking Rules. Their
stored associations are rebuilt on the next Triggers read.
"""

from typing import Sequence, Union

from alembic import op

revision: str = "0004_shorter_window"
down_revision: Union[str, None] = "0003_onboarding"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        "UPDATE user_settings SET correlation_window_hours = 6 WHERE correlation_window_hours = 24"
    )


def downgrade() -> None:
    op.execute(
        "UPDATE user_settings SET correlation_window_hours = 24 WHERE correlation_window_hours = 6"
    )
