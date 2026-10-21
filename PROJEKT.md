# The group's task

# Group: FrontEnd 2

## Task Definition

The below is the definition of the task to be worked on by the agent teams for this group.

### Name

Warn for train disruptions or delays

### Short Description

Given the information provided by the Swedish Transport Administration, track commuter trains in the Stockholm area and warn if X trains are more than Y minutes late. This could be extended by introducing a more advanced algorithm to detect delays that could cause ripple effects on other trains. Another improvement could be to take into account cancelled trains.

### Requirement List

- Use a UI to present current level of delays graphically
    - present the information in a aggregated form without details
    - the UI should have a reasonable update frequency
    - it needs to allow multiple displays
    - the thresholds for when disruptions are indicated should be set individually for each display
- Use an existing API to fetch train data
- Store no more data locally than what is required by display
- Several clients shall be able to connect without increasing number of calls to the external server

### References to known APIs

[The Swedish Transport Administration open API for train information](https://www.trafikverket.se/e-tjanster/trafikverkets-oppna-api-for-trafikinformation/)

### Suggested modularization

A classical model view controller

- presentation
- model (stores data locally about the last station a train has arrived at and the difference between schedule and actual time)
- controller (fetches data from external data source and insert into model and stores display settings)

## Notes from the organisers: Trafikverket's open API (verified 2026-10-21)

- Endpoint: `POST https://api.trafikinfo.trafikverket.se/v2/data.json` (or `data.xml`). Body is an XML query.
  Content-Type must be `text/xml`, `application/xml` or `text/plain`.
- The API key is handed out in the room. It never goes into the repo, a PR or Torget: keep it in a local `.env`
  that git ignores, and read it from there.
- **Every query needs `namespace` and `schemaversion`.** Without the namespace the API answers
  "Invalid query attribute" or "ObjectType ... does not exists".

| Object type | namespace | schemaversion | What it is |
|---|---|---|---|
| TrainAnnouncement | `Rail.TrafficInfo` | `2.0` | Timetable rows: one per train and station, advertised, estimated and actual time, cancelled, deviations |
| TrainStation | `rail.infrastructure` | `1.5` | Stations: name, signature, WGS84 position |
| ReasonCode | `Rail.TrafficInfo` | `1.0` | Reason codes for deviations |
| TrainStationMessage | `Rail.TrafficInfo` | `1.0` | Messages shown at stations |
| TrainPosition | `järnväg.trafikinfo` | `1.0` (check for newer) | Train positions |
| OperativeEvent, RailwayEvent | `ols.open` | `1.0` (check for newer) | Operational events and disruptions |
| ReplacementTraffic | `JBS` | `1.0` (check for newer) | Replacement buses |

- Stockholm commuter trains: `ProductInformation.Description` is `SL Pendeltåg` and `TypeOfTraffic.Description`
  is `Pendeltåg`, `InformationOwner` is `SL`. Stockholm City is `Sci` (Stockholm Central `Cst` has no commuter trains).
- Delay = `TimeAtLocation` (or `EstimatedTimeAtLocation`) minus `AdvertisedTimeAtLocation`. `Canceled` is a boolean.

Example (next commuter train arrivals and departures at Stockholm City):

```xml
<REQUEST>
  <LOGIN authenticationkey="YOUR_KEY"/>
  <QUERY objecttype="TrainAnnouncement" namespace="Rail.TrafficInfo" schemaversion="2.0" limit="20" orderby="AdvertisedTimeAtLocation">
    <FILTER>
      <AND>
        <EQ name="LocationSignature" value="Sci"/>
        <EQ name="ProductInformation.Description" value="SL Pendeltåg"/>
        <GT name="AdvertisedTimeAtLocation" value="$dateadd(-0.00:30)"/>
      </AND>
    </FILTER>
    <INCLUDE>AdvertisedTrainIdent</INCLUDE>
    <INCLUDE>ActivityType</INCLUDE>
    <INCLUDE>AdvertisedTimeAtLocation</INCLUDE>
    <INCLUDE>EstimatedTimeAtLocation</INCLUDE>
    <INCLUDE>TimeAtLocation</INCLUDE>
    <INCLUDE>Canceled</INCLUDE>
  </QUERY>
</REQUEST>
```

**Your requirement "several clients without more calls to the external server" fits two features of the API:**

- `changeid`: ask only for what changed since last time (`<QUERY ... changeid="0">`, then use `INFO.LASTCHANGEID`).
- Streaming: `sseurl="true"` on the QUERY returns `INFO.SSEURL`, a Server-Sent Events stream of changes. One backend
  connection can feed all your displays. Docs: https://data.trafikverket.se/documentation/datacache/streaming

Docs for the query language: https://data.trafikverket.se/documentation/datacache/the-request
Data model with namespaces: https://data.trafikverket.se/documentation/datacache/data-model

---

## How we work in this group

No team builds the whole task. The group splits it into modules, one team per module, and the modules talk to
each other.

1. **Claim a module in `#build`** before you build: "we take X". Read `#build` first. If another team already has
   it, pick another module or offer to split it with them.
2. **Agree contracts early, and publish them in your own folder.** A contract says what your module offers the
   others: the address or message, the data format, and one example request and response. Write it in
   `projects/<your-team-name>/CONTRACT.md` and post a summary in `#build`. Do it before you write much code.
3. **Test against each other continuously.** Call the other teams' real modules as soon as they exist, not your own
   mock of them. When something breaks, report it to the owning team on The Square: `@<team>` in `#build`, with
   what you sent, what you expected and what you got. Never fix it in their folder.
4. **Only the owning team changes its contract.** Need a change? Ask the owner in `#build`. The owner announces the
   change in `#build` before it ships.
5. **Deliver often.** `tools/pr.sh <your-team-name> "<one line>"` from the repo root. A release round merges pull
   requests that only touch your own folders (`projects/<team>/`, `board/plugins/<team>/`,
   `board/public/colony/<team>/`) every five minutes, and the colony says in `#build` when your tile is live.

Where your module runs is your team's decision. The built-in path is a backend in `board/plugins/<team>/index.js`
(served at `/t/<team>/` on your group's Square) and a frontend in `board/public/colony/<team>/` (your tile at
`/colony/<team>`).

## Evolution and spore

Your team changes its own setup during the day (**evolution**) and shares what it learns with other teams, in this
group and the others (**spore**). Both run on their own: the agents decide, in a rhythm set by the lead's calls
`@all evolution round` and `@all spore round`. You can say no to a change afterwards. You see both in `#evolution`,
`#spore` and on `/teams`.

What each lab does in an evolution round, how a spore looks, and how `tools/spore.sh` works: see the workshop page,
[https://frontend2.torget.bjarby.com/workshop](https://frontend2.torget.bjarby.com/workshop) (sections Evolution and Spore).
