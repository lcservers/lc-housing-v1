# LC Housing

**Created by LC**

A self-contained property and housing system for QBCore and QBox/QBX FiveM servers. LC Housing stores its own properties, ownership, doors, interior points, and furniture. `qb-houses` is not required.

## Features

- Administrator and real-estate property management panel
- Create, edit, delete, list, purchase, and sell properties
- Spawned shell properties with named visual shell selection
- Live shell thumbnails captured from the front door looking inward
- In-world MLO and IPL property records with PolyZone boundaries
- Owner property menu and saved interior points
- Property entrances, garages, map blips, and door locks
- Native persistent furniture catalogue and placement editor
- Server-authoritative ownership, purchase, furniture, and property validation
- Automatic database table creation and schema updates
- Prompt and optional `qb-target`/`ox_target` interaction modes
- QBCore and QBox/QBX framework detection

## Requirements

Required:

- A current FiveM server artifact
- `oxmysql`
- `qb-core` or `qbx_core`
- A MySQL/MariaDB database configured for the framework

Recommended:

- `screenshot-basic` for administrator shell thumbnails
- `qb-inventory` or `ox_inventory` for property stashes
- `qb-garages` for house garages
- `qb-target` or `ox_target` for third-eye interaction
- `illenium-appearance`, `qb-clothing`, or `fivem-appearance` for wardrobes

Shell previews fail safely when `screenshot-basic` is unavailable; property management remains usable.

## Installation

1. Place the folder in your resources directory and keep its name as `lc-housing`.
2. Ensure the required resources start before LC Housing:

   ```cfg
   ensure oxmysql
   ensure qb-core       # or: ensure qbx_core
   ensure screenshot-basic
   ensure lc-housing
   ```

3. Import `install/lc_housing.sql` if you want to create the main table manually. LC Housing also creates and updates its tables automatically when it starts.
4. Add the `realestate` job using `install/realestate_job.lua`, or give an existing job the name configured in `Config.JobName`.
5. Restart the framework after changing its jobs file, then restart `lc-housing`.
6. Join the server as an authorized real-estate employee and run `/housing`.

Do not install `qb-houses` for LC Housing. `Config.MirrorQbHouses` is disabled by default and should remain disabled unless you deliberately maintain a legacy `houselocations` table.

## Framework job

The included `install/realestate_job.lua` contains the default job and grades expected by `Config.Permissions`. For QBCore, place the entry inside `QBShared.Jobs` in `qb-core/shared/jobs.lua`. For QBox/QBX, register the equivalent job using the job-management method supported by your QBox version.

The configured permission grades are:

| Action | Minimum grade |
|---|---:|
| View panel | 0 |
| Create properties | 0 |
| Edit properties | 1 |
| Delete properties | 3 |

Change these in `Config.Permissions` if your job grades differ.

## Commands

| Command | Purpose |
|---|---|
| `/housing` | Open the staff/real-estate management panel |
| `/createhouse` | Open the same property-creation panel |
| `/myhouse` | Open owner management inside or near an owned property |
| `/decorate` | Open the furniture editor for the active owned property |

## Property setup

### Shell property

1. Open `/housing` or `/createhouse`.
2. Enter the address and price.
3. Select **Shell**.
4. Choose a named shell and check its generated interior thumbnail.
5. Capture the exterior entrance and optional garage.
6. Draw the property boundary when requested.
7. Save the property.

Shells are spawned by LC Housing. Owners enter and leave through saved teleport points.

### MLO property

MLOs are map interiors supplied by another mapping resource. LC Housing does not install or discover MLO maps.

1. Ensure the MLO resource is already installed and started.
2. Create an **MLO** property at its physical entrance.
3. Draw a PolyZone around the property interior/exterior area that belongs to the house.
4. Save the required doors and owner interaction points.

MLO furniture placement is restricted to the saved property PolyZone.

### IPL property

LC Housing records IPL properties as in-world interiors. The mapping or IPL resource remains responsible for requesting/loading the IPL itself. LC Housing does not guess IPL names or automatically activate arbitrary IPLs.

1. Install and start the resource that loads the IPL.
2. Create an **IPL** property at the physical entrance.
3. Draw its property PolyZone and configure its doors.

Furniture decoration is intentionally disabled for IPL properties.

## Adding custom shells

Shells are **not automatically detected** because FiveM does not expose reliable friendly names, entrances, camera angles, or bounds for arbitrary streamed models.

Add each custom model once in `Config.Shells`:

```lua
{
    model = 'my_custom_shell',
    label = 'Modern Family Home',
    description = 'Three-bedroom modern interior',
    preview = {
        camera = { 2.50, -4.00, 1.70 },
        target = { 0.00, 1.00, 1.45 },
        fov = 68.0
    }
}
```

The `camera` and `target` values are offsets from the temporary shell object's origin:

- Put `camera` near the front-door position at normal eye height.
- Point `target` farther inside the main usable room.
- Lower `fov` to zoom in; raise it for a wider image.
- Restart `lc-housing` after changing the catalogue.
- If Chromium shows an old thumbnail, clear the LC Housing NUI site storage or change the preview cache version in `html/app.js`.

Do not add a shell unless its model is actually streamed by an installed resource.

## Main configuration

All runtime settings are in `config.lua`:

- `Config.Debug` and `Config.DebugDraw`: development diagnostics; keep disabled in production
- `Config.Framework`: `auto`, `qb`, or `qbox`
- `Config.Command`, `Config.CreateCommand`, `Config.OwnerCommand`: command names
- `Config.JobName`, `Config.RequireOnDuty`, `Config.Permissions`: staff access
- `Config.Purchase`, `Config.SellBack`: purchase and refund behavior
- `Config.Garage`: garage resource and interaction settings
- `Config.Interaction`: prompt/target mode and marker settings
- `Config.DoorLocks`: door discovery, interaction, and physical locking
- `Config.Blips`: for-sale and purchased map blips
- `Config.Inventory`: supported inventory order and stash size
- `Config.Clothing`: supported wardrobe-resource order
- `Config.Interior`: shell interaction distances and fallback exit
- `Config.Defaults`: new-property defaults
- `Config.Shells`: shell names, labels, descriptions, and preview cameras
- `Config.ShellPreview`: local screenshot resource, timing, and quality
- `Config.MapBounds`: administrator map projection bounds

Furniture settings and catalogue entries are kept separately in `furniture.lua`.

## Controls

### Property boundary drawing

- `E`: add a point
- `Backspace`: remove the latest point
- `Enter`: save the boundary
- `Esc`: cancel

### Interactive point placement

After selecting Set Exit, Set Stash, Set Wardrobe, or another supported point:

- `E`: confirm the player’s current position
- `Esc`: cancel and reopen the menu

### Furniture editor

- `W`, `A`, `S`, `D`: move the editor camera
- Hold right mouse button and move the mouse: look around
- `Q` / `E`: lower or raise the camera
- Use the on-screen transform controls to position the selected object
- Confirm placement using the bottom action tray

## Database

LC Housing uses these tables:

- `lc_houses`
- `lc_house_doors`
- `lc_house_furniture`

Tables and missing columns are created automatically. The SQL file is provided for administrators who prefer manual provisioning.

Furniture is linked to properties by stable property name:

```text
lc_house_furniture.house_name -> lc_houses.name
```

Do not rename a live property directly in SQL without migrating its related rows.

## Optional integrations

### Target interaction

Set `Config.Interaction.mode` to:

- `prompt`: keyboard prompts only
- `target`: target interaction only
- `hybrid`: both prompts and the first supported target resource
- `auto`: prompts with target support when enabled

### Inventory and clothing order

The first started resource listed in `Config.Inventory.resources` or `Config.Clothing.resources` is used. Only list integrations supported by LC Housing; adding an arbitrary resource name does not create compatibility automatically.

### Legacy qb-houses mirroring

`Config.MirrorQbHouses` writes compatible property rows to a pre-existing `houselocations` table. It is migration compatibility only. LC Housing does not read furniture, keys, or ownership from `qb-houses`, and `qb-houses` is not a runtime dependency.

## Production checklist

Before releasing or moving the resource to another server:

- Keep `Config.Debug = false`
- Keep `Config.DebugDraw.enabled = false`
- Confirm `Config.JobName` and permission grades
- Confirm your inventory, clothing, garage, and target resource names
- Verify every `Config.Shells` model exists on that server
- Test every shell preview and front-door angle
- Keep database and resource backups outside the resource directory
- Never place webhooks, database credentials, framework secrets, or server tokens in this resource

## License and attribution

LC Housing is distributed under the **GNU General Public License v3.0**. See `LICENSE` for the complete terms.

The furniture catalogue is adapted from [`qbcore-framework/qb-houses`](https://github.com/qbcore-framework/qb-houses), which is distributed under GPL-3.0. LC Housing's property management, ownership, placement, persistence, and user interfaces are implemented separately for this resource.

## Support information

When reporting a problem, include:

- LC Housing version from `Config.Version`
- Framework and inventory resource
- Property type: shell, MLO, or IPL
- Relevant client/server console error
- Steps needed to reproduce the problem

Do not share database credentials, license keys, webhooks, or private server tokens.
