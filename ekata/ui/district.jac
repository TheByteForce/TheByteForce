"""District coordination portal: overview, appeals and rumours, registry, agent activity, results."""
import from "react" { useEffect }
import type from ekata.portal { DistrictOverview, RequestView }
import from ekata.portal_api { district_board, all_requests }
import from .atoms { PortalHeader, Empty, Chip, RequestBadge, VulnerableBadge, tone_for, pretty, people_label }
import from .cases { Cases }
import from .metrics { MetricsPage }
import from .trace { AgentActivity }
import from .district_registry { RegistryTab }

def:pub Figure(label: str, value: int, hot: bool = False) -> JsxElement {
    <div className="min-w-0">
        <p className="text-[13px] text-muted-foreground">{label}</p>
        <p
            className={"text-[28px] font-semibold leading-tight tabular-nums "
                + ("text-alert" if hot and value > 0 else "")}
        >
            {value}
        </p>
    </div>
}

def:pub OverviewTab -> JsxElement {
    has board: DistrictOverview | None = None;
    has reqs: list[RequestView] = [];
    has tick: int = 0;
    has error: str = "";
    has loaded: bool = False;

    async def refresh -> None {
        try {
            tick = tick + 1;
            board = await district_board(tick);
            reqs = await all_requests(tick);
            error = "";
        } except Exception as e {
            error = "Could not load the district board. It will retry.";
        }
        loaded = True;
    }
    async can with entry {
        await refresh();
    }
    useEffect(
        lambda {
            timer = setInterval(lambda { refresh(); }, 5000);
            return lambda { clearInterval(timer); };
        },
        []
    );

    <section aria-label="Overview" className="space-y-8">
        {if error != "" {
            <p role="alert" className="text-[13px] text-blocked">{error}</p>
        }}
        {if board is not None {
            <div className="grid grid-cols-2 gap-x-6 gap-y-4 border-b border-border pb-6 sm:grid-cols-3 lg:grid-cols-5">
                <Figure label="Open households" value={board.open_incidents}/>
                <Figure label="Not yet called" value={board.unanswered}/>
                <Figure label="With vulnerable people" value={board.vulnerable_open}/>
                <Figure label="Open requests to groups" value={board.open_requests}/>
                <Figure label="No group could cover" value={board.uncovered_requests} hot={True}/>
            </div>
            <div>
                <h2 className="mb-2 text-[17px] font-semibold">Escalations</h2>
                {if len(board.escalations) == 0 {
                    <Empty title="Nothing has waited too long" hint="Households that wait past the limit appear here, oldest first."/>
                }}
                {if len(board.escalations) > 0 {
                    <div className="overflow-x-auto border-y border-border">
                        <table className="w-full text-left text-[15px]">
                            <thead>
                                <tr className="border-b border-border text-[13px] text-muted-foreground">
                                    <th className="py-2 pr-4 font-semibold">Level</th>
                                    <th className="py-2 pr-4 font-semibold">Waiting</th>
                                    <th className="py-2 pr-4 font-semibold">Household</th>
                                    <th className="py-2 pr-4 font-semibold">Division</th>
                                    <th className="py-2 font-semibold">Reason</th>
                                </tr>
                            </thead>
                            <tbody>
                                {for esc in board.escalations {
                                    <tr key={esc.inc_id} className="border-b border-border align-top last:border-0">
                                        <td className="py-2 pr-4">
                                            <Chip label={pretty(esc.level)} tone={tone_for("alert")}/>
                                        </td>
                                        <td className="py-2 pr-4 font-semibold text-alert">{esc.waiting}</td>
                                        <td className="py-2 pr-4">
                                            <p>{esc.place if esc.place != "" else esc.inc_id}</p>
                                            <p className="text-[13px] text-muted-foreground">
                                                {people_label(esc.headcount)}
                                            </p>
                                            {if len(esc.vulnerable) > 0 {
                                                <div className="mt-1 flex flex-wrap gap-1">
                                                    {for v in esc.vulnerable {
                                                        <VulnerableBadge key={v} flag={v}/>
                                                    }}
                                                </div>
                                            }}
                                        </td>
                                        <td className="py-2 pr-4">{esc.ds}</td>
                                        <td className="py-2">{esc.reason}</td>
                                    </tr>
                                }}
                            </tbody>
                        </table>
                    </div>
                }}
            </div>
            <div>
                <h2 className="mb-2 text-[17px] font-semibold">Divisions</h2>
                <div className="overflow-x-auto border-y border-border">
                    <table className="w-full text-left text-[15px]">
                        <thead>
                            <tr className="border-b border-border text-[13px] text-muted-foreground">
                                <th className="py-2 pr-4 font-semibold">District</th>
                                <th className="py-2 pr-4 font-semibold">Division</th>
                                <th className="py-2 pr-4 font-semibold">Officer</th>
                                <th className="py-2 pr-4 font-semibold">Open</th>
                                <th className="py-2 pr-4 font-semibold">Vulnerable</th>
                                <th className="py-2 font-semibold">Not yet called</th>
                            </tr>
                        </thead>
                        <tbody>
                            {for d in board.divisions {
                                <tr key={d.ds} className="border-b border-border last:border-0">
                                    <td className="py-2 pr-4">{d.district}</td>
                                    <td className="py-2 pr-4 font-semibold">{d.ds}</td>
                                    <td className="py-2 pr-4">{d.officer}</td>
                                    <td className="py-2 pr-4 tabular-nums">{d.open_count}</td>
                                    <td className="py-2 pr-4 tabular-nums">{d.vulnerable_open}</td>
                                    <td className="py-2 tabular-nums">{d.unanswered}</td>
                                </tr>
                            }}
                        </tbody>
                    </table>
                </div>
            </div>
        }}
        {if board is None and loaded {
            <Empty title="No district data yet"/>
        }}
        <div>
            <h2 className="mb-2 text-[17px] font-semibold">Requests to groups</h2>
            {if len(reqs) == 0 {
                <Empty title="No requests to groups yet" hint="Officers raise these when a household needs boats, food or medicine."/>
            }}
            {if len(reqs) > 0 {
                <div className="overflow-x-auto border-y border-border">
                    <table className="w-full text-left text-[15px]">
                        <thead>
                            <tr className="border-b border-border text-[13px] text-muted-foreground">
                                <th className="py-2 pr-4 font-semibold">Status</th>
                                <th className="py-2 pr-4 font-semibold">Need</th>
                                <th className="py-2 pr-4 font-semibold">Where</th>
                                <th className="py-2 pr-4 font-semibold">Group</th>
                                <th className="py-2 font-semibold">Why this group</th>
                            </tr>
                        </thead>
                        <tbody>
                            {for r in reqs {
                                <tr
                                    key={r.req_id}
                                    className={"border-b border-border align-top last:border-0 "
                                        + ("bg-blocked-soft" if r.status == "UNCOVERED" else "")}
                                >
                                    <td className="py-2 pr-4"><RequestBadge status={r.status}/></td>
                                    <td className="py-2 pr-4 font-semibold">{pretty(r.need)}</td>
                                    <td className="py-2 pr-4">
                                        {r.place if r.place != "" else r.inc_id}
                                        <span className="block text-[13px] text-muted-foreground">
                                            {people_label(r.headcount)}
                                        </span>
                                    </td>
                                    <td className="py-2 pr-4">
                                        {r.ngo if r.ngo != "" else "None yet"}
                                        {if r.ngo_contact != "" {
                                            <span className="block text-[13px] text-muted-foreground">
                                                {r.ngo_contact}
                                            </span>
                                        }}
                                    </td>
                                    <td className="py-2">{r.reason}</td>
                                </tr>
                            }}
                        </tbody>
                    </table>
                </div>
            }}
        </div>
    </section>
}

def:pub DistrictPortal -> JsxElement {
    has tab: str = "overview";
    tabs = [
        ["overview", "Overview"],
        ["cases", "Appeals and rumours"],
        ["registry", "Registry and bulletins"],
        ["agents", "Agent activity"],
        ["results", "Results"]
    ];
    <div className="min-h-screen bg-background text-foreground">
        <PortalHeader portal="District coordination" who="Kegalle and Ratnapura districts"/>
        <nav aria-label="District sections" className="border-b border-border bg-card">
            <div className="mx-auto flex max-w-[1500px] gap-1 overflow-x-auto px-4 lg:px-6">
                {for t in tabs {
                    <button
                        key={t[0]}
                        type="button"
                        aria-current={"page" if tab == t[0] else None}
                        className={"whitespace-nowrap border-b-2 px-3 py-3 text-[15px] font-semibold focus-visible:outline-2 focus-visible:outline-primary "
                            + ("border-primary text-primary" if tab == t[0] else "border-transparent text-muted-foreground hover:text-foreground")}
                        onClick={lambda (e: MouseEvent) { tab = t[0]; }}
                    >
                        {t[1]}
                    </button>
                }}
            </div>
        </nav>
        <main className="mx-auto max-w-[1500px] px-4 py-6 lg:px-6">
            {if tab == "overview" {
                <OverviewTab/>
            }}
            {if tab == "cases" {
                <Cases/>
            }}
            {if tab == "registry" {
                <RegistryTab/>
            }}
            {if tab == "agents" {
                <AgentActivity/>
            }}
            {if tab == "results" {
                <MetricsPage/>
            }}
        </main>
    </div>
}
