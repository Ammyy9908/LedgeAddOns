# Calculator

Basic and scientific math in Ledge's notch. Use the basic keypad or the full 10 × 5 scientific keypad, or type an expression above the live result and press Return. Click a result to copy it. The scientific view has a second function bank, degrees/radians and memory registers. History keeps the last 50 evaluated expressions and restores one for editing. A small result widget can be paired with another widget on Home.

## Set up

Requires macOS 14 or later and Ledge with LedgeKit API 0.23.0. Install the built `Calculator.ledgeaddon` through Ledge → Settings → Add-on Store → ⋯ → Load Add-on. Open Calculator from the Add-ons page, or set its C keyboard shortcut in its Settings page.

The **Basic** and **Scientific** buttons switch views. The clock opens history; select an entry to restore it. The pin keeps the page open when the pointer leaves (clicking elsewhere still closes it). **2nd** switches to inverse functions; **DEG/RAD** changes angle units. Scientific functions act on the current expression. **EE** enters a scientific exponent: `1e3` means 1,000. Complete the closing parenthesis after entering an nth root. Click the large result or the copy icon to copy its full precision.

Click the expression above the result to type directly; Return evaluates and saves it. The opening shortcut focuses that field. It uses the keyboard only while this page has focus; it does not capture keys globally.

Examples: `249 * 12`, `200 + 10%`, `sin(30) + 2pi` in degrees, `sin(pi/2)` in radians, `5!`, `4(2+3)`, `sqrt(81)` and `1e3 + 2.5e-2`.

## Data and permissions

Everything is calculated on this Mac. There are no network requests, background timers, clipboard reads or processes. Draft expressions are not saved. Evaluated history and preferences are stored through Ledge's per-add-on settings; memory lasts for the running session. Turn off Keep history to stop saving new entries, or use the confirmed Clear history action to remove existing entries.

- `clipboard-write`: copies a result when you click it. Calculations continue if it is disabled.
- `notch-control`: pins or opens the calculator from its widget, Settings button or shortcut. The Add-ons page still works if it is disabled.
- Surfaces: notch page, settings page, widget and shortcut.

## Limits

Uses finite double-precision numbers, not arbitrary precision or financial decimal arithmetic. Display precision is 2, 6, 10 or 14 decimal places; operations retain the underlying number. Expressions are limited to 512 bytes and bounded nesting. Invalid expressions, division by zero and non-finite results are refused; factorial takes integers from 0 to 170.

The host draws native buttons, semantic colors, focus, pressed feedback and an adaptive wide scientific page. This is an independent calculator built with public LedgeKit surfaces, not the embedded Apple Calculator app.

Requires a Ledge host supporting LedgeKit API 0.23.0 or later. Older hosts report that an update is needed before running this package.

## Develop and verify

```sh
swift test
ledgekit build
ledgekit check --report .build/check.json
ledgekit check --deny all --report .build/check-denied.json
ledgekit shots --out .build/shots
ledgekit lint
ledgekit validate --submit
```

The package pins the public LedgeKit 0.23.0 release by its HTTPS URL. Sources in CalculatorCore contain the parser, state and every surface; the executable only connects them to the Ledge session.
