"""Inbox: every message received so far, plus a box to paste a new one."""

import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { InboxIcon, SentIcon }
import type from ekata.views { MsgView }
import from ekata.api { inbox_messages, submit_message }
import from ..components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..components.ui.button { Button }
import from ..components.ui.textarea { Textarea }
import from ..components.ui.native_select { NativeSelectOption }
import from ..components.ui.tabs { Tabs, TabsList, TabsTrigger }
import from ..components.ui.alert { Alert, AlertDescription }
import from ..components.app.desk_state { use_desk }
import from ..components.app.items { MessageItem }
import from ..components.app.labels { plural }
import from ..components.app.page_parts { PageHero, EmptyNote, LoadingRows, SelectField }

glob KIND_FILTERS: list[list[str]] = [
    ["ALL", "All"], ["SOS", "SOS"], ["UPDATE", "Updates"], ["OFFER", "Offers"],
    ["APPEAL", "Appeals"], ["RUMOUR", "Rumours"]
];

def:pub InboxPage -> JsxPage {
    ctx: any = use_desk();
    has messages: list[MsgView] = [];
    has loaded: bool = False;
    has filter: str = "ALL";
    has draft: str = "";
    has channel: str = "WEB";
    has sending: bool = False;
    has notice: str = "";
    has err: str = "";

    async def load(t: int) -> None {
        try {
            messages = await inbox_messages(t);
        } except Exception as ex {
            err = "Could not load the inbox: " + str(ex);
        }
        loaded = True;
    }

    async def send -> None {
        text = draft.strip();
        if text == "" or sending {
            return;
        }
        sending = True;
        err = "";
        notice = "";
        try {
            r = await submit_message(text, channel);
            draft = "";
            notice = "Message received and processed." if r.message is None else f"Message {r.message.msg_id} received and processed.";
            ctx.bump();
        } except Exception as ex {
            err = "Could not submit: " + str(ex);
        }
        sending = False;
    }

    async can with [ctx.tick] entry {
        await load(ctx.tick);
    }

    shown: list[MsgView] = messages if filter == "ALL" else [m for m in messages if m.kind == filter];
    sos_n: int = len([m for m in messages if m.kind == "SOS"]);
    offer_n: int = len([m for m in messages if m.kind == "OFFER"]);
    appeal_n: int = len([m for m in messages if m.kind == "APPEAL"]);

    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow="Duty desk · Inbox"
            title="Every message, in one place."
            description="SMS, WhatsApp, hotline and web reports arrive here newest first. Paste a message to run it through the same pipeline."
            image="/static/assets/images/operations-center.jpg"
            imageAlt="Operators at their desks in an emergency operations centre"
            capsules={[
                [plural(len(messages), "message", "messages"), "blue"],
                [f"{sos_n} SOS", "red"],
                [plural(offer_n, "offer", "offers"), "green"],
                [plural(appeal_n, "appeal", "appeals"), "violet"]
            ]}
        />

        <Card>
            <CardHeader>
                <CardTitle>Paste a message</CardTitle>
                <CardDescription>An SOS, update, offer or appeal in any language.</CardDescription>
            </CardHeader>
            <CardContent>
                <form
                    className="flex flex-col gap-4"
                    onSubmit={lambda (e: FormEvent) { e.preventDefault(); send(); }}
                >
                    <label htmlFor="paste-text" className="sr-only">Message text</label>
                    <Textarea
                        id="paste-text"
                        rows={3}
                        value={draft}
                        placeholder="Example: 4 people on the roof at No 7 Udagama Road, Mawanella. 07X-555-0103"
                        onChange={lambda (e: ChangeEvent) { draft = e.target.value; }}
                    />
                    <div className="flex flex-wrap items-center gap-2">
                        <label htmlFor="paste-channel" className="text-sm text-muted-foreground">Channel</label>
                        <SelectField
                            id="paste-channel"
                            value={channel}
                            onChange={lambda (e: ChangeEvent) { channel = e.target.value; }}
                        >
                            <NativeSelectOption value="WEB">Web</NativeSelectOption>
                            <NativeSelectOption value="SMS">SMS</NativeSelectOption>
                            <NativeSelectOption value="WHATSAPP">WhatsApp</NativeSelectOption>
                            <NativeSelectOption value="HOTLINE">Hotline</NativeSelectOption>
                        </SelectField>
                        <Button type="submit" className="ml-auto rounded-full pl-4 pr-4" disabled={sending or draft.strip() == ""}>
                            <HugeiconsIcon icon={SentIcon} strokeWidth={2} data-icon="inline-start" />
                            {"Sending..." if sending else "Submit message"}
                        </Button>
                    </div>
                    {if notice != "" {
                        <p role="status" className="text-sm text-muted-foreground">{notice}</p>
                    }}
                    {if err != "" {
                        <Alert variant="destructive">
                            <AlertDescription>{err}</AlertDescription>
                        </Alert>
                    }}
                </form>
            </CardContent>
        </Card>

        <div className="flex flex-col gap-4">
            <div className="flex flex-wrap items-center justify-between gap-2">
                <Tabs value={filter} onValueChange={lambda (v: str) { filter = v; }}>
                    <TabsList className="h-auto flex-wrap rounded-full pt-1 pb-1 pl-1 pr-1">
                        {for f in KIND_FILTERS {
                            <TabsTrigger key={f[0]} value={f[0]} className="rounded-full pl-3 pr-3">{f[1]}</TabsTrigger>
                        }}
                    </TabsList>
                </Tabs>
                <span className="text-sm text-muted-foreground">{plural(len(shown), "message", "messages")}</span>
            </div>
            {if not loaded {
                <LoadingRows count={4} className="h-24" />
            } elif len(shown) == 0 {
                <EmptyNote
                    title="No messages here yet"
                    description="Start the demo night from the header, or paste a message above."
                    icon={InboxIcon}
                />
            } else {
                <div className="flex flex-col gap-2">
                    {for m in shown {
                        <MessageItem key={m.msg_id} m={m} />
                    }}
                </div>
            }}
        </div>
    </div>
}
