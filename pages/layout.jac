"""App shell: a sidebar with the current portal's pages and its workspace
picker, a slim header with a live indicator, and the shared live state."""

import from "@jac/runtime" { Outlet, Link, useLocation }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Home01Icon, InformationCircleIcon, GridIcon }
import type from ekata.portal { DivisionView, NgoView }
import from ekata.portal_api { divisions, ngos }
import from ..components.ui.sidebar {
    SidebarProvider, Sidebar, SidebarHeader, SidebarContent, SidebarGroup, SidebarGroupLabel,
    SidebarGroupContent, SidebarMenu, SidebarMenuItem, SidebarMenuButton, SidebarFooter,
    SidebarInset, SidebarTrigger, SidebarRail
}
import from ..components.ui.separator { Separator }
import from ..components.ui.tooltip { TooltipProvider }
import from ..components.ui.alert { Alert, AlertDescription }
import from ..components.ui.native_select { NativeSelectOption }
import from ..components.app.brand { Wordmark }
import from ..components.app.page_parts { SelectField }
import from ..components.app.desk_state { DeskProvider, use_desk, fresh_tick }
import from ..components.app.portals { portal_for, all_portals, citizen_areas }

def:pub is_active(path: str, to: str, home: str) -> bool {
    if to == home {
        return path == to;
    }
    return path == to or path.startswith(to + "/");
}

def:pub page_title(path: str, portal: dict[str, any] | None) -> str {
    if path == "/about" {
        return "About";
    }
    if portal is None {
        return "CrisisConnect";
    }
    if path.startswith("/officer/cases/") {
        return "Open case";
    }
    for item in portal["nav"] {
        if is_active(path, item["to"], portal["path"]) {
            return item["label"];
        }
    }
    return portal["name"];
}

def:pub NavGroup(label: str, items: list[dict[str, any]], path: str, home: str) -> JsxElement {
    <SidebarGroup>
        <SidebarGroupLabel>{label}</SidebarGroupLabel>
        <SidebarGroupContent>
            <SidebarMenu>
                {for item in items {
                    <SidebarMenuItem key={item["to"]}>
                        <SidebarMenuButton asChild={True} isActive={is_active(path, item["to"], home)} tooltip={item["label"]}>
                            <Link to={item["to"]}>
                                <HugeiconsIcon icon={item["icon"]} strokeWidth={2} />
                                <span>{item["label"]}</span>
                            </Link>
                        </SidebarMenuButton>
                    </SidebarMenuItem>
                }}
            </SidebarMenu>
        </SidebarGroupContent>
    </SidebarGroup>
}

# The picker that says whose workspace this is: area, division, group or analyst.
def:pub WorkspacePicker(portal: dict[str, any]) -> JsxElement {
    ctx: any = use_desk();
    has division_rows: list[DivisionView] = [];
    has group_rows: list[NgoView] = [];
    key: str = portal["key"];

    async can with [key] entry {
        try {
            if key == "officer" {
                division_rows = await divisions(fresh_tick());
            } elif key == "ngo" {
                group_rows = await ngos(fresh_tick());
            }
        } except Exception as ex {
            division_rows = [];
        }
    }

    <div className="flex flex-col gap-2 pt-2 pb-2 pl-2 pr-2">
        <label htmlFor="workspace" className="text-xs font-medium text-muted-foreground">{portal["workspace"]}</label>
        {if key == "citizen" {
            <SelectField id="workspace" value={ctx.area} className="w-full" onChange={lambda (e: ChangeEvent) { ctx.setArea(e.target.value); }}>
                <NativeSelectOption value="">Choose your area</NativeSelectOption>
                {for a in citizen_areas() {
                    <NativeSelectOption key={a} value={a}>{a}</NativeSelectOption>
                }}
            </SelectField>
        } elif key == "officer" {
            <SelectField id="workspace" value={ctx.ds} className="w-full" onChange={lambda (e: ChangeEvent) { ctx.setDs(e.target.value); }}>
                <NativeSelectOption value="">Choose your division</NativeSelectOption>
                {for d in division_rows {
                    <NativeSelectOption key={d.ds} value={d.ds}>{d.ds + " (" + d.district + ")"}</NativeSelectOption>
                }}
            </SelectField>
        } elif key == "ngo" {
            <SelectField id="workspace" value={ctx.group} className="w-full" onChange={lambda (e: ChangeEvent) { ctx.setGroup(e.target.value); }}>
                <NativeSelectOption value="">Choose your group</NativeSelectOption>
                {for g in group_rows {
                    <NativeSelectOption key={g.office} value={g.office}>{g.office}</NativeSelectOption>
                }}
            </SelectField>
        } else {
            <SelectField id="workspace" value={ctx.analyst} className="w-full" onChange={lambda (e: ChangeEvent) { ctx.setAnalyst(e.target.value); }}>
                <NativeSelectOption value="Analyst A">Analyst A</NativeSelectOption>
                <NativeSelectOption value="Analyst B">Analyst B</NativeSelectOption>
            </SelectField>
        }}
    </div>
}

def:pub AppSidebar -> JsxElement {
    location = useLocation();
    path: str = location.pathname;
    portal = portal_for(path);
    start_items: list[dict[str, any]] = [{"to": "/", "label": "Start", "icon": Home01Icon}];
    for p in all_portals() {
        start_items = start_items + [{"to": p["path"], "label": p["name"], "icon": p["nav"][0]["icon"]}];
    }

    <Sidebar collapsible="icon">
        <SidebarHeader>
            <div className="pt-2 pb-2 pl-2 pr-2">
                <Link to="/" aria-label="CrisisConnect start page">
                    <Wordmark />
                </Link>
            </div>
        </SidebarHeader>
        <SidebarContent>
            {if portal is not None {
                <NavGroup label={portal["name"]} items={portal["nav"]} path={path} home={portal["path"]} />
                <NavGroup
                    label="Switch"
                    items={[{"to": "/", "label": "All portals", "icon": GridIcon}]}
                    path={path}
                    home="/"
                />
            } else {
                <NavGroup label="Portals" items={start_items} path={path} home="/" />
                <NavGroup
                    label="Help"
                    items={[{"to": "/about", "label": "About", "icon": InformationCircleIcon}]}
                    path={path}
                    home="/"
                />
            }}
        </SidebarContent>
        {if portal is not None {
            <SidebarFooter>
                <WorkspacePicker portal={portal} />
            </SidebarFooter>
        }}
        <SidebarRail />
    </Sidebar>
}

def:pub LiveIndicator -> JsxElement {
    ctx: any = use_desk();
    count: int = ctx.live.messages_in if ctx.live else 0;
    <span className="ml-auto inline-flex items-center gap-2 rounded-full border bg-background pt-1 pb-1 pl-3 pr-3 text-xs font-medium text-muted-foreground" role="status">
        <span aria-hidden="true" className="relative flex size-2">
            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400 opacity-75"></span>
            <span className="relative inline-flex size-2 rounded-full bg-emerald-500"></span>
        </span>
        <span className="text-foreground">Live</span>
        <span className="hidden sm:inline">{f"{count} reports received"}</span>
    </span>
}

def:pub Frame -> JsxElement {
    ctx: any = use_desk();
    location = useLocation();
    path: str = location.pathname;
    <SidebarProvider>
        <AppSidebar />
        <SidebarInset>
            <header className="sticky top-0 z-10 flex h-14 shrink-0 items-center gap-2 border-b bg-background pl-4 pr-4">
                <SidebarTrigger />
                <Separator orientation="vertical" className="mr-2 h-4" />
                <span className="truncate text-sm font-medium">{page_title(path, portal_for(path))}</span>
                <LiveIndicator />
            </header>
            <main className="flex flex-1 flex-col gap-6 pt-6 pb-12 pl-4 pr-4 sm:pl-6 sm:pr-6">
                {if ctx.error {
                    <Alert variant="destructive">
                        <AlertDescription>{ctx.error}</AlertDescription>
                    </Alert>
                }}
                <Outlet />
            </main>
        </SidebarInset>
    </SidebarProvider>
}

def:pub Shell -> JsxLayout {
    <DeskProvider>
        <TooltipProvider delayDuration={0}>
            <Frame />
        </TooltipProvider>
    </DeskProvider>
}
