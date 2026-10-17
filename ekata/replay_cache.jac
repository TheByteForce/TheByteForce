"""Exact-input cache of real model outputs; never stores credentials or labels."""
import os;
import json;
import time;
import hashlib;
import fcntl;

def cache_mode() -> str { return os.environ.get("EKATA_CACHE_MODE", "live"); }

def cache_path() -> str { return os.environ.get("EKATA_CACHE_FILE", os.path.join("ekata", "fixtures", "recorded_run.json")); }

def cache_key(kind: str, payload: dict[str, any]) -> str {
    return hashlib.sha256(json.dumps([kind, payload], ensure_ascii=False, sort_keys=True).encode("utf-8")).hexdigest();
}

def cache_book() -> dict[str, any] {
    path = cache_path();
    if os.path.isfile(path) {
        with open(path, encoding="utf-8") as fh { return json.load(fh); }
    }
    return {"recorded_at": "", "entries": {}, "note": "Real model outputs for synthetic demo inputs only."};
}

def read_cached(kind: str, payload: dict[str, any]) -> any {
    if cache_mode() != "cached" { return None; }
    book = cache_book();
    return book["entries"].get(cache_key(kind, payload));
}

def record_cached(kind: str, payload: dict[str, any], value: dict[str, any], model: str) {
    if cache_mode() != "record" { return; }
    path = cache_path();
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True);
    with open(path + ".lock", "a") as lock {
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX);
        try {
            book = cache_book();
            stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime());
            if book["recorded_at"] == "" { book["recorded_at"] = stamp; }
            book["entries"][cache_key(kind, payload)] = {"kind": kind, "recorded_at": stamp, "model": model, "value": value};
            with open(path + ".tmp", "w", encoding="utf-8") as fh { json.dump(book, fh, ensure_ascii=False, indent=2); }
            os.replace(path + ".tmp", path);
        } finally { fcntl.flock(lock.fileno(), fcntl.LOCK_UN); }
    }
}

def cache_label() -> str {
    if os.environ.get("EKATA_AI", "on") == "off" { return "Rules engine"; }
    if cache_mode() == "cached" { return "Cached replay · live on cache miss"; }
    return "Live model engine";
}

def cache_timestamp() -> str {
    return str(cache_book().get("recorded_at", "")) if cache_mode() == "cached" else "";
}
