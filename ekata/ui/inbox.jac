"""Left column: messages received so far, plus a paste-a-message box."""

import from ekata.views { MsgView, ReplayStep }
import from ekata.api { submit_message }
import from ...components.ui.button { Button }
import from .atoms { Panel, MessageItem }

def:pub PasteBox(onSent: Callable[[ReplayStep], None]) -> JsxElement {
    has draft: str = "";
    has channel: str = "WEB";
    has sending: bool = False;
    has err: str = "";

    async def send() -> None {
        text = draft.strip();
        if text == "" or sending {
            return;
        }
        sending = True;
        err = "";
        try {
            r = await submit_message(text, channel);
            draft = "";
            onSent(r);
        } except Exception as ex {
            err = "Could not submit: " + str(ex);
        }
        sending = False;
    }

    <form
        className="mb-3 rounded-lg border bg-muted/40 p-3"
        onSubmit={lambda (e: FormEvent) { e.preventDefault(); send(); }}
    >
        <label htmlFor="paste-text" className="text-sm font-semibold">
            Paste a message
        </label>
        <textarea
            id="paste-text"
            rows={3}
            value={draft}
            placeholder="Paste an SOS, update or appeal here (any language)"
            className="mt-1 w-full rounded-md border bg-background p-2 text-base"
            onChange={lambda (e: ChangeEvent) { draft = e.target.value; }}
        ></textarea>
        <div className="mt-2 flex items-center gap-2">
            <label htmlFor="paste-channel" className="sr-only">
                Channel
            </label>
            <select
                id="paste-channel"
                value={channel}
                className="h-9 rounded-md border bg-background px-2 text-sm"
                onChange={lambda (e: ChangeEvent) { channel = e.target.value; }}
            >
                <option value="WEB">Web</option>
                <option value="SMS">SMS</option>
                <option value="WHATSAPP">WhatsApp</option>
                <option value="HOTLINE">Hotline</option>
            </select>
            <Button type="submit" className="ml-auto" disabled={sending or draft.strip() == ""}>
                {"Sending..." if sending else "Submit message"}
            </Button>
        </div>
        {if err != "" {
            <p role="alert" className="mt-2 text-sm font-semibold text-red-700 dark:text-red-300">{err}</p>
        }}
    </form>
}

def:pub Inbox(messages: list[MsgView], onSent: Callable[[ReplayStep], None]) -> JsxElement {
    <Panel title="Inbox" note={f"{len(messages)} received"}>
        <PasteBox onSent={onSent} />
        {if len(messages) == 0 {
            <p className="rounded-lg border border-dashed p-4 text-center text-muted-foreground">
                No messages yet. Load the demo data and start the replay, or paste one above.
            </p>
        }}
        <div className="flex flex-col gap-2">
            {for m in messages {
                <MessageItem key={m.msg_id} m={m} />
            }}
        </div>
    </Panel>
}
