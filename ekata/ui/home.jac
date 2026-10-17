"""Ekata home: one door per kind of person. Each person uses only their own."""

def:pub Door(href: str, title: str, who: str, does: list[str]) -> JsxElement {
    <a
        href={href}
        className="group flex flex-col rounded-lg border border-border bg-card p-5 transition-colors hover:border-primary focus-visible:outline-2 focus-visible:outline-primary"
    >
        <span className="text-[21px] font-bold leading-tight group-hover:text-primary">
            {title}
        </span>
        <span className="mt-1 text-[13px] text-muted-foreground">{who}</span>
        <ul className="mt-4 space-y-1.5 text-[15px]">
            {for d in does {
                <li key={d} className="flex gap-2">
                    <span
                        className="mt-2 size-1.5 shrink-0 rounded-full bg-primary"
                        aria-hidden="true"
                    ></span>
                    <span>{d}</span>
                </li>
            }}
        </ul>
    </a>
}

def:pub Home -> JsxElement {
    <main className="mx-auto max-w-[1100px] px-4 py-10 lg:py-16">
        <div className="flex items-center gap-3">
            <span
                className="flex size-11 items-center justify-center rounded-full bg-primary text-[21px] font-bold text-primary-foreground"
                aria-hidden="true"
            >
                E
            </span>
            <span className="text-[21px] font-bold">Ekata</span>
        </div>
        <h1 className="mt-8 max-w-[22ch] text-[28px] font-bold leading-tight sm:text-[40px]">
            One call per household on a flood night, the most vulnerable first.
        </h1>
        <p className="mt-4 max-w-[60ch] text-[17px] text-muted-foreground">
            Ekata reads every SOS, merges the duplicates, sends each household to the
            right division and finds a group that can help. It also checks donation
            appeals and rumours against the registry and official bulletins.
        </p>
        <div className="mt-10 grid gap-4 sm:grid-cols-2">
            <Door
                href="#/citizen"
                title="I need help"
                who="For people in the flood and their families"
                does={["Send an SOS in Sinhala, Tamil or English", "Follow your request until help arrives", "Check an appeal or a forwarded message", "Read official bulletins for your area"]}
            />
            <Door
                href="#/officer"
                title="Division officer"
                who="Grama Niladhari and divisional secretariat desks"
                does={["Households in your division, most vulnerable first", "Call, confirm and record what you heard", "Ask a registered group for a boat, food or medicine", "Confirm appeals that name your office"]}
            />
            <Door
                href="#/ngo"
                title="Relief group"
                who="Registered NGOs and volunteer groups"
                does={["Requests matched to your area and what you offer", "Accept, decline, mark on the way or delivered", "See what is still uncovered near you"]}
            />
            <Door
                href="#/district"
                title="District coordination"
                who="District disaster management unit"
                does={["Every division at a glance", "Households waiting too long, escalated", "Publish bulletins, review appeals and rumours", "Every agent decision, with its reason"]}
            />
        </div>
        <p className="mt-10 text-[13px] text-muted-foreground">
            All names, phone numbers and organisations shown are invented for this demonstration.
        </p>
    </main>
}
