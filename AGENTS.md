# Project-specific workflow

- Do not control or debug through the Parallels Windows virtual machine.
- Build Windows installation artifacts locally on macOS whenever possible.
- After generating a Windows artifact, provide a concise manual installation and debugging checklist; the user performs the Windows-side validation.
- After every completed macOS fix or update, run the relevant verification, package the latest app, and replace `/Applications/MobiVerse.app` so the installed local app is immediately ready for testing.
