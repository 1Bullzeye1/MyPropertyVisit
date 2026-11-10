# Start here — first paid iOS release

Decision: MyPropertyVisit 1.0, USD 4.99 one-time paid download. Publisher: Mayuresh Sonawane, individual. Current Apple account: free/Xcode only, as confirmed by owner on 10 November 2026.

The immediate goal is an approved paid iOS app, with existing offline features. Website domain purchase, subscriptions, online accounts, cloud storage and live calling are not needed for this release. A free/Xcode account cannot submit this paid App Store release.

## Owner actions in order

1. Create a dedicated support Gmail mailbox. Send only its public address and your actual country of residence/operation so the publisher/privacy details can be finished. Do not send the password.
2. Enroll in the standard [Apple Developer Program](https://developer.apple.com/programs/enroll/) as an individual under your verified legal name. Apple lists USD 99 per year or local currency where available. The public seller name will be your legal name. Complete identity verification and membership payment directly with Apple; do not buy the Enterprise program.
3. When enrollment is active, open [App Store Connect](https://appstoreconnect.apple.com/). In Business, accept the Paid Apps Agreement, then complete the tax and banking information requested for your account. Enter it only in the official portal. Refer to [Apple's agreement steps](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements) and [payment setup](https://developer.apple.com/help/app-store-connect/getting-paid/overview-of-receiving-payments).
4. Review the finished support/privacy pages and make them publicly readable before submitting their URLs to Apple. The current private website URL cannot serve as a public support/privacy endpoint. A custom .com is optional. The site audience remains private until an explicit owner instruction to make it public.
5. Review the submission build and authorize the final release after Apple approval. Use USD 4.99 as the base price and review regional prices/territories in App Store Connect. A paid download needs no in-app purchase or subscription paywall.

## Technical work underway / completed

- [x] Native iOS/Android and website rebrand committed/pushed in prior work.
- [x] First-launch scope and App Store listing copy prepared.
- [x] iOS unfinished calling controls removed; Add a property and Walkthroughs describe working features.
- [x] Settings → About & your data explains manual dimensions, compass limits, local storage and media-export limitations.
- [x] First-party privacy manifest added for local UserDefaults and file timestamps.
- [x] Build unsigned Release archive 1.0 (3); verify embedded privacy manifest/reasons and bundle identifier. Photo regression checks passed. Signed distribution/store validation remains pending.
- [ ] Finalize policy/support contact fields and public URLs; add accessible policy/support links in the app.
- [ ] Capture real screenshots from the final UI and finish store questionnaires/review notes.
- [ ] Set distribution signing after membership is active; create and validate the signed upload archive.
- [ ] Upload, test the submission candidate, submit to Apple and inspect actual review outcome.

An unsigned archive is a build check, not an App Store upload artifact. Compilation and simulator success do not establish review approval. No membership payment, financial agreement, store record, tax submission or public release has been completed by the agent.

## Getting the first paying users

After the store link exists, share a short demonstration with a small group of brokers, sellers and active buyers who actually document visits. Show one real workflow: create property → capture compass media → add room dimensions → export selected files. Use permissioned/demo property content.

Suggested message for you to send:

> I built MyPropertyVisit for keeping property-visit photos, silent walkthrough videos, compass directions and manually entered room details together. It works offline and costs $4.99 once. Here is the App Store link: APP_STORE_URL. If you document property visits, I would value your feedback after a real visit.

Replace APP_STORE_URL only with the actual published link. No messages have been sent on your behalf. Start with direct feedback rather than paid advertising; the launch needs evidence of willingness to pay and reliable repeat use, not a promised sales target. Use App Store Connect sales/diagnostic reports for the initial operational review; no new analytics SDK is required.

## Status to report back

- Public support Gmail: pending.
- Country: pending.
- Apple Developer enrollment: not started/confirmed active yet.
- Paid Apps agreement, tax and banking: pending owner completion.
- Signed upload and App Store approval: pending.
