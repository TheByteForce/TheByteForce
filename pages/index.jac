"""Start page: the situation at a glance and a door into each portal."""

import from "@jac/runtime" { Link }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { ArrowRight01Icon }
import type from ekata.portal { DistrictOverview }
import from ekata.portal_api { district_board }
import from ..components.ui.button { Button }
import from ..components.app.desk_state { use_desk }
import from ..components.app.page_parts { Capsule }
import from ..components.app.portals { all_portals }

def:pub PortalDoor(p: dict[str, any]) -> JsxElement {
    <Link
        to={p["path"]}
        className="group flex flex-col overflow-hidden rounded-xl border bg-card transition-shadow hover:shadow-md focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
    >
        <div className="relative h-36 overflow-hidden">
            <img src={p["image"]} alt={p["imageAlt"]} className="h-full w-full object-cover transition-transform duration-500 group-hover:scale-105" />
            <div className="absolute inset-0 bg-gradient-to-t from-black/70 via-black/20 to-transparent"></div>
            <p className="absolute bottom-3 left-4 text-lg font-semibold text-white">{p["name"]}</p>
        </div>
        <div className="flex flex-1 flex-col gap-2 pt-4 pb-4 pl-4 pr-4">
            <p className="text-sm font-medium">{p["who"]}</p>
            <p className="flex-1 text-sm leading-relaxed text-muted-foreground">{p["pitch"]}</p>
            <span className="mt-2 inline-flex items-center gap-1 text-sm font-medium text-primary">
                {"Open " + p["name"].lower()}
                <HugeiconsIcon icon={ArrowRight01Icon} strokeWidth={2} className="size-4 transition-transform group-hover:translate-x-0.5" />
            </span>
        </div>
    </Link>
}

def:pub StartPage -> JsxPage {
    ctx: any = use_desk();
    has board: DistrictOverview | None = None;

    async can with [ctx.tick] entry {
        try {
            board = await district_board(ctx.tick);
        } except Exception as ex {
            board = None;
        }
    }

    capsules: list[list[str]] = [];
    if board is not None {
        capsules = [
            [f"{board.messages} reports received", "blue"],
            [f"{board.open_incidents} open cases", "amber"],
            [f"{board.vulnerable_open} with vulnerable people", "red"],
            [f"{board.unanswered} not yet called", "violet"]
        ];
    }

    <div className="flex flex-col gap-6">
        <section className="relative overflow-hidden rounded-xl border">
            <img
                src="/static/assets/images/rescue-team.jpg"
                alt="A water rescue team in an inflatable boat moving through a flooded street"
                className="absolute inset-0 h-full w-full object-cover"
            />
            <div className="absolute inset-0 bg-gradient-to-r from-black/85 via-black/65 to-black/20"></div>
            <div className="relative flex max-w-2xl flex-col gap-4 pt-12 pb-12 pl-6 pr-6 text-white sm:pt-16 sm:pb-16 sm:pl-10 sm:pr-10">
                <p className="text-sm font-medium text-white/80">CrisisConnect · Kegalle and Ratnapura floods</p>
                <h1 className="text-balance text-3xl font-bold tracking-tight sm:text-4xl">
                    Every SOS in one trusted queue.
                </h1>
                <p className="text-balance text-base leading-relaxed text-white/85">
                    Messages from SMS, WhatsApp, the hotline and the web are merged into cases, ranked by who needs a call first, and passed to the people who can help.
                </p>
                {if len(capsules) > 0 {
                    <div className="flex flex-wrap gap-2">
                        {for c in capsules {
                            <Capsule key={c[0]} label={c[0]} tone={c[1]} />
                        }}
                    </div>
                }}
                <div className="flex flex-wrap gap-2">
                    <Button asChild={True} className="rounded-full pl-4 pr-4">
                        <Link to="/officer">
                            Open the call queue
                            <HugeiconsIcon icon={ArrowRight01Icon} strokeWidth={2} data-icon="inline-end" />
                        </Link>
                    </Button>
                    <Button asChild={True} variant="secondary" className="rounded-full pl-4 pr-4">
                        <Link to="/citizen">Ask for help</Link>
                    </Button>
                </div>
            </div>
        </section>

        <div className="flex flex-col gap-1">
            <h2 className="text-xl font-semibold tracking-tight">Choose your portal</h2>
            <p className="text-sm text-muted-foreground">Each person works in one portal. The system keeps them all on the same picture.</p>
        </div>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {for p in all_portals() {
                <PortalDoor key={p["key"]} p={p} />
            }}
        </div>
    </div>
}
