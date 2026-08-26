# AGENTS.md

Add-on for Turtle WoW (1.12.1 vanilla client, `Interface: 11200`). Pure Lua, no build system, no tests, no linter, no external dependencies. Loaded directly by the WoW client from a folder named `ModernSpellBook` in `Interface/AddOns/`.

## Load order is the contract

Files load in the order declared in `ModernSpellBook.toc`; later files depend on globals defined by earlier ones. Do not reorder entries. Roughly:

- `Lib/MSB_Compat.lua` must load first — polyfills Classic SoD APIs missing from vanilla 1.12.1 (`_G`, `string.gmatch`, `C_Timer`, `SOUNDKIT`, `GetSpellBookItemName`, `HookScript`, numeric `FileDataID` → texture paths via `MSB_Textures`). Anything touching frame methods or spell APIs should go through the `MSB_*` wrappers, not the raw WoW APIs.
- `Lib/MSB_Class.lua` provides the OOP system: `class "CName" { __init = ...; Method = ...; }`, `:extends("Base")`. Classes are registered as globals; instances are stored as globals (e.g. `SpellBook = CSpellBook()`, `SlashCommands = CSlashCommands()`).
- `Core/`, `Spellbook/`, `Talents/`, `Debug/` follow.

## Conventions

- File names: `MSB_<Name>.lua`. Class names: `C<Name>`; singletons use PascalCase globals (`SpellBook`, `TalentTree`, `SlashCommands`).
- Inter-file communication is via globals and the single saved table `ModernSpellBook_DB` (per-character). DB schema is versioned by `DB_VERSION` in `MSB_Spellbook.lua`; bump and migrate when shape changes.
- No `require`/imports — only the `.toc` load order. Adding a new file means editing `ModernSpellBook.toc`.
- RpLua 5.0 semantics in vanilla: `arg`/`unpack(arg)` for varargs, no `string.gmatch`, no `_G` (compat patches these). Don't assume Lua 5.1+ idioms.

## In-game verification

There is no CLI test path. To verify changes, the user copies the folder into their game's `Interface/AddOns/` and runs `/reload` (or `/msb reset` to restore defaults). Relevant slash commands:

- `/msb` — toggle modern vs vanilla spellbook
- `/msb talents` — toggle custom talent tree
- `/msb reset` — reset settings to defaults (keep spell cache)
- `/msb rescan` — clear trainer spell cache, rescan on next trainer visit
- `/msbdebug` — dump spell/talent tab and `AllSpells` state to chat (defined in `Debug/MSB_Debug.lua`, loaded last)

## Gotchas

- Texture IDs that are `FileDataID` numbers (e.g. `335575`) don't resolve in vanilla; route through `MSB_ResolveTexture` / extend `MSB_Textures` in `Lib/MSB_Compat.lua`.
- The modern spellbook hooks `SpellBookFrame_OnShow` at runtime; `MSB_OriginalSpellBookFrameOnShow` is the saved vanilla handler. `DisableModern`/`EnableModern` toggle which is active.
- Unlearned spells come from scanning a class trainer; the scan populates `ModernSpellBook_DB.spells` and sets `trainerScanned`. Higher-level trainers yield more complete data.
- Localized strings live in `Core/MSB_Localization.lua`; new user-facing strings should be added to enUS (source of truth) plus any translations you can provide (zhCN/zhTW, frFR, deDE, esES, esMX, ruRU). Non-enUS locales fall back to enUS per-key, so partial translations are safe. Use `MSB_L("Key", args...)` for formatted strings (string.format-style `%d`/`%s`); raw access via `Localization.current.Key` or `self.frame.ClientLocale.Key` also works. Do NOT hardcode user-facing English — route it through a locale key.

## Commit / release

No CI, no pre-commit hooks, no enforced style. Commits are short imperative summaries (e.g. `Fix command conflict with Mik's Scroll Battle Text`). Version is set in `ModernSpellBook.toc` (`## Version:`).