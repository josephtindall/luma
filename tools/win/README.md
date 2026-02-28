# Luma - Windows Scripts Guide

This guide walks you through building and running Luma on your Windows machine.
No prior experience required — just follow the steps in order.

---

## Before you start

You need three programs installed. If you already have them, skip ahead.

**Docker Desktop**
This is what runs the database, the cache, and the Haven identity service.
Think of it as a box that runs small isolated programs so they don't interfere with your computer.
Download from: https://www.docker.com/products/docker-desktop

**Flutter**
This builds the web interface (the part you see in your browser).
Download from: https://docs.flutter.dev/get-started/install/windows

**Go**
This is the programming language the Luma server is written in.
Download from: https://go.dev/dl

Once all three are installed, open **Docker Desktop** and leave it running in the background.
Everything else happens in a terminal.

---

## Opening a terminal

1. Press `Win + X` and choose **Terminal** (or **PowerShell**).
2. Navigate to the Luma project folder:
   ```
   cd C:\Projects\luma
   ```
   All commands in this guide are run from that folder.

---

## The four scripts

All scripts live in `tools\win\`. You run them by typing their name at the terminal prompt.

| Script | What it does |
|--------|-------------|
| `build.ps1` | Compiles the code into something runnable |
| `run.ps1` | Starts the entire application stack |
| `clean.ps1` | Stops everything and cleans up files |
| `publish.ps1` | Sends a finished build to a registry so others can use it |

---

## Typical workflow

### Step 1 — Build

Run this once before you start for the first time, and again whenever you change Flutter code:

```powershell
.\tools\win\build.ps1
```

This does two things:
- Compiles the web interface (`src\luma-web\`) and saves it to `artifacts\web\`
- Builds a Docker image of the Go server called `luma:latest`

You will see a lot of output scroll by. That is normal. When it finishes you should see:

```
Build complete.
```

If it fails, read the last error message — it will usually tell you exactly what went wrong
(missing tool, syntax error, etc.).

---

### Step 2 — Run

```powershell
.\tools\win\run.ps1
```

This starts everything: the database, the cache, Haven (the identity service), and Luma itself.

Once it is running you will see log lines streaming in the terminal. Leave this window open.
Open your browser and go to:

```
http://localhost:8002
```

You should see the Luma web interface.

To stop the stack at any time, press `Ctrl + C` in the terminal.

---

### Step 3 — Make changes

**Go (server) changes:**
The server reloads automatically when you save a `.go` file. You do not need to restart anything.

**Flutter (web interface) changes:**
Flutter does not hot-reload through the server. After changing Flutter code, run:

```powershell
.\tools\win\build.ps1 -Web
```

Then stop and restart the stack (`Ctrl + C`, then `.\tools\win\run.ps1` again).

---

## Testing the setup wizard from scratch

The setup wizard (the screen that asks for an instance name, timezone, and owner account)
only appears when the database is completely empty. To see it again:

```powershell
.\tools\win\run.ps1 -Fresh
```

The `-Fresh` flag wipes the database before starting. Haven will start in "unclaimed" mode
and print a one-time setup token in its logs. It looks like this:

```
========================================
  Setup token: abc123...
  Expires in:  2 hours
========================================
```

Scroll up in the terminal to find it, or if you used `-Detach`, run:

```powershell
docker compose -f docker-compose.dev.yml logs haven
```

Open `http://localhost:8002`, paste the token into Step 1, and follow the wizard.

> **Note:** `-Fresh` permanently deletes the local database. Any accounts, vaults, or content
> you created will be gone. Only use it when you want a clean slate.

---

## Cleaning up

### Light clean (keep the database)

Stops containers and deletes compiled output. Good for freeing disk space or starting a fresh build:

```powershell
.\tools\win\clean.ps1
```

### Full reset (wipe the database too)

Deletes everything including the database. After this, Haven will be in "unclaimed" mode
on the next start, exactly like a brand new install:

```powershell
.\tools\win\clean.ps1 -Full
```

### Preview before deleting

Not sure what will be deleted? Run this first — it shows you exactly what would happen
without actually doing anything:

```powershell
.\tools\win\clean.ps1 -WhatIf
```

---

## Running infrastructure without the Luma server

Useful when you are actively editing Go code and want faster restarts than Docker allows:

```powershell
.\tools\win\run.ps1 -DbOnly
```

This starts only the database, cache, and Haven. The terminal will print the command
to run Luma directly on your machine. Open a second terminal window and paste it.

---

## Publishing a release

When you are ready to share a build with others:

```powershell
.\tools\win\publish.ps1 -Registry ghcr.io/josephtindall -Tag v1.0.0
```

Replace `ghcr.io/josephtindall` with your own registry address.

You must be logged in to your registry first:

```powershell
docker login ghcr.io
```

To also export a standalone binary and the web app files (for attaching to a GitHub release):

```powershell
.\tools\win\publish.ps1 -Registry ghcr.io/josephtindall -Tag v1.0.0 -WithAssets
```

The exported files will appear in the `artifacts\` folder.

---

## Quick reference

| Goal | Command |
|------|---------|
| Build everything | `.\tools\win\build.ps1` |
| Build only the web interface | `.\tools\win\build.ps1 -Web` |
| Start the stack | `.\tools\win\run.ps1` |
| Start fresh (resets database) | `.\tools\win\run.ps1 -Fresh` |
| Start in background | `.\tools\win\run.ps1 -Detach` |
| Start infra only (run Go locally) | `.\tools\win\run.ps1 -DbOnly` |
| Stop and clean build files | `.\tools\win\clean.ps1` |
| Full reset (wipes database too) | `.\tools\win\clean.ps1 -Full` |
| Preview a clean without doing it | `.\tools\win\clean.ps1 -WhatIf` |
| Push a release | `.\tools\win\publish.ps1 -Registry <your-registry> -Tag v1.0.0` |

---

## Something went wrong?

**"Docker is not running"**
Open Docker Desktop and wait for it to finish starting up, then try again.

**"flutter is not installed or not in PATH"**
Flutter is not installed, or the installer did not add it to your PATH.
Re-run the Flutter installer and make sure to tick the option that adds it to PATH.

**"Port 8002 is already in use"**
Something else is using that port. Run `.\tools\win\clean.ps1` to stop Luma's containers,
then try again.

**The browser shows a blank page or an error**
The web interface may not have been built yet. Run `.\tools\win\build.ps1 -Web`, then restart
the stack.

**The setup wizard keeps showing up**
You used `-Fresh` or `-Full` which wiped the database. Complete the wizard to create
an owner account — it only asks once per fresh install.
