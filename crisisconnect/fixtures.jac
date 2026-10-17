"""Fixture loader for the replay: reads crisisconnect/fixtures/storm_night.json (a list of
{msg_id, storm_time, channel, text}); falls back to 8 built-in synthetic
messages when the file is missing or unreadable. All text is synthetic.
"""

import os;
import json;
import from crisisconnect.schema { CrisisConnectHub }

glob FIXTURE_FILE: str = "storm_night.json";

obj FixtureMsg {
    has msg_id: str;
    has storm_time: str;
    has channel: str = "WEB";
    has text: str = "";
}

def builtin_fixture() -> list[FixtureMsg] {
    return [
        FixtureMsg(
            msg_id="B001", storm_time="18:05", channel="SMS",
            text="HELP! 5 of us stuck on the roof, water rising fast. Granny is in a wheelchair. House 14 Temple Road Mawanella. Call 07X-555-0101 - Kumari Perera"
        ),
        FixtureMsg(
            msg_id="B002", storm_time="18:20", channel="WHATSAPP",
            text="My sister's family is trapped at 14 Temple Road Mawanella, please send a boat. Her number 07X 555 0101"
        ),
        FixtureMsg(
            msg_id="B003", storm_time="18:40", channel="SMS",
            text="Nimal Perera, 22 Temple Road Mawanella. 3 people, water inside the house. 07X-555-0102"
        ),
        FixtureMsg(
            msg_id="B004", storm_time="19:10", channel="SMS",
            text="Update: we are now 6 people at 14 Temple Road Mawanella. 07X-555-0101"
        ),
        FixtureMsg(
            msg_id="B005", storm_time="19:30", channel="HOTLINE",
            text="A baby and her mother need insulin urgently, Rambukkana junction school. 07X-555-0103"
        ),
        FixtureMsg(
            msg_id="B006", storm_time="20:00", channel="WHATSAPP",
            text="I heard the Kotmale dam has broken! Everyone run to the hills!"
        ),
        FixtureMsg(
            msg_id="B007", storm_time="20:30", channel="WHATSAPP",
            text="URGENT: donate to account SYN-XXXX-0001 for flood victims in Kegalle. Send money now."
        ),
        FixtureMsg(
            msg_id="B008", storm_time="21:15", channel="SMS",
            text="Update: the family at 14 Temple Road Mawanella was rescued by boat at 9pm. 07X-555-0101"
        )
    ];
}

def fixture_paths(path: str) -> list[str] {
    paths: list[str] = [];
    if path != "" {
        paths.append(path);
    }
    paths.append(os.path.join("crisisconnect", "fixtures", FIXTURE_FILE));
    try {
        paths.append(os.path.join(os.path.dirname(__file__), "fixtures", FIXTURE_FILE));
    } except Exception {
        paths.append(os.path.join("fixtures", FIXTURE_FILE));
    }
    return paths;
}

def parse_fixture(raw: str) -> list[FixtureMsg] {
    out: list[FixtureMsg] = [];
    data: any = json.loads(raw);
    items: any = data;
    if isinstance(data, dict) {
        items = data.get("messages", []);
    }
    for item in items {
        text = str(item.get("text", ""));
        mid = str(item.get("msg_id", ""));
        if text == "" or mid == "" {
            continue;
        }
        out.append(FixtureMsg(
            msg_id=mid,
            storm_time=str(item.get("storm_time", "")),
            channel=str(item.get("channel", "WEB")),
            text=text
        ));
    }
    return out;
}

# Reads the JSON fixture (first readable path wins); built-in messages otherwise.
def load_fixture(path: str = "") -> list[FixtureMsg] {
    for p in fixture_paths(path) {
        if os.path.exists(p) {
            try {
                with open(p, "r", encoding="utf-8") as fh {
                    raw = fh.read();
                }
                msgs = parse_fixture(raw);
                if len(msgs) > 0 {
                    return msgs;
                }
            } except Exception {
                continue;
            }
        }
    }
    return builtin_fixture();
}

# Record how many messages the replay will play.
def prepare_replay(hub: CrisisConnectHub) -> int {
    total = len(load_fixture());
    hub.replay_total = total;
    hub.replay_pos = 0;
    return total;
}

# The fixture message at the hub's replay position, or None when the night is over.
def peek_next(hub: CrisisConnectHub) -> FixtureMsg | None {
    msgs = load_fixture();
    hub.replay_total = len(msgs);
    if hub.replay_pos >= len(msgs) {
        return None;
    }
    return msgs[hub.replay_pos];
}
