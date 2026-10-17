"""Seed data for the demo: admin spine, registry of invented offices and NGOs,
and synthetic bulletins. Everything is fictional and hangs off the hub.

Real district and DS division names are used (they are public geography);
GN division names, offices, NGOs and contacts are invented. Phones follow
07X-555-01NN with a literal X so nobody can dial them.
"""

import json;
import os;
import from ekata.schema {
    EkataHub, Holds, District, DSDivision, GNDivision, InDS, InDistrict,
    RegistryEntry, Bulletin
}
import from ekata.store { wipe_hub, is_seeded }

# district -> DS divisions (a subset of the real ones)
glob SPINE: dict[str, list[str]] = {
    "Kegalle": ["Kegalle", "Mawanella", "Rambukkana", "Warakapola", "Aranayaka", "Dehiowita", "Yatiyantota"],
    "Ratnapura": ["Ratnapura", "Kuruwita", "Eheliyagoda", "Pelmadulla", "Balangoda"]
};

# invented GN division suffixes; the last one is the "GN not stated" placeholder
glob GN_SUFFIXES: list[str] = ["North", "South", "(GN not stated)"];

obj RegistrySeed {
    has office: str;
    has contact: str;
    has kind: str = "OFFICE";
}

obj BulletinSeed {
    has issuer: str;
    has area: str;
    has text: str;
    has issued_at: str;
}

def registry_seeds() -> list[RegistrySeed] {
    path = os.path.join("ekata", "fixtures", "registry.json");
    if os.path.exists(path) {
        with open(path, encoding="utf-8") as fh { data = json.load(fh); }
        return [RegistrySeed(office=str(x["office"]), contact=str(x["contact"]), kind=str(x.get("kind", "OFFICE"))) for x in data["offices"]];
    }
    return [
        RegistrySeed(office="Relief Coordinator, Kegalle Relief Unit", contact="07X-555-0190", kind="OFFICE"),
        RegistrySeed(office="Relief Coordinator, Ratnapura Relief Unit", contact="07X-555-0191", kind="OFFICE"),
        RegistrySeed(office="Operations Desk, Kegalle Flood Response Cell", contact="07X-555-0192", kind="OFFICE"),
        RegistrySeed(office="Rescue Liaison, Ratnapura Flood Response Cell", contact="07X-555-0193", kind="OFFICE"),
        RegistrySeed(office="Hill Country Aid Circle", contact="07X-555-0194", kind="NGO"),
        RegistrySeed(office="Kelani Valley Volunteers", contact="07X-555-0195", kind="NGO"),
        RegistrySeed(office="Green Ridge Boat Volunteers", contact="07X-555-0196", kind="NGO"),
        RegistrySeed(office="Ratnapura Helping Hands Society", contact="07X-555-0197", kind="NGO")
    ];
}

def bulletin_seeds() -> list[BulletinSeed] {
    return [
        BulletinSeed(
            issuer="DMC", area="Kegalle",
            text="Situation note 19:30: heavy rain continues over Kegalle and Ratnapura districts. Residents near river banks should be ready to move to higher ground.",
            issued_at="19:30"
        ),
        BulletinSeed(
            issuer="NBRO", area="Kegalle",
            text="Landslide alert (level 2) for the Mawanella, Aranayaka and Warakapola divisions. Avoid steep slopes and cut banks tonight.",
            issued_at="20:15"
        ),
        BulletinSeed(
            issuer="Irrigation", area="Kotmale",
            text="Kotmale dam: spill gates are operating as planned and water levels are within safe limits. The dam is safe; reports of a breach are false.",
            issued_at="21:00"
        ),
        BulletinSeed(
            issuer="Irrigation", area="Ratnapura",
            text="River level rising at the Ratnapura gauge. Flood warning for low-lying areas along the river.",
            issued_at="22:00"
        ),
        BulletinSeed(
            issuer="DMC", area="Ratnapura",
            text="Relief shelters are open at schools in Ratnapura and Kuruwita. Families should bring identity papers and essential medicine.",
            issued_at="22:30"
        )
    ];
}

def seed_spine(hub: EkataHub) {
    for dist_name in SPINE.keys() {
        d = District(name=dist_name);
        hub +>:Holds:+> d;
        for ds_name in SPINE[dist_name] {
            ds = DSDivision(name=ds_name);
            hub +>:Holds:+> ds;
            ds +>:InDistrict:+> d;
            for suffix in GN_SUFFIXES {
                gn = GNDivision(name=f"{ds_name} {suffix}");
                hub +>:Holds:+> gn;
                gn +>:InDS:+> ds;
            }
        }
    }
}

def seed_registry(hub: EkataHub) {
    for r in registry_seeds() {
        reg = RegistryEntry(office=r.office, contact=r.contact, kind=r.kind);
        hub +>:Holds:+> reg;
    }
}

def seed_bulletins(hub: EkataHub) {
    for b in bulletin_seeds() {
        bulletin = Bulletin(issuer=b.issuer, area=b.area, text=b.text, issued_at=b.issued_at);
        hub +>:Holds:+> bulletin;
    }
}

# Seed the static data if the hub is empty of it (idempotent, never duplicates).
def ensure_seeded(hub: EkataHub) {
    if is_seeded(hub) {
        return;
    }
    seed_spine(hub);
    seed_registry(hub);
    seed_bulletins(hub);
}

# load_demo: wipe everything the hub holds, reset counters, seed again.
def reset_and_seed(hub: EkataHub) {
    wipe_hub(hub);
    seed_spine(hub);
    seed_registry(hub);
    seed_bulletins(hub);
}
