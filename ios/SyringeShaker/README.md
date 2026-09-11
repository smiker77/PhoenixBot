# Syringe Agitator

A single-button iPhone app that drives the Taptic Engine with a vibration
pattern designed to redisperse settled crystals in a suspension — e.g. a drawn
-up syringe of triamcinolone acetonide (Kenalog).

Press the syringe barrel against the back of the phone, tap the button, and the
Taptic Engine runs a continuous agitation pattern for a set duration.

---

## Read this first

**Kenalog is a suspension, not a solution.** Triamcinolone acetonide crystals
do not dissolve — they disperse. The goal of agitation is a *uniform
suspension*, not dissolution, and a suspension that looks clear has not been
mixed, it has been diluted or is the wrong vial. Judge the result the way you
normally would: uniform opacity, no visible clumps, no sediment line.

**This supplements hand agitation, it does not replace it.** The Taptic Engine
is a linear resonant actuator with a displacement on the order of a fraction of
a millimetre. It couples a lot of *acceleration* into a small object held
against it, which is useful for breaking up caked sediment and for keeping an
already-mixed suspension uniform. It does not move fluid the way inverting or
rolling a syringe does. Use it alongside your normal technique, and always
inspect the syringe before injecting.

Nothing here is a validated clinical protocol, and this is not a medical
device. The pattern design below is engineering reasoning about actuators and
suspensions — treat it as such, and keep following your own preparation
standards and the product labelling.

---

## Building and installing

Requires **Xcode 16 or newer** and a Mac. The project uses Xcode's synchronized
file groups, so there is no file list to maintain — anything you drop into
`SyringeShaker/` is compiled.

1. Open `SyringeShaker.xcodeproj`.
2. Select the **SyringeShaker** target → **Signing & Capabilities**.
3. Set **Team** to your Apple ID, and change the **Bundle Identifier** from
   `com.example.SyringeShaker` to something unique to you
   (e.g. `com.yourname.SyringeShaker`). Signing will fail until you do.
4. Plug in your iPhone, select it as the run destination, and press ⌘R.
5. On the phone, the first launch needs
   **Settings → General → VPN & Device Management → trust your developer cert**.

**You must run this on a real device.** The Simulator has no Taptic Engine; the
app will launch there but tells you there is nothing to drive.

A note on signing lifetime: with a *free* Apple ID the app stops launching after
**7 days** and you re-run it from Xcode to renew. A paid Apple Developer
Program membership extends that to a year. If you plan to use this in clinic
day to day, the paid membership is the difference between a tool and a chore.

---

## Using it

- **Couple it firmly.** Press the barrel flat against the **lower half of the
  back** of the phone — the Taptic Engine sits near the bottom of the chassis.
  Firm, continuous contact matters far more than anything else; a loosely held
  syringe just absorbs the vibration in your fingers.
- **Take the case off** if it is thick. Foam and silicone cases are very good at
  damping exactly the frequencies this relies on.
- **Turn off Low Power Mode.** It silences the Taptic Engine system-wide. The
  app detects this and warns you, because otherwise the phone just feels dead.
- Keep the app in the foreground — iOS cuts haptics the moment the app is
  backgrounded or the screen locks. The app holds the screen awake while it
  runs and stops cleanly if it loses focus.
- Three quick taps signal the end of a run, so you can watch the syringe instead
  of the screen.

### Patterns

| Pattern | What it does | When |
| --- | --- | --- |
| **Resuspend** *(default)* | Full-intensity continuous drive, amplitude-modulated at 2 Hz, with a sharpness sweep and 4 Hz impulse shocks on top. | General use. Start here. |
| **Smooth** | Flat maximum-intensity continuous drive, no modulation. | When the pulsing is distracting, or for keeping an already-mixed syringe uniform. |
| **Percussive** | Nothing but hard transients at 8 Hz. Highest peak impulse, lowest average energy. | Stubborn sediment caked against the barrel wall. |

You can switch patterns mid-run and feel the difference immediately.

---

## Why this pattern

The Taptic Engine is an LRA: one mechanical resonance, a fairly narrow usable
band around it, and "harder" mostly means pinning intensity at 1.0. Raw energy
alone is a poor way to redisperse a suspension, for two reasons:

1. **A constant single-frequency drive lets the fluid reach steady state.** A
   standing-wave pattern establishes, crystals migrate toward the velocity
   nodes, and they sit there. You get vibration without much net mixing.
2. **Caked sediment needs a shock to break static friction with the glass.** A
   smooth sinusoid never delivers one, no matter how loud.

So the default pattern deliberately does three things at once:

- Holds base intensity at maximum, for energy transfer.
- Sweeps sharpness (shifting the drive's spectral content) and
  amplitude-modulates at a few Hz, so no standing-wave pattern has time to
  establish and the excitation keeps wandering across the fluid's own
  resonances.
- Fires hard transients over the continuous bed — impulse shocks aimed at
  dislodging crystals stuck to the wall.

The loop is built so its start and end values match, so it repeats seamlessly
rather than clicking once per period.

---

## Source layout

```
SyringeShaker/
├── SyringeShakerApp.swift    App entry point
├── ContentView.swift         The button, countdown ring, and controls
├── HapticAgitator.swift      Taptic Engine lifecycle, looping, countdown
└── AgitationPattern.swift    The vibration recipes and the reasoning behind them
```

`HapticAgitator` handles the awkward parts of Core Haptics: the engine is
stopped by the system on calls, Siri, and backgrounding, and is occasionally
reset out from under you — both cases rebuild the player and resume rather than
leaving a countdown running against a silent engine.
