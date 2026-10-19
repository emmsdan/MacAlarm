# MacAlarm Now ⏰🔊

A native macOS application designed to work like a phone alarm: it **blocks the entire screen fullscreen**, displays the alarm label and detailed description, **rings with high-decibel alert tones**, and **sings/announces the description loudly** via speech synthesis.

![MacAlarm Now Icon](scripts/icon_1024.png)

---

## Key Features

1. **Fullscreen Screen-Lock Overlay**
   - Uses `CGShieldingWindowLevel` to float above **all** windows, spaces, the macOS Dock, and the Menu Bar.
   - For multi-monitor setups, companion displays show a dark ambient blackout screen so you cannot look away.
   - Prevents display and system sleep while ringing (`IOPMAssertionCreateWithName`).
   - Disables Escape and forces completion of the wake-up dismiss or snooze requirement.

2. **Rings & Sings Loud**
   - **Rings**: Synthesized high-piercing tone profiles:
     - *Digital Pulse Beeps* (urgent high-frequency alert)
     - *Mechanical Twin-Bell* (authentic dual-hammer alarm clock)
     - *Emergency Red Siren* (frequency-sweeping siren)
     - *Harmonious Marimba Chime* (arpeggiated major chords)
   - **Sings Loud**: Built-in `AVSpeechSynthesizer` loudly announces your alarm title and custom description repeatedly alongside the alarm chords.
   - **100% Volume Blast**: Automatically boosts macOS output volume to 100% and un-mutes the speaker, restoring your previous volume once dismissed.
   - **Dynamic Audio Visualizer**: Live spectrum bars bouncing to the beat of the ring and voice announcement.

3. **Delightful & Intuitive User Experience**
   - Clean tabbed interface:
     - **Alarms**: Overview of scheduled alarms with smooth toggles and duplicate actions.
     - **Quick Focus**: 1-click power naps (20m), Pomodoro sprints (25m), deep work (45m), and short recharges (5m).
     - **Cloud Sync**: Simple email-based device synchronization without technical jargon.
   - **One-Tap Presets**: Quick chips for Morning Wake-Up, Deep Focus, Heavy Sleeper, and Daily Medicine.
   - **Voice Preview**: Listen to how your custom alarm message sounds in the editor.

4. **Wake-Up Dismiss Requirements**
   - **Standard Dismiss**: High-contrast button.
   - **Hold 3 Seconds**: Requires holding down the button for 3 uninterrupted seconds with progress fill.
   - **Solve Math Problem**: Presents a random arithmetic equation (e.g. `28 + 19 = ?`) that must be solved before the alarm will stop.
   - **Snooze**: One-click or Spacebar shortcut (+5m, +9m, +15m).

5. **Cloud Synchronization (Environment-Driven)**
   - **Seamless Device Sync**: Users simply enter their email address to synchronize alarms across devices.
   - **Zero Developer Jargon**: All server settings are driven via environment variables or `.env` files rather than cluttering user settings.
   - **Supported Environment Variables**:
     - `REDIS_HOST`: Redis host / IP (default: `127.0.0.1`)
     - `REDIS_PORT`: Redis port (default: `6379`, or `6380` for TLS)
     - `REDIS_PASSWORD`: Optional authentication token
     - `REDIS_TLS`: Set to `true` or `1` for TLS/SSL
     - `REDIS_CHANNEL_PREFIX`: Optional channel prefix (default: `macalarm:sync:`)

---

## Single-Command Releases

To create a new release, auto-increment the version, save the increment, and build the distribution `.dmg`:

```bash
# Auto-increments patch version (e.g. 1.0.1 -> 1.0.2) and builds MacAlarm-1.0.2.dmg
./release.sh

# Or bump minor version (e.g. 1.0.2 -> 1.1.0)
./release.sh minor

# Or bump major version (e.g. 1.1.0 -> 2.0.0)
./release.sh major

# Or specify an explicit version
./release.sh 1.2.0
```

Every release command automatically:
1. Reads the current version from `VERSION`.
2. Computes and saves the new incremented version back to `VERSION`.
3. Builds the production binary and bundles `MacAlarm Now.app`.
4. Creates and compresses the DMG installer: `MacAlarm-x.x.x.dmg`.
5. Creates a git tag and commit for the release.

---

## Quick Start

### Launching the Application
Double-click `MacAlarm Now.app` or run:
```bash
open "MacAlarm Now.app"
```
