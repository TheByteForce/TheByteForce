"""Page furniture shared by every route: header, empty state, loading rows."""

import from "@hugeicons/react" { HugeiconsIcon }
import from ..ui.empty { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription, EmptyContent }
import from ..ui.skeleton { Skeleton }
import from ..ui.native_select { NativeSelect }
import from ...lib.utils { cn }

# Title block for a page, with an optional photo on wide screens.
def:pub PageHeader(
    title: str,
    description: str = "",
    image: str = "",
    imageAlt: str = "",
    children: any = None
) -> JsxElement {
    <div className="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
        <div className="flex min-w-0 flex-1 flex-col gap-2">
            <h1 className="text-balance text-2xl font-semibold tracking-tight sm:text-3xl">{title}</h1>
            {if description != "" {
                <p className="max-w-2xl text-base leading-relaxed text-muted-foreground">{description}</p>
            }}
            {if children {
                <div className="mt-2 flex flex-wrap items-center gap-2">{children}</div>
            }}
        </div>
        {if image != "" {
            <img
                src={image}
                alt={imageAlt}
                className="hidden h-28 w-48 shrink-0 rounded-xl border object-cover md:block lg:h-32 lg:w-56"
            />
        }}
    </div>
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
