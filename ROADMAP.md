# Roadmap

## Scope rule

DingsKit is not built speculatively. Features land when one of our apps needs
them. Extracting infrastructure from a real consumer (LuftDings, then
ZuckerDings) keeps the API grounded in shipping code instead of guessed-at
generality. The items below are things a future app will plausibly want; each
is deferred until an app actually reaches for it.

## Nice-to-haves

- **Template repo**: a minimal starter app that bootstraps DingsKit with one
  example provider, so a new app skips the boilerplate.
- **OAuth auth-code helper**: shared flow for providers that need interactive
  OAuth (redirect, code exchange, token refresh) rather than a pasted key.
- **watchOS scaffolding**: complication and Watch-app plumbing on top of the
  existing App Group cache.
- **`SensorReading` unit-conversion seam**: a registered conversion layer
  (e.g. °C/°F, mg/dL vs mmol/L) so display units are a user preference rather
  than fixed per provider.
