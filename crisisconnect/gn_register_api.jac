"""GN register endpoints (all :pub, on the shared graph). See gn_register.jac.

Readers are pure and take a tick because the client caches reads for 60 s.
Writers take the graph writer lock: setup_gn_register seeds the register once
(load_demo also does), and open_gn_register leaves one audit Decision when an
officer opens a GN.
"""

import from crisisconnect.store { get_hub }
import from crisisconnect.locking { graph_writer }
import from crisisconnect.gn_register {
    GnChoice, GnRegisterView, current_register, ensure_register, register_size,
    gn_choices_in, gn_register_in, log_register_open
}

def:pub gn_areas(tick: int = 0) -> list[GnChoice] {
    return gn_choices_in(current_register());
}

def:pub gn_register(gn: str, tick: int = 0) -> GnRegisterView {
    return gn_register_in(get_hub(), current_register(), gn);
}

def:pub setup_gn_register() -> int {
    with graph_writer() {
        reg = ensure_register();
        commit();
        return register_size(reg);
    }
}

def:pub open_gn_register(gn: str, officer: str = "") -> bool {
    with graph_writer() {
        reg = ensure_register();
        ok = log_register_open(get_hub(), reg, gn, officer);
        commit();
        return ok;
    }
}
