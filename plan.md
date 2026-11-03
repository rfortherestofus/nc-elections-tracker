# NC election tracker: plan
Linear: [R4-8806](https://linear.app/rfortherestofus/issue/R4-8806/do-livestream-of-election-results). Built live on stream today, November 3, 2026. Polls close at 7:30 p.m. ET (4:30 p.m. PT, 00:30 UTC November 4). After the stream, the site updates itself with nobody watching.
## Decisions
| #   | Topic | Decision |
| --- | --- | --- |
| 1   | When | Build it live on stream now; it runs on its own tonight |
| 2   | Refresh | One looping GitHub Actions job, not a 5-minute cron |
| 3   | Repo | `rfortherestofus/nc-elections-tracker`, public |
| 4   | Hosting | Loop pushes rendered HTML to a `cloudflare` branch; Cloudflare Workers serves it (David's usual pattern) |
| 5   | Address | `ncelectionstracker.rfortherestofus.com` (David sets up the custom domain) |
| 6   | Scope | US Senate and US House only |
| 7   | Senate page | Results bars plus a county map of the margin; no vote-type chart |
| 8   | House page | Grid of 14 cards, one per district |
| 9   | Race calls | Never. "Leading" only, with an unofficial-results note |
| 10  | 2024 vs 2026 | 2024 for local preview only; only 2026 is ever published |
| 11  | Packages | renv |
| 12  | Loop timing | Start by hand on stream; 4:00 p.m. PT cron as backup; stop at full reporting plus 60 quiet minutes, or noon ET tomorrow |
| 13  | Git | Commit straight to `main` today, this repo only |
| 14  | Look | Navy (`#002868`) nav bar with the NC flag, Public Sans, party colors only in results |
## Data
All from the NC State Board of Elections live results server, `https://er.ncsbe.gov/enr/{ELECTION_DATE}/data/`:

- `county.txt`**:** one row per county plus statewide (`cid` 0): precincts reporting, ballots cast, registered voters, turnout, update time (`imp`).
  
- `results_0.txt`**:** statewide results, one row per candidate.
  
- `results_1.txt` **to** `results_100.txt`**:** the same by county, for the map. Fetched only when `results_0.txt` changed.
  

Field notes (verified against the 2024 precinct zip): every value is a string; `evc` is Election Day, `ovc` is early voting (one-stop), `avc` is mail, `pvc` is provisional; `prt`/`ptl` are precincts reporting and total; `col` is the state's party color without `#`. No CORS headers, so R fetches the data at render time. The server answers conditional requests with `304 Not Modified`.

The precinct zip is not used.
## Site
- **Status bar on every page:** last updated (from `county.txt`), precincts reporting, ballots cast, turnout.
  
- `index.qmd`**, US Senate:** a bar per candidate (share and votes, "Leading" label), then a county map of Cooper minus Whatley margin, diverging between the two party colors, grey for counties with no results yet.
  
- `house.qmd`**, US House:** 14 cards with candidate bars and precincts reporting.
  
- **Before results:** "Polls close at 7:30 p.m. ET. Results will appear here as counties report." Candidates listed, no zero bars, grey map. The site switches over once statewide votes are above zero.
  
- **Footer:** "Unofficial results from the NC State Board of Elections. Not a race call." plus "Made by R for the Rest of Us".
  
- **Look:** Quarto `cosmo` theme, navy `#002868` nav bar with a public-domain NC flag SVG as the logo, Public Sans from Google Fonts. No state red or gold in the design. Party colors come from the data.
  
- **Auto-refresh:** `<meta http-equiv="refresh" content="120">` so an open tab reloads every 2 minutes.
  
## 2024 preview vs 2026 publishing
- `ELECTION_DATE` sets the year. The code defaults to `20261103`.
  
- **Your Mac** has `_environment.local` with `ELECTION_DATE=20241105`, which Quarto reads. It's gitignored, so the Action never sees it.
  
- **Any render that isn't 2026** shows a large "2024 test data" banner.
  
- **Only the Action publishes.** Before every push, the loop checks the election date inside the downloaded data and refuses to publish anything but `11/03/2026`.
  
- **Gitignored:** `_site/`, `data/raw/`, `_environment.local`.
  
## Files
```
_quarto.yml
_environment.local      # Mac only, gitignored
index.qmd               # US Senate
house.qmd               # US House
_status.qmd             # status bar, included on both pages
R/fetch.R               # downloads with ETags into data/raw/
R/tidy.R                # tidy tibbles, numbers converted, "(VOTE FOR n)" split off
R/plots.R               # bars, cards, map
data/nc_counties.rds    # county outlines as a plain data frame, made once with tigris
images/nc-flag.svg
styles.scss
wrangler.jsonc          # copied onto the cloudflare branch
scripts/loop.sh         # the publish loop
.github/workflows/live.yml
renv.lock
```
## Refresh loop
`.github/workflows/live.yml`:

- **Triggers:** `workflow_dispatch`, plus `cron: "0 0 4 11 *"` (4:00 p.m. PT) as a backup.
  
- `concurrency` so two loops never run at once.
  
- **Setup once per run:** R, renv packages, Quarto.
  
- **Every 5 minutes:** conditional GET on `results_0.txt` and `county.txt`. If either changed, fetch the county files, render, check the election date, then force-push one fresh commit of `_site/` plus `wrangler.jsonc` to the `cloudflare` branch. Cloudflare deploys it in about a minute.
  
- **Errors:** a failed download or render keeps the last good site and tries again next cycle.
  
- **Stop:** all 2,626 Senate precincts reporting and no change for 60 minutes, or noon ET November 4.
  
- **6-hour job limit:** at about 5 hours 45 minutes, the loop starts a fresh run of the workflow and exits.
  
## Build order on stream
1. Scaffold the project, renv, `_environment.local`, `.gitignore`. Commit.
  
2. `R/fetch.R` and `R/tidy.R` against 2024. Commit.
  
3. Senate page: bars, then the map (make the county shapes file). Commit.
  
4. House page cards. Commit.
  
5. Theme, nav bar flag, status bar, footer. Commit.
  
6. Switch `_environment.local` to 2026 and preview the waiting state.
  
7. Create the GitHub repo, push, add the workflow. Commit.
  
8. David: connect the `cloudflare` branch in Cloudflare and add the custom domain.
  
9. Start the loop by hand and watch the first deploy.
  
## Risks to watch
- **Cloudflare and GitHub's built-in token:** I expect Cloudflare to see pushes made by the Action's token. The first loop push confirms it.
  
- **The state's 5 to 10 minute update rhythm** sets the real pace, not our loop.
  
- **Late-night county stragglers:** the noon ET hard stop covers them. Anything later, David updates by hand tomorrow.
