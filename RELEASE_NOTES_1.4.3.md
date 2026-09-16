# LC Housing 1.4.3

## Target-only interaction release

This version sets LC Housing to **target-only** interaction. It removes the normal E prompts and the green/yellow world arrows while keeping the `qb-target`/`ox_target` third-eye zones active.

### Included changes

- Sets `Config.Interaction.mode` to `target`.
- Disables target-resource sprites/arrows in the world.
- Disables exterior prompt markers in target mode.
- Disables interior exit, stash, wardrobe, and logout prompt markers and E prompts in target mode.
- Keeps property, management, exit, stash, wardrobe, and logout target actions available through the target system.
- Updates the resource version to `1.4.3`.

This release was syntax-checked with Lua before packaging. Actual target-menu behaviour still depends on the configured target resource being installed and working.