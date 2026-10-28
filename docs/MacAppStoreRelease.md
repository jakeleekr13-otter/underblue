# UnderBlue for Mac — App Store release prep

Created: 2026-10-20. Updated: 2026-10-20 (later the same day). The Mac app is built; see [MacApp.md](MacApp.md) for the state. This file is stage 8 of that plan.
It is based on [AppStoreRelease.md](AppStoreRelease.md) and [AppStoreMetadata.md](AppStoreMetadata.md) (iOS).

Rules for this file:
- Values marked **unverified** come from memory or from the plan. Check them in App Store Connect or Xcode first.
- Nothing here is submitted. A ticked box names what was done on 20 Oct 2026 and where to see it.

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
3. Purchase: stage 5 manual sandbox check. Done on 20 Oct for buy and export. Open: Pro after a relaunch, Restore Purchase (no StoreKit tests).
4. Screenshots come from the final build, not from an earlier one.

## Part A — Can prepare now (no build needed)

- [x] The Mac app record exists in App Store Connect (the IAP below is attached to it). Platform: macOS.
  - Name: `UnderBlue - Underwater Photos` (29 characters; Jake, 28 Oct 2026). The iOS app is `UnderBlue - Underwater photo`.
  - Rejected name: `UnderBlue for Mac - UW photo`. App Review rejected 1.0 (1) on 27 Oct 2026 under Guideline 5.2.5: "for Mac" in the app name. Do not use Apple product names (Mac, iPhone) in the name or the description.
  - Resubmitted on 28 Oct 2026 with the same build, 1.0 (1). Only the metadata changed (Jake).
  - SKU: `UNDERBLUE-MAC-001` (proposed). It cannot change later.
  - Primary language: English (U.S.). Category: Photo & Video.
- [x] Register the Mac bundle IDs in the Developer portal: app and share extension. Done by Jake; Xcode signing was checked for both targets.
- [ ] Age-rating questionnaire. Same answers as iOS. Expected 4+.
- [ ] Copyright owner and App Review contact. Same as iOS.
- [ ] App Privacy answers. Copy the iOS answers (see AppStoreRelease.md, "App Privacy declaration"). Check each line against the Mac support process.
- [ ] Support URL, Privacy Policy URL and emails. Same as iOS. Add one line to the support site: "UnderBlue for Mac".
- [ ] After the release: put the Mac App Store link on the website.
  - Set `MAC_APP_STORE` in `underblue-support/_build/build_landing.py`, rebuild and push.
  - Then the Mac section shows a Mac App Store badge instead of "coming soon" (see AppStoreRelease.md, "Website").
- [x] Create `com.underblue.mac.pro`: non-consumable. Status "Prepare for Submission". Price 19.99 USD; Jake checked the generated prices. The review screenshot is `AppStoreAssets/IAP/Mac/mac-pro-review-1280x800.png`. Display name and description: not written yet (part 3 of the metadata review).
- [ ] Draft the metadata (Part C below). Jake reviews the English text.
- [ ] Decide Family Sharing for the IAP. Default: off, like iOS. It cannot be undone.

## Part B — After the build exists

Xcode configuration to set in stage 1 and check at archive time:

- [ ] Target `UnderBlueMac`: `SDKROOT = macosx`, deployment target 26.0, architecture arm64 only.
- [ ] App Sandbox on. Entitlements: user-selected files (read-write), Photos library, app group.
- [ ] App group ID. **Unverified:** the Mac App Store may need a team-ID prefix on the group ID. Check at stage 1, before the first archive.
- [ ] Output folder uses a security-scoped bookmark. Test: pick a folder, quit, relaunch, export. It must still write. Not measured yet. The "Show in Finder" link after a relaunch uses the same bookmark.
- [x] Encryption: `ITSAppUsesNonExemptEncryption = NO`. Category `public.app-category.photography`. Both keys are in the built Info.plist.
- [x] Privacy manifest. `PrivacyInfo.xcprivacy` is in the built Mac app. Recheck the required-reason APIs for Mac-only code before the upload.
- [x] Hardened Runtime on. Signing: Automatic, team `M3HJ7YK7N7`. Both are set in the project.
- [ ] Version and build numbers match in the app and the share extension.
- [ ] Archive. Run **Validate App** before **Distribute App**. Check the archive has the share extension and both profiles carry the app group.
- [ ] Review the UI as the reviewer will: first launch, trial, paywall, restore purchase, redeem code.

App icon and Help:
- [x] The Mac app uses the iPhone icon, `UnderBlue/Resources/AppIcon.icon` (Icon Composer), since 24 Oct 2026. The draft icon set is removed. See `IconComposer.md`.
- [x] Help window and About panel. Help shows the Apache-2.0 license of the depth model, as the iPhone app does. `ComplianceTests` checks it.
- [x] About shows `© 2026 Enheart` (`NSHumanReadableCopyright`). In App Store Connect the Copyright field takes `2026 Enheart`, without the © sign and without a URL.

Screenshots:
- [x] Mac screenshot size. App Store Connect accepts 2880×1800, 2560×1600, 1440×900 and 1280×800 (text shown on the upload page, pasted by Jake).
- [x] Five captioned shots, 2560×1600, in `AppStoreAssets/Screenshots/mac-en-US/final`. They come from an unsigned Debug build of the same sources, **not** from the final build. Retake them if the release build looks different. Media: developer-owned only; the two-diver wreck photo is cropped so no other person shows. The set:
  1. Fix a whole dive in one batch (queue with photos and a video)
  2. Bring back the real colour (wreck before and after)
  3. Drop in a folder. Walk away. (batch in progress)
  4. Video, fixed too (the iPhone video frames)
  5. Pick a look. Set the strength. (Custom sliders)
  Earlier plan, replaced:
  1. Batch window with a mixed queue
  2. Before/after preview
  3. Looks and Custom sliders
  4. Finder drag and drop
  5. On-device, no account
- [x] IAP review screenshot: the Mac paywall at 1280×800 with $19.99 (local StoreKit file), feature list, Restore Purchase and Redeem Code.
- [ ] Do not use UIEB benchmark images (non-commercial licence).

## Part C — Metadata draft (English, for Jake's review)

Not final. Jake asked on 20 Oct for more emphasis on batch jobs. A rewrite is pending his review, in three parts: 1 screenshot captions (approved, done), 2 metadata, 3 review notes and IAP text. Claims marked **confirm** depend on checks not done yet.

**Subtitle:** `Batch underwater colour fix`

**Promotional text:** Fix the colour of many underwater photos and videos in one batch. Private, on-device processing on your Mac. No account needed.

**Description:**

UnderBlue brings believable colour and clarity back to underwater photos and videos. It works on a whole folder at once.

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

UnderBlue processes imported photos and videos entirely on the device. No account or cloud service is used. The free trial allows one photo export and one video export limited to the first 10 seconds. Batch processing is a Pro feature. UnderBlue Pro is the non-consumable product `com.underblue.mac.pro`. The output folder is chosen by the user and kept with a security-scoped bookmark. Diagnostics stay on the device and are shared only when the user uses the system share sheet. **Confirm** the trial limits after stage 5.

Korean text: write after Jake approves the English text.

**Review notes must also say where the purchase is.** App Review Guideline 2.1(b) asks that in-app purchases are visible to the reviewer. Add: "Buy, Restore Purchase and Redeem Code are in the app menu: UnderBlue > UnderBlue Pro…". Not added to the draft yet.

## Part D — Likely review questions

| Risk | Prepare |
|---|---|
| Reviewer cannot find the Pro feature | Review notes say batch is Pro. Paywall names batch. |
| Reviewer has no underwater media | Ship no sample media. Say in the notes that any photo or video works. **Unverified:** whether review needs sample files. |
| Sandbox write failure after relaunch | Run the bookmark test above before every upload. |
| Metadata claims what the app does not do | Check every "confirm" line against the build. |
| Name clash with the iOS record | Check the name before creating the record. |

## App Review Guidelines check (20 Oct 2026)

Source: the guidelines page, read on 20 Oct 2026 up to character 100000 of 114428. The rest is unread. The Human Interface Guidelines were not read.

| Rule | Result |
|---|---|
| 2.4.5(i) sandbox | Pass. Entitlements: app sandbox, user-selected files, Photos library, app group. No exceptions. |
| 2.4.5(ii) one bundle | Pass. The share extension is inside the app. No build scripts. |
| 2.4.5(iii) no auto start | Pass. No login item or background process code. |
| 2.4.5(iv) no code download | Pass. No network code. The depth model is in the app. |
| 2.4.5(vi) no license keys | Pass. Redeem Code uses Apple's own sheet. |
| 2.4.5(vii) updates | Pass. No updater code. |
| 2.4.5(viii) current OS | Pass. Minimum macOS 26.0. |
| 2.4.5(ix) one bundle for languages | Pass. The string catalog is in the app. |
| 3.1.1 restore | Fixed on 20 Oct. It was reachable only from a blocked export. The app menu now has "UnderBlue Pro…". |
| 5.1.1(i) privacy link in app | Pass. About and Help link to the policy. Also needed in the App Store Connect field. |
| 5.1.1(ii) purpose strings | Pass. Photos is add-only and the text matches. |
| 2.1(b) IAP visible | Open. The review notes must name the menu item (see Part C). |
| 2.1(a) no placeholders | Pass for the icon: the final Icon Composer icon since 24 Oct 2026. |

## Hardening

Jake (26 Oct 2026): do this before the next Mac build. Mac App Store binaries have no encryption. On this Mac, Magnet and Input Recorder had 0 `LC_ENCRYPTION` load commands. So a download alone exposes the binary and `default.metallib`.

Steps:

1. Build a real archive (Mac). Measure `strings`, `nm` and the metallib.
2. Set Release `SWIFT_REFLECTION_METADATA_LEVEL = none`. Test SwiftUI, `@Observable` and Codable after the change.
3. Rename the stitchable kernels and their arguments to meaningless names. The math stays in the IR (AIR). Only the meaning is hidden.

Measured on the iPhone 1.1.7 (13) archive (27 Oct 2026). The Mac archive is not measured yet.

| Check | Result |
|---|---|
| `nm -U` (defined symbols) | 1 (`__mh_execute_header`). The archive strips symbols. The 23 Oct Release build had 374 `ColorCorrection` symbols; the archive has 0. |
| Swift field names (`waterRedness`, `redCeiling`, `violetGuard`, `physicalWeight`, `lightGradient`) | All 5 are in the binary. `__swift5_reflstr` is 9,816 bytes, `__swift5_fieldmd` 13,540 bytes. Step 2 is still needed. |
| `default.metallib` (183,700 bytes) | Kernel names (`UnderBlueRestoration`, `UnderBlueFinishColor`) and argument names (`betaDirect`, `betaBackscatter`, `recoverability`, `backscatter`) are in it. Step 3 is still needed. |
| `LC_ENCRYPTION_INFO_64` | `cryptid 0` in the archive. The App Store copy was not checked. |

## Open items for Jake

1. Approve the English metadata draft (part 2 of 3 next, then part 3).
2. Final Mac icon: done. It uses the iPhone icon (24 Oct 2026).
3. Confirm the Mac build 1.0 (1) is final. Then the screenshots count as final.
4. Run the signed-build checks: folder write after a relaunch, Finder share menu, Pro after a relaunch, Restore Purchase.
5. Free Offer codes for friends? (iOS method: IAP → Offer Codes, only after the app is approved.)
6. Japanese and Chinese translations have no native review. Ship as they are, or review first?
