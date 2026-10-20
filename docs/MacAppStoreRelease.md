# UnderBlue for Mac — App Store release prep

Created: 2026-10-20. Nothing is built yet (see [MacApp.md](MacApp.md)). This file is stage 8 of that plan.
It is based on [AppStoreRelease.md](AppStoreRelease.md) and [AppStoreMetadata.md](AppStoreMetadata.md) (iOS).

Rules for this file:
- Values marked **unverified** come from memory or from the plan. Check them in App Store Connect or Xcode first.
- Nothing here is submitted. Every box starts open.

## Decisions already made

| Item | Value | Source |
|---|---|---|
| Separate app record | Yes. Not Universal Purchase. | Jake, 20 Oct 2026 |
| Bundle ID | `com.underblue.mac` | MacApp.md decision 1 |
| Share extension bundle ID | `com.underblue.mac.share` (proposed) | MacApp.md decision 6 |
| App price | Free download | MacApp.md decision 2 |
| Pro product | Non-consumable, one-time, lifetime. `com.underblue.mac.pro` (proposed). | Jake, 20 Oct 2026 |
| Pro price | 19.99 USD (base price). iPhone Pro is 25,000 KRW. Check the KRW and other prices that App Store Connect generates. | Jake, 20 Oct 2026 |
| Minimum OS | macOS 26, Apple silicon only | MacApp.md decision 3 |
| Store | Mac App Store only, sandboxed | MacApp.md decision 4 |
| Target user | Mac users who may own an Android phone and no iPhone | Jake, 20 Oct 2026 |

## Release gates (same idea as iOS)

An App Store Connect form being complete does not override these.

1. Colour: stage 6 of MacApp.md is done. Gate and m5 numbers exist for the Mac render.
2. Batch: stage 3 test passes (3 photos + 2 videos → 5 valid files).
3. Purchase: stage 5 manual sandbox check is done (no StoreKit tests).
4. Screenshots come from the final build, not from an earlier one.

## Part A — Can prepare now (no build needed)

- [ ] Create the app record in App Store Connect. Platform: macOS.
  - Name `UnderBlue`. It is already used by the iOS record. **Unverified:** whether the same name is allowed for a second record. Check first.
  - SKU: `UNDERBLUE-MAC-001` (proposed). It cannot change later.
  - Primary language: English (U.S.). Category: Photo & Video.
- [ ] Register the Mac bundle IDs in the Developer portal: app and share extension.
- [ ] Age-rating questionnaire. Same answers as iOS. Expected 4+.
- [ ] Copyright owner and App Review contact. Same as iOS.
- [ ] App Privacy answers. Copy the iOS answers (see AppStoreRelease.md, "App Privacy declaration"). Check each line against the Mac support process.
- [ ] Support URL, Privacy Policy URL and emails. Same as iOS. Add one line to the support site: "UnderBlue for Mac".
- [ ] Create `com.underblue.mac.pro`: non-consumable, display name, description, tax category. Price after Jake decides.
- [ ] Draft the metadata (Part C below). Jake reviews the English text.
- [ ] Decide Family Sharing for the IAP. Default: off, like iOS. It cannot be undone.

## Part B — After the build exists

Xcode configuration to set in stage 1 and check at archive time:

- [ ] Target `UnderBlueMac`: `SDKROOT = macosx`, deployment target 26.0, architecture arm64 only.
- [ ] App Sandbox on. Entitlements: user-selected files (read-write), Photos library, app group.
- [ ] App group ID. **Unverified:** the Mac App Store may need a team-ID prefix on the group ID. Check at stage 1, before the first archive.
- [ ] Output folder uses a security-scoped bookmark. Test: pick a folder, quit, relaunch, export. It must still write.
- [ ] Encryption: `ITSAppUsesNonExemptEncryption = NO`. Category `public.app-category.photography`.
- [ ] Privacy manifest. Same declarations as iOS. Recheck the required-reason APIs for Mac-only code.
- [ ] Hardened Runtime on. Signing: Automatic, team `M3HJ7YK7N7`.
- [ ] Version and build numbers match in the app and the share extension.
- [ ] Archive. Run **Validate App** before **Distribute App**. Check the archive has the share extension and both profiles carry the app group.
- [ ] Review the UI as the reviewer will: first launch, trial, paywall, restore purchase, redeem code.

App icon and Help:
- [x] A Mac icon set exists (`UnderBlueMac/Assets.xcassets/AppIconMac.appiconset`). It is a **draft** from `scripts/make_mac_icon.py`. Confirm the final design.
- [x] Help window and About panel. Help shows the Apache-2.0 license of the depth model, as the iPhone app does. `ComplianceTests` checks it.
- [x] About shows `© 2026 Enheart` (`NSHumanReadableCopyright`). In App Store Connect the Copyright field takes `2026 Enheart`, without the © sign and without a URL.

Screenshots:
- [ ] Mac screenshot size. **Unverified:** App Store Connect accepts 1280×800, 1440×900, 2560×1600 and 2880×1800. Confirm in the upload page.
- [ ] Five shots from the final build. Use developer-owned media only. Suggested set:
  1. Batch window with a mixed queue
  2. Before/after preview
  3. Looks and Custom sliders
  4. Finder drag and drop
  5. On-device, no account
- [ ] IAP review screenshot: the real Mac paywall, with price, feature list, Restore Purchase and Redeem Code.
- [ ] Do not use UIEB benchmark images (non-commercial licence).

## Part C — Metadata draft (English, for Jake's review)

Not final. Claims marked **confirm** depend on work that does not exist yet.

**Subtitle:** `Batch underwater colour fix`

**Promotional text:** Fix the colour of many underwater photos and videos in one batch. Private, on-device processing on your Mac. No account needed.

**Description:**

UnderBlue for Mac brings believable colour and clarity back to underwater photos and videos. It works on a whole folder at once.

Drag in files or folders from Finder. Pick a look. Press Correct. UnderBlue processes the queue and saves each result to the folder you choose.

Features:

• Batch queue for photos and videos together (**confirm** limit after stage 3)
• Natural Dive, Tropical and Deep Dive looks
• Custom look with five adjustment sliders
• Before and after preview for each item
• Depth-aware photo and video restoration
• Original-resolution export (**confirm** 4K and HDR on Mac after stage 6)
• Works with files from any camera or phone (**confirm** formats after the format check)
• Fully on-device. No account, no cloud upload.

Try one photo export and one 10-second video for free. UnderBlue Pro is a one-time purchase. It unlocks batch processing, unlimited photos, full-length video and supported 4K and HDR export. (**Confirm** the Pro feature list with the Mac paywall.)

UnderBlue is made for recreational diving memories. It is not a scientific colour-measurement or professional grading tool.

**Keywords (draft):** underwater,diving,scuba,snorkel,batch,color,colour,restore,photo,video,reef,ocean,marine

**Review notes (draft):**

UnderBlue for Mac processes imported photos and videos entirely on the device. No account or cloud service is used. The free trial allows one photo export and one video export limited to the first 10 seconds. Batch processing is a Pro feature. UnderBlue Pro is the non-consumable product `com.underblue.mac.pro`. The output folder is chosen by the user and kept with a security-scoped bookmark. Diagnostics stay on the device and are shared only when the user uses the system share sheet. **Confirm** the trial limits after stage 5.

Korean text: write after Jake approves the English text.

## Part D — Likely review questions

| Risk | Prepare |
|---|---|
| Reviewer cannot find the Pro feature | Review notes say batch is Pro. Paywall names batch. |
| Reviewer has no underwater media | Ship no sample media. Say in the notes that any photo or video works. **Unverified:** whether review needs sample files. |
| Sandbox write failure after relaunch | Run the bookmark test above before every upload. |
| Metadata claims what the app does not do | Check every "confirm" line against the build. |
| Name clash with the iOS record | Check the name before creating the record. |

## Open items for Jake

1. Check the generated KRW price against the iPhone price (25,000 KRW).
2. Approve the English metadata draft.
3. Free Offer codes for friends? (iOS method: IAP → Offer Codes, only after the app is approved.)
