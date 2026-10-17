"""About: how CrisisConnect works, its safety rules, and image credits."""

import from "@jac/runtime" { Link }
import from ..components.ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..components.ui.separator { Separator }
import from ..components.app.page_parts { PageHero }

glob STEPS: list[list[str]] = [
    ["1", "Read", "Each SOS, update, offer or appeal is read into the same fields: who, how many, where, which phone, and who is vulnerable."],
    ["2", "Match", "Messages that share a phone number, a full name or a household-level place are proposed as the same incident."],
    ["3", "Referee", "Clear matches merge automatically. Unclear ones wait for a person. Nothing is merged on a guess."],
    ["4", "Rank", "Open incidents are ranked by risk, vulnerable people and waiting time, and every rank says why."]
];

glob PRINCIPLES: list[str] = [
    "People make the calls and the dispatch decisions; the app only lists, ranks and explains.",
    "Every status is written as a word. Colour is only a visual aid.",
    "A missing confirmed incident is never treated as evidence that an appeal is a scam.",
    "This build runs on synthetic data. Names and numbers are invented."
];

glob CREDITS: list[list[str]] = [
    ["Water rescue team in Oklahoma", "Marvin Nauman / FEMA", "Public domain", "https://commons.wikimedia.org/wiki/File:FEMA_-_32076_-_A_water_rescue_team_in_a_boat_searching_for_people_in_Oklahoma.jpg"],
    ["Rescue workers traveling by boat in Iowa", "Leo 'Jace' Anderson / FEMA", "Public domain", "https://commons.wikimedia.org/wiki/File:FEMA_-_44983_-_Rescue_workers_traveling_by_boat_in_Iowa.jpg"],
    ["Inside the Bexar County Emergency Operations Center", "Jocelyn Augustino / FEMA", "Public domain", "https://commons.wikimedia.org/wiki/File:FEMA_-_38187_-_Inside_the_Bexar_County_Emergency_Operations_Center_in_Texas.jpg"],
    ["Texas Emergency Operations Center", "Jocelyn Augustino / FEMA", "Public domain", "https://commons.wikimedia.org/wiki/File:FEMA_-_38220_-_Texas_Emergency_Operations_Center.jpg"],
    ["FEMA Community Relations workers speak with a resident", "Adam Dubrowa / FEMA", "Public domain", "https://commons.wikimedia.org/wiki/File:FEMA_-_39900_-_FEMA_Community_Relations_workers_speak_with_a_resident_in_Washington.jpg"],
    ["FCO meeting at the MEMA Emergency Operations Center", "George Armstrong / FEMA", "Public domain", "https://commons.wikimedia.org/wiki/File:FEMA_-_44036_-_FEMA_FCO_Meeting_at_MEMA_Emergency_Operations_Center_Yazoo_City.jpg"],
    ["Local volunteers at a Disaster Recovery Center in Ohio", "Mark Wolfe / FEMA", "Public domain", "https://commons.wikimedia.org/wiki/File:FEMA_-_32252_-_Local_Volunteers_help_at_the_Disaster_Recovery_Center_in_Ohio.jpg"],
    ["National Guard Black Hawk flood rescue", "Spc. Megan Zander / National Guard", "Public domain", "https://commons.wikimedia.org/wiki/File:National_Guard_assists_flood_fight_with_Blackhawk_rescue_160310-Z-KY097-004.jpg"],
    ["Colorado National Guard flood response", "The National Guard", "Public domain", "https://commons.wikimedia.org/wiki/File:Colorado_National_Guard_Flood_Response_(9772169535).jpg"],
    ["Flooding in Sri Lanka, MODIS, 9 December 2025", "MODIS Land Rapid Response Team, NASA GSFC", "Public domain", "https://commons.wikimedia.org/wiki/File:Flooding_in_Sri_Lanka_(MODIS_2025-12-09).jpg"]
];

glob STEP_TONES: list[str] = ["bg-blue-50 text-blue-600", "bg-violet-50 text-violet-600", "bg-amber-50 text-amber-700", "bg-emerald-50 text-emerald-600"];

def:pub AboutPage -> JsxPage {
    <div className="flex flex-col gap-6">
        <PageHero
            eyebrow="Help · About"
            title="One trusted inbox for a flood duty desk."
            description="CrisisConnect turns a night of scattered SOS messages into one ranked, explained call queue, so duty officers spend their calls on the people who need them most."
            image="/static/assets/images/helicopter-response.jpg"
            imageAlt="A rescue helicopter flying low over trees during a flood response"
            capsules={[["People decide", "blue"], ["Every rank explained", "violet"], ["Synthetic demo data", "amber"]]}
        />

        <Card>
            <CardHeader>
                <CardTitle>How it works</CardTitle>
                <CardDescription>Four steps for every message that arrives.</CardDescription>
            </CardHeader>
            <CardContent>
                <ol className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                    {for (i, s) in enumerate(STEPS) {
                        <li key={s[0]} className="flex gap-4 rounded-lg border pt-4 pb-4 pl-4 pr-4">
                            <span className={"flex size-9 shrink-0 items-center justify-center rounded-full text-sm font-semibold " + STEP_TONES[i % 4]}>
                                {s[0]}
                            </span>
                            <div>
                                <p className="font-medium">{s[1]}</p>
                                <p className="mt-1 text-sm text-muted-foreground">{s[2]}</p>
                            </div>
                        </li>
                    }}
                </ol>
            </CardContent>
        </Card>

        <Card>
            <CardHeader>
                <CardTitle>Safety rules</CardTitle>
            </CardHeader>
            <CardContent>
                <ul className="flex list-disc flex-col gap-2 pl-5 text-sm">
                    {for p in PRINCIPLES {
                        <li key={p}>{p}</li>
                    }}
                </ul>
            </CardContent>
        </Card>

        <Card>
            <CardHeader>
                <CardTitle>Image credits</CardTitle>
                <CardDescription>Photos and satellite imagery from Wikimedia Commons.</CardDescription>
            </CardHeader>
            <CardContent>
                <ul className="flex flex-col divide-y text-sm">
                    {for c in CREDITS {
                        <li key={c[3]} className="flex flex-col gap-1 pt-3 pb-3 first:pt-0 sm:flex-row sm:items-center sm:gap-4">
                            <a href={c[3]} target="_blank" rel="noopener noreferrer" className="font-medium text-primary underline-offset-4 hover:underline">
                                {c[0]}
                            </a>
                            <span className="text-muted-foreground">{c[1]}</span>
                            <span className="text-muted-foreground sm:ml-auto">{c[2]}</span>
                        </li>
                    }}
                </ul>
            </CardContent>
        </Card>

        <Separator />
        <p className="text-sm text-muted-foreground">
            Ready to start?
            {" "}
            <Link to="/" className="font-medium text-primary underline-offset-4 hover:underline">Go to the overview</Link>
        </p>
    </div>
}
