# ios-hacking tools
Basically just some tools I use to reduce friction when iOS pentesting, or to make setting up a testing device a little less painful.

Hate some of this code. I normally write these sloppily by hand and relish the fact that I can still code. But since this repo is now public I had AI make them more reliable (no hard-coded paths, etc).

Tools are nothing crazy unique, **NO Craby Patty Secret Formula**. Just basics automated. Friction reduced. Hacking started faster. 

## TOOL LIST SUMMARY (AI GENERATED):
- `host_scripts/install_deps.sh`: installs the host deps with brew (libimobiledevice, sshpass, node, pipx), frida-tools + dump.py's python deps via pipx, and the agent's npm toolchain; `--caido` adds the Caido cask.
- `device_setup/installer.sh`: pushes TrollDecrypt, `tool_install.sh` and the zsh dotfiles to the device over SSH, then drops you into a shell.
- `device_setup/tool_install.sh`: runs on the device, installs frida-server, openssh, git, Filza, TrollDecrypt etc. via apt and sets up zsh + powerlevel10k.
- `host_scripts/connect.sh` (`usb_connect_port`): starts/restarts the iproxy USB tunnel so the device's SSH is on `localhost:2222`.
- `host_scripts/ssh_profile.sh`: one-time setup, installs an SSH key for `mobile` and `root` on the device and adds `ssh phone` / `ssh phone-root` aliases.
- `host_scripts/decrypt_and_pull.sh` (`ios_decrypt`): lists installed apps, pick one or many from a menu, decrypts them with Frida and drops the `.ipa`s locally.
- `host_scripts/pull_from_device.sh` (`td_pull`): browses a folder on the device (default: TrollDecrypt's output) and copies chosen files to the host.
- `host_scripts/ts_install.sh` (`ts_install`): copies an `.ipa` to the device and installs it with TrollStore's `trollstorehelper`.
- `host_scripts/proxy.sh` (`proxy2phone`): launches Caido if needed and reverse-forwards it so the phone can proxy through `127.0.0.1:8080`.
- `host_scripts/frida_connect.sh` (`frida_connect`): `frida-ps -U`, quick check that frida-server is reachable over USB.
- `host_scripts/link_bin.sh`: symlinks the scripts above into `~/.tools/bin` under the short names in parentheses.
- `frida/ios-dump/dump.py` (`frida-dump`): Frida 17 port of `frida-ios-dump`; the actual decryptor behind `ios_decrypt`.
- `frida/ios-dump/agent/dump.js` (`npm run build`): source of the injected agent, rewritten for the current Frida 17 API (upstream `frida-ios-dump` breaks on it); rebuild with `npm install && npm run build` in `frida/ios-dump/` after editing it or upgrading Frida.
- `rev_eng/syscall.sh` (`syscall`): a "man page" for Darwin syscalls. Looks one up by name or number (`syscall.sh iphone write`, `syscall.sh macosx 4`, `syscall.sh mmap` defaults to macOS) against the SDK headers Xcode ships: name/number from `sys/syscall.h`, arg struct + kernel prototype from `sysproto.h`, and the `man 2` one-liner if there is one. `-l` lists platforms (iPhoneOS, MacOSX, AppleTVOS, WatchOS, XROS), `-r` rebuilds the header-path cache in `~/.cache/syscall` (first run is slow, rest are instant). Handy when you're staring at an `svc 0x80` in a disassembler.

## How I use these on the Host OS:
1. Run `install_deps.sh` (brew, frida, etc.), then `link_bin.sh` (then go look at the new commands you goober `~/.tools/bin`).
2. Assuming you have the device's SSH set up and you changed the default password, run `ssh_profile.sh` so you never have to type an SSH password.
3. Add the following to your `~/.zshrc` (if you're using `~/.bashrc` while reading this... why?? Should be on a Mac):
```bash
export PATH="$PATH:$HOME/.tools/bin"
alias phone_root='ssh -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@localhost'
alias phone='ssh -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null mobile@localhost'
alias prep_phone="usb_connect_port && proxy2phone && frida_connect" # iproxy + port forward + connect 2 frida server
```

## How I use these on the iOS device: 
*NOTE*: Haven't tested this, written post by-hand jailbreak & setup (first time). But will be updating for some XS devices running iOS 18

Maybe dont run the the tool install script on JB device yet. LOL
