"""Top bar: title, storm clock, synthetic-data badge, replay controls and progress."""

import from ...components.ui.button { Button }
import from ...components.ui.badge { Badge }

def:pub TopBar(
    stormTime: str,
    position: int,
    total: int,
    running: bool,
    locked: bool,
    finished: bool,
    busy: bool,
    loading: bool,
    onLoad: Callable[[], None],
    onToggle: Callable[[], None]
) -> JsxElement {
    pct: int = 0;
    if total > 0 {
        pct = (position * 100) // total;
    }
    clock: str = stormTime if stormTime != "" else "--:--";
    toggle_label: str = "Start replay";
    if running {
        toggle_label = "Pause replay";
    } elif finished {
        toggle_label = "Replay finished";
    } elif position > 0 {
        toggle_label = "Resume replay";
    }
    is_live: bool = running or locked;

    <header className="border-b bg-card px-4 py-3 lg:px-6">
        <div className="flex flex-wrap items-center gap-x-6 gap-y-3">
            <div>
                <h1 className="text-xl font-bold tracking-tight">Rescue operations</h1>
                <p className="text-sm text-muted-foreground">
                    One call per household, most vulnerable first
                </p>
            </div>
            <div
                className="flex items-baseline gap-2"
                role="timer"
                aria-label="Storm clock"
            >
                <span
                    className="text-xs font-semibold uppercase tracking-wider text-muted-foreground"
                >
                    Storm clock
                </span>
                <span className="font-mono text-3xl font-semibold tabular-nums">
                    {clock}
                </span>
            </div>
            <div className="ml-auto flex flex-wrap items-center gap-3">
                {if is_live {
                    <span
                        className="flex items-center gap-2 rounded-full border border-emerald-600 bg-emerald-50 px-3 py-1 text-sm font-semibold text-emerald-900 dark:bg-emerald-950 dark:text-emerald-100"
                        role="status"
                    >
                        <span
                            className="size-2 animate-pulse rounded-full bg-emerald-600"
                            aria-hidden="true"
                        ></span>
                        Replay running
                    </span>
                }}
                <div
                    className="min-w-44 flex-1 sm:min-w-52"
                    aria-label="Replay progress"
                >
                    <div className="flex justify-between gap-4 text-xs tabular-nums">
                        <span className="text-muted-foreground">Replay</span>
                        <span className="font-semibold">{f"{position} / {total}"}</span>
                    </div>
                    <div
                        className="mt-1 h-2 overflow-hidden rounded-full bg-muted"
                        role="progressbar"
                        aria-valuemin={0}
                        aria-valuemax={100}
                        aria-valuenow={pct}
                    >
                        <div
                            className="h-full bg-primary transition-all"
                            style={{"width": f"{pct}%"}}
                        ></div>
                    </div>
                    <p className="mt-1 text-xs text-muted-foreground">
                        1 message every 1.5 seconds
                    </p>
                </div>
                <Button
                    variant="outline"
                    size="lg"
                    disabled={loading or busy}
                    onClick={lambda (e: MouseEvent) { onLoad(); }}
                >
                    {"Loading..." if loading else "Load demo data"}
                </Button>
                <Button
                    size="lg"
                    disabled={loading or finished}
                    onClick={lambda (e: MouseEvent) { onToggle(); }}
                >
                    {toggle_label}
                </Button>
            </div>
        </div>
    </header>
}
