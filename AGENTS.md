# AGENTS.md

Context for AI agents working on GoonStrike. Read this before changing gameplay, networking, UI, resources, or scenes.

## Project Snapshot

GoonStrike is a Godot 4.6 GDScript multiplayer PvP/FPS prototype.

- Engine/config: `project.godot`
- Main scene: `scenes/ui/menus/main_menu.tscn`
- Render/features: Forward Plus, Windows D3D12
- Physics: Jolt Physics, 120 physics ticks/sec
- 3D physics layers: `world`, `characters`, `pickups`
- Core language: GDScript; no C# project is present
- Gameplay model: multiplayer PvP; there is no dedicated enemy AI layer yet
- Local Godot CLI command: `godot4` (verified as Godot 4.6.1)

Important VCS facts:

- `.godot/`, `*.uid`, and `export_presets.cfg` are not reliable project context.
- Some autoloads in `project.godot` are UID references; resolve them by matching scripts under `scripts/autoloads/`.
- Some gameplay data is binary `.res`; inspect related scripts and `.tres` files when text diff is not enough.
- `README.md` is currently only a stub.

## Repository Map

- `scripts/` - gameplay, networking, UI, resources, autoloads, tools.
- `scenes/` - Godot scene composition for menus, HUD, game world, characters, weapons, modes, VFX.
- `resources/` - gameplay data such as weapons, maps, character registries, spread resources.
- `assets/` - models, textures, animation resources, weapon imagery.
- `addons/` - editor/Git tooling; do not treat it as core gameplay unless the task explicitly targets addons.

## Runtime Flow

The usual player flow is:

1. `scenes/ui/menus/main_menu.tscn`
2. `scripts/ui/menus/main_menu.gd`
3. connect to a separately running dedicated server
4. `scripts/ui/menus/lobby_screen.gd`
5. `scripts/autoloads/lobby.gd`
6. selected map from `scripts/data/maps_registry.gd`
7. leader presses start, then `scenes/game/game_world.tscn`
8. `scripts/game/game_manager.gd`
9. active mode from `scripts/data/game_mode_catalog.gd`
10. player spawning via `scripts/player/player_spawner.gd`
11. HUD via `scripts/ui/hud/hud_manager.gd`

Dedicated servers start through `scenes/server/server_bootstrap.tscn`, wait in the lobby by default, and only load the match after the lobby leader requests start. The technical server peer `1` is not the lobby leader on dedicated servers. A terminal-started dedicated server does not auto-assign OP unless launched with `--auto-op-first`.

Local play can start a local dedicated server from the main menu. That path must not require Docker or `--backend-url`; players can run as guest/local peers. It does pass `--auto-op-first`, so the first joined local client can manage the lobby.

Backend integration is optional persistence only. Active match state belongs to the Godot dedicated server, not FastAPI/PostgreSQL. Keep positions, damage, money, rounds, pickups, teams, and live timers in Godot; use backend for accounts, profiles, inventory/cosmetics, long-term stats, and optional finished-match history.

`GameModeCatalog` currently exposes:

- `dm` -> `scenes/game_modes/deathmatch_mode_node.tscn`
- `team_elim` -> `scenes/game_modes/team_elimination_mode_node.tscn`

`MapsRegistry` currently loads `resources/maps/default.tres`.

## Autoloads

Autoloads are declared in `project.godot`.

- `WeaponRegistry` -> `scripts/autoloads/weapon_registry.gd`
- `ChatNetwork` -> `scripts/autoloads/chat_network.gd`
- `ConsoleCommands` -> `scripts/autoloads/console_commands.gd`
- `Lobby` -> `scripts/autoloads/lobby.gd`
- `SceneRouter` -> `scripts/autoloads/scene_router.gd`
- `ServerConfig` -> `scripts/autoloads/server_config.gd`
- `Settings` -> `scripts/autoloads/Settings.gd`


## Core Architecture

### Player

`scripts/player/player.gd` defines `OnlinePlayer`.

`OnlinePlayer` is intentionally a thin orchestrator: it initializes components and routes input/RPC calls. Keep major behavior in child components or domain collaborators, not directly in `player.gd`.

Key components:

- `scripts/player/components/movement_component.gd`
- `scripts/player/components/network_component.gd`
- `scripts/player/components/health_component.gd`
- `scripts/player/components/animation_component.gd`
- `scripts/player/components/aim_component.gd`
- `scripts/weapons/weapon_holder.gd`

Useful invariant from the source:

```gdscript
class_name OnlinePlayer extends CharacterBody3D
## Тонкий оркестратор: инициализирует компоненты и роутит RPC.
## Никакой логики здесь нет — только делегирование.
```

### Game Manager and Modes

`scripts/game/game_manager.gd` defines `GameManager`, the in-world coordinator for spawning, HUD, match state, money, rounds, pickups, player lifecycle, and game-mode wiring.

`GameManager` is already large. Prefer adding new match rules in `GameMode` subclasses or focused helper nodes instead of growing `GameManager` further.

`scripts/game/game_mode.gd` is the base contract for modes:

```gdscript
class_name GameMode extends Node
## Базовый контракт игрового режима.
## GameManager делегирует сюда ключевые события матча.
```

Existing mode scripts live under `scripts/game/game_modes/`.

When adding a mode:

- Implement or extend a `GameMode` subclass.
- Add the mode scene under `scenes/game_modes/`.
- Register it in `scripts/data/game_mode_catalog.gd`.
- Ensure maps/lobby UI allow selecting it if needed.
- Keep FFA peer-id semantics separate from team-id semantics; existing signals use `ffa_*` and `team_*` prefixes for this reason.

### Weapons

Weapon logic is split across:

- `scripts/weapons/weapon.gd` - local weapon behavior, ammo, spread, shoot/reload requests.
- `scripts/weapons/weapon_holder.gd` - equipped weapon, pickup/drop, RPC synchronization, server-side shot validation.
- `scripts/weapons/weapon_data.gd` - resource-driven weapon stats.
- `scripts/weapons/spread_pattern.gd` and `scripts/weapons/spread_component.gd` - spread data and runtime behavior.
- `scripts/autoloads/weapon_registry.gd` - `short_name` to `WeaponData` path registry.

`WeaponRegistry` is manual:

```gdscript
## Новое оружие = новый _register() в _ready().
```

When adding a weapon, create/update the `WeaponData` resource, weapon scene, buy data, and registry entry. Use `resource_path` consistently for pickup/drop/buy flows.

### UI

HUD and menus are separated:

- Menus: `scripts/ui/menus/`
- Settings: `scripts/ui/settings/`
- HUD: `scripts/ui/hud/`
- Shared scene constants: `scripts/scene_paths.gd`

UI that blocks gameplay input should follow the existing `OnlinePlayer._is_ui_input_blocked()` pattern: focused GUI, visible mouse mode, and pause overlay checks matter.

Avoid hiding gameplay state mutations in UI scripts. UI should request actions, display state, and connect/disconnect signals carefully.

## Networking Rules

This project uses a host-authoritative model. Treat peer `1` as the host/server authority unless the surrounding code says otherwise.

Follow these rules for networked gameplay:

- Server owns damage, death, money, round state, pickup validity, and authoritative weapon results.
- Clients may predict input/UI, but must ask the server for gameplay-impacting actions.
- Existing client-to-server calls often use `rpc_id(1, ...)`; follow local patterns.
- Every new `@rpc("any_peer", ...)` must validate `multiplayer.get_remote_sender_id()`.
- Validate player identity, alive/dead state, ownership, distance, aim direction, cooldowns, and resource existence on the server.
- Do not trust client-provided hit results. The existing weapon flow validates aim and performs the authoritative raycast server-side.
- Keep late-join and respawn synchronization in mind; many systems replicate state after spawn.

`WeaponHolder` contains important examples of server validation for shooting, including sender checks, aim-dot checks, origin distance checks, ammo consumption, and server raycasts.

## Signals and Lifecycle

Signals are a core orchestration mechanism in this project.

Common signal owners:

- `Lobby` - connection/session/load events.
- `GameManager` - spawn/despawn/death, rounds, money, match stats, buy availability.
- `GameMode` - FFA/team scores and round state.
- `Weapon` and `WeaponHolder` - shot/ammo/reload/equip changes.
- `HealthComponent` - health and death.
- `ChatNetwork` and HUD scripts - chat, feedback, UI events.

Guidelines:

- Connect signals in `_ready()`, setup methods, or explicit wiring methods.
- Disconnect signals in `_exit_tree()` or matching teardown paths when nodes can be recreated.
- Avoid duplicate connections after respawn, scene reload, or HUD recreation.
- Prefer signals for cross-component notifications instead of direct deep node coupling.

## Data-Driven Patterns

Prefer resources and registries for content:

- Weapons: `WeaponData`, spread resources, `WeaponRegistry`.
- Maps: `MapData`, `MapsRegistry`, `.tres` map resources.
- Characters: `CharacterData`, character registry resources, `Settings.get_selected_character_scene()`.
- Modes: `GameModeCatalog` and mode scenes.

Do not duplicate resource paths across unrelated scripts when a registry or constant already exists. `scripts/scene_paths.gd` exists specifically to reduce scene path drift for common overlays.

## Coding Guidelines

Use the existing style before introducing new patterns.

- Keep classes small and responsibility-focused.
- Preserve the thin-controller pattern for `OnlinePlayer`.
- Do not place match rules in weapons, HUD, or player input code.
- Do not place UI behavior in gameplay managers beyond necessary HUD creation/removal.
- Prefer explicit typed variables and return types, matching the existing GDScript style.
- Use `class_name` for reusable project-level types.
- Keep Russian comments acceptable and consistent with nearby gameplay files.
- Add comments only when they explain an invariant, authority rule, networking assumption, or non-obvious Godot behavior.
- Avoid broad refactors while implementing a focused feature.
- If a file is already large, add a collaborator instead of increasing its responsibilities.

SRP expectations:

- `OnlinePlayer` routes input/RPC and delegates to components.
- Movement logic belongs in `MovementComponent`.
- Network command buffering belongs in `NetworkComponent`.
- Damage/death state belongs in `HealthComponent` and server-authoritative flows.
- Match rules belong in `GameMode` subclasses.
- Scene-level orchestration belongs in `GameManager`.
- Weapon state and RPC validation belong in `WeaponHolder`.
- Static content belongs in `Resource` files and registries.

## Checklists

### Add a Weapon

- Add or update a `WeaponData` resource.
- Add the weapon scene under `scenes/weapons/`.
- Ensure spread data is present if needed.
- Register the data resource in `scripts/autoloads/weapon_registry.gd`.
- Verify buy menu category/price fields.
- Verify pickup/drop snapshots preserve `data_path`, ammo in mag, and reserve ammo.
- Verify server shot validation still works with the new weapon's spread/range/damage.

### Add a Game Mode

- Create a `GameMode` subclass or extend an existing mode.
- Create a mode scene under `scenes/game_modes/`.
- Register it in `scripts/data/game_mode_catalog.gd`.
- Decide whether players spawn on connect or only through round logic.
- Implement score, alive tracking, buy period, round timer, and death handling as needed.
- Keep `ffa_*` and `team_*` signal meanings distinct.
- Update lobby/map support if the mode should be selectable.

### Add HUD or Menu UI

- Place scene files under `scenes/ui/`.
- Place scripts under `scripts/ui/`.
- Use signals from `GameManager`, `GameMode`, `ChatNetwork`, or player components instead of polling deep nodes when possible.
- Disconnect from long-lived autoloads or managers on teardown.
- If the UI blocks gameplay, check input blocking, mouse mode, and pause overlay behavior.
- Keep gameplay mutations behind server requests or existing manager APIs.

### Add a Map or Character

- For maps, add a `MapData` resource and register it in `scripts/data/maps_registry.gd`.
- Ensure the map points to a valid game world scene.
- For characters, add `CharacterData` and registry entries used by `Settings`.
- Verify spawn markers and team/DM spawn expectations in the scene.

### Add a Networked Action

- Decide what is client-predicted and what is server-authoritative.
- Add an RPC only where ownership belongs.
- Validate sender id and target player id on the server.
- Validate distance, state, cooldowns, resources, and authority.
- Replicate only the state clients need.
- Consider late joins and respawns.
- Add signal/UI updates after authoritative state changes, not before.

## Common Pitfalls

- Do not assume "enemy" means AI; enemies are currently other `OnlinePlayer` instances.
- Do not edit `.godot/` cache or rely on `.uid` files being committed.
- Do not assume export presets exist in the repo.
- Do not treat addon code as gameplay architecture.
- Do not add new string scene paths in multiple places when `ScenePaths`, registries, or catalogs can own them.
- Do not bypass `PlayerSpawner` for player instantiation.
- Do not let HUD scripts become sources of truth for match, money, damage, or weapon state.
- Do not make client-side hit detection authoritative.

## Files Worth Reading First

For most gameplay tasks, read these before editing:

- `project.godot`
- `scripts/game/game_manager.gd`
- `scripts/game/game_mode.gd`
- `scripts/data/game_mode_catalog.gd`
- `scripts/player/player.gd`
- `scripts/player/player_spawner.gd`
- `scripts/weapons/weapon.gd`
- `scripts/weapons/weapon_holder.gd`
- `scripts/autoloads/lobby.gd`
- `scripts/autoloads/server_config.gd`
- `scripts/ui/hud/hud_manager.gd`
- `scripts/ui/hud/game_hud.gd`

For content tasks, also read:

- `scripts/autoloads/weapon_registry.gd`
- `scripts/data/maps_registry.gd`
- `scripts/data/characters_registry.gd`
- `scripts/autoloads/Settings.gd`

