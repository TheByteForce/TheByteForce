"""Page furniture shared by every route: photo hero, capsules, empty state, loading rows."""

import from "@hugeicons/react" { HugeiconsIcon }
import from ..ui.empty { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription, EmptyContent }
import from ..ui.skeleton { Skeleton }
import from ..ui.native_select { NativeSelect }
import from .tags { dot_class }
import from ...lib.utils { cn }

# A pill on a photo hero: a coloured dot and a live count or fact.
def:pub Capsule(label: str, tone: str = "slate") -> JsxElement {
    <span className="inline-flex items-center gap-2 rounded-full border border-white/25 bg-white/15 pt-1 pb-1 pl-3 pr-3 text-sm font-medium text-white backdrop-blur-sm">
        <span aria-hidden="true" className={cn("size-2 shrink-0 rounded-full", dot_class(tone))}></span>
        {label}
    </span>
}

# Page banner: a photo under a dark gradient, the page title, live capsules
# ([label, tone] pairs) and optional action buttons as children.
def:pub PageHero(
    title: str,
    image: str,
    imageAlt: str,
    eyebrow: str = "",
    description: str = "",
    capsules: list[list[str]] = [],
    children: any = None
) -> JsxElement {
    <section className="relative overflow-hidden rounded-xl border">
        <img src={image} alt={imageAlt} className="absolute inset-0 h-full w-full object-cover" />
        <div className="absolute inset-0 bg-gradient-to-r from-black/85 via-black/65 to-black/20"></div>
        <div className="relative flex max-w-3xl flex-col gap-4 pt-10 pb-10 pl-6 pr-6 text-white sm:pt-12 sm:pb-12 sm:pl-10 sm:pr-10">
            {if eyebrow != "" {
                <p className="text-sm font-medium text-white/80">{eyebrow}</p>
            }}
            <h1 className="text-balance text-3xl font-bold tracking-tight sm:text-4xl">{title}</h1>
            {if description != "" {
                <p className="text-balance text-base leading-relaxed text-white/85">{description}</p>
            }}
            {if len(capsules) > 0 {
                <div className="flex flex-wrap gap-2">
                    {for c in capsules {
                        <Capsule key={c[0]} label={c[0]} tone={c[1]} />
                    }}
                </div>
            }}
            {if children {
                <div className="flex flex-wrap gap-2">{children}</div>
            }}
        </div>
    </section>
}

# A soft coloured icon chip for card headers.
def:pub IconChip(icon: any, tone: str = "blue") -> JsxElement {
    <span className={cn("flex size-9 shrink-0 items-center justify-center rounded-full", chip_class(tone))}>
        <HugeiconsIcon icon={icon} strokeWidth={2} className="size-4" />
    </span>
}

def:pub chip_class(tone: str) -> str {
    if tone == "red" {
        return "bg-red-50 text-red-600";
    }
    if tone == "orange" {
        return "bg-orange-50 text-orange-600";
    }
    if tone == "amber" {
        return "bg-amber-50 text-amber-700";
    }
    if tone == "green" {
        return "bg-emerald-50 text-emerald-600";
    }
    if tone == "violet" {
        return "bg-violet-50 text-violet-600";
    }
    if tone == "slate" {
        return "bg-zinc-100 text-zinc-600";
    }
    return "bg-blue-50 text-blue-600";
}

def:pub EmptyNote(title: str, description: str, icon: any, children: any = None) -> JsxElement {
    <div className="rounded-xl border border-dashed pt-6 pb-6">
    <Empty>
        <EmptyHeader>
            <EmptyMedia variant="icon">
                <HugeiconsIcon icon={icon} strokeWidth={2} />
            </EmptyMedia>
            <EmptyTitle>{title}</EmptyTitle>
            <EmptyDescription>{description}</EmptyDescription>
        </EmptyHeader>
        {if children {
            <EmptyContent>{children}</EmptyContent>
        }}
    </Empty>
    </div>
}

# A native select with a single border (the registry wrapper draws a second one).
def:pub SelectField(
    id: str,
    value: str,
    onChange: Callable[[ChangeEvent], None],
    className: str = "",
    children: any = None
) -> JsxElement {
    <NativeSelect
        id={id}
        value={value}
        onChange={onChange}
        className={cn("h-auto border-0 bg-transparent p-0", className)}
    >
        {children}
    </NativeSelect>
}

def:pub LoadingRows(count: int = 3, className: str = "h-16") -> JsxElement {
    <div className="flex flex-col gap-2" aria-busy="true" aria-label="Loading">
        {for i in range(count) {
            <Skeleton key={str(i)} className={cn("w-full rounded-lg", className)} />
        }}
    </div>
}
