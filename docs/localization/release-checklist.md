# Roblox Localization Release Checklist

This project uses a hybrid localization setup:

- Static UI and source-string collection are owned in Roblox Studio and Creator Dashboard.
- Scripted runtime strings use `ReplicatedStorage.Shared.Localization.TranslationHelper`.
- Translation keys live in `ReplicatedStorage.Shared.Localization.Keys`.

## Before Release

1. In Creator Dashboard, set the experience source language to the real authoring language.
2. Add the launch languages you want enabled for release.
3. Enable translated content for the experience.
4. Enable Automatic Text Capture for long-term maintenance, but do not depend on it for launch-critical strings.

## Pre-Seed Release Strings

1. Open Studio and turn on Localization Tools text capture.
2. Play through the release UI flows:
   - main HUD
   - titles
   - inventory
   - player inspect
   - merchant shop
   - appraisal
   - gifting / marketplace
3. Wait for Studio-captured strings to land in the localization table.
4. Download the localization CSV and add any missing scripted entries from `src/game/ReplicatedStorage/Shared/Localization/Keys.lua`.

## Dynamic String Coverage

The current code pass localizes scripted runtime strings in:

- body part summary and preview text
- aura preview text
- potion preview and status hover text
- inventory capacity, preview, sell, and action labels
- player inspect headers, summary, and preview text
- title empty states and equip controls
- merchant shop status, costs, countdown text, and purchase controls
- appraisal prompts, fields, risk copy, and result copy
- marketplace gift prompts and owned-price labels

## Studio Validation Notes

Validated in the live `DEV Body Part RNG` Studio session on April 23, 2026:

- `StarterGui.ScreenEffects` has `AutoLocalize = true`
- `StarterGui.Main` has `AutoLocalize = true`
- `StarterGui.AdminPanel` has `AutoLocalize = true`
- `StarterGui.ModalRoot` has `AutoLocalize = true`
- `StarterGui.MainInterface` has `AutoLocalize = true`
- the inspected `ProximityPrompt` instances already have `AutoLocalize = true`

## Final Checks

1. Switch the Roblox client language and verify the scripted UI above updates correctly.
2. Confirm player names, usernames, and gift-recipient labels are not being auto-localized.
3. Confirm untranslated keys fall back to readable English.
4. Lock reviewed manual translations for high-importance strings after approval.
