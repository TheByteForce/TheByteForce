"""Small live provider check. Requires a configured local environment."""
import from crisisconnect.ai.intake { extract_report, intake_run_info }
import from crisisconnect.schema { MsgKind }
import from crisisconnect.ai.models { call_stats }
with entry:__main__ {
    rep = extract_report("Kumari Perera, 3 people including an elderly wheelchair user at house 14 Temple Road, Mawanella. Water is rising. Call 07X-555-0101", "WEB");
    info = intake_run_info();
    assert info["engine"] == "llm", "Live intake fell back to rules: " + info.get("error", "unknown error");
    assert rep.kind == MsgKind.SOS;
    assert "07X5550101" in rep.phones;
    assert rep.people_count == 3;
    assert info["model"] != "";
    stats = call_stats();
    assert stats["calls"] > 0;
    print("LIVE_INTAKE_OK model=" + info["model"] + " usage=" + str(stats));
}
