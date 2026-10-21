# Distribution readiness

Status: proposal, not a release. No verified downloadable binary exists as of
2026-10-21. Source baseline: d789f062203464c18254f46289fa23f0e17b9948 (0.4.2).
The current build is an independent, unofficial macOS preview.

## Answer to users

A maintainer can build once and supply the resulting RDKP; recipients do not need
Xcode, Swift, Clang or the Qt development SDK. They still need a compatible RoboDK
host and the runtime dependencies must resolve on their machine. Do not direct
users to a download until the actual package has passed clean-machine installation.

Start with one macOS x86_64 candidate for RoboDK 6.0.6.26900 / Qt 6.10.1.
Apple Silicon hardware running an Intel host under Rosetta is a separate test
configuration; it does not validate a native arm64 package. Windows/NVDA and
Linux/Orca are unimplemented.

## Build automation

The existing Makefile already implements build, package, unit and integration
checks. Use scripts/build_candidate.sh on a clean, dedicated macOS checkout with
Qt 6.10.1 configured through VOICEACCESS_QT. It saves toolchain provenance,
binary architectures, load commands, signature checks and a SHA-256 checksum.
It deliberately does not upload anything, create a tag or create a GitHub Release.

Options:
- GitHub-hosted Intel runner: macos-15-intel currently matches the target CPU.
  Provision an exact Qt 6.10.1 SDK and pin the installer/action and its checksums;
  select and record an exact Xcode installation. Do not use macos-latest, currently
  arm64. Runner images change, so this alone is not bit-for-bit reproducibility.
- Dedicated self-hosted Intel Mac: provision Qt/Xcode once and invoke the same
  script manually or through a manually dispatched workflow. Use a dedicated
  runner with no personal stations; do not run untrusted PR code on it.
- Existing maintainer Mac: fastest first candidate, provided it is built from a
  clean checkout and independently installed on a second machine.

No CI workflow is enabled by this change. Native builds and GUI tests cannot run
in the Linux environment used to prepare this proposal. Exact compiler/SDK inputs
must be locked before claiming reproducible binary output. The ZIP writer fixes
timestamps and ordering, but that does not make native signed binaries reproducible.

## Release blockers and concrete changes

1. Fix generated manifest platform/CPU selectors. package_addin.py currently emits
   cpu="any", system="any" for every asset, including macOS native binaries.
   Compare the exact accepted selector values and generated metadata with Add-in
   Creator before changing them; verify extraction and rejection/behavior on
   unsupported hosts. Do not guess selector spellings.
2. Add package validation for Mach-O CPU, deployment target and dependent libraries.
   Review otool output for ALL three binaries: no developer Qt paths or other
   machine-local dependencies. Prove host Qt resolution on a Mac without the Qt SDK.
   verify_package.py currently checks archive structure, metadata, licenses and
   executable bits, not native ABI, signature or successful installation.
3. Complete publisher/contact/website and compatibility metadata through Add-in
   Creator; compare its manifest with the custom OPC packager. Existing icon,
   README, MIT license, third-party notices and screenshot can be reused.
   Resolve the com.robodk.voiceaccess identifiers with RoboDK before submission;
   keep the unofficial attribution unless explicitly agreed otherwise.
4. Decide distribution signing. Existing scripts use ad-hoc signing, not Developer
   ID signing or notarization. Test the downloaded/quarantined delivery route on a
   clean Mac. For general distribution, implement Developer ID signing in correct
   nested-code order and Apple's notarization process with private credentials.
   Confirm host plug-in loading/library-validation constraints. Notarization is
   separate from marketplace acceptance; public RoboDK submission docs do not state
   a specific notarization requirement.
5. Record clean-machine validation of the EXACT final package checksum, after any
   signing/packaging changes. Do not reuse results from a development symlink.

## Validation gate before sharing a download

- Run make unit, make package and make integration. Integration needs installed
  RoboDK, its GUI session, matching Qt and the licensed local ABB test robot model;
  never bundle that model. A candidate script pass is not this full gate.
- Install via Add-in Manager in a fresh user profile with no source checkout or
  developer Qt SDK. Check launch, dock/native load, standalone fallback, restart,
  upgrade and uninstall, including executable permissions after extraction.
- Manually exercise VoiceOver focus/tree navigation, EN/ES/CA labels, selection,
  narration, silence and deactivation. Confirm documented simulation stopping
  behavior and no connection to physical hardware.
- Exercise the downloaded file with normal macOS quarantine/Gatekeeper behavior;
  record OS, host CPU, RoboDK build, Qt, signatures and any prompts.
- Attach reports and final SHA-256 to an explicitly labeled macOS Intel preview.
  Only after review, manually publish a GitHub prerelease with the verified RDKP,
  checksum, compatibility and known limitations. Do not publish source-only assets
  as if they were an installable package.

## Marketplace submission is a separate decision

RoboDK welcomes external developers and free or paid listings. Its English guide
requests README, icon and a manifest generated by Add-in Creator containing product
and company details; RDKP and screenshots/video are listed as optional. Source
disclosure is not required. Submit by email/contact for RoboDK review; there is no
documented automatic admission or mandatory cross-platform support. Ask RoboDK to
confirm a macOS-only preview listing, publisher identity, identifiers, compatibility
fields and any additional internal testing/signing requirements.

Recommended order: validated candidate -> limited tester distribution / GitHub
prerelease -> RoboDK submission. A listing is not evidence of official authorship.

Sources checked 2026-10-21:
- https://robodk.com/doc/en/Add-ins-Submit-Add.html
- https://robodk.com/downloads/doc/Anatomy%20of%20a%20RoboDK%20Package-Add-in%20Manager.pdf
- https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
