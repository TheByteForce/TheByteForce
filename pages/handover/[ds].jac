"""One DS division's hand-over sheet: phone-verified incidents only."""

import from "@jac/runtime" { Link, useParams }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { PrinterIcon, CallIcon }
import type from ekata.ds_sheet { DsSheet }
import from ekata.coordination_api { ds_handover }
import from ...components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ...components.ui.button { Button }
import from ...components.ui.table { Table, TableHeader, TableBody, TableRow, TableHead, TableCell }
import from ...components.ui.breadcrumb {
    Breadcrumb, BreadcrumbList, BreadcrumbItem, BreadcrumbLink, BreadcrumbPage, BreadcrumbSeparator
}
import from ...components.app.desk_state { use_desk }
import from ...components.app.tags { StatusTag, VulnerableTag }
import from ...components.app.labels { people_label }
import from ...components.app.page_parts { EmptyNote, LoadingRows }

def:pub print_page -> None {
    win: any = window;
    win.print();
}

def:pub HandoverSheet -> JsxPage {
    ctx: any = use_desk();
    params = useParams();
    ds: str = params["ds"] or "";
    has sheet: DsSheet | None = None;
    has loaded: bool = False;

    async def load(t: int) -> None {
        try {
            sheet = await ds_handover(ds, t);
        } except Exception as ex {
            sheet = None;
        }
        loaded = True;
    }

    async can with (ctx.tick, ds) entry {
        await load(ctx.tick);
    }

    <div className="flex flex-col gap-6">
        <Breadcrumb>
            <BreadcrumbList>
                <BreadcrumbItem>
                    <BreadcrumbLink asChild={True}>
                        <Link to="/handover">DS hand-over</Link>
                    </BreadcrumbLink>
                </BreadcrumbItem>
                <BreadcrumbSeparator />
                <BreadcrumbItem>
                    <BreadcrumbPage>{ds}</BreadcrumbPage>
                </BreadcrumbItem>
            </BreadcrumbList>
        </Breadcrumb>

        {if not loaded {
            <LoadingRows count={3} className="h-16" />
        } elif sheet is None {
            <EmptyNote title="Sheet unavailable" description={f"No hand-over sheet could be built for {ds}."} icon={CallIcon} />
        } else {
            <Card>
                <CardHeader>
                    <div className="flex items-start justify-between gap-4">
                        <div className="flex flex-col gap-1">
                            <CardTitle className="text-xl">{sheet.ds + " DS division"}</CardTitle>
                            <CardDescription>{f"{sheet.district} district · as of {sheet.storm_time} · {sheet.confirmed} confirmed, {sheet.open_count} open"}</CardDescription>
                        </div>
                        <Button variant="outline" size="sm" onClick={lambda (e: MouseEvent) { print_page(); }}>
                            <HugeiconsIcon icon={PrinterIcon} strokeWidth={2} data-icon="inline-start" />
                            Print
                        </Button>
                    </div>
                </CardHeader>
                <CardContent className="flex flex-col gap-4">
                    <p className="text-sm text-muted-foreground">{sheet.note}</p>
                    {if len(sheet.rows) == 0 {
                        <EmptyNote
                            title="No phone-verified incidents yet"
                            description="An incident is listed here once a desk logs a confirmed call for it."
                            icon={CallIcon}
                        />
                    } else {
                        <Table>
                            <TableHeader>
                                <TableRow>
                                    <TableHead>Incident</TableHead>
                                    <TableHead>GN division</TableHead>
                                    <TableHead>Status</TableHead>
                                    <TableHead>People</TableHead>
                                    <TableHead>Needs</TableHead>
                                    <TableHead>Last call</TableHead>
                                </TableRow>
                            </TableHeader>
                            <TableBody>
                                {for r in sheet.rows {
                                    <TableRow key={r.inc_id}>
                                        <TableCell>
                                            <Link to={"/incidents/" + r.inc_id} className="font-mono text-sm text-primary underline-offset-4 hover:underline">
                                                {r.inc_id}
                                            </Link>
                                        </TableCell>
                                        <TableCell className="whitespace-normal">
                                            {r.gn}
                                            {if r.place != "" {
                                                <span className="block text-xs text-muted-foreground">{r.place}</span>
                                            }}
                                        </TableCell>
                                        <TableCell><StatusTag status={r.status} /></TableCell>
                                        <TableCell className="whitespace-normal">
                                            {people_label(r.headcount)}
                                            <span className="mt-1 flex flex-wrap gap-1">
                                                {for v in r.vulnerable {
                                                    <VulnerableTag key={v} flag={v} />
                                                }}
                                            </span>
                                        </TableCell>
                                        <TableCell className="whitespace-normal">{", ".join(r.needs) if len(r.needs) > 0 else "—"}</TableCell>
                                        <TableCell>
                                            {r.last_call if r.last_call != "" else "—"}
                                            {if r.last_desk != "" {
                                                <span className="block text-xs text-muted-foreground">{r.last_desk}</span>
                                            }}
                                        </TableCell>
                                    </TableRow>
                                }}
                            </TableBody>
                        </Table>
                    }}
                </CardContent>
            </Card>
        }}
    </div>
}
