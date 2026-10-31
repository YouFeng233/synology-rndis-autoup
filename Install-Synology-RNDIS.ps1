# Requires Windows PowerShell 5.1+ and Windows OpenSSH Client.
$ErrorActionPreference = 'Stop'
try {
    $sshCommand = Get-Command ssh.exe -ErrorAction Stop
    $server = (Read-Host 'NAS SSH address (example: 192.168.1.100; no port)').Trim()
    if ($server -notmatch '^[A-Za-z0-9][A-Za-z0-9.:-]*$') { throw 'Invalid host address.' }
    $portText = (Read-Host 'SSH port [22]').Trim()
    if (-not $portText) { $portText = '22' }
    $port = 0
    if (-not [int]::TryParse($portText, [ref]$port) -or $port -lt 1 -or $port -gt 65535) { throw 'Invalid port.' }
    $login = (Read-Host 'SSH username').Trim()
    if (-not $login) { throw 'Username is required.' }
    if ($login -notmatch '^[A-Za-z0-9_][A-Za-z0-9_.-]*$') { throw 'Invalid username.' }
    $scriptPath = Join-Path $PSScriptRoot 'install-rndis-remote.sh'
    $remoteScript = [IO.File]::ReadAllText($scriptPath).Replace("`r`n", "`n")
    $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteScript))
    Write-Host 'CPU/platform/DSM/kernel checks run before installation.'
    Write-Host 'SSH will request your password; sudo may request it again. Passwords are not saved.'
    Write-Host 'On first connection, verify the server host-key fingerprint before accepting.'
    $remoteCommand = 'umask 077; command -v base64 >/dev/null || exit 1; f=$(mktemp /tmp/rndis-launch.XXXXXX) || exit 1; printf %s PAYLOAD | base64 -d > $f || exit 1; /bin/sh $f; r=$?; rm -f $f; exit $r'
    $remoteCommand = $remoteCommand.Replace('PAYLOAD', $payload)
    & $sshCommand.Source -t -p $port -o StrictHostKeyChecking=ask -o ConnectTimeout=15 "$login@$server" $remoteCommand
    if ($LASTEXITCODE -ne 0) { throw "Remote operation failed (exit $LASTEXITCODE). Read the output above." }
    Write-Host 'Completed. Review the remote output for interface status.'
} catch {
    Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

