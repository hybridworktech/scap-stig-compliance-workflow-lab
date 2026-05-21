# SCAP/STIG Compliance Automation Lab

This repository is a synthetic demonstration of security compliance automation. It does not contain real scan results, host identifiers, client data, production configurations, proprietary product concepts, founder ideas, or internal architecture.

## What It Does

The mini engine converts synthetic SCAP/STIG-style findings into job-ready artifacts:

- Remediation tracker CSV
- Before/after compliance summary
- CAT I / CAT II / CAT III severity counts
- Markdown runbooks for failed controls
- Static HTML dashboard
- Read-only local validation checks
- Windows validation layer for safe command availability evidence

## Why It Exists

This lab showcases security compliance automation skills without exposing private work. It is suitable for early-career DevOps, cloud, platform engineering, security automation, GRC, and eDiscovery infrastructure roles.

## Quick Start

Run from PowerShell:

```powershell
cd .\scap-stig-compliance-lab
.\scripts\Invoke-ComplianceEngine.ps1
```

Outputs are written to:

```text
output/
```

Open `output/dashboard.html` in a browser for a polished, free portfolio dashboard with before/after metrics, workflow progression, generated artifacts, and a filterable remediation tracker.

## Demo Data

The files in `sample-data/` are synthetic SCAP-style XML files:

- `scan-before.xml`
- `scan-after.xml`

They use synthetic host aliases such as `lab-win-endpoint-01` and synthetic control IDs such as `SYN-AC-001`.

## Portfolio Summary

```text
Built a synthetic SCAP/STIG compliance automation lab that parses benchmark-style findings, prioritizes CAT I/CAT II risks, generates remediation trackers, and produces before/after compliance reports without exposing sensitive infrastructure data or proprietary product ideas.
```

For a fuller employer-facing write-up and Figma progression outline, see `CASE_STUDY.md`.

## Safe Boundaries

This project intentionally avoids:

- Real system names
- Real usernames
- IP addresses
- Domain names
- Client or employer data
- Private scan identifiers
- Founder/product ideas
- Production architecture
- Automated remediation that changes system settings

## Project Structure

```text
scap-stig-compliance-lab/
  README.md
  sample-data/
    scan-before.xml
    scan-after.xml
  scripts/
    Invoke-ComplianceEngine.ps1
    Invoke-ReadOnlyValidationChecks.ps1
  output/
```
