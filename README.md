# Munlay HUD — Minimal & Clean HUD for ESX

A lightweight, fully **client-side** HUD with a clean modern design. Zero server scripts, zero external UI frameworks, zero bloat. Built for ESX servers that want performance and aesthetics.

Everything runs on the client — no network overhead, no server lag.

DISCORD: https://discord.gg/zAVv4cVX9R

## Preview

<img width="1280" height="720" alt="LLORO POR TODO (1)" src="https://github.com/user-attachments/assets/af7a0656-1144-4454-b155-1f0a2019b3b9" />

<img width="1918" height="1196" alt="image" src="https://github.com/user-attachments/assets/2e4198f8-4e6f-4f4a-9269-6e2a838e60ab" />


## Features

**Player Status (always visible)**
- **Health** — smoothed bar with averaging (no flickering on damage)
- **Armor** — auto-hides when armor is 0
- **Stamina** — shows current sprint stamina
- **Hunger & Thirst** — reads real values from esx_status (includes fallback simulation if not installed)
- **Oxygen** — only appears when swimming underwater
- **Player ID** — displayed next to voice indicator

**Voice Indicator**
- Animated voice waves with **3 proximity levels** (Whisper / Normal / Shout)
- Green glow effect when talking
- Automatically reads proximity mode from **pma-voice**

**Money & Job Panel (toggle with /hud)**
- **Cash** (green), **Bank** (blue), **Black Money** (red)
- **Job name & grade** displayed below money
- Black money row auto-hides when balance is $0
- Job auto-hides when unemployed
- **Instant data refresh** — no delay when toggling on

**Vehicle HUD (auto-shows when in vehicle)**
- **Speedometer** in KM/H with animated speed bar
- **Fuel level** with percentage and bar
- **Lights indicator** — Off (gray) / Low beam (yellow) / High beam (blue)
- **Engine status** icon
- **Seatbelt** icon (via export for your seatbelt script)
- **Cruise control** icon (via export)

**Minimap Control (toggle with /mapa)**
- **Auto mode** by default: visible in vehicle, hidden on foot
- `/mapa` to force show or hide
- HUD auto-repositions when minimap is visible to avoid overlap

**Responsive Design**
- Auto-scales for **all resolutions** (720p to 4K)
- **Aspect ratio aware** (16:9, 16:10, 4:3, 5:4, ultrawide)
- Safe zone support
- User layout overrides persist via KVP
- `/hudreset` to restore defaults

## Commands

| Command | Description |
| --- | --- |
| `/hud` | Toggle money and job panel on/off |
| `/mapa` | Toggle minimap visibility |
| `/hudreset` | Reset HUD scale and position to defaults |

## Exports

```lua
-- Seatbelt integration (call from your seatbelt script)
exports['munlay_hud']:SeatbeltState(true) -- or false

-- Cruise control integration
exports['munlay_hud']:CruiseControlState(true) -- or false

-- Control visibility from other scripts
exports['munlay_hud']:SetMoneyHudVisible(true)
exports['munlay_hud']:SetJobHudVisible(true)
exports['munlay_hud']:SetMoneyJobHudVisible(true)

-- Read current config
local config = exports['munlay_hud']:GetHudConfig()
```

## Installation

1. Drop `munlay_hud` into your resources folder
2. Add to your `server.cfg` (after `es_extended` and `esx_status`):
```
ensure munlay_hud
```
3. Done. No config file needed.

## Dependencies

| Resource | Required | Purpose |
| --- | --- | --- |
| es_extended (ESX) | Yes | Player data, money, job |
| esx_status | Recommended | Real hunger and thirst values |
| pma-voice | Recommended | Voice range detection |

Works without `esx_status` (uses simulated hunger/thirst decay) and without `pma-voice` (defaults to Normal range).

## Performance

- **Resmon:** ~0.02ms idle
- **0 server scripts** — 100% client-side
- Adaptive polling: fast refresh when data changes, slow when idle
- Only 3 files total: `client.lua` + `html/index.html` + `fxmanifest.lua`

## License

Free and open source. Use it, modify it, share it.
