# TestFlight external testing: what to paste into App Store Connect

External testers need a first Beta App Review. These are the fields it asks for, drafted so
they match what the build does. Lines marked **YOU** need your own details.

## Test Information
- **Beta App Description**
  > VOIDLINE is a retro tunnel shooter in the style of mid-90s DOS games. Fly a small
  > ship through twisting sectors, clear the arenas and beat the boss at the end of each
  > episode. It plays with touch controls or a Bluetooth game controller, in landscape.
- **Feedback Email:** **YOU**
- **Marketing URL** (optional): <https://beyondthevoidrunner.netlify.app/>
- **Privacy Policy URL:** <https://beyondthevoidrunner.netlify.app/privacy.html>
  (live once this branch is deployed; the page is `web/privacy.html`)

## What to Test
> Play Sector 1 with touch, then again with a controller if you have one.
> Tell us: did you understand the controls in the first minute? Did flying and shooting
> feel good? Was anything confusing? The FEEDBACK button in the menu opens a short form.

## Beta App Review Information
- **Sign-in required:** No. There are no accounts.
- **Contact:** **YOU** (name, phone, email)
- **Review notes**
  > No login and no network connection are needed. The game opens on a title screen; tap to
  > start. All controls are on screen. A game controller is optional. The game contains
  > flashing lights; a notice is shown on first launch and SETUP has a REDUCE FLASH switch.

## App Privacy (the "nutrition label")
- **Data collection:** Data Not Collected.
- **Tracking:** No.

## Age rating questionnaire
Answer from what is on screen. The honest answers are:
- Cartoon or Fantasy Violence: **Infrequent/Mild** (ships and robots shoot coloured bolts;
  no people, no blood).
- Everything else: **None**. No web access inside the app, no purchases, no chat, no ads.
- Not in the Kids category for now: the feedback link opens a web page, and Kids apps need
  a parental gate in front of any link out.

## Export compliance
Already answered by the build (`ITSAppUsesNonExemptEncryption` is false), so App Store
Connect does not ask on each upload.

## After approval
Create an external group in TestFlight, add the build, and share the public link. The first
build of each new version (`0.4.0`, then `0.5.0`, ...) is reviewed again; later builds of
the same version usually are not.
