"""Catch-all for unknown paths."""

import from "@jac/runtime" { Link }
import from "@hugeicons/core-free-icons" { Search01Icon }
import from ..components.ui.button { Button }
import from ..components.app.page_parts { EmptyNote }

def:pub NotFound -> JsxPage {
    <EmptyNote
        title="Page not found"
        description="This page does not exist. Use the sidebar to find what you need."
        icon={Search01Icon}
    >
        <Button asChild={True}>
            <Link to="/">Go to the overview</Link>
        </Button>
    </EmptyNote>
}
