"""District: every division at once, escalations and relief requests."""

import from "@jac/runtime" { Link }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    Message01Icon, Call02Icon, Alert02Icon, TruckIcon, UserGroupIcon, Clock01Icon
}
import type from ekata.portal { DistrictOverview, RequestView }
import from ekata.portal_api { district_board, all_requests }
import from ...components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ...components.ui.table { Table, TableHeader, TableBody, TableRow, TableHead, TableCell }
import from ...components.app.desk_state { use_desk }
import from ...components.app.tags { Tag, RequestTag, VulnerableTag }
import from ...components.app.labels { pretty, people_label, place_label }
import from ...components.app.page_parts { PageHero, LoadingRows, IconChip }
import from ...lib.utils { cn }

def:pub Figure(label: str, value: int, note: str, icon: any, tone: str, warn: bool = False) -> JsxElement {
    <Card className={cn("", "border-orange-200 bg-orange-50/50" if warn else "")}>
        <CardHeader>
            <div className="flex items-center justify-between">
                <CardDescription>{label}</CardDescription>
                <IconChip icon={icon} tone={tone} />
            </div>
            <CardTitle className="text-3xl font-semibold tabular-nums">{str(value)}</CardTitle>
        </CardHeader>
        <CardContent>
            <p className="text-sm text-muted-foreground">{note}</p>
        </CardContent>
    </Card>
}

def:pub DistrictOverviewPage -> JsxPage {
    ctx: any = use_desk();
    has board: DistrictOverview | None = None;
    has requests: list[RequestView] = [];

    async can with [ctx.tick] entry {
        try {
            board = await district_board(ctx.tick);
            requests = await all_requests(ctx.tick);
        } except Exception as ex {
            board = board;
        }
    }

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow="District coordination · Kegalle and Ratnapura"
            title="Every division, one picture."
            description="Where people are still waiting, which divisions are stretched, and which requests no relief group can cover yet."
            image="/static/assets/images/officials-meeting.jpg"
            imageAlt="Officials around a table at an emergency operations centre"
            capsules={[
                [f"{board.messages if board else 0} reports received", "blue"],
                [f"{len(board.escalations) if board else 0} escalations", "red"],
                [f"{len(board.divisions) if board else 0} divisions", "violet"]
            ]}
        />
        {if board is None {
            <LoadingRows count={4} className="h-28" />
        } else {
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-5">
                <Figure label="Open cases" value={board.open_incidents} note="Households still waiting or being helped" icon={Call02Icon} tone="blue" />
                <Figure label="Not yet called" value={board.unanswered} note="No officer has phoned them yet" icon={Clock01Icon} tone="amber" warn={board.unanswered > 0} />
                <Figure label="With vulnerable people" value={board.vulnerable_open} note="Children, elderly, disabled, pregnant or ill" icon={UserGroupIcon} tone="red" />
                <Figure label="Relief requests open" value={board.open_requests} note="Asked of relief groups, not yet delivered" icon={TruckIcon} tone="green" />
                <Figure label="No group can cover" value={board.uncovered_requests} note="Needs a district decision" icon={Alert02Icon} tone="orange" warn={board.uncovered_requests > 0} />
            </div>

            <Card>
                <CardHeader>
                    <CardTitle>Escalations</CardTitle>
                    <CardDescription>Households waiting too long without a call. 30 minutes, or 15 when someone vulnerable is there.</CardDescription>
                </CardHeader>
                <CardContent>
                    {if len(board.escalations) == 0 {
                        <p className="text-sm text-muted-foreground">No one is waiting too long right now.</p>
                    } else {
                        <Table>
                            <TableHeader>
                                <TableRow>
                                    <TableHead>Level</TableHead>
                                    <TableHead>Waiting</TableHead>
                                    <TableHead>Where</TableHead>
                                    <TableHead>People</TableHead>
                                    <TableHead>Division</TableHead>
                                    <TableHead>Why</TableHead>
                                </TableRow>
                            </TableHeader>
                            <TableBody>
                                {for e in board.escalations {
                                    <TableRow key={e.inc_id}>
                                        <TableCell><Tag label={e.level} tone={"red" if e.level == "District" else "amber"} /></TableCell>
                                        <TableCell className="tabular-nums">{e.waiting}</TableCell>
                                        <TableCell className="whitespace-normal">
                                            <Link to={"/officer/cases/" + e.inc_id} className="font-medium text-primary underline-offset-4 hover:underline">
                                                {place_label(e.place)}
                                            </Link>
                                            <span className="block text-xs text-muted-foreground">{e.inc_id}</span>
                                        </TableCell>
                                        <TableCell className="whitespace-normal">
                                            {people_label(e.headcount)}
                                            <span className="mt-1 flex flex-wrap gap-1">
                                                {for v in e.vulnerable {
                                                    <VulnerableTag key={v} flag={v} />
                                                }}
                                            </span>
                                        </TableCell>
                                        <TableCell>{e.ds}</TableCell>
                                        <TableCell className="whitespace-normal text-muted-foreground">{e.reason}</TableCell>
                                    </TableRow>
                                }}
                            </TableBody>
                        </Table>
                    }}
                </CardContent>
            </Card>

            <div className="grid grid-cols-1 gap-6 xl:grid-cols-2">
                <Card>
                    <CardHeader>
                        <CardTitle>Divisions</CardTitle>
                        <CardDescription>Load on each divisional desk.</CardDescription>
                    </CardHeader>
                    <CardContent>
                        <Table>
                            <TableHeader>
                                <TableRow>
                                    <TableHead>Division</TableHead>
                                    <TableHead>Desk</TableHead>
                                    <TableHead className="text-right">Open</TableHead>
                                    <TableHead className="text-right">Vulnerable</TableHead>
                                    <TableHead className="text-right">Not called</TableHead>
                                </TableRow>
                            </TableHeader>
                            <TableBody>
                                {for d in board.divisions {
                                    <TableRow key={d.ds}>
                                        <TableCell>
                                            <span className="font-medium">{d.ds}</span>
                                            <span className="block text-xs text-muted-foreground">{d.district}</span>
                                        </TableCell>
                                        <TableCell className="whitespace-normal text-muted-foreground">{d.officer}</TableCell>
                                        <TableCell className="text-right tabular-nums">{str(d.open_count)}</TableCell>
                                        <TableCell className="text-right tabular-nums">{str(d.vulnerable_open)}</TableCell>
                                        <TableCell className={cn("text-right tabular-nums", "font-semibold text-orange-600" if d.unanswered > 0 else "")}>{str(d.unanswered)}</TableCell>
                                    </TableRow>
                                }}
                            </TableBody>
                        </Table>
                    </CardContent>
                </Card>

                <Card>
                    <CardHeader>
                        <CardTitle>Requests to relief groups</CardTitle>
                        <CardDescription>Who is bringing what, and what nobody can cover yet.</CardDescription>
                    </CardHeader>
                    <CardContent className="flex flex-col gap-2">
                        {if len(requests) == 0 {
                            <p className="text-sm text-muted-foreground">No relief requests yet.</p>
                        }}
                        {for r in requests[:12] {
                            <div key={r.req_id} className={cn("flex flex-wrap items-center gap-2 rounded-lg border pt-3 pb-3 pl-3 pr-3 text-sm", "border-red-200 bg-red-50/60" if r.status == "UNCOVERED" else "")}>
                                <RequestTag status={r.status} />
                                <span className="font-medium">{pretty(r.need)}</span>
                                <span className="text-muted-foreground">{"for " + place_label(r.place)}</span>
                                <span className="ml-auto text-xs text-muted-foreground">{r.ngo if r.ngo != "" else r.reason}</span>
                            </div>
                        }}
                    </CardContent>
                </Card>
            </div>
        }}
    </div>
}
