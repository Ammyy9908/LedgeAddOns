# LocalSend

Send files between your Mac and phones or computers nearby that run [LocalSend](https://localsend.org), with no
cloud in between. It speaks LocalSend's open protocol, so the other device needs only the LocalSend app, on the same
network.

## Sending

Devices that answer show on the add-on's page in the open notch. Drop files or folders on a device, or choose
**Send with LocalSend** on a shelf item and pick the device. The person on the other side accepts, then the page
shows the transfer; the ✕ button cancels it.

If nothing shows up, press ↻ to look again. The add-on announces itself to LocalSend's multicast group and, when
nothing answers, asks every address on your network, as LocalSend does where multicast is blocked.

## Receiving

When another device sends to this Mac, the notch asks whether to accept, naming the files and their size. No answer
in a minute declines. Accepted files are saved to Downloads (or Desktop or Documents, in the add-on's settings) and
put on the shelf. A sent folder keeps its shape. A text message offers to copy it.

Set a **PIN** in the settings and senders must enter it before you're asked; five wrong tries from one address stop
it asking.

## Security

Transfers use HTTPS. The add-on makes its own certificate once, the same kind LocalSend makes, and keeps it in the
folder Ledge gives the add-on; its SHA-256 is this Mac's fingerprint. When sending, it trusts only the certificate
whose fingerprint the device announced, and a device found by scanning is known by its certificate, not by what it
says. Names of received files are cleaned so nothing can be written outside the folder you chose, and every file's
size, and its checksum when the sender gives one, is checked before it gets its name.

## What it asks for

- `shared-files`, for files you send from the shelf or drop on a device.
- `shelf-add`, to put received files on the shelf.
- `questions`, to ask you before accepting a transfer.
- `clipboard-write`, to copy a text message you accept.
- `local-network`: it listens on port 53317 (the next free one if the LocalSend app has it) and on LocalSend's
  multicast group, on your local network only. macOS asks once whether Ledge may use the local network.

## What it can't do yet

- Send to a device that asks for a PIN. Turn the PIN off on that device to send from Ledge.
- Talk to devices with encryption turned off (HTTP), or over IPv6.
- Send text messages, or use LocalSend's "receive via link".

LocalSend is made by Tien Do Nam and its contributors; this add-on isn't. See NOTICE.md.
