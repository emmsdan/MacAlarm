# Real Alarm for macOS

A native macOS application designed to work like a phone alarm: it **blocks the entire screen fullscreen**, displays the alarm label and detailed description, **rings with high-decibel alert tones**, and **sings/announces the description loudly** via speech synthesis.

![Real Alarm Icon](scripts/icon_1024.png)

---

## Key Features

1. **Fullscreen Screen-Lock Overlay**
   - Uses `CGShieldingWindowLevel` to float above **all** windows, spaces, macOS Dock, and the Menu Bar.
   - For multi-monitor setups, it locks companion displays with a dark ambient blackout screen so you cannot simply look away.
   - Disables Escape and forces you to interact with the Dismiss or Snooze controls.
   - Prevents display and system sleep while ringing (`IOPMAssertionCreateWithName`).

2. **Rings & Sings Loud**
   - **Rings**: Synthesized high-piercing tone profiles:
     - *Digital Pulse Beeps* (urgent high-frequency alert)
     - *Mechanical Twin-Bell* (authentic dual-hammer alarm clock)
     - *Emergency Red Siren* (frequency-sweeping siren)
     - *Harmonious Marimba Chime* (arpeggiated major chords)
   - **Sings Loud**: Built-in `AVSpeechSynthesizer` loudly announces your alarm title and custom description repeatedly alongside the alarm chords.
   - **100% Volume Blast**: Automatically boosts macOS output volume to 100% and un-mutes the speaker, restoring your previous volume once dismissed.
   - **Dynamic Audio Visualizer**: Live spectrum bars bouncing to the beat of the ring and voice announcement.

3. **Wake-Up Dismiss Requirements**
   - **Standard Dismiss**: Instant high-contrast button.
   - **Hold 3 Seconds**: Requires holding down the button for 3 uninterrupted seconds with progress fill (prevents accidental taps while groggy).
   - **Solve Math Problem**: Presents a random arithmetic equation (e.g. `28 + 19 = ?`) that must be solved before the alarm will stop.
   - **Snooze**: One-click or Spacebar shortcut (+5m, +9m, +15m).

4. **Menubar & Background Execution**
   - Lives in the macOS menu bar with an alarm status item.
   - Displays real-time countdown to your next upcoming alarm.
   - Stays active in the background even if the main dashboard window is closed.
   - Automatically stores all alarms in `~/Library/Application Support/com.alarm.macapp/alarms.json`.

---

## Quick Start

### Launching the Application
Double-click `Alarm.app` in this folder or run from terminal:
```bash
open Alarm.app
```

### Re-building & Re-bundling
To recompile and create a new signed release bundle:
```bash
./scripts/bundle_app.sh
```

### Immediate Fullscreen Test
Click the **"⚡ Test Alarm Now"** button in the dashboard or choose **"Test Fullscreen Alarm"** from the Menubar status icon.
