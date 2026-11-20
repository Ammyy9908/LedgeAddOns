# Calculator

Basic and scientific math in Ledge's notch. Use the 4 × 5 keypad or type an expression with a live result, then press Evaluate. Click a result to copy it. The scientific view has a second function bank, degrees/radians and memory registers. History keeps the last 50 evaluated expressions and restores one for editing. A small result widget can be paired with another widget on Home.

## Set up

Requires macOS 14 or later and Ledge with LedgeKit API 0.22.0. Install the built `Calculator.ledgeaddon` through Ledge → Settings → Add-on Store → ⋯ → Load Add-on. Open Calculator from the Add-ons page, or set its C keyboard shortcut in its Settings page.

The **Basic**, **Scientific** and **Type** buttons switch views; the header clock opens history. Scientific **Digits** returns to the basic keypad without losing the expression. **2nd** changes the function bank; **DEG/RAD** changes the angle unit. Complete a function's closing parenthesis before evaluating it. **EE** enters an exponent: `1e3` means 1,000. The result button and **Copy** copy the full result, even if the display is rounded.

Examples: `249 * 12`, `200 + 10%`, `sin(30) + 2pi` in degrees, `sin(pi/2)` in radians, `5!`, `4(2+3)`, `sqrt(81)` and `1e3 + 2.5e-2`.

## Data and permissions

Everything is calculated on this Mac. There are no network requests, background timers, clipboard reads or processes. Draft expressions are not saved. Evaluated history and preferences are stored through Ledge's per-add-on settings; memory lasts for the running session. Turn off Keep history to stop saving new entries, or use the confirmed Clear history action to remove existing entries.

- `clipboard-write`: copies a result when you click it. Calculations continue if it is disabled.
- `notch-control`: opens the calculator from its widget, Settings button or shortcut. The Add-ons page still works if it is disabled.
- Surfaces: notch page, settings page, widget and shortcut.

## Limits

Uses finite double-precision numbers, not arbitrary precision or financial decimal arithmetic. Display precision is 2, 6, 10 or 14 decimal places; operations retain the underlying number. Expressions are limited to 512 bytes and bounded nesting. Invalid expressions, division by zero and non-finite results are refused; factorial takes integers from 0 to 170.

Keyboard input uses LedgeKit's native text editor in the typing view. It does not capture keys globally, highlight keypad presses from typing, or treat Return as equals; use Evaluate. The keypad stays four columns wide to fit compact notches. Ledge controls its colors, button shapes and sizing. This is an independent calculator built with public LedgeKit surfaces, not the embedded Apple Calculator app.

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

The package pins the public LedgeKit 0.22.0 release. No local SDK path is required. Sources in CalculatorCore contain the parser, state and every surface; the executable only connects them to the Ledge session.
