"""Appeal checks: fraud signals and an evidence-backed verdict per appeal."""

import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Shield01Icon, SecurityCheckIcon }
import type from ekata.appeal_check { AppealVerdict }
import from ekata.coordination_api { appeal_verdicts, run_appeal_checks }
import from ..components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..components.ui.button { Button }
import from ..components.ui.alert { Alert, AlertTitle, AlertDescription }
import from ..components.app.desk_state { use_desk }
import from ..components.app.tags { Tag, VerdictTag }
import from ..components.app.labels { plural, pretty }
import from ..components.app.page_parts { PageHero, EmptyNote, LoadingRows }

def:pub count_verdict(rows: list[AppealVerdict], verdict: str) -> int {
    return len([v for v in rows if v.verdict == verdict]);
}

def:pub AppealsPage -> JsxPage {
    ctx: any = use_desk();
    has rows: list[AppealVerdict] = [];
    has loaded: bool = False;
    has checking: bool = False;
    has err: str = "";

    async def load(t: int) -> None {
        try {
            rows = await appeal_verdicts(t);
        } except Exception as ex {
            rows = [];
        }
        loaded = True;
    }

    async def run_checks -> None {
        if checking {
            return;
        }
        checking = True;
        err = "";
        try {
            rows = await run_appeal_checks();
            ctx.bump();
        } except Exception as ex {
            err = "Could not run the checks: " + str(ex);
        }
        checking = False;
    }

    async can with [ctx.tick] entry {
        await load(ctx.tick);
    }

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow="Coordination · Appeal checks"
            title="Check an appeal before anyone pays."
            description="Fundraising and help appeals are checked for bank accounts shared across appeals, impersonation of officials, and requests for OTPs, NIC photos or bank logins."
            image="/static/assets/images/community-check.jpg"
            imageAlt="Response workers speaking with a resident at their door"
            capsules={[
                [f"{count_verdict(rows, 'LIKELY_SCAM')} likely scam", "red"],
                [f"{count_verdict(rows, 'SUSPICIOUS')} suspicious", "orange"],
                [f"{count_verdict(rows, 'MATCHED')} matched", "green"],
                [f"{count_verdict(rows, 'UNVERIFIED')} unverified", "slate"]
            ]}
        >
            <Button className="rounded-full pl-4 pr-4" disabled={checking} onClick={lambda (e: MouseEvent) { run_checks(); }}>
                <HugeiconsIcon icon={SecurityCheckIcon} strokeWidth={2} data-icon="inline-start" />
                {"Checking..." if checking else "Run appeal checks"}
            </Button>
        </PageHero>

        <Alert>
            <HugeiconsIcon icon={Shield01Icon} strokeWidth={2} />
            <AlertTitle>No confirmed incident is not proof of fraud</AlertTitle>
            <AlertDescription>
                An appeal is only flagged on positive fraud signals. Unverified appeals stay unverified until an official channel or a confirmed incident matches.
            </AlertDescription>
        </Alert>

        {if err != "" {
            <Alert variant="destructive">
                <AlertDescription>{err}</AlertDescription>
            </Alert>
        }}

        <p className="text-sm text-muted-foreground">{plural(len(rows), "appeal", "appeals")}</p>
        {if not loaded {
            <LoadingRows count={3} className="h-24" />
        } elif len(rows) == 0 {
            <EmptyNote
                title="No appeals received yet"
                description="Appeals asking for money or credentials are listed here with their verdict."
                icon={Shield01Icon}
            />
        } else {
            <div className="flex flex-col gap-4">
                {for v in rows {
                    <Card key={v.appeal_id}>
                        <CardHeader>
                            <div className="flex flex-wrap items-center gap-2">
                                <CardTitle className="font-mono">{v.appeal_id}</CardTitle>
                                <VerdictTag verdict={v.verdict} />
                                {for s in v.signals {
                                    <Tag key={s} label={pretty(s)} tone="red" />
                                }}
                            </div>
                            <CardDescription>{v.reason}</CardDescription>
                        </CardHeader>
                        {if len(v.evidence) > 0 {
                            <CardContent>
                                <p className="text-sm font-medium">Evidence</p>
                                <ul className="mt-2 list-disc pl-5 text-sm text-muted-foreground">
                                    {for ev in v.evidence {
                                        <li key={ev}>{ev}</li>
                                    }}
                                </ul>
                            </CardContent>
                        }}
                    </Card>
                }}
            </div>
        }}
    </div>
}
