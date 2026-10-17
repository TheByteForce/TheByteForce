"""App shell: sidebar navigation, a header with the storm clock and replay
controls, and the shared desk state that every page reads."""

import from "@jac/runtime" { Outlet, Link, useLocation }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    DashboardSquare01Icon, InboxIcon, Call02Icon, Alert02Icon, UserGroupIcon,
    Shield01Icon, File01Icon, Activity01Icon, InformationCircleIcon, Clock01Icon,
    PlayIcon, PauseIcon, Database01Icon
}
import from ..components.ui.sidebar {
    SidebarProvider, Sidebar, SidebarHeader, SidebarContent, SidebarGroup, SidebarGroupLabel,
    SidebarGroupContent, SidebarMenu, SidebarMenuItem, SidebarMenuButton, SidebarFooter,
    SidebarInset, SidebarTrigger, SidebarRail
}
import from ..components.ui.separator { Separator }
import from ..components.ui.tooltip { TooltipProvider }
import from ..components.ui.button { Button }
import from ..components.ui.badge { Badge }
import from ..components.ui.progress { Progress }
import from ..components.ui.alert { Alert, AlertDescription }
import from ..components.ui.native_select { NativeSelectOption }
import from ..components.app.page_parts { SelectField }
import from ..components.app.brand { Wordmark }
import from ..components.app.desk_state { DeskProvider, use_desk }

glob DESK_NAV: list[dict[str, any]] = [
    {"to": "/", "label": "Overview", "icon": DashboardSquare01Icon},
    {"to": "/inbox", "label": "Inbox", "icon": InboxIcon},
    {"to": "/queue", "label": "Call queue", "icon": Call02Icon},
    {"to": "/activity", "label": "Agent activity", "icon": Activity01Icon}
];

glob COORD_NAV: list[dict[str, any]] = [
    {"to": "/alerts", "label": "Alert levels", "icon": Alert02Icon},
    {"to": "/volunteers", "label": "Volunteer offers", "icon": UserGroupIcon},
    {"to": "/appeals", "label": "Appeal checks", "icon": Shield01Icon},
    {"to": "/handover", "label": "DS hand-over", "icon": File01Icon}
];

def:pub is_active(path: str, to: str) -> bool {
    if to == "/" {
        return path == "/";
    }
    return path == to or path.startswith(to + "/");
}

def:pub page_title(path: str) -> str {
    if path.startswith("/incidents/") {
        return "Incident";
    }
    for item in DESK_NAV + COORD_NAV + [{"to": "/about", "label": "About"}] {
        if is_active(path, item["to"]) {
            return item["label"];
        }
    }
    return "CrisisConnect";
}

def:pub NavGroup(label: str, items: list[dict[str, any]], path: str) -> JsxElement {
    <SidebarGroup>
        <SidebarGroupLabel>{label}</SidebarGroupLabel>
        <SidebarGroupContent>
            <SidebarMenu>
                {for item in items {
                    <SidebarMenuItem key={item["to"]}>
                        <SidebarMenuButton asChild={True} isActive={is_active(path, item["to"])} tooltip={item["label"]}>
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

def:pub AppSidebar -> JsxElement {
    ctx: any = use_desk();
    location = useLocation();
    path: str = location.pathname;
    <Sidebar collapsible="icon">
        <SidebarHeader>
            <div className="pt-2 pb-2 pl-2 pr-2">
                <Link to="/" aria-label="CrisisConnect home">
                    <Wordmark />
                </Link>
            </div>
        </SidebarHeader>
        <SidebarContent>
            <NavGroup label="Duty desk" items={DESK_NAV} path={path} />
            <NavGroup label="Coordination" items={COORD_NAV} path={path} />
            <NavGroup label="Help" items={[{"to": "/about", "label": "About", "icon": InformationCircleIcon}]} path={path} />
        </SidebarContent>
        <SidebarFooter>
            <div className="flex flex-col gap-2 pt-2 pb-2 pl-2 pr-2">
                <label htmlFor="acting-desk" className="text-xs font-medium text-muted-foreground">Acting as</label>
                <SelectField
                    id="acting-desk"
                    value={ctx.desk}
                    className="w-full"
                    onChange={lambda (e: ChangeEvent) { ctx.setDesk(e.target.value); }}
                >
                    <NativeSelectOption value="Desk A">Desk A</NativeSelectOption>
                    <NativeSelectOption value="Desk B">Desk B</NativeSelectOption>
                    <NativeSelectOption value="Desk C">Desk C</NativeSelectOption>
                </SelectField>
            </div>
        </SidebarFooter>
        <SidebarRail />
    </Sidebar>
}

def:pub ReplayControls -> JsxElement {
    ctx: any = use_desk();
    position: int = 0;
    total: int = 0;
    clock: str = "--:--";
    if ctx.demo {
        position = ctx.demo.position;
        total = ctx.demo.total;
        if ctx.demo.storm_time {
            clock = ctx.demo.storm_time;
        }
    }
    finished: bool = total > 0 and position >= total;
    pct: int = (position * 100) // total if total > 0 else 0;
    toggle_label: str = "Start replay";
    if ctx.running {
        toggle_label = "Pause";
    } elif finished {
        toggle_label = "Finished";
    } elif position > 0 {
        toggle_label = "Resume replay";
    }

    <div className="ml-auto flex items-center gap-2 sm:gap-4">
        <div className="hidden items-center gap-2 text-sm md:flex" role="timer" aria-label="Storm clock">
            <HugeiconsIcon icon={Clock01Icon} strokeWidth={2} className="size-4 text-muted-foreground" />
            <span className="font-mono font-medium tabular-nums">{clock}</span>
        </div>
        <div className="hidden w-36 flex-col gap-1 lg:flex">
            <div className="flex justify-between text-xs text-muted-foreground">
                <span>Replay</span>
                <span className="tabular-nums">{f"{position} / {total}"}</span>
            </div>
            <Progress value={pct} aria-label="Replay progress" />
        </div>
        <Badge variant="secondary" className="hidden sm:inline-flex">Synthetic data</Badge>
        <Button
            variant="outline"
            size="sm"
            disabled={ctx.loading or ctx.busy}
            onClick={lambda (e: MouseEvent) { ctx.load(); }}
        >
            <HugeiconsIcon icon={Database01Icon} strokeWidth={2} data-icon="inline-start" />
            <span className="hidden sm:inline">{"Loading..." if ctx.loading else "Load demo data"}</span>
            <span className="sm:hidden">Load</span>
        </Button>
        <Button size="sm" disabled={ctx.loading or finished} onClick={lambda (e: MouseEvent) { ctx.toggle(); }}>
            <HugeiconsIcon icon={PauseIcon if ctx.running else PlayIcon} strokeWidth={2} data-icon="inline-start" />
            {toggle_label}
        </Button>
    </div>
}

def:pub Frame -> JsxElement {
    ctx: any = use_desk();
    location = useLocation();
    <SidebarProvider>
        <AppSidebar />
        <SidebarInset>
            <header className="sticky top-0 z-10 flex h-14 shrink-0 items-center gap-2 border-b bg-background pl-4 pr-4">
                <SidebarTrigger />
                <Separator orientation="vertical" className="mr-2 h-4" />
                <span className="truncate text-sm font-medium">{page_title(location.pathname)}</span>
                <ReplayControls />
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
