"""CrisisConnect brand: a location pin holding three linked points.

The pin is the place where help is needed; the linked points are the
messages, desks and responders the app connects.
"""

import from ...lib.utils { cn }

def:pub LogoMark(className: str = "size-8") -> JsxElement {
    <svg viewBox="0 0 32 32" className={cn("shrink-0", className)} role="img" aria-label="CrisisConnect">
        <rect width="32" height="32" rx="8" className="fill-primary" />
        <path
            d="M16 5.5c-4.4 0-8 3.4-8 7.8 0 5.6 8 13.2 8 13.2s8-7.6 8-13.2c0-4.4-3.6-7.8-8-7.8z"
            className="fill-primary-foreground"
        />
        <path d="M12.9 12.2 16 16.6l3.1-4.4M12.9 12.2h6.2" fill="none" strokeWidth="1.3" strokeLinecap="round" className="stroke-primary" />
        <circle cx="12.9" cy="12.2" r="1.7" className="fill-primary" />
        <circle cx="19.1" cy="12.2" r="1.7" className="fill-primary" />
        <circle cx="16" cy="16.6" r="1.7" className="fill-primary" />
    </svg>
}

def:pub Wordmark -> JsxElement {
    <span className="flex items-center gap-2">
        <LogoMark className="size-8" />
        <span className="flex flex-col leading-tight">
            <span className="text-sm font-semibold tracking-tight">
                Crisis
                <span className="text-primary">Connect</span>
            </span>
            <span className="text-xs text-muted-foreground">Flood response desk</span>
        </span>
    </span>
}
