class_name BuildInfo
extends RefCounted
## Shown as a small stamp in the corner of the screen. The GitHub Actions workflow overwrites
## this file before exporting, with the real commit hash and build time.
const COMMIT := "dev"
const TIME := "local"
