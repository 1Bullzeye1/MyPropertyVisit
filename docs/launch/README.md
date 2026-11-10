# MyPropertyVisit launch documentation

Prepared 10 November 2026. Baseline: current local source, including photo/video sharing and saving to Photos/Gallery. This is a launch scope freeze, not confirmation that store review or release testing has finished.

For the shortest route to a paid release, follow [Start here](START-HERE.md).

## Decisions

- iOS launch price: **USD 4.99, one-time paid download**. Configure regional prices in App Store Connect. No subscription or in-app purchase is part of this launch.
- Product: offline property visits, compass media, manually entered room details and media exports.
- Selected product name: **MyPropertyVisit**, approved 10 November 2026. Matching .com registration and final brand clearance remain pending; preliminary web/registry screening is not a reservation.
- Public seller identity: Mayuresh Sonawane, individual. Country: India. Public support mailbox: mypropertyvisit05@gmail.com. A custom domain is optional. Never publish unresolved template tokens.
- iOS repository contains iOS documentation only. Android-specific release documents are in the separate Android repository. Website source is in the sibling MyPropertyVisit-Website folder.

See [brand change and compatibility notes](BRAND-RENAME.md).

## Documents

| File | Purpose | Status |
| --- | --- | --- |
| [Launch scope](LAUNCH-SCOPE.md) | Included features, exclusions and accepted limitations | Prepared against source |
| [Owner setup](OWNER-SETUP.md) | Seller identity, domain, email and pricing setup | Publisher/contact confirmed; Apple setup pending |
| [User guide](USER-GUIDE.md) | Current paths, permissions, capture and exports | Prepared; walkthrough on release build pending |
| [Privacy policy](PRIVACY-POLICY.md) | App handling, sharing, retention, support and website distinction | Contact fields complete; public access pending |
| [Support content](SUPPORT.md) | Help page and troubleshooting | Contact fields complete; public access pending |
| [Store listing](APP-STORE-LISTING.md) | Copy, screenshots and review notes | Copy and URL candidates prepared; screenshots/public access pending |
| [Privacy inventory](PRIVACY-INVENTORY.md) | Evidence and proposed privacy answers | Source review and unsigned archive checked; store validation pending |
| [Release checklist](RELEASE-CHECKLIST.md) | SDLC gates, acceptance tests and release record | Open release actions explicitly listed |

## Publication rules

All files are editable Markdown. Public-facing drafts must have owner/contact placeholders resolved before public release. Website preview is private; its URL cannot serve as the public App Store privacy/support URL while authentication is required.

The existing November 6 tag remains a historical checkpoint. The launch candidate includes later local export changes and must receive its own reviewed commit/build identity. No Git commit, push, store submission, domain registration or public audience change is implied by preparing these documents.
