"""Citizen: check an appeal or forwarded message before acting on it."""

import from "@jac/runtime" { Link }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { SecurityCheckIcon, Search01Icon }
import type from crisisconnect.portal { CitizenStatus }
import from crisisconnect.portal_api { citizen_send }
import from ...components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ...components.ui.button { Button }
import from ...components.ui.textarea { Textarea }
import from ...components.ui.alert { Alert, AlertTitle, AlertDescription }
import from ...components.app.desk_state { use_desk, remember_ref }
import from ...components.app.tags { VerdictTag }
import from ...components.app.page_parts { PageHero }

def:pub CheckPage -> JsxPage {
    ctx: any = use_desk();
    has text: str = "";
    has checking: bool = False;
    has result: CitizenStatus | None = None;
    has err: str = "";

    async def check -> None {
        msg = text.strip();
        if msg == "" or checking {
            return;
        }
        checking = True;
        err = "";
        try {
            result = await citizen_send(msg, "WHATSAPP");
            if result is not None and result.kind == "SOS" {
                remember_ref(result.msg_id);
            }
            ctx.bump();
        } except Exception as ex {
            err = "We could not check that message: " + str(ex);
        }
        checking = False;
    }

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow="Citizen · Check a message"
            title="Check an appeal before you pay or share."
            description="Paste a fundraising appeal or a forwarded warning. We compare it with official bulletins, the relief registry and other appeals."
            image="/static/assets/images/community-check.jpg"
            imageAlt="Response workers speaking with a resident at their door"
            capsules={[["Never share OTP codes", "red"], ["Official bulletins checked", "green"], ["Shared bank accounts flagged", "amber"]]}
        />

        <Card>
            <CardHeader>
                <CardTitle>Paste the message</CardTitle>
                <CardDescription>An appeal for money, a request for documents, or a forwarded warning.</CardDescription>
            </CardHeader>
            <CardContent>
                <form className="flex flex-col gap-4" onSubmit={lambda (e: FormEvent) { e.preventDefault(); check(); }}>
                    <label htmlFor="check-text" className="sr-only">Message to check</label>
                    <Textarea
                        id="check-text"
                        rows={5}
                        value={text}
                        className="text-base"
                        placeholder="Paste the appeal or forwarded message here"
                        onChange={lambda (e: ChangeEvent) { text = e.target.value; }}
                    />
                    <div>
                        <Button type="submit" size="lg" className="rounded-full pl-4 pr-4" disabled={checking or text.strip() == ""}>
                            <HugeiconsIcon icon={SecurityCheckIcon} strokeWidth={2} data-icon="inline-start" />
                            {"Checking..." if checking else "Check this message"}
                        </Button>
                    </div>
                    {if err != "" {
                        <Alert variant="destructive">
                            <AlertDescription>{err}</AlertDescription>
                        </Alert>
                    }}
                </form>
            </CardContent>
        </Card>

        {if result is None {
            skip;
        } elif result.kind == "SOS" {
                <Alert>
                    <HugeiconsIcon icon={Search01Icon} strokeWidth={2} />
                    <AlertTitle>This reads like a request for help</AlertTitle>
                    <AlertDescription>
                        <p>{"We sent it to the division desk. Your reference is " + result.msg_id + "."}</p>
                        <Link to={"/citizen/track?ref=" + result.msg_id} className="font-medium text-primary underline underline-offset-4">Track this request</Link>
                    </AlertDescription>
                </Alert>
        } elif result.kind == "APPEAL" or result.kind == "RUMOUR" {
                <Card>
                    <CardHeader>
                        <div className="flex flex-wrap items-center gap-2">
                            <CardTitle>{"What we found" if result.kind == "APPEAL" else "About this warning"}</CardTitle>
                            <VerdictTag verdict={result.verdict} />
                        </div>
                        <CardDescription>{result.verdict_reason}</CardDescription>
                    </CardHeader>
                    <CardContent>
                        <p className="text-sm font-medium">Do not send money, OTP codes or photos of your NIC to anyone you cannot verify.</p>
                    </CardContent>
                </Card>
        } else {
            <Alert>
                <AlertTitle>Nothing to check in this message</AlertTitle>
                <AlertDescription>It does not ask for money or make a claim we can check against official sources.</AlertDescription>
            </Alert>
        }}
    </div>
}
