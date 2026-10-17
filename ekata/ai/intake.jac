"""Intake agent (A1): message text -> typed SosReport.

Contract stub: the AI implementation replaces the body; the signature stays.
"""

import from ekata.schema { SosReport, MsgKind }

def extract_report(text: str, channel: str = "WEB") -> SosReport {
    return SosReport(kind=MsgKind.SOS, summary=text[:80]);
}
