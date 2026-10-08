"""The medical disclaimer, and the record of who accepted which version.

The server is the only source of this text. The app fetches it to display and
posts back the version it showed, so the stored acceptance refers to wording the
server can still produce. A bundled copy in the app would be easier, but the two
could drift, and then someone's acceptance would point at wording they never
actually saw — which is the one thing this record exists to establish.

Change the text and the version together. Accounts that accepted an older
version keep that version on their row; they are not silently treated as having
agreed to wording that did not exist yet.
"""

# Bump on every wording change. Dates sort, read clearly in a database, and make
# "which text did they accept" answerable without a code archaeology session.
DISCLAIMER_VERSION = "2026-10-08"

DISCLAIMER_TEXT = (
    "TasteTrace is not a diagnostic tool and does not replace medical care. "
    "The app is intended to help users observe patterns between food and "
    "symptoms, not to diagnose, treat, or replace consultation with a licensed "
    "physician. TasteTrace uses AI to analyze the food and symptom data you log "
    "and to generate the patterns and insights shown in the app; these insights "
    "are generated automatically and are not reviewed by a medical professional "
    "before being shown to you. Users experiencing severe or worsening symptoms "
    "are directed within the app to seek medical attention rather than rely on "
    "the app's pattern-tracking features."
)

# Shown when a symptom is logged at Severe. The disclaimer above promises this
# exists, so it is kept beside the text that makes the promise.
SEVERE_SYMPTOM_GUIDANCE = (
    "That's a severe symptom. Please contact a doctor or seek medical attention "
    "rather than waiting to see what TasteTrace finds. Pattern tracking looks "
    "backwards over weeks; it is not a judgement about what you need right now."
)

# Intensity at or above this is "Severe" (see domain/severity.py).
SEVERE_INTENSITY = 4
