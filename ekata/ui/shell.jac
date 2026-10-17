"""App shell shared by every portal: a coloured sidebar (brand, workspace
picker, icon nav, collapse) and a quiet light content area.

Each portal has its own sidebar colour so a person always knows where they
are: citizen teal, officer river navy, relief group plum, district graphite.
Nav items are [key, label, icon] triples; icons are named, see NavIcon.
"""

import from "lucide-react" {
    LifeBuoy, Search, ShieldCheck, Megaphone, PhoneCall, Truck, Inbox, Building2,
    LayoutDashboard, MessageSquareWarning, BookUser, Activity, ChartColumn, Network,
    ChevronsLeft, ChevronsRight, ChevronDown, Users, MapPin
}

def:pub shell_bg(tone: str) -> str {
    if tone == "citizen" {
        return "bg-[#0F4C45]";
    }
    if tone == "officer" {
        return "bg-[#0E3550]";
    }
    if tone == "ngo" {
        return "bg-[#43204F]";
    }
    return "bg-[#1F2533]";
}

def:pub shell_mark(tone: str) -> str {
    if tone == "citizen" {
        return "bg-[#5FD3BC] text-[#0F4C45]";
    }
    if tone == "officer" {
        return "bg-[#7CC4E8] text-[#0E3550]";
    }
    if tone == "ngo" {
        return "bg-[#E2A8F0] text-[#43204F]";
    }
    return "bg-[#C9D2E3] text-[#1F2533]";
}

def:pub NavIcon(name: str) -> JsxElement {
    cls = "size-[18px] shrink-0";
    if name == "sos" { return <LifeBuoy className={cls}/>; }
    if name == "track" { return <Search className={cls}/>; }
    if name == "check" { return <ShieldCheck className={cls}/>; }
    if name == "bulletin" { return <Megaphone className={cls}/>; }
    if name == "call" { return <PhoneCall className={cls}/>; }
    if name == "truck" { return <Truck className={cls}/>; }
    if name == "inbox" { return <Inbox className={cls}/>; }
    if name == "org" { return <Building2 className={cls}/>; }
    if name == "overview" { return <LayoutDashboard className={cls}/>; }
    if name == "appeal" { return <MessageSquareWarning className={cls}/>; }
    if name == "registry" { return <BookUser className={cls}/>; }
    if name == "activity" { return <Activity className={cls}/>; }
    if name == "results" { return <ChartColumn className={cls}/>; }
    if name == "graph" { return <Network className={cls}/>; }
    if name == "people" { return <Users className={cls}/>; }
    return <MapPin className={cls}/>;
}

# A select styled for the dark sidebar card.
def:pub WorkspaceSelect(
    value: str, options: list[str], onPick: Callable[[str], None], placeholder: str = "Choose"
) -> JsxElement {
    <div className="relative">
        <select
            value={value}
            className="w-full appearance-none rounded-md border border-white/15 bg-white/10 py-2 pl-3 pr-8 text-[14px] font-semibold text-white focus-visible:outline-2 focus-visible:outline-white"
            onChange={lambda (e: ChangeEvent) { onPick(e.target.value); }}
        >
            {if value == "" {
                <option value="" className="text-foreground">{placeholder}</option>
            }}
            {for o in options {
                <option key={o} value={o} className="text-foreground">{o}</option>
            }}
        </select>
        <ChevronDown className="pointer-events-none absolute right-2.5 top-1/2 size-4 -translate-y-1/2 text-white/70"/>
    </div>
}

def:pub AppShell(
    tone: str,
    tagline: str,
    nav: list[list[str]],
    active: str,
    onNav: Callable[[str], None],
    title: str = "",
    subtitle: str = "",
    workspaceLabel: str = "",
    workspace: any = None,
    actions: any = None,
    children: any = None
) -> JsxElement {
    has collapsed: bool = False;

    bg = shell_bg(tone);
    mark = shell_mark(tone);

    <div className="min-h-dvh bg-background text-foreground lg:flex">
        <aside
            className={bg + " sticky top-0 hidden h-dvh shrink-0 flex-col text-white transition-[width] duration-200 lg:flex "
                + ("w-[76px]" if collapsed else "w-[264px]")}
        >
            <a href="#/" className="flex items-center gap-3 px-5 pb-5 pt-6" aria-label="Ekata home">
                <span className={mark + " flex size-10 shrink-0 items-center justify-center rounded-xl text-[18px] font-bold"}>
                    E
                </span>
                {if not collapsed {
                    <span className="min-w-0">
                        <span className="block text-[18px] font-bold leading-tight">Ekata</span>
                        <span className="block truncate text-[13px] text-white/70">{tagline}</span>
                    </span>
                }}
            </a>
            {if workspaceLabel != "" and not collapsed {
                <div className="mx-4 mb-5 rounded-lg bg-white/[0.07] p-3">
                    <p className="mb-2 flex items-center gap-2 text-[12px] font-semibold text-white/75">
                        <span className="size-1.5 rounded-full bg-white/80" aria-hidden="true"></span>
                        {workspaceLabel}
                    </p>
                    {workspace}
                </div>
            }}
            <nav aria-label="Sections" className="flex-1 space-y-1 px-3">
                {for item in nav {
                    <button
                        key={item[0]}
                        type="button"
                        title={item[1]}
                        aria-current={"page" if item[0] == active else "false"}
                        className={"flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-left text-[15px] transition-colors focus-visible:outline-2 focus-visible:outline-white "
                            + (
                                "bg-white/[0.13] font-semibold text-white"
                                    if item[0] == active
                                    else "text-white/75 hover:bg-white/[0.07] hover:text-white"
                            )}
                        onClick={lambda (e: MouseEvent) { onNav(item[0]); }}
                    >
                        <NavIcon name={item[2]}/>
                        {if not collapsed {
                            <span className="truncate">{item[1]}</span>
                        }}
                    </button>
                }}
            </nav>
            <button
                type="button"
                className="mx-3 mb-5 flex items-center justify-center gap-2 rounded-lg px-3 py-2 text-[13px] text-white/65 hover:bg-white/[0.07] hover:text-white"
                onClick={lambda (e: MouseEvent) { collapsed = not collapsed; }}
            >
                {if collapsed {
                    <ChevronsRight className="size-4"/>
                } else {
                    <ChevronsLeft className="size-4"/>
                }}
                {if not collapsed {
                    <span>Collapse</span>
                }}
            </button>
        </aside>

        <div className={bg + " sticky top-0 z-30 text-white lg:hidden"}>
            <div className="flex items-center gap-3 px-4 py-3">
                <a href="#/" className={mark + " flex size-8 items-center justify-center rounded-lg text-[15px] font-bold"} aria-label="Ekata home">
                    E
                </a>
                <span className="text-[16px] font-bold">Ekata</span>
                <span className="truncate text-[13px] text-white/70">{tagline}</span>
            </div>
            {if workspaceLabel != "" {
                <div className="px-4 pb-2">{workspace}</div>
            }}
            <nav aria-label="Sections" className="no-scrollbar flex gap-1 overflow-x-auto px-3 pb-2">
                {for item in nav {
                    <button
                        key={item[0]}
                        type="button"
                        className={"flex shrink-0 items-center gap-2 rounded-md px-3 py-2 text-[14px] "
                            + ("bg-white/[0.15] font-semibold" if item[0] == active else "text-white/75")}
                        onClick={lambda (e: MouseEvent) { onNav(item[0]); }}
                    >
                        <NavIcon name={item[2]}/>
                        <span>{item[1]}</span>
                    </button>
                }}
            </nav>
        </div>

        <main className="min-w-0 flex-1">
            <div className="mx-auto max-w-[1280px] px-4 py-6 lg:px-10 lg:py-9">
                {if title != "" {
                    <div className="mb-7 flex flex-wrap items-end justify-between gap-4">
                        <div>
                            <h1 className="text-[28px] font-bold leading-tight tracking-tight">{title}</h1>
                            {if subtitle != "" {
                                <p className="mt-1 text-[15px] text-muted-foreground">{subtitle}</p>
                            }}
                        </div>
                        <div className="flex flex-wrap items-center gap-2">{actions}</div>
                    </div>
                }}
                {children}
            </div>
        </main>
    </div>
}

# A quiet white surface for content blocks inside a page.
def:pub Surface(title: str = "", note: str = "", children: any = None) -> JsxElement {
    <section className="rounded-xl border border-border bg-card">
        {if title != "" {
            <div className="flex items-baseline justify-between gap-3 border-b border-border px-5 py-3.5">
                <h2 className="text-[16px] font-semibold">{title}</h2>
                <span className="text-[13px] text-muted-foreground">{note}</span>
            </div>
        }}
        <div className="p-5">{children}</div>
    </section>
}
