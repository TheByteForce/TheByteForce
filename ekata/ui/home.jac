"""Ekata home: one door per kind of person, each in its portal's colour.
Each person uses only their own portal."""

import from .shell { NavIcon, shell_bg, shell_mark }

def:pub Door(href: str, tone: str, icon: str, title: str, who: str, does: list[str]) -> JsxElement {
    <a
        href={href}
        className="group flex flex-col overflow-hidden rounded-xl border border-border bg-card transition-colors hover:border-foreground/30 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
    >
        <div className={shell_bg(tone) + " flex items-center gap-3 px-5 py-4 text-white"}>
            <span className={shell_mark(tone) + " flex size-9 items-center justify-center rounded-lg"}>
                <NavIcon name={icon}/>
            </span>
            <span>
                <span className="block text-[18px] font-bold leading-tight">{title}</span>
                <span className="block text-[13px] text-white/75">{who}</span>
            </span>
        </div>
        <ul className="space-y-2 px-5 py-4 text-[15px]">
            {for d in does {
                <li key={d} className="flex gap-2.5">
                    <span
                        className="mt-[9px] size-1.5 shrink-0 rounded-full bg-foreground/40"
                        aria-hidden="true"
                    ></span>
                    <span>{d}</span>
                </li>
            }}
        </ul>
        <span className="mt-auto px-5 pb-4 text-[14px] font-semibold text-primary group-hover:underline">
            {"Open " + title.lower()}
        </span>
    </a>
}

def:pub Home -> JsxElement {
    <main className="mx-auto max-w-[1100px] px-4 py-10 lg:py-16">
        <div className="flex items-center gap-3">
            <span
                className="flex size-11 items-center justify-center rounded-xl bg-[#0E3550] text-[20px] font-bold text-white"
                aria-hidden="true"
            >
                E
            </span>
            <span>
                <span className="block text-[20px] font-bold leading-tight">Ekata</span>
                <span className="block text-[13px] text-muted-foreground">One inbox for flood nights</span>
            </span>
        </div>
        <h1 className="mt-10 max-w-[24ch] text-[32px] font-bold leading-[1.15] tracking-tight sm:text-[42px]">
            One call per household on a flood night, the most vulnerable first.
        </h1>
        <p className="mt-4 max-w-[62ch] text-[17px] leading-relaxed text-muted-foreground">
            Ekata reads every SOS, merges the duplicates, sends each household to the
            right division and finds a group that can help. It also checks donation
            appeals and rumours against the registry and official bulletins.
        </p>
        <div className="mt-10 grid gap-4 sm:grid-cols-2">
            <Door
                href="#/citizen" tone="citizen" icon="sos"
                title="Citizen"
                who="People in the flood and their families"
                does={["Send an SOS in Sinhala, Tamil or English", "Follow your request until help arrives", "Check an appeal or a forwarded message", "Read official bulletins for your area"]}
            />
            <Door
                href="#/officer" tone="officer" icon="call"
                title="Division officer"
                who="Grama Niladhari and divisional desks"
                does={["Households in your division, most vulnerable first", "Call, confirm and record what you heard", "Ask a registered group for a boat, food or medicine"]}
            />
            <Door
                href="#/ngo" tone="ngo" icon="truck"
                title="Relief group"
                who="Registered NGOs and volunteer groups"
                does={["Requests matched to your area and what you offer", "Accept, decline, mark on the way or delivered", "See what is still waiting near you"]}
            />
            <Door
                href="#/district" tone="district" icon="overview"
                title="District coordination"
                who="District disaster management unit"
                does={["Every division at a glance", "Households waiting too long, escalated", "Bulletins, appeals, rumours and every agent decision"]}
            />
        </div>
        <p className="mt-10 text-[13px] text-muted-foreground">
            All names, phone numbers and organisations shown are invented for this demonstration.
        </p>
    </main>
}
