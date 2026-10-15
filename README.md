# Vorssaint Add-ons

Extra modules for the [Vorssaint](https://github.com/vorssaint/vorssaint-utils) Dynamic Island:

- **KDE Connect**: drag a file or a link onto the island and drop it on one of your paired devices.
- **AirDrop**: drop it on the AirDrop tile and the AirDrop window opens with nearby devices.
- **Send from the Shelf**: drag a file out of the Shelf and small AirDrop and device targets appear at the bottom.

With the Shelf on too, the island splits into side-by-side drop zones. With only one module on, it takes the whole island. It also works with the Shelf in its own window.

Vorssaint has no plugin system, so the add-ons are a patch on top of the official source code, built on your Mac by the install script.

## Install

1. Open **Terminal**: press `⌘ Space`, type `Terminal` and press Return.
2. Paste this line and press Return:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/RaspyGray/vorssaint-addons/main/install.sh | zsh
   ```

3. If a window asks to install the **command line developer tools**, click *Install*, wait for it to finish, then paste the same line again.
4. Wait a few minutes while it builds. When it's done, **Vorssaint (Developer)** opens by itself.
5. In Vorssaint, go to *Settings → Features → Dynamic Island* and turn on **KDE Connect Integration** and/or **AirDrop in the Island**.

That's it. If you were already using Vorssaint, your settings are copied over and the official app is closed, so only one island runs. The official app itself is not modified.

The options are in *Settings → Dynamic Island → Content → Files*: tile animations, sending from the Shelf, opening KDE Connect automatically.

## Updates

Nothing to do. Once a day the add-on checks for a new Vorssaint release or a new version of the add-on, rebuilds in the background and sends a notification.

If a new Vorssaint release changes too much for the patch to apply, the version you have keeps working until the add-on is updated.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/RaspyGray/vorssaint-addons/main/install.sh | zsh -s -- --uninstall
```

This removes Vorssaint (Developer) and the daily check. The official Vorssaint is untouched.

## Notes

- KDE Connect must be installed, with your devices paired. If it's closed, the island starts it in the background.
- macOS doesn't let apps list nearby AirDrop devices, so the AirDrop tile opens the system AirDrop window to pick one.
- Other options: `--force` rebuilds even if up to date, `--no-auto-update` turns the daily check off (add them after `zsh -s --`).
- Log: `~/Library/Application Support/Vorssaint Addons/install.log`

## License

GPL-3.0, same as Vorssaint.
