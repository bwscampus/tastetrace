"""Project: TasteTrace tables, and the profile columns on users.

Revision ID: 0002_tastetrace_schema
Revises: 0001_template_auth

Branches from the last template revision so a future template migration can be
inserted before it with a one-line edit (references/schema.md).
"""

from typing import Sequence, Union

import fastapi_users_db_sqlalchemy
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "0002_tastetrace_schema"
down_revision: Union[str, None] = '0001_template_auth'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('ai_syntheses',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('user_id', fastapi_users_db_sqlalchemy.generics.GUID(), nullable=False),
    sa.Column('kind', sa.Text(), nullable=False),
    sa.Column('week_start', sa.String(length=10), nullable=False),
    sa.Column('symptom_filter', sa.Text(), nullable=False),
    sa.Column('input_hash', sa.String(length=64), nullable=False),
    sa.Column('source', sa.Text(), nullable=False),
    sa.Column('model', sa.Text(), nullable=True),
    sa.Column('text', sa.Text(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='cascade'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('user_id', 'kind', 'week_start', 'symptom_filter', name='uq_ai_synthesis_key')
    )
    op.create_table('correlations',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('user_id', fastapi_users_db_sqlalchemy.generics.GUID(), nullable=False),
    sa.Column('food_name', sa.Text(), nullable=False),
    sa.Column('symptom_name', sa.Text(), nullable=False),
    sa.Column('dimension', sa.Text(), nullable=False),
    sa.Column('exposures', sa.Integer(), nullable=False),
    sa.Column('flare_exposures', sa.Integer(), nullable=False),
    sa.Column('occurrences', sa.Integer(), nullable=False),
    sa.Column('confidence', sa.Integer(), nullable=False),
    sa.Column('is_ingredient', sa.Boolean(), nullable=False),
    sa.Column('baseline_rate', sa.Float(), nullable=True),
    sa.Column('lift', sa.Float(), nullable=True),
    sa.Column('avg_onset_hours', sa.Float(), nullable=True),
    sa.Column('window_hours', sa.Integer(), nullable=True),
    sa.Column('last_flare_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='cascade'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_correlations_user', 'correlations', ['user_id'], unique=False)
    op.create_table('custom_symptoms',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('user_id', fastapi_users_db_sqlalchemy.generics.GUID(), nullable=False),
    sa.Column('key', sa.Text(), nullable=False),
    sa.Column('name', sa.Text(), nullable=False),
    sa.Column('emoji', sa.String(length=16), nullable=False),
    sa.Column('body_region', sa.Text(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='cascade'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('user_id', 'key', name='uq_custom_symptoms_user_key')
    )
    op.create_table('dishes',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('user_id', fastapi_users_db_sqlalchemy.generics.GUID(), nullable=False),
    sa.Column('name', sa.Text(), nullable=False),
    sa.Column('emoji', sa.String(length=16), nullable=False),
    sa.Column('ingredients', sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), 'postgresql'), nullable=False),
    sa.Column('contains_gluten', sa.Boolean(), nullable=False),
    sa.Column('contains_dairy', sa.Boolean(), nullable=False),
    sa.Column('contains_grains', sa.Boolean(), nullable=False),
    sa.Column('contains_sugar', sa.Boolean(), nullable=False),
    sa.Column('contains_nuts', sa.Boolean(), nullable=False),
    sa.Column('times_logged', sa.Integer(), nullable=False),
    sa.Column('last_logged_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='cascade'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_dishes_user_id'), 'dishes', ['user_id'], unique=False)
    op.create_table('symptoms',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('user_id', fastapi_users_db_sqlalchemy.generics.GUID(), nullable=False),
    sa.Column('name', sa.Text(), nullable=False),
    sa.Column('severity', sa.Text(), nullable=False),
    sa.Column('intensity', sa.Integer(), nullable=True),
    sa.Column('duration_minutes', sa.Integer(), nullable=True),
    sa.Column('catalog_key', sa.Text(), nullable=True),
    sa.Column('timestamp', sa.DateTime(timezone=True), nullable=False),
    sa.Column('notes', sa.Text(), nullable=True),
    sa.Column('date', sa.String(length=10), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='cascade'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_symptoms_user_timestamp', 'symptoms', ['user_id', 'timestamp'], unique=False)
    op.create_table('user_settings',
    sa.Column('user_id', fastapi_users_db_sqlalchemy.generics.GUID(), nullable=False),
    sa.Column('timezone', sa.Text(), nullable=False),
    sa.Column('correlation_window_hours', sa.Integer(), nullable=False),
    sa.Column('min_trigger_count', sa.Integer(), nullable=False),
    sa.Column('min_confidence', sa.Integer(), nullable=False),
    sa.Column('streak_meals_per_day', sa.Integer(), nullable=False),
    sa.Column('nudge_time', sa.Text(), nullable=False),
    sa.Column('nudges_enabled', sa.Boolean(), nullable=False),
    sa.Column('meal_check_ins_enabled', sa.Boolean(), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='cascade'),
    sa.PrimaryKeyConstraint('user_id')
    )
    op.create_table('watchlist',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('user_id', fastapi_users_db_sqlalchemy.generics.GUID(), nullable=False),
    sa.Column('ingredient', sa.Text(), nullable=False),
    sa.Column('source', sa.Text(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='cascade'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('user_id', 'ingredient', name='uq_watchlist_user_ingredient')
    )
    op.create_table('meals',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('user_id', fastapi_users_db_sqlalchemy.generics.GUID(), nullable=False),
    sa.Column('name', sa.Text(), nullable=False),
    sa.Column('meal_type', sa.Text(), nullable=False),
    sa.Column('timestamp', sa.DateTime(timezone=True), nullable=False),
    sa.Column('notes', sa.Text(), nullable=True),
    sa.Column('is_custom', sa.Boolean(), nullable=False),
    sa.Column('ingredients', sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), 'postgresql'), nullable=False),
    sa.Column('ingredient_details', sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), 'postgresql'), nullable=True),
    sa.Column('dish_id', sa.Integer(), nullable=True),
    sa.Column('contains_gluten', sa.Boolean(), nullable=False),
    sa.Column('contains_dairy', sa.Boolean(), nullable=False),
    sa.Column('contains_grains', sa.Boolean(), nullable=False),
    sa.Column('contains_sugar', sa.Boolean(), nullable=False),
    sa.Column('contains_nuts', sa.Boolean(), nullable=False),
    sa.Column('date', sa.String(length=10), nullable=False),
    sa.ForeignKeyConstraint(['dish_id'], ['dishes.id'], ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='cascade'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_meals_user_timestamp', 'meals', ['user_id', 'timestamp'], unique=False)
    op.add_column('users', sa.Column('first_name', sa.String(length=60), nullable=True))
    op.add_column('users', sa.Column('last_name', sa.String(length=60), nullable=True))
    op.add_column('users', sa.Column('display_name', sa.String(length=80), nullable=True))
    op.add_column('users', sa.Column('avatar_emoji', sa.String(length=16), nullable=True))
    op.add_column('users', sa.Column('discovery_purpose', sa.Text(), nullable=True))
    op.add_column('users', sa.Column('sensitivity_tags', sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), 'postgresql'), nullable=False, server_default=sa.text("'[]'")))
    op.add_column('users', sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()))


def downgrade() -> None:
    op.drop_column('users', 'created_at')
    op.drop_column('users', 'sensitivity_tags')
    op.drop_column('users', 'discovery_purpose')
    op.drop_column('users', 'avatar_emoji')
    op.drop_column('users', 'display_name')
    op.drop_column('users', 'last_name')
    op.drop_column('users', 'first_name')
    op.drop_index('ix_meals_user_timestamp', table_name='meals')
    op.drop_table('meals')
    op.drop_table('watchlist')
    op.drop_table('user_settings')
    op.drop_index('ix_symptoms_user_timestamp', table_name='symptoms')
    op.drop_table('symptoms')
    op.drop_index(op.f('ix_dishes_user_id'), table_name='dishes')
    op.drop_table('dishes')
    op.drop_table('custom_symptoms')
    op.drop_index('ix_correlations_user', table_name='correlations')
    op.drop_table('correlations')
    op.drop_table('ai_syntheses')
