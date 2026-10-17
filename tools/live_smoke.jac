"""Small live provider check. Requires a configured local environment."""
import from ekata.ai.intake { extract_report, intake_run_info }
import from ekata.schema { MsgKind }
with entry:__main__ {
    rep = extract_report("Kumari Perera, 3 people including an elderly wheelchair user at house 14 Temple Road, Mawanella. Water is rising. Call 07X-555-0101", "WEB");
    info = intake_run_info();
    assert info["engine"] == "llm", "Live intake fell back to rules; inspect provider configuration.";
    assert rep.kind == MsgKind.SOS;
    assert "07X5550101" in rep.phones;
    assert rep.people_count == 3;
    print("LIVE_INTAKE_OK model=" + info["model"]);
}
