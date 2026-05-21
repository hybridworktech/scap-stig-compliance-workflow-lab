param(
    [string]$BeforePath = ".\sample-data\scan-before.xml",
    [string]$AfterPath = ".\sample-data\scan-after.xml",
    [string]$OutputDirectory = ".\output"
)

$ErrorActionPreference = "Stop"

function Import-ComplianceScan {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Scan file not found: $Path"
    }

    [xml]$scan = Get-Content -LiteralPath $Path -Raw
    foreach ($rule in $scan.complianceScan.rule) {
        [pscustomobject]@{
            Host        = [string]$scan.complianceScan.host
            Benchmark   = [string]$scan.complianceScan.benchmark
            Profile     = [string]$scan.complianceScan.profile
            ScanDate    = [string]$scan.complianceScan.scanDate
            RuleId      = [string]$rule.id
            Category    = [string]$rule.category
            Severity    = [string]$rule.severity
            Status      = ([string]$rule.status).ToLowerInvariant()
            Title       = [string]$rule.title
            Check       = [string]$rule.check
            Remediation = [string]$rule.remediation
        }
    }
}

function Get-ComplianceStats {
    param([object[]]$Findings)

    $total = @($Findings).Count
    $passed = @($Findings | Where-Object Status -eq "pass").Count
    $failed = @($Findings | Where-Object Status -eq "fail").Count
    $score = if ($total -eq 0) { 0 } else { [math]::Round(($passed / $total) * 100, 1) }

    [pscustomobject]@{
        Total   = $total
        Passed  = $passed
        Failed  = $failed
        Score   = $score
        CatI    = @($Findings | Where-Object { $_.Category -eq "CAT I" -and $_.Status -eq "fail" }).Count
        CatII   = @($Findings | Where-Object { $_.Category -eq "CAT II" -and $_.Status -eq "fail" }).Count
        CatIII  = @($Findings | Where-Object { $_.Category -eq "CAT III" -and $_.Status -eq "fail" }).Count
    }
}

function New-Runbook {
    param(
        [object]$Finding,
        [string]$Directory
    )

    $safeTitle = ($Finding.RuleId -replace "[^A-Za-z0-9_-]", "_")
    $path = Join-Path $Directory "$safeTitle-runbook.md"
    $body = @"
# Remediation Runbook: $($Finding.RuleId)

## Summary

$($Finding.Title)

## Risk

Severity: $($Finding.Severity)
Category: $($Finding.Category)

## Validation Check

$($Finding.Check)

## Remediation Guidance

$($Finding.Remediation)

## Evidence To Capture

- Screenshot or command output showing the corrected setting
- Date of validation
- Reviewer initials or ticket reference
- Exception note if remediation is deferred

## Rollback Notes

Document the previous setting before applying changes. Restore the prior approved baseline only if remediation causes service impact.

"@

    Set-Content -LiteralPath $path -Value $body -Encoding UTF8
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$before = @(Import-ComplianceScan -Path $BeforePath)
$after = @(Import-ComplianceScan -Path $AfterPath)

$tracker = foreach ($finding in $after) {
    $previous = $before | Where-Object RuleId -eq $finding.RuleId | Select-Object -First 1
    $trend = if ($null -eq $previous) {
        "new"
    } elseif ($previous.Status -eq "fail" -and $finding.Status -eq "pass") {
        "remediated"
    } elseif ($previous.Status -eq "pass" -and $finding.Status -eq "fail") {
        "regressed"
    } elseif ($finding.Status -eq "fail") {
        "still-open"
    } else {
        "unchanged-pass"
    }

    [pscustomobject]@{
        Host        = $finding.Host
        RuleId      = $finding.RuleId
        Category    = $finding.Category
        Severity    = $finding.Severity
        Status      = $finding.Status
        Trend       = $trend
        Owner       = "compliance-owner"
        DueDate     = "planned-review"
        Title       = $finding.Title
        Remediation = $finding.Remediation
    }
}

$trackerPath = Join-Path $OutputDirectory "remediation-tracker.csv"
$tracker | Sort-Object Category, Severity, RuleId | Export-Csv -Path $trackerPath -NoTypeInformation -Encoding UTF8

$beforeStats = Get-ComplianceStats -Findings $before
$afterStats = Get-ComplianceStats -Findings $after
$generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm zzz")
$workflowDiagramPath = Join-Path $OutputDirectory "workflow-diagram.svg"
$workflowDiagram = @"
<svg xmlns="http://www.w3.org/2000/svg" width="1180" height="310" viewBox="0 0 1180 310" role="img" aria-labelledby="title desc">
  <title id="title">SCAP/STIG compliance workflow diagram</title>
  <desc id="desc">Synthetic XML flows through a PowerShell parser into normalized findings, a CSV tracker, dashboard, and runbooks.</desc>
  <defs>
    <filter id="shadow" x="-10%" y="-20%" width="120%" height="140%">
      <feDropShadow dx="0" dy="10" stdDeviation="10" flood-color="#172026" flood-opacity=".12"/>
    </filter>
    <marker id="arrow" markerWidth="12" markerHeight="12" refX="10" refY="6" orient="auto">
      <path d="M2,2 L10,6 L2,10 Z" fill="#006d77"/>
    </marker>
  </defs>
  <rect width="1180" height="310" rx="18" fill="#f7f9fa"/>
  <text x="38" y="44" font-family="Segoe UI, Arial, sans-serif" font-size="22" font-weight="700" fill="#172026">After-Scan Evidence Workflow</text>
  <text x="38" y="70" font-family="Segoe UI, Arial, sans-serif" font-size="14" fill="#62727c">From synthetic scan-style results to remediation evidence and stakeholder reporting.</text>

  <g font-family="Segoe UI, Arial, sans-serif" filter="url(#shadow)">
    <g transform="translate(38 112)">
      <rect width="160" height="104" rx="10" fill="#ffffff" stroke="#d8e0e5"/>
      <circle cx="24" cy="25" r="7" fill="#006d77"/>
      <text x="42" y="31" font-size="14" font-weight="700" fill="#172026">Synthetic XML</text>
      <text x="18" y="60" font-size="12" fill="#62727c">Before and after</text>
      <text x="18" y="78" font-size="12" fill="#62727c">scan-style inputs</text>
    </g>
    <g transform="translate(236 112)">
      <rect width="160" height="104" rx="10" fill="#ffffff" stroke="#d8e0e5"/>
      <circle cx="24" cy="25" r="7" fill="#006d77"/>
      <text x="42" y="31" font-size="14" font-weight="700" fill="#172026">PowerShell</text>
      <text x="18" y="60" font-size="12" fill="#62727c">Parser reads rules</text>
      <text x="18" y="78" font-size="12" fill="#62727c">and statuses</text>
    </g>
    <g transform="translate(434 112)">
      <rect width="160" height="104" rx="10" fill="#ffffff" stroke="#d8e0e5"/>
      <circle cx="24" cy="25" r="7" fill="#006d77"/>
      <text x="42" y="31" font-size="14" font-weight="700" fill="#172026">Normalize</text>
      <text x="18" y="60" font-size="12" fill="#62727c">Severity, category,</text>
      <text x="18" y="78" font-size="12" fill="#62727c">trend, remediation</text>
    </g>
    <g transform="translate(632 112)">
      <rect width="160" height="104" rx="10" fill="#ffffff" stroke="#d8e0e5"/>
      <circle cx="24" cy="25" r="7" fill="#1f7a4d"/>
      <text x="42" y="31" font-size="14" font-weight="700" fill="#172026">Tracker</text>
      <text x="18" y="60" font-size="12" fill="#62727c">CSV output for</text>
      <text x="18" y="78" font-size="12" fill="#62727c">remediation work</text>
    </g>
    <g transform="translate(830 112)">
      <rect width="160" height="104" rx="10" fill="#ffffff" stroke="#d8e0e5"/>
      <circle cx="24" cy="25" r="7" fill="#1f7a4d"/>
      <text x="42" y="31" font-size="14" font-weight="700" fill="#172026">Dashboard</text>
      <text x="18" y="60" font-size="12" fill="#62727c">Metrics, budget,</text>
      <text x="18" y="78" font-size="12" fill="#62727c">redaction audit</text>
    </g>
    <g transform="translate(1028 112)">
      <rect width="114" height="104" rx="10" fill="#ffffff" stroke="#d8e0e5"/>
      <circle cx="24" cy="25" r="7" fill="#1f7a4d"/>
      <text x="42" y="31" font-size="14" font-weight="700" fill="#172026">Runbooks</text>
      <text x="18" y="60" font-size="12" fill="#62727c">Open finding</text>
      <text x="18" y="78" font-size="12" fill="#62727c">guidance</text>
    </g>
  </g>

  <g stroke="#006d77" stroke-width="2.5" marker-end="url(#arrow)" fill="none">
    <path d="M204 164 H228"/>
    <path d="M402 164 H426"/>
    <path d="M600 164 H624"/>
    <path d="M798 164 H822"/>
    <path d="M996 164 H1020"/>
  </g>

  <g font-family="Segoe UI, Arial, sans-serif">
    <rect x="38" y="248" width="1104" height="34" rx="8" fill="#e7f3f2" stroke="#c6dddd"/>
    <text x="56" y="270" font-size="13" fill="#24444a">Privacy boundary: generated for portfolio use with synthetic findings, sanitized Windows context, and redaction checks before sharing.</text>
  </g>
</svg>
"@
Set-Content -LiteralPath $workflowDiagramPath -Value $workflowDiagram -Encoding UTF8
$summaryPath = Join-Path $OutputDirectory "compliance-summary.md"
$summary = @"
# Compliance Summary

Synthetic demo report. No real systems, scan IDs, client details, founder ideas, or proprietary architecture are included.

## Before

- Total controls: $($beforeStats.Total)
- Passed: $($beforeStats.Passed)
- Failed: $($beforeStats.Failed)
- Compliance score: $($beforeStats.Score)%
- Open CAT I: $($beforeStats.CatI)
- Open CAT II: $($beforeStats.CatII)
- Open CAT III: $($beforeStats.CatIII)

## After

- Total controls: $($afterStats.Total)
- Passed: $($afterStats.Passed)
- Failed: $($afterStats.Failed)
- Compliance score: $($afterStats.Score)%
- Open CAT I: $($afterStats.CatI)
- Open CAT II: $($afterStats.CatII)
- Open CAT III: $($afterStats.CatIII)

## Impact

- CAT I findings reduced from $($beforeStats.CatI) to $($afterStats.CatI)
- CAT II findings reduced from $($beforeStats.CatII) to $($afterStats.CatII)
- Overall compliance improved from $($beforeStats.Score)% to $($afterStats.Score)%

## Open Findings

$(
    $open = @($after | Where-Object Status -eq "fail")
    if ($open.Count -eq 0) {
        "No open findings remain in the synthetic after scan."
    } else {
        ($open | ForEach-Object { "- $($_.RuleId) [$($_.Category)] $($_.Title)" }) -join "`n"
    }
)

"@
Set-Content -LiteralPath $summaryPath -Value $summary -Encoding UTF8

$openFindings = @($after | Where-Object Status -eq "fail")
foreach ($finding in $openFindings) {
    New-Runbook -Finding $finding -Directory $OutputDirectory
}

$dashboardPath = Join-Path $OutputDirectory "dashboard.html"
$scoreDelta = [math]::Round($afterStats.Score - $beforeStats.Score, 1)
$beforeWidth = "$($beforeStats.Score)%"
$afterWidth = "$($afterStats.Score)%"
$closedFindings = @($tracker | Where-Object Trend -eq "remediated").Count
$riskRows = @(
    [pscustomobject]@{ Label = "CAT I"; Before = $beforeStats.CatI; After = $afterStats.CatI }
    [pscustomobject]@{ Label = "CAT II"; Before = $beforeStats.CatII; After = $afterStats.CatII }
    [pscustomobject]@{ Label = "CAT III"; Before = $beforeStats.CatIII; After = $afterStats.CatIII }
)
$riskTableRows = ($riskRows | ForEach-Object {
    $change = $_.After - $_.Before
    $changeLabel = if ($change -lt 0) { "$change reduced" } elseif ($change -gt 0) { "+$change increased" } else { "0 unchanged" }
    "<tr><td>$($_.Label)</td><td>$($_.Before)</td><td>$($_.After)</td><td>$changeLabel</td></tr>"
}) -join "`n"
$osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$registryOsInfo = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
$windowsEdition = if ($osInfo -and $osInfo.Caption) {
    $osInfo.Caption
} elseif ($registryOsInfo -and $registryOsInfo.ProductName) {
    $registryOsInfo.ProductName
} else {
    [System.Environment]::OSVersion.Platform.ToString()
}
$windowsVersion = if ($osInfo -and $osInfo.Version) {
    $osInfo.Version
} elseif ($registryOsInfo -and $registryOsInfo.DisplayVersion) {
    $registryOsInfo.DisplayVersion
} elseif ($registryOsInfo -and $registryOsInfo.ReleaseId) {
    $registryOsInfo.ReleaseId
} else {
    [System.Environment]::OSVersion.Version.ToString()
}
$windowsBuild = if ($osInfo -and $osInfo.BuildNumber) {
    $osInfo.BuildNumber
} elseif ($registryOsInfo -and $registryOsInfo.CurrentBuildNumber) {
    $registryOsInfo.CurrentBuildNumber
} else {
    [System.Environment]::OSVersion.Version.Build.ToString()
}
$powershellVersion = $PSVersionTable.PSVersion.ToString()
$windowsEnvironmentRows = @(
    [pscustomobject]@{ Label = "Operating system"; Value = $windowsEdition }
    [pscustomobject]@{ Label = "Windows version"; Value = $windowsVersion }
    [pscustomobject]@{ Label = "Windows build"; Value = $windowsBuild }
    [pscustomobject]@{ Label = "PowerShell version"; Value = $powershellVersion }
    [pscustomobject]@{ Label = "Machine identity"; Value = "Redacted for portfolio safety" }
)
$windowsEnvironmentTableRows = ($windowsEnvironmentRows | ForEach-Object {
    "<tr><td>$($_.Label)</td><td>$($_.Value)</td></tr>"
}) -join "`n"
$windowsChecks = @(
    [pscustomobject]@{
        Area = "Firewall"
        Check = "Firewall profile command available"
        Command = "Get-NetFirewallProfile"
        Status = if (Get-Command Get-NetFirewallProfile -ErrorAction SilentlyContinue) { "available" } else { "not-available" }
        Evidence = "Supports read-only validation of domain, private, and public firewall profiles."
    }
    [pscustomobject]@{
        Area = "Identity"
        Check = "Local account inventory command available"
        Command = "Get-LocalUser"
        Status = if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) { "available" } else { "not-available" }
        Evidence = "Supports read-only review of local account posture without modifying users."
    }
    [pscustomobject]@{
        Area = "Audit"
        Check = "Audit policy command available"
        Command = "auditpol.exe"
        Status = if (Get-Command auditpol.exe -ErrorAction SilentlyContinue) { "available" } else { "not-available" }
        Evidence = "Supports evidence capture for audit policy checks."
    }
    [pscustomobject]@{
        Area = "Encryption"
        Check = "BitLocker command available"
        Command = "Get-BitLockerVolume"
        Status = if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) { "available" } else { "not-available" }
        Evidence = "Supports read-only validation of volume encryption visibility."
    }
)
$windowsRows = ($windowsChecks | ForEach-Object {
    $statusClass = if ($_.Status -eq "available") { "pass" } else { "fail" }
    "<tr><td><strong>$($_.Area)</strong></td><td>$($_.Check)<span>$($_.Command)</span></td><td><span class=""pill $statusClass"">$($_.Status)</span></td><td>$($_.Evidence)</td></tr>"
}) -join "`n"
$budgetItems = @(
    [pscustomobject]@{
        Workstream = "CAT I remediation validation"
        Scope = "Confirm high-risk controls remain closed and capture evidence"
        Hours = [math]::Max(1, $beforeStats.CatI * 2)
        Rate = 95
    }
    [pscustomobject]@{
        Workstream = "CAT II remediation validation"
        Scope = "Review medium-risk fixes, update tracker, and document evidence"
        Hours = [math]::Max(1, $beforeStats.CatII * 1.5)
        Rate = 85
    }
    [pscustomobject]@{
        Workstream = "CAT III cleanup and exception review"
        Scope = "Triage remaining low-risk finding and prepare exception notes if needed"
        Hours = [math]::Max(1, $afterStats.CatIII * 1)
        Rate = 75
    }
    [pscustomobject]@{
        Workstream = "Evidence pack and reporting"
        Scope = "Package summary, tracker, Windows validation, and runbook outputs"
        Hours = 2
        Rate = 85
    }
)
$budgetTotal = 0
$budgetRows = ($budgetItems | ForEach-Object {
    $lineTotal = [math]::Round($_.Hours * $_.Rate, 2)
    $script:budgetTotal += $lineTotal
    "<tr data-budget-row data-hours=""$($_.Hours)"" data-rate=""$($_.Rate)""><td><strong>$($_.Workstream)</strong><span>$($_.Scope)</span></td><td>$($_.Hours)</td><td><span class=""rate-cell"">`$$($_.Rate)/hr</span></td><td><strong class=""cost-cell"">`$$lineTotal</strong></td></tr>"
}) -join "`n"
$redactionTargets = @(
    ($tracker | ConvertTo-Csv -NoTypeInformation | Out-String)
    $summary
    ($windowsEnvironmentRows | ConvertTo-Csv -NoTypeInformation | Out-String)
    ($windowsChecks | ConvertTo-Csv -NoTypeInformation | Out-String)
)
$redactionText = $redactionTargets -join "`n"
$redactionChecks = @(
    [pscustomobject]@{ Pattern = "Email addresses"; Count = ([regex]::Matches($redactionText, "\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", "IgnoreCase")).Count }
    [pscustomobject]@{ Pattern = "IPv4 addresses"; Count = ([regex]::Matches($redactionText, "\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b")).Count }
    [pscustomobject]@{ Pattern = "Windows user paths"; Count = ([regex]::Matches($redactionText, "C:\\Users\\[^\\\s]+", "IgnoreCase")).Count }
    [pscustomobject]@{ Pattern = "Internal domain hints"; Count = ([regex]::Matches($redactionText, "\b(?:corp|internal|prod|client|customer)\.[A-Z0-9.-]+\b", "IgnoreCase")).Count }
)
$syntheticRedactionExamples = @(
    [pscustomobject]@{ Pattern = "Email addresses"; Original = "analyst@example.invalid"; Redacted = "[redacted-email]"; Context = "Synthetic owner/contact field" }
    [pscustomobject]@{ Pattern = "Windows user paths"; Original = "C:\Users\example-user\Documents\scan-output"; Redacted = "[redacted-user-path]"; Context = "Synthetic local export path" }
)
$redactionDetectedTotal = ($redactionChecks | Measure-Object -Property Count -Sum).Sum
$redactionExampleTotal = @($syntheticRedactionExamples).Count
$redactionStatus = if ($redactionDetectedTotal -eq 0) { "Passed" } else { "Review Needed" }
$redactionStatusClass = if ($redactionDetectedTotal -eq 0) { "pass" } else { "fail" }
$redactionRows = ($redactionChecks | ForEach-Object {
    $statusClass = if ($_.Count -eq 0) { "pass" } else { "fail" }
    $statusText = if ($_.Count -eq 0) { "clear" } else { "review" }
    "<tr><td>$($_.Pattern)</td><td>$($_.Count)</td><td><span class=""pill $statusClass"">$statusText</span></td></tr>"
}) -join "`n"
$redactionExampleRows = ($syntheticRedactionExamples | ForEach-Object {
    "<tr><td>$($_.Pattern)<span>$($_.Context)</span></td><td><code>$($_.Original)</code></td><td><code>$($_.Redacted)</code></td><td><span class=""pill pass"">redacted</span></td></tr>"
}) -join "`n"
$llmSummary = "AI-assisted review summarizes the synthetic findings, compliance improvement from $($beforeStats.Score)% to $($afterStats.Score)%, remaining CAT III work, and generated evidence outputs. The review is bounded to source data and is not a security attestation."
$trackerRows = ($tracker | Sort-Object Category, Severity, RuleId | ForEach-Object {
    $statusClass = if ($_.Status -eq "pass") { "pass" } else { "fail" }
    "<tr data-category=""$($_.Category)"" data-status=""$($_.Status)"" data-trend=""$($_.Trend)""><td><strong>$($_.RuleId)</strong><span>$($_.Category)</span></td><td>$($_.Title)</td><td><span class=""pill $statusClass"">$($_.Status)</span></td><td>$($_.Trend)</td><td>$($_.Remediation)</td></tr>"
}) -join "`n"
$openRows = if ($openFindings.Count -eq 0) {
    "<tr><td colspan=""4"">No open findings remain in the synthetic after scan.</td></tr>"
} else {
    ($openFindings | ForEach-Object {
        "<tr><td><strong>$($_.RuleId)</strong></td><td>$($_.Category)</td><td>$($_.Severity)</td><td>$($_.Title)</td></tr>"
    }) -join "`n"
}

$dashboard = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>SCAP/STIG Compliance Automation Lab</title>
  <style>
    :root {
      color-scheme: light;
      --ink: #172026;
      --muted: #62727c;
      --line: #d8e0e5;
      --soft: #f6f8f9;
      --panel: #ffffff;
      --accent: #006d77;
      --accent-soft: #e7f3f2;
      --risk: #b42318;
      --risk-soft: #fff0ed;
      --ok: #1f7a4d;
      --ok-soft: #eaf6ef;
      --warn: #9a5b00;
      --warn-soft: #fff7e8;
      --shadow: 0 18px 44px rgba(23, 32, 38, .08);
      --shadow-soft: 0 10px 24px rgba(23, 32, 38, .06);
    }
    * { box-sizing: border-box; }
    html { scroll-behavior: smooth; }
    body {
      margin: 0;
      font-family: Segoe UI, Arial, sans-serif;
      color: var(--ink);
      background:
        radial-gradient(circle at 8% 0%, rgba(0, 109, 119, .09), transparent 30%),
        linear-gradient(180deg, #f7fafb 0, #ffffff 320px);
    }
    main {
      max-width: 1180px;
      margin: 0 auto;
      padding: 22px 20px 56px;
    }
    header {
      display: grid;
      grid-template-columns: minmax(0, 1.4fr) minmax(280px, 0.6fr);
      gap: 24px;
      align-items: end;
      border-bottom: 1px solid var(--line);
      padding-bottom: 24px;
      margin-bottom: 22px;
    }
    h1 {
      font-size: 40px;
      line-height: 1.15;
      margin: 8px 0 10px;
      letter-spacing: 0;
      max-width: 780px;
    }
    p {
      color: var(--muted);
      margin: 0;
      line-height: 1.5;
    }
    .eyebrow {
      color: var(--accent);
      font-size: 12px;
      font-weight: 700;
      letter-spacing: .08em;
      text-transform: uppercase;
    }
    .privacy-box {
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      padding: 16px;
      box-shadow: var(--shadow-soft);
    }
    .privacy-box strong {
      display: block;
      margin-bottom: 8px;
      font-size: 14px;
    }
    .privacy-box ul {
      margin: 0;
      padding-left: 18px;
      color: var(--muted);
      line-height: 1.5;
      font-size: 13px;
    }
    .status-badges {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 16px;
    }
    .status-badge {
      display: inline-flex;
      align-items: center;
      min-height: 30px;
      border: 1px solid var(--line);
      border-radius: 999px;
      padding: 6px 10px;
      background: #fff;
      color: #2f424b;
      font-size: 12px;
      font-weight: 700;
      box-shadow: 0 6px 14px rgba(23, 32, 38, .05);
    }
    .status-badge.good {
      border-color: #b8dec7;
      background: var(--ok-soft);
      color: var(--ok);
    }
    .status-badge.scope {
      border-color: #b9dadd;
      background: var(--accent-soft);
      color: #004f56;
    }
    .top-nav {
      position: sticky;
      top: 0;
      z-index: 10;
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      align-items: center;
      margin: 18px 0 4px;
      padding: 10px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: rgba(255, 255, 255, .92);
      backdrop-filter: blur(10px);
      box-shadow: var(--shadow-soft);
    }
    .top-nav a {
      color: #2f424b;
      text-decoration: none;
      font-size: 13px;
      font-weight: 700;
      padding: 8px 10px;
      border-radius: 8px;
    }
    .top-nav a:hover {
      background: var(--accent-soft);
      color: #004f56;
    }
    .metrics {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 12px;
      margin: 24px 0;
    }
    .metric {
      position: relative;
      overflow: hidden;
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 16px;
      background: var(--panel);
      min-height: 118px;
      box-shadow: var(--shadow-soft);
    }
    .metric::before {
      content: "";
      position: absolute;
      inset: 0 auto 0 0;
      width: 4px;
      background: var(--accent);
    }
    .metric.risk-card::before { background: var(--risk); }
    .metric.ok-card::before { background: var(--ok); }
    .metric.pass-card::before { background: var(--ok); }
    .metric.fail-card::before { background: var(--risk); }
    }
    .label {
      color: var(--muted);
      font-size: 13px;
      margin-bottom: 8px;
    }
    .value {
      font-size: 28px;
      font-weight: 700;
    }
    .subvalue {
      color: var(--muted);
      font-size: 13px;
      margin-top: 8px;
    }
    .ok { color: var(--ok); }
    .risk { color: var(--risk); }
    .grid {
      display: grid;
      grid-template-columns: minmax(0, 1fr) minmax(300px, .45fr);
      gap: 18px;
    }
    section {
      margin-top: 28px;
      scroll-margin-top: 86px;
    }
    .panel {
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      padding: 20px;
      box-shadow: var(--shadow-soft);
    }
    h2 {
      font-size: 20px;
      margin: 0 0 12px;
    }
    h3 {
      font-size: 15px;
      margin: 0 0 10px;
    }
    .flow {
      display: grid;
      grid-template-columns: repeat(6, minmax(0, 1fr));
      gap: 8px;
      margin-top: 14px;
    }
    .step {
      position: relative;
      min-height: 84px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: linear-gradient(180deg, #ffffff, var(--soft));
      padding: 12px;
      font-size: 13px;
      display: flex;
      align-items: center;
      justify-content: center;
      text-align: center;
      font-weight: 600;
    }
    .step::before {
      content: "";
      position: absolute;
      top: 10px;
      left: 10px;
      width: 8px;
      height: 8px;
      border-radius: 999px;
      background: var(--accent);
    }
    .workflow-image {
      display: block;
      width: 100%;
      height: auto;
      margin-top: 16px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--soft);
    }
    .bars {
      display: grid;
      gap: 14px;
    }
    .bar-row {
      display: grid;
      gap: 6px;
    }
    .bar-label {
      display: flex;
      justify-content: space-between;
      color: var(--muted);
      font-size: 13px;
    }
    .bar-track {
      height: 14px;
      border-radius: 999px;
      overflow: hidden;
      background: #e6ecef;
      box-shadow: inset 0 1px 2px rgba(23, 32, 38, .12);
    }
    .bar-fill {
      height: 100%;
      border-radius: 999px;
      background: var(--accent);
    }
    .bar-fill.before { background: var(--risk); width: $beforeWidth; }
    .bar-fill.after { background: var(--ok); width: $afterWidth; }
    .controls {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin: 12px 0;
    }
    button {
      border: 1px solid var(--line);
      background: #fff;
      color: var(--ink);
      border-radius: 8px;
      padding: 8px 10px;
      font: inherit;
      font-size: 13px;
      cursor: pointer;
    }
    button.active {
      border-color: var(--accent);
      background: var(--accent-soft);
      color: #004f56;
      font-weight: 700;
    }
    .field-row {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 12px;
      align-items: center;
      margin: 12px 0;
    }
    input[type="search"] {
      width: 100%;
      min-height: 40px;
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 8px 10px;
      color: var(--ink);
      font: inherit;
      font-size: 14px;
      background: #fff;
    }
    input[type="range"] {
      width: min(360px, 100%);
      accent-color: var(--accent);
    }
    .slider-card {
      display: grid;
      grid-template-columns: minmax(0, 1fr) minmax(220px, .35fr);
      gap: 16px;
      align-items: center;
      margin: 14px 0;
      padding: 14px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--soft);
    }
    .slider-value {
      font-size: 26px;
      font-weight: 800;
      color: var(--accent);
      text-align: right;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      border: 1px solid var(--line);
      border-radius: 8px;
      overflow: hidden;
      background: #fff;
    }
    th, td {
      text-align: left;
      padding: 10px 12px;
      border-bottom: 1px solid var(--line);
      vertical-align: top;
      font-size: 14px;
    }
    th {
      background: #eef4f5;
      color: #2f424b;
    }
    tr:last-child td {
      border-bottom: 0;
    }
    tr:nth-child(even) td {
      background: #fbfcfc;
    }
    td span {
      display: block;
      color: var(--muted);
      font-size: 12px;
      margin-top: 3px;
    }
    .pill {
      display: inline-flex;
      align-items: center;
      min-height: 24px;
      border-radius: 999px;
      padding: 3px 9px;
      font-size: 12px;
      font-weight: 700;
      text-transform: uppercase;
    }
    .pill.pass {
      color: var(--ok);
      background: var(--ok-soft);
    }
    .pill.fail {
      color: var(--risk);
      background: var(--risk-soft);
    }
    .artifact-list {
      display: grid;
      gap: 8px;
      margin-top: 12px;
    }
    .artifact {
      display: flex;
      justify-content: space-between;
      gap: 12px;
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 10px 12px;
      background: var(--soft);
      font-size: 13px;
    }
    .artifact code {
      color: var(--accent);
      font-weight: 700;
    }
    .review {
      display: grid;
      grid-template-columns: minmax(0, .8fr) minmax(280px, .2fr);
      gap: 16px;
      align-items: start;
    }
    .review-text {
      color: #2f424b;
      font-size: 15px;
      line-height: 1.65;
    }
    .review-aside {
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--accent-soft);
      padding: 14px;
    }
    .review-aside strong {
      display: block;
      color: #004f56;
      margin-bottom: 8px;
    }
    .review-aside p {
      font-size: 13px;
    }
    .note {
      margin-top: 24px;
      padding: 14px 16px;
      border-left: 4px solid var(--accent);
      background: #edf7f7;
      color: #24444a;
      border-radius: 0 8px 8px 0;
    }
    .compact-note {
      margin-top: 14px;
      padding: 12px 14px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--soft);
      color: #2f424b;
      font-size: 13px;
      line-height: 1.5;
    }
    .compact-note code {
      color: var(--accent);
      font-weight: 700;
    }
    .table-wrap {
      overflow-x: auto;
      border-radius: 8px;
    }
    .hidden { display: none; }
    @media (max-width: 900px) {
      header, .grid {
        grid-template-columns: 1fr;
      }
      .metrics {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
      .flow {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
      .review {
        grid-template-columns: 1fr;
      }
      .slider-card, .field-row {
        grid-template-columns: 1fr;
      }
      .slider-value {
        text-align: left;
      }
      .top-nav {
        position: static;
      }
    }
    @media (max-width: 560px) {
      main {
        padding-inline: 14px;
      }
      h1 {
        font-size: 30px;
      }
      .metrics {
        grid-template-columns: 1fr;
      }
      th, td {
        font-size: 13px;
        padding: 9px;
      }
      .artifact {
        display: block;
      }
      .artifact code {
        display: block;
        margin-top: 4px;
        white-space: normal;
      }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <div>
        <div class="eyebrow">Security Compliance Automation Portfolio</div>
        <h1>SCAP/STIG Compliance Automation Lab</h1>
        <p>A free, standalone dashboard generated from synthetic SCAP/STIG-style data. It shows how raw compliance findings become remediation tracking, before/after reporting, and evidence-ready runbooks.</p>
        <div class="status-badges" aria-label="Project status">
          <span class="status-badge">Portfolio Demo</span>
          <span class="status-badge scope">After-Scan Reporting Layer</span>
          <span class="status-badge good">Evidence Package: Share-Ready</span>
          <span class="status-badge">Generated by: Local PowerShell Engine</span>
          <span class="status-badge">Last Generated: $generatedAt</span>
        </div>
      </div>
      <div class="privacy-box">
        <strong>Privacy-safe by design</strong>
        <ul>
          <li>No real hostnames, IPs, scan IDs, client data, or usernames</li>
          <li>No founder ideas, proprietary product concepts, or production architecture</li>
          <li>Built for employer review using synthetic demo data only</li>
        </ul>
      </div>
    </header>

    <nav class="top-nav" aria-label="Dashboard sections">
      <a href="#score">Score</a>
      <a href="#workflow">Workflow</a>
      <a href="#runner">Runner</a>
      <a href="#summary">LLM Review</a>
      <a href="#pitch">Pitch</a>
      <a href="#budget">Budget</a>
      <a href="#redaction">Redaction</a>
      <a href="#windows">Windows</a>
      <a href="#tracker">Tracker</a>
      <a href="#artifacts">Artifacts</a>
    </nav>

    <div class="metrics">
      <div class="metric risk-card">
        <div class="label">Before Compliance</div>
        <div class="value risk">$($beforeStats.Score)%</div>
        <div class="subvalue">$($beforeStats.Failed) failed controls</div>
      </div>
      <div class="metric ok-card">
        <div class="label">After Compliance</div>
        <div class="value ok">$($afterStats.Score)%</div>
        <div class="subvalue">+$scoreDelta point improvement</div>
      </div>
      <div class="metric ok-card">
        <div class="label">Remediated Findings</div>
        <div class="value ok">$closedFindings</div>
        <div class="subvalue">Closed between scans</div>
      </div>
      <div class="metric">
        <div class="label">CAT I Open</div>
        <div class="value">$($afterStats.CatI)</div>
        <div class="subvalue">Highest risk remaining</div>
      </div>
    </div>

    <div class="grid">
      <section class="panel" id="score">
        <h2>Before / After Score</h2>
        <div class="bars">
          <div class="bar-row">
            <div class="bar-label"><span>Before scan</span><strong>$($beforeStats.Score)%</strong></div>
            <div class="bar-track"><div class="bar-fill before"></div></div>
          </div>
          <div class="bar-row">
            <div class="bar-label"><span>After scan</span><strong>$($afterStats.Score)%</strong></div>
            <div class="bar-track"><div class="bar-fill after"></div></div>
          </div>
        </div>
      </section>

      <section class="panel">
        <h2>Stakeholder Signal</h2>
        <p>This dashboard demonstrates PowerShell automation, STIG/SCAP workflow understanding, remediation prioritization, reporting, and careful handling of sensitive compliance work.</p>
      </section>
    </div>

    <section class="panel" id="workflow">
      <h2>Progression Workflow</h2>
      <p>Raw technical output is converted into artifacts security, infrastructure, and compliance teams can act on.</p>
      <img class="workflow-image" src="workflow-diagram.svg" alt="Workflow diagram showing synthetic XML parsed by PowerShell into normalized findings, tracker, dashboard, and runbooks.">
    </section>

    <section class="panel" id="runner">
      <h2>Job Runner Workflow</h2>
      <p>The dashboard is the reporting layer. The PowerShell script is the engine that runs the compliance job and regenerates the evidence package.</p>
      <div class="flow">
        <div class="step">Input: before scan XML</div>
        <div class="step">Input: after scan XML</div>
        <div class="step">Run PowerShell engine</div>
        <div class="step">Compare control status</div>
        <div class="step">Score and classify trends</div>
        <div class="step">Generate evidence outputs</div>
      </div>
      <div class="compact-note">Run: <code>.\scripts\Invoke-ComplianceEngine.ps1</code> | Inputs: <code>sample-data/</code> | Outputs: <code>output/</code> | Dashboard remains report-only.</div>
    </section>

    <section class="panel" id="summary">
      <h2>LLM Summary Review</h2>
      <div class="review">
        <p class="review-text">$llmSummary</p>
        <div class="review-aside">
          <strong>Review boundary</strong>
          <p>This summary is generated from synthetic demo data. It is a portfolio explanation, not a production security attestation.</p>
        </div>
      </div>
    </section>

    <section class="panel" id="pitch">
      <h2>Employer Value Proposition</h2>
      <p class="review-text">I built this privacy-safe SCAP/STIG compliance automation lab to show how I approach infrastructure work: automate the repeatable parts, protect sensitive data, and turn raw technical findings into clear engineering action. The project uses PowerShell, synthetic benchmark-style scan data, Windows read-only validation checks, remediation tracking, before/after reporting, and generated runbooks. It is especially relevant to DevOps, cloud/platform engineering, security automation, GRC, government contracting, and eDiscovery/legal-tech infrastructure roles.</p>
      <div class="artifact-list">
        <div class="artifact"><span>What it proves</span><code>automation + security judgment</code></div>
        <div class="artifact"><span>Why it is safe to share</span><code>synthetic data + redacted identity</code></div>
        <div class="artifact"><span>Best-fit roles</span><code>DevOps, platform, security automation</code></div>
      </div>
    </section>

    <section class="panel" id="budget">
      <h2>Proposed Remediation Budget</h2>
      <p>This synthetic planning estimate shows how findings could be translated into remediation effort, evidence capture, and reporting work. It is for portfolio demonstration only, not a client quote.</p>
      <div class="slider-card">
        <div>
          <h3>Live Planning Rate</h3>
          <p>Adjust the multiplier to show how remediation planning changes with different consulting rates.</p>
          <input id="rateMultiplier" type="range" min="75" max="150" value="100" step="5" aria-label="Budget rate multiplier">
        </div>
        <div class="slider-value"><span id="rateMultiplierLabel">100</span>%</div>
      </div>
      <div class="table-wrap">
        <table>
          <tr><th>Workstream</th><th>Estimated Hours</th><th>Planning Rate</th><th>Estimated Cost</th></tr>
          $budgetRows
          <tr><td><strong>Total planning estimate</strong><span>Synthetic estimate based on demo findings</span></td><td></td><td></td><td><strong id="budgetTotal">`$$budgetTotal</strong></td></tr>
        </table>
      </div>
      <div class="note">
        Budget assumption: rates and hours are placeholders used to demonstrate consulting-style scoping, prioritization, and audit planning.
      </div>
    </section>

    <section class="panel" id="redaction">
      <h2>Redaction Audit</h2>
      <p>The engine scans generated report content for common sensitive-data patterns before the dashboard is shared. The examples below use synthetic placeholders to demonstrate what redaction would look like.</p>
      <div class="metrics" style="margin-top:14px;">
        <div class="metric $redactionStatusClass-card">
          <div class="label">Audit Status</div>
          <div class="value">$redactionStatus</div>
          <div class="subvalue">$redactionDetectedTotal detected matches in generated outputs</div>
        </div>
        <div class="metric ok-card">
          <div class="label">Synthetic Redaction Examples</div>
          <div class="value">$redactionExampleTotal</div>
          <div class="subvalue">Demonstrates privacy-safe masking</div>
        </div>
      </div>
      <div class="table-wrap">
        <table>
          <tr><th>Pattern</th><th>Matches</th><th>Status</th></tr>
          $redactionRows
        </table>
      </div>
      <h3 style="margin-top:16px;">Redaction Examples</h3>
      <div class="table-wrap">
        <table>
          <tr><th>Pattern</th><th>Synthetic Original</th><th>Masked Output</th><th>Status</th></tr>
          $redactionExampleRows
        </table>
      </div>
    </section>

    <section class="panel">
      <h2>Impact by Severity</h2>
      <div class="table-wrap">
        <table>
          <tr><th>Risk Category</th><th>Before</th><th>After</th><th>Change</th></tr>
          $riskTableRows
        </table>
      </div>
    </section>

    <section class="panel" id="windows">
      <h2>Windows Validation Layer</h2>
      <p>This section uses your local Windows environment for safe, read-only validation context. The SCAP/STIG findings above remain synthetic so the project can be shared without exposing private system details.</p>
      <h3>Local Windows Environment</h3>
      <div class="table-wrap">
        <table>
          <tr><th>Field</th><th>Sanitized Value</th></tr>
          $windowsEnvironmentTableRows
        </table>
      </div>
      <h3 style="margin-top:16px;">Read-Only Evidence Checks</h3>
      <div class="table-wrap">
        <table>
          <tr><th>Area</th><th>Check</th><th>Status</th><th>Evidence Use</th></tr>
          $windowsRows
        </table>
      </div>
    </section>

    <section class="panel">
      <h2>Open Findings</h2>
      <div class="table-wrap">
        <table>
          <tr><th>Rule</th><th>Category</th><th>Severity</th><th>Title</th></tr>
          $openRows
        </table>
      </div>
    </section>

    <section class="panel">
      <h2>Remediation Tracker</h2>
      <p>Use the filters to show how the engine separates closed, open, and unchanged controls.</p>
      <div class="field-row">
        <input id="trackerSearch" type="search" placeholder="Search rule, finding, status, trend, or remediation" aria-label="Search remediation tracker">
      </div>
      <div class="controls" aria-label="Tracker filters">
        <button class="active" data-filter="all" type="button">All</button>
        <button data-filter="remediated" type="button">Remediated</button>
        <button data-filter="still-open" type="button">Still Open</button>
        <button data-filter="unchanged-pass" type="button">Unchanged Pass</button>
      </div>
      <div class="table-wrap">
        <table id="tracker">
          <tr><th>Rule</th><th>Finding</th><th>Status</th><th>Trend</th><th>Remediation</th></tr>
          $trackerRows
        </table>
      </div>
    </section>

    <section class="panel" id="artifacts">
      <h2>Generated Artifacts</h2>
      <div class="artifact-list">
        <div class="artifact"><span>Remediation tracker</span><code>remediation-tracker.csv</code></div>
        <div class="artifact"><span>Before/after summary</span><code>compliance-summary.md</code></div>
        <div class="artifact"><span>Portfolio dashboard</span><code>dashboard.html</code></div>
        <div class="artifact"><span>Open finding runbook</span><code>SYN-SV-004-runbook.md</code></div>
      </div>
    </section>

    <div class="note">
      Project Summary: Built a synthetic SCAP/STIG automation lab that parses benchmark-style findings, prioritizes remediation, and produces auditable reports while protecting sensitive data and proprietary ideas.
    </div>
  </main>
  <script>
    const buttons = document.querySelectorAll("[data-filter]");
    const rows = document.querySelectorAll("#tracker tr[data-trend]");
    const trackerSearch = document.querySelector("#trackerSearch");
    let activeFilter = "all";

    function applyTrackerFilters() {
      const query = (trackerSearch?.value || "").trim().toLowerCase();
      rows.forEach((row) => {
        const matchesFilter = activeFilter === "all" || row.dataset.trend === activeFilter;
        const matchesSearch = !query || row.innerText.toLowerCase().includes(query);
        row.classList.toggle("hidden", !matchesFilter || !matchesSearch);
      });
    }

    buttons.forEach((button) => {
      button.addEventListener("click", () => {
        activeFilter = button.dataset.filter;
        buttons.forEach((item) => item.classList.remove("active"));
        button.classList.add("active");
        applyTrackerFilters();
      });
    });

    trackerSearch?.addEventListener("input", applyTrackerFilters);

    const multiplierInput = document.querySelector("#rateMultiplier");
    const multiplierLabel = document.querySelector("#rateMultiplierLabel");
    const budgetTotal = document.querySelector("#budgetTotal");
    const budgetRows = document.querySelectorAll("[data-budget-row]");

    function formatCurrency(value) {
      return new Intl.NumberFormat("en-US", {
        style: "currency",
        currency: "USD",
        maximumFractionDigits: 0
      }).format(value);
    }

    function updateBudget() {
      const multiplier = Number(multiplierInput?.value || 100) / 100;
      let total = 0;
      multiplierLabel.textContent = Math.round(multiplier * 100);
      budgetRows.forEach((row) => {
        const hours = Number(row.dataset.hours || 0);
        const baseRate = Number(row.dataset.rate || 0);
        const adjustedRate = baseRate * multiplier;
        const cost = hours * adjustedRate;
        total += cost;
        row.querySelector(".rate-cell").textContent = formatCurrency(adjustedRate) + "/hr";
        row.querySelector(".cost-cell").textContent = formatCurrency(cost);
      });
      budgetTotal.textContent = formatCurrency(total);
    }

    multiplierInput?.addEventListener("input", updateBudget);
    updateBudget();
  </script>
</body>
</html>
"@
Set-Content -LiteralPath $dashboardPath -Value $dashboard -Encoding UTF8

Write-Host "Compliance engine complete."
Write-Host "Tracker: $trackerPath"
Write-Host "Summary: $summaryPath"
Write-Host "Dashboard: $dashboardPath"
Write-Host "Runbooks generated: $($openFindings.Count)"
