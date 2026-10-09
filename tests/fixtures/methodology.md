# Analytics Methodology (test fixture: `share` is an extra action, absent from the hard-coded fallback)

## Actor — closed dictionary

| Actor | When |
| --- | --- |
| `user` | The user did something |
| `system` | It happened automatically |

## Action — closed dictionary

### Navigation & UI

| Action | When | Not this |
| --- | --- | --- |
| `view` | A screen appeared | |
| `open` | A layer appeared | |
| `share` | Test-only action | |

## How it maps to the code

| `notanaction` | must not be read |
