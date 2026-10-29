# QVAC adapter notices

The Dart compact-encoding/framing/RPC client and native byte relays are adapted
from [SebastianKumor/qvac_flutter](https://github.com/SebastianKumor/qvac_flutter),
Apache-2.0. Its license is preserved at
`lib/modules/local_ai/engines/qvac/LICENSE`. Copyright belongs to the upstream
contributors. Journal modifications add primitive-only RPC, foreground lifecycle
handling, isolated resources, and app-owned downloading and operations.

QVAC SDK and its inference core: 0.22.0, Apache-2.0.
BareKit 2.5.5: Apache-2.0; embeds Bare (Apache-2.0), V8 (BSD-3-Clause)
and libuv (MIT). Android also includes libc++ under Apache-2.0 with LLVM exception.
The native inference addons contain llama.cpp and stable-diffusion.cpp and their
transitive components. Run `npm run build` to collect the installed package
licenses, notices and a package/version manifest into `qvac/licenses`; Android
ships that folder as assets. Review the native addons' bundled license files
before distributing a release. Model licenses are listed separately in the
catalog and are not covered by these runtime licenses.
