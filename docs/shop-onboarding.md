# Adding a shop

A shop needs rule data, a campaign entry and an independent art scene. `ShopRules` remains a pure simulation; normal application sessions and the authoring CLI enforce the configuration boundary. Supported fulfillment/dispatch settings and reserved fields are listed in [shop-capabilities.md](shop-capabilities.md).

## Data and campaign

1. Create a `SpecShop` resource containing its items, dishes, stations, stages, staff, layout, goals, fulfillment, dispatch and auxiliary rules. Keep IDs stable and unique within each collection, and resolve references inside the shop.
2. Set `scene_path` to a `PackedScene` whose root is `Node2D`. Set a shop-specific `save_file`.
3. Add a `SpecCampaignShop` with the same shop ID and its resource path to the desired campaign. Empty paths remain unimplemented entries and are skipped by navigation.
4. Validate before opening the shop. Errors are dictionaries with `code`, `path` and `message`; for example, `fulfillment.arrival` identifies an unsupported arrival policy. `ShopSpecValidator.summary(errors)` produces the startup/CLI message.

The production `Profile` defaults to the production campaign. A separate campaign can be supplied with `Profile.new(profile_path, campaign)`. Reopening that profile requires passing the same campaign. Use `profile.available_shops()` and `profile.next_shop(id)` for instance navigation; `Profile.shops()` intentionally retains the default production list. `ShopSession.shop_for(profile, target_id)` resolves an entry from the instance campaign.

## Art contract

`presentation/shop/shop_scene_contract.gd` exposes read-only `validate(shop, art)` and `prepare(shop)`. Preparation returns `{errors, art}` and frees rejected instances. The caller owns a successful candidate. The generic scene validates data and prepares one art candidate before calling `Session.start`; it adopts that exact candidate on success and frees it when session startup fails. An authoring error blocks business and saving without replacing or quarantining existing progress. Repair the configuration and use the retry button.

The scene uses one shared world coordinate system:

- Art root and the actor-parent chain must have identity transforms. `Anchors` is a `Node2D` at the origin. Descendant anchors support translation only; rotation, scale and skew are rejected.
- `Anchors` metadata can override `world_size`, `customer_height`, `staff_height` and `customer_speed`; sizes/speeds must be finite and positive. `sortables` resolves a `Node2D` relative to the art root, defaulting to `Sortables`. Rectangle anchors use `AnchorRect` with positive finite size. Optional numeric/vector metadata is type-checked before use.
- Every stage-unlocked station needs `Stations/<id>/Tap` and `/Frame`. Stations with upgrades/material purchases need a Tap. A counter can use the existing dining-seat chip entry instead of a Tap.
- A draggable seatable station or counter needs a Post rectangle and a matching `Drops/<n>` rectangle with `metadata/post`. Drop references must resolve to shop stations. Ground placement still uses the layout's existing fallback.
- Queue needs at least one point. The renderer extends its final segment for additional customers. Seat groups need enough `Seats/<group>/<n>` points for all declared stage seats and purchases.
- Every enabled connection needs `Connections/<id>/Frame` and at least two `Path` points. The rules use the same connection ID for the displayed route.
- An installed `shop_dining.gd` component additionally requires `Lanes`, `Aisle` and `Entrance`, because its path builder directly consumes those anchors. Its rendered dining group also needs enough `Tables/<group>` points for the declared seat capacity (starting seats plus explicit purchase steps, or the fixed step times purchase count). Table count rounds up for partial tables; `per_table` defaults to 2 and must be a positive integer. Table anchors remain optional without the dining component.
- `Nav` is optional (straight layouts commonly omit it). When present, its exported points/posts, areas, obstacles and navigation metadata must equal `shop.layout`; preflight never silently changes rule data to fit art.

Safe existing fallbacks stay optional: station Mark/Badge/Buffer/Put, shelf/chip decoration, Waiting, Sale and Pickup, and Exit (falls back to Entrance). In a scene without the dining component, Entrance and Aisle also have safe fallbacks. Other arbitrary art metadata remains available for decoration and extensions.

## Isolated third-shop example

`tests/fixtures/noodle/` contains a full `SpecShop`, its own one-shop campaign and an independent graybox scene. The scene exports the fixture's unchanged straight-layout coordinates. Its ASCII labels fit the existing production font; it uses generic character/item artwork, including the default drink placeholder for items. It is an interaction fixture, not a production noodle art pack.

The real-click regression constructs a real `Profile`, `ShopSave` and `ShopSession`; it never assigns `Profile.shop` directly. It opens the shop, hires employees, unlocks stations, upgrades a flavor, sells every dish, saves and reopens, checks exact subsequent simulation, and restarts into a new business. It also tests malformed data/art with an existing old shop file and a pending fresh-shop marker, including repair/retry and candidate disposal. The default campaign remains unchanged, and `tests/*` remains excluded from production exports.

Run from the project root:

```powershell
$env:APPDATA = 'D:/Tes/eatventure-analysis/shop-contracts-userdata/session-lifecycle-userdata/scene'
& 'D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe' --headless --path . -s tools/validate_shops.gd
& 'D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe' --headless --path . -s tests/render_shop_noodle.gd
```

The read-only CLI checks both production shops and the isolated fixture. CI runs it with a 30-second limit and the third-shop GUI regression with a 60-second limit. For graphical QA, omit `--headless` and append `-- --size=480x800 --screenshot=D:/path/noodle.png`; also check `720x1280` and `1280x720`. Capture arguments only resize the final QA view; the full input regression runs at 720x1280. Use isolated APPDATA/XDG_DATA_HOME for every test run; the session-lifecycle runner requires a `session-lifecycle-userdata` path segment.
