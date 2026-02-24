# IntuneConfigurator

**IntuneConfigurator** is a PowerShell-based automation toolkit for Microsoft Intune. Run the executable and pick a tool — everything is handled automatically.

## 🛠️ Tools

| Tool | Description |
|------|-------------|
| **Baseline** | Automatically creates baseline Intune configuration profiles (device restrictions, password policies, etc.) |
| **Datto RMM** | Packages and deploys the Datto RMM agent to Intune as a Win32 app |
| **Duo Security** | Packages and deploys Duo Security Windows Logon to Intune, including a Proactive Remediation to enforce the required registry key |
| **Printers** | Exports a selected Windows printer (driver, port, and queue) using PrintBrm, builds a single-printer .intunewin package, uploads it to Intune as a Win32 app via Microsoft Graph, and assigns it to All Devices with a PowerShell detection rule |

## 🚀 Getting Started

1. [Download](https://github.com/El3ctr1cR/IntuneConfigurator/releases/latest/download/IntuneConfigurator.exe) the latest version of the executable.
2. Run the executable as **Administrator**.
3. Select the tool you want to run from the menu.

> Ensure you have the necessary admin permissions on your Microsoft 365 tenant before running.