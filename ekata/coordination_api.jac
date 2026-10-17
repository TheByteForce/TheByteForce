"""Coordination endpoints for the desk and its partners (all :pub, on the shared hub).

  alert_levels      A 5-level alert per open incident with an action
                    (Level 3 means vulnerable people first).
  volunteer_offers  Offers of help listed against open incidents that need them
                    (listing only, no dispatch).
  appeal_verdicts   Ring, impersonation and credential-request signals give an
                    evidence-backed appeal verdict (R8/R9).
  run_appeal_checks The same check as a writer: stores each verdict on its appeal.
  ds_handover       A clean sheet of phone-verified incidents for one DS
                    division's officers.
  ds_divisions      Which DS divisions have incidents, for picking a sheet.

Readers take a tick argument because the client caches reads for 60 s.
"""

import from ekata.store { get_hub }
import from ekata.alert_level { alert_board, AlertRow }
import from ekata.volunteer_centre { match_offers, OfferMatch }
import from ekata.appeal_check { check_all_appeals, AppealVerdict }
import from ekata.ds_sheet { build_ds_sheet, ds_summary, DsSheet, DsCount }

def:pub alert_levels(tick: int = 0) -> list[AlertRow] {
    return alert_board(get_hub());
}

def:pub volunteer_offers(tick: int = 0) -> list[OfferMatch] {
    return match_offers(get_hub());
}

def:pub appeal_verdicts(tick: int = 0) -> list[AppealVerdict] {
    return check_all_appeals(get_hub(), False);
}

def:pub run_appeal_checks() -> list[AppealVerdict] {
    verdicts = check_all_appeals(get_hub(), True);
    commit();
    return verdicts;
}

def:pub ds_handover(ds: str, tick: int = 0) -> DsSheet {
    return build_ds_sheet(get_hub(), ds);
}

def:pub ds_divisions(tick: int = 0) -> list[DsCount] {
    return ds_summary(get_hub());
}
