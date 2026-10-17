"""District: the relief registry, and publishing official bulletins."""

import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Megaphone01Icon, CheckmarkCircle01Icon, BookOpen01Icon }
import type from ekata.portal { NgoView, BulletinView, DivisionView }
import from ekata.portal_api { registry, bulletins, divisions, publish_bulletin }
import from ...components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ...components.ui.button { Button }
import from ...components.ui.textarea { Textarea }
import from ...components.ui.native_select { NativeSelectOption }
import from ...components.ui.table { Table, TableHeader, TableBody, TableRow, TableHead, TableCell }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.app.desk_state { use_desk }
import from ...components.app.tags { Tag }
import from ...components.app.labels { plural, pretty }
import from ...components.app.page_parts { PageHero, SelectField, IconChip }

glob ISSUERS: list[str] = ["District Flood Desk", "Landslide Watch", "Reservoir Office", "District Secretariat"];

def:pub RegistryPage -> JsxPage {
    ctx: any = use_desk();
    has offices: list[NgoView] = [];
    has notes: list[BulletinView] = [];
    has division_rows: list[DivisionView] = [];
    has issuer: str = "District Flood Desk";
    has area: str = "Kegalle";
    has text: str = "";
    has publishing: bool = False;
    has notice: str = "";
    has err: str = "";

    async can with [ctx.tick] entry {
        try {
            offices = await registry(ctx.tick);
            notes = await bulletins("", ctx.tick);
            division_rows = await divisions(ctx.tick);
        } except Exception as ex {
            offices = offices;
        }
    }

    async def publish -> None {
        msg = text.strip();
        if msg == "" or publishing {
            return;
        }
        publishing = True;
        err = "";
        notice = "";
        try {
            await publish_bulletin(issuer, area, msg);
            text = "";
            notice = "Bulletin published for " + area + ". Citizens in that area see it now.";
            ctx.bump();
        } except Exception as ex {
            err = "Could not publish: " + str(ex);
        }
        publishing = False;
    }

    areas: list[str] = ["Kegalle", "Ratnapura"] + [d.ds for d in division_rows if d.ds not in ["Kegalle", "Ratnapura"]];
    groups_n: int = len([o for o in offices if o.kind == "NGO"]);

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow="District coordination · Registry and bulletins"
            title="Who can help, and what people are told."
            description="The official registry of offices and relief groups, and the bulletins citizens see in their area."
            image="/static/assets/images/officials-meeting.jpg"
            imageAlt="Officials around a table at an emergency operations centre"
            capsules={[[plural(groups_n, "relief group", "relief groups"), "violet"], [plural(len(offices) - groups_n, "office", "offices"), "blue"], [plural(len(notes), "bulletin", "bulletins"), "orange"]]}
        />

        <div className="grid grid-cols-1 gap-6 xl:grid-cols-5">
            <Card className="xl:col-span-2">
                <CardHeader>
                    <div className="flex items-center gap-4">
                        <IconChip icon={Megaphone01Icon} tone="orange" />
                        <div className="flex flex-col gap-1">
                            <CardTitle>Publish a bulletin</CardTitle>
                            <CardDescription>Citizens in the area see it straight away. Warnings also mark the map.</CardDescription>
                        </div>
                    </div>
                </CardHeader>
                <CardContent>
                    <form className="flex flex-col gap-4" onSubmit={lambda (e: FormEvent) { e.preventDefault(); publish(); }}>
                        <div className="grid grid-cols-2 gap-4">
                            <div className="flex flex-col gap-2">
                                <label htmlFor="issuer" className="text-sm font-medium">Issued by</label>
                                <SelectField id="issuer" value={issuer} className="w-full" onChange={lambda (e: ChangeEvent) { issuer = e.target.value; }}>
                                    {for i in ISSUERS {
                                        <NativeSelectOption key={i} value={i}>{i}</NativeSelectOption>
                                    }}
                                </SelectField>
                            </div>
                            <div className="flex flex-col gap-2">
                                <label htmlFor="area" className="text-sm font-medium">Area</label>
                                <SelectField id="area" value={area} className="w-full" onChange={lambda (e: ChangeEvent) { area = e.target.value; }}>
                                    {for a in areas {
                                        <NativeSelectOption key={a} value={a}>{a}</NativeSelectOption>
                                    }}
                                </SelectField>
                            </div>
                        </div>
                        <div className="flex flex-col gap-2">
                            <label htmlFor="bulletin" className="text-sm font-medium">Bulletin text</label>
                            <Textarea id="bulletin" rows={4} value={text} onChange={lambda (e: ChangeEvent) { text = e.target.value; }} />
                        </div>
                        <Button type="submit" className="rounded-full" disabled={publishing or text.strip() == ""}>
                            {"Publishing..." if publishing else "Publish bulletin"}
                        </Button>
                        {if notice != "" {
                            <Alert>
                                <HugeiconsIcon icon={CheckmarkCircle01Icon} strokeWidth={2} />
                                <AlertDescription>{notice}</AlertDescription>
                            </Alert>
                        }}
                        {if err != "" {
                            <Alert variant="destructive">
                                <AlertDescription>{err}</AlertDescription>
                            </Alert>
                        }}
                    </form>
                </CardContent>
            </Card>

            <Card className="xl:col-span-3">
                <CardHeader>
                    <CardTitle>Published bulletins</CardTitle>
                    <CardDescription>Newest first.</CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-2">
                    {for (i, b) in enumerate(notes) {
                        <div key={str(i) + b.issued_at} className="rounded-lg border pt-3 pb-3 pl-3 pr-3 text-sm">
                            <p className="text-xs text-muted-foreground">{b.issued_at + " · " + b.issuer + " for " + b.area}</p>
                            <p className="mt-1 leading-relaxed">{b.text}</p>
                        </div>
                    }}
                </CardContent>
            </Card>
        </div>

        <Card>
            <CardHeader>
                <div className="flex items-center gap-4">
                    <IconChip icon={BookOpen01Icon} tone="violet" />
                    <div className="flex flex-col gap-1">
                        <CardTitle>Registry</CardTitle>
                        <CardDescription>Offices and relief groups CrisisConnect can route requests to.</CardDescription>
                    </div>
                </div>
            </CardHeader>
            <CardContent>
                <Table>
                    <TableHeader>
                        <TableRow>
                            <TableHead>Name</TableHead>
                            <TableHead>Contact</TableHead>
                            <TableHead>Areas</TableHead>
                            <TableHead>Offers</TableHead>
                            <TableHead className="text-right">Open requests</TableHead>
                        </TableRow>
                    </TableHeader>
                    <TableBody>
                        {for o in offices {
                            <TableRow key={o.office}>
                                <TableCell className="whitespace-normal">
                                    <span className="font-medium">{o.office}</span>
                                    <span className="mt-1 block"><Tag label={"Relief group" if o.kind == "NGO" else "Office"} tone={"violet" if o.kind == "NGO" else "blue"} /></span>
                                </TableCell>
                                <TableCell>{o.contact}</TableCell>
                                <TableCell className="whitespace-normal text-muted-foreground">{", ".join(o.areas)}</TableCell>
                                <TableCell className="whitespace-normal text-muted-foreground">{", ".join([pretty(x) for x in o.offers])}</TableCell>
                                <TableCell className="text-right tabular-nums">{str(o.open_requests)}</TableCell>
                            </TableRow>
                        }}
                    </TableBody>
                </Table>
            </CardContent>
        </Card>
    </div>
}
