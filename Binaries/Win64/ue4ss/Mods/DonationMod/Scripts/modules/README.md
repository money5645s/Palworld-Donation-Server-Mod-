# DonationMod Lua modules

- `config.lua` — reward amounts and file paths.
- `runtime.lua` — Palworld/UE4SS helpers, player lookup, inventory delivery,
  and chat delivery.
- `rewards.lua` — roulette reward catalog, Pal spawning, instant-kill rule,
  and reward execution.
- `commands.lua` — administrator test command and CHZZK registration commands.
- `donation_queue.lua` — donation queue polling, player-status output, and
  CHZZK registration response polling.
- `events.lua` — UE4SS custom-event and binding-dump handlers.

`main.lua` only loads these files. Keep this entire `modules` directory beside
`main.lua` when installing or updating the server mod.
