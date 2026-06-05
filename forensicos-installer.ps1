#Requires -RunAsAdministrator

# PS Menu
# https://github.com/Sebazzz/PSMenu
# -------
function Format-MenuItem(
    [Parameter(Mandatory)] $MenuItem, 
    [Switch] $MultiSelect, 
    [Parameter(Mandatory)][bool] $IsItemSelected, 
    [Parameter(Mandatory)][bool] $IsItemFocused) {

    $SelectionPrefix = '    '
    $FocusPrefix = '  '
    $ItemText = ' -------------------------- '

    if ($(Test-MenuSeparator $MenuItem) -ne $true) {
        if ($MultiSelect) {
            $SelectionPrefix = if ($IsItemSelected) { '[x] ' } else { '[ ] ' }
        }

        $FocusPrefix = if ($IsItemFocused) { '> ' } else { '  ' }
        $ItemText = $MenuItem.ToString()
    }

    $WindowWidth = (Get-Host).UI.RawUI.WindowSize.Width

    $Text = "{0}{1}{2}" -f $FocusPrefix, $SelectionPrefix, $ItemText
    if ($WindowWidth - ($Text.Length + 2) -gt 0) {
        $Text = $Text.PadRight($WindowWidth - ($Text.Length + 2), ' ')
    }
    
    Return $Text
}

function Format-MenuItemDefault($MenuItem) {
    Return $MenuItem.ToString()
}

function Get-CalculatedPageIndexNumber(
    [Parameter(Mandatory, Position = 0)][Array] $MenuItems,
    [Parameter(Position = 1)][int]$MenuPosition,
    [Switch]$TopIndex,
    [Switch]$ItemCount,
    [Switch]$BottomIndex
) {
    $WindowHeight = Get-ConsoleHeight

    $TopIndexNumber = 0;
    $MenuItemCount = $MenuItems.Count

    if ($MenuItemCount -gt $WindowHeight) {
        $MenuItemCount = $WindowHeight;
        if ($MenuPosition -gt $MenuItemCount) {
            $TopIndexNumber = $MenuPosition - $MenuItemCount;
        }
    }

    if ($TopIndex) {
        Return $TopIndexNumber
    }

    if ($ItemCount) {
        Return $MenuItemCount
    }

    if ($BottomIndex) {
        Return $TopIndexNumber + [Math]::Min($MenuItemCount, $WindowHeight) - 1
    }

    Throw 'Invalid option combination'
}

function Get-ConsoleHeight() {
    Return (Get-Host).UI.RawUI.WindowSize.Height - 2
}

function Get-PositionWithVKey([Array]$MenuItems, [int]$Position, $VKeyCode) {
    $MinPosition = 0
    $MaxPosition = $MenuItems.Count - 1
    $WindowHeight = Get-ConsoleHeight
    
    Set-Variable -Name NewPosition -Option AllScope -Value $Position

    <#
    .SYNOPSIS

    Updates the position until we aren't on a separator
    #>
    function Reset-InvalidPosition([Parameter(Mandatory)][int] $PositionOffset) {
        $NewPosition = Get-WrappedPosition $MenuItems $NewPosition $PositionOffset
    }

    If (Test-KeyUp $VKeyCode) { 
        $NewPosition--

        Reset-InvalidPosition -PositionOffset -1
    }

    If (Test-KeyDown $VKeyCode) {
        $NewPosition++

        Reset-InvalidPosition -PositionOffset 1
    }

    If (Test-KeyPageDown $VKeyCode) {
        $NewPosition = [Math]::Min($MaxPosition, $NewPosition + $WindowHeight)

        Reset-InvalidPosition -PositionOffset -1
    }

    If (Test-KeyEnd $VKeyCode) {
        $NewPosition = $MenuItems.Count - 1

        Reset-InvalidPosition -PositionOffset 1
    }

    IF (Test-KeyPageUp $VKeyCode) {
        $NewPosition = [Math]::Max($MinPosition, $NewPosition - $WindowHeight)

        Reset-InvalidPosition -PositionOffset -1
    }

    IF (Test-KeyHome $VKeyCode) {
        $NewPosition = $MinPosition

        Reset-InvalidPosition -PositionOffset -1
    }

    Return $NewPosition
}

function  Get-WrappedPosition([Array]$MenuItems, [int]$Position, [int]$PositionOffset) {
    # Wrap position
    if ($Position -lt 0) {
        $Position = $MenuItems.Count - 1
    }

    if ($Position -ge $MenuItems.Count) {
        $Position = 0
    }

    # Ensure to skip separators
    while (Test-MenuSeparator $($MenuItems[$Position])) {
        $Position += $PositionOffset

        $Position = Get-WrappedPosition $MenuItems $Position $PositionOffset
    }

    Return $Position
}

function Read-VKey() {
    $CurrentHost = Get-Host
    $ErrMsg = "Current host '$CurrentHost' does not support operation 'ReadKey'"

    try {
         # Issues with reading up and down arrow keys
         # - https://github.com/PowerShell/PowerShell/issues/16443
         # - https://github.com/dotnet/runtime/issues/63387
         # - https://github.com/PowerShell/PowerShell/issues/16606
         if ($IsLinux -or $IsMacOS) {
            ## A bug with Linux and Mac where arrow keys are return in 2 chars.  First is esc follow by A,B,C,D
            $key1 = $CurrentHost.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            
            if ($key1.VirtualKeyCode -eq 0x1B) {
               ## Found that we got an esc chair so we need to grab one more char
               $key2 = $CurrentHost.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

               ## We just care about up and down arrow mapping here for now.
                if ($key2.VirtualKeyCode -eq 0x41) {
                    # VK_UP = 0x26 up-arrow
                    $key1.VirtualKeyCode = 0x26
                }
                if ($key2.VirtualKeyCode -eq 0x42) {
                    # VK_DOWN = 0x28 down-arrow
                    $key1.VirtualKeyCode = 0x28
                }
            }
            Return $key1
        }
        
        Return $CurrentHost.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    catch [System.NotSupportedException] {
        Write-Error -Exception $_.Exception -Message $ErrMsg
    }
    catch [System.NotImplementedException] {
        Write-Error -Exception $_.Exception -Message $ErrMsg
    }
}

function Test-HostSupported() {
    $Whitelist = @("ConsoleHost","Visual Studio Code Host")

    if ($Whitelist -inotcontains $Host.Name) {
        Throw "This host is $($Host.Name) and does not support an interactive menu."
    }
}

# Ref: https://docs.microsoft.com/en-us/windows/desktop/inputdev/virtual-key-codes
$KeyConstants = [PSCustomObject]@{
    VK_RETURN   = 0x0D;
    VK_ESCAPE   = 0x1B;
    VK_UP       = 0x26;
    VK_DOWN     = 0x28;
    VK_SPACE    = 0x20;
    VK_PAGEUP   = 0x21; # Actually VK_PRIOR
    VK_PAGEDOWN = 0x22; # Actually VK_NEXT
    VK_END      = 0x23;
    VK_HOME     = 0x24;
}

function Test-KeyEnter($VKeyCode) {
    Return $VKeyCode -eq $KeyConstants.VK_RETURN
}

function Test-KeyEscape($VKeyCode) {
    Return $VKeyCode -eq $KeyConstants.VK_ESCAPE
}

function Test-KeyUp($VKeyCode) {
    Return $VKeyCode -eq $KeyConstants.VK_UP
}

function Test-KeyDown($VKeyCode) {
    Return $VKeyCode -eq $KeyConstants.VK_DOWN
}

function Test-KeySpace($VKeyCode) {
    Return $VKeyCode -eq $KeyConstants.VK_SPACE
}

function Test-KeyPageDown($VKeyCode) {
    Return $VKeyCode -eq $KeyConstants.VK_PAGEDOWN
}

function Test-KeyPageUp($VKeyCode) {
    Return $VKeyCode -eq $KeyConstants.VK_PAGEUP
}

function Test-KeyEnd($VKeyCode) {
    Return $VKeyCode -eq $KeyConstants.VK_END
}

function Test-KeyHome($VKeyCode) {
    Return $VKeyCode -eq $KeyConstants.VK_HOME
}

function Test-MenuItemArray([Array]$MenuItems) {
    foreach ($MenuItem in $MenuItems) {
        $IsSeparator = Test-MenuSeparator $MenuItem
        if ($IsSeparator -eq $false) {
            Return
        }
    }

    Throw 'The -MenuItems option only contains non-selectable menu-items (like separators)'
}

function Test-MenuSeparator([Parameter(Mandatory)] $MenuItem) {
    $Separator = Get-MenuSeparator

    # Separator is a singleton and we compare it by reference
    Return [Object]::ReferenceEquals($Separator, $MenuItem)
}

function Toggle-Selection {
    param ($Position, [Array]$CurrentSelection)
    if ($CurrentSelection -contains $Position) { 
        $result = $CurrentSelection | where { $_ -ne $Position }
    }
    else {
        $CurrentSelection += $Position
        $result = $CurrentSelection
    }
   
    Return $Result
}

function Write-MenuItem(
    [Parameter(Mandatory)][String] $MenuItem,
    [Switch]$IsFocused,
    [ConsoleColor]$FocusColor) {
    if ($IsFocused) {
        Write-Host $MenuItem -ForegroundColor $FocusColor
    }
    else {
        Write-Host $MenuItem
    }
}

function Write-Menu {
    param (
        [Parameter(Mandatory)][Array] $MenuItems, 
        [Parameter(Mandatory)][Int] $MenuPosition,
        [Parameter()][Array] $CurrentSelection, 
        [Parameter(Mandatory)][ConsoleColor] $ItemFocusColor,
        [Parameter(Mandatory)][ScriptBlock] $MenuItemFormatter,
        [Switch] $MultiSelect
    )
    
    $CurrentIndex = Get-CalculatedPageIndexNumber -MenuItems $MenuItems -MenuPosition $MenuPosition -TopIndex
    $MenuItemCount = Get-CalculatedPageIndexNumber -MenuItems $MenuItems -MenuPosition $MenuPosition -ItemCount
    $ConsoleWidth = [Console]::BufferWidth
    $MenuHeight = 0

    for ($i = 0; $i -le $MenuItemCount; $i++) {
        if ($null -eq $MenuItems[$CurrentIndex]) {
            Continue
        }

        $RenderMenuItem = $MenuItems[$CurrentIndex]
        $MenuItemStr = if (Test-MenuSeparator $RenderMenuItem) { $RenderMenuItem } else { & $MenuItemFormatter $RenderMenuItem }
        if (!$MenuItemStr) {
            Throw "'MenuItemFormatter' returned an empty string for item #$CurrentIndex"
        }

        $IsItemSelected = $CurrentSelection -contains $CurrentIndex
        $IsItemFocused = $CurrentIndex -eq $MenuPosition

        $DisplayText = Format-MenuItem -MenuItem $MenuItemStr -MultiSelect:$MultiSelect -IsItemSelected:$IsItemSelected -IsItemFocused:$IsItemFocused
        Write-MenuItem -MenuItem $DisplayText -IsFocused:$IsItemFocused -FocusColor $ItemFocusColor
        $MenuHeight += [Math]::Max([Math]::Ceiling($DisplayText.Length / $ConsoleWidth), 1)

        $CurrentIndex++;
    }

    $MenuHeight
}

function Get-MenuSeparator() {
    [CmdletBinding()]
    Param()

    # Internally we will check this parameter by-reference
    Return $Separator
}

function Show-Menu {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory, Position = 0)][Array] $MenuItems,
        [Switch]$ReturnIndex, 
        [Switch]$MultiSelect, 
        [ConsoleColor] $ItemFocusColor = [ConsoleColor]::Green,
        [ScriptBlock] $MenuItemFormatter = { Param($M) Format-MenuItemDefault $M },
        [Array] $InitialSelection = @(),
        [ScriptBlock] $Callback = $null
    )

    Test-HostSupported
    Test-MenuItemArray -MenuItems $MenuItems

    # Current pressed virtual key code
    $VKeyCode = 0

    # Initialize valid position
    $Position = Get-WrappedPosition $MenuItems -Position 0 -PositionOffset 1

    $CurrentSelection = $InitialSelection
    
    try {
        [System.Console]::CursorVisible = $False # Prevents cursor flickering

        # Body
        $WriteMenu = {
            ([ref]$MenuHeight).Value = Write-Menu -MenuItems $MenuItems `
                -MenuPosition $Position `
                -MultiSelect:$MultiSelect `
                -CurrentSelection:$CurrentSelection `
                -ItemFocusColor $ItemFocusColor `
                -MenuItemFormatter $MenuItemFormatter
        }
        $MenuHeight = 0

        & $WriteMenu
        $NeedRendering = $false
        
        While ($True) {
            If (Test-KeyEscape $VKeyCode) {
                Return $null
            }

            If (Test-KeyEnter $VKeyCode) {
                Break
            }

            # While there are 
            Do {
                # Read key when callback and available key, or no callback at all
                $VKeyCode = $null
                if ($null -eq $Callback -or [Console]::KeyAvailable) {
                    $CurrentPress = Read-VKey
                    $VKeyCode = $CurrentPress.VirtualKeyCode
                }

                If (Test-KeySpace $VKeyCode) {
                    $CurrentSelection = Toggle-Selection $Position $CurrentSelection
                }

                $Position = Get-PositionWithVKey -MenuItems $MenuItems -Position $Position -VKeyCode $VKeyCode

                If (!$(Test-KeyEscape $VKeyCode)) {
                    [System.Console]::SetCursorPosition(0, [Math]::Max(0, [Console]::CursorTop - $MenuHeight))
                    $NeedRendering = $true
                }
            } While ($null -eq $Callback -and [Console]::KeyAvailable);

            If ($NeedRendering) {
                & $WriteMenu
                $NeedRendering = $false
            }

            If ($Callback) {
                & $Callback

                Start-Sleep -Milliseconds 10
            }
        }
    }
    finally {
        [System.Console]::CursorVisible = $true
    }

    if ($ReturnIndex -eq $false -and $null -ne $Position) {
        if ($MultiSelect) {
            if ($null -ne $CurrentSelection) {
                Return $MenuItems[$CurrentSelection]
            }
        }
        else {
            Return $MenuItems[$Position]
        }
    }
    else {
        if ($MultiSelect) {
            Return $CurrentSelection
        }
        else {
            Return $Position
        }
    }
}

# -------
# CUSTOM FUNCTIONS FOR INSTALLER OPTIONS
# -------

$script:InstallerLogPath = $null
$script:InstallerConsoleTranscriptPath = $null
$script:InstallerConsoleTranscriptStarted = $false
$script:ConfigRepoUri = 'https://raw.githubusercontent.com/Brottus/ForensicOS/refs/heads/main'
$script:ForensicOSLinkerModuleUri = 'https://raw.githubusercontent.com/Brottus/ForensicOS/refs/heads/main/powershell-module/ForensicOS.Linker'
$script:ForensicOSLinkerModulePsd1Uri = "$script:ForensicOSLinkerModuleUri/ForensicOS.Linker.psd1"
$script:ForensicOSLinkerModulePsm1Uri = "$script:ForensicOSLinkerModuleUri/ForensicOS.Linker.psm1"
$script:BundleConfigUri = "$script:ConfigRepoUri/bundle-config.json"
$script:UniGetUISettingsUri = "$script:ConfigRepoUri/UniGetUI_Settings.json"
$script:MandiantChocoSourceName = 'Mandiant-repo'
$script:MandiantChocoSourceUri = 'https://www.myget.org/F/vm-packages/api/v2'
$script:InstallerExecutionSummary = [ordered]@{
    ActionsAttempted = 0
    ActionsSucceeded = 0
    ActionsFailed = 0
    ActionsSkipped = 0
    PackagesTotal = 0
    PackagesInstalled = 0
    PackagesFailed = 0
    PackagesSkipped = 0
    PostInstallCommandsTotal = 0
    PostInstallCommandsSucceeded = 0
    PostInstallCommandsFailed = 0
}
$script:InstallerActionStatus = [ordered]@{}

function Reset-InstallerExecutionSummary {
    $script:InstallerExecutionSummary.ActionsAttempted = 0
    $script:InstallerExecutionSummary.ActionsSucceeded = 0
    $script:InstallerExecutionSummary.ActionsFailed = 0
    $script:InstallerExecutionSummary.ActionsSkipped = 0
    $script:InstallerExecutionSummary.PackagesTotal = 0
    $script:InstallerExecutionSummary.PackagesInstalled = 0
    $script:InstallerExecutionSummary.PackagesFailed = 0
    $script:InstallerExecutionSummary.PackagesSkipped = 0
    $script:InstallerExecutionSummary.PostInstallCommandsTotal = 0
    $script:InstallerExecutionSummary.PostInstallCommandsSucceeded = 0
    $script:InstallerExecutionSummary.PostInstallCommandsFailed = 0
    $script:InstallerActionStatus = [ordered]@{}
}

function Invoke-TrackedInstallerAction {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ActionName,
        [Parameter(Mandatory = $true)]
        [bool]$ShouldRun,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    if (-not $ShouldRun) {
        $script:InstallerExecutionSummary.ActionsSkipped++
        $script:InstallerActionStatus[$ActionName] = 'Skipped'
        Write-InstallerLog -Message "Action skipped: $ActionName" -Level 'WARN'
        return
    }

    $script:InstallerExecutionSummary.ActionsAttempted++
    Write-InstallerLog -Message "Action started: $ActionName"

    try {
        & $Action
        $script:InstallerExecutionSummary.ActionsSucceeded++
        $script:InstallerActionStatus[$ActionName] = 'Succeeded'
        Write-InstallerLog -Message "Action completed: $ActionName"
    }
    catch {
        $script:InstallerExecutionSummary.ActionsFailed++
        $script:InstallerActionStatus[$ActionName] = 'Failed'
        Write-InstallerLog -Message "Action failed: $ActionName. $($_.Exception.Message)" -Level 'ERROR'
        throw
    }
}

function Write-InstallerExecutionSummary {
    $summaryLines = @(
        'Execution Summary',
        "Actions attempted: $($script:InstallerExecutionSummary.ActionsAttempted)",
        "Actions succeeded: $($script:InstallerExecutionSummary.ActionsSucceeded)",
        "Actions failed: $($script:InstallerExecutionSummary.ActionsFailed)",
        "Actions skipped: $($script:InstallerExecutionSummary.ActionsSkipped)",
        "Packages total: $($script:InstallerExecutionSummary.PackagesTotal)",
        "Packages installed: $($script:InstallerExecutionSummary.PackagesInstalled)",
        "Packages failed: $($script:InstallerExecutionSummary.PackagesFailed)",
        "Packages skipped: $($script:InstallerExecutionSummary.PackagesSkipped)",
        "Post-install commands total: $($script:InstallerExecutionSummary.PostInstallCommandsTotal)",
        "Post-install commands succeeded: $($script:InstallerExecutionSummary.PostInstallCommandsSucceeded)",
        "Post-install commands failed: $($script:InstallerExecutionSummary.PostInstallCommandsFailed)"
    )

    Write-Host ''
    Write-Host '=== Execution Summary ===' -ForegroundColor Cyan
    Write-Host "Actions attempted: $($script:InstallerExecutionSummary.ActionsAttempted)"
    Write-Host "Actions succeeded: $($script:InstallerExecutionSummary.ActionsSucceeded)" -ForegroundColor Green
    Write-Host "Actions failed: $($script:InstallerExecutionSummary.ActionsFailed)" -ForegroundColor Yellow
    Write-Host "Actions skipped: $($script:InstallerExecutionSummary.ActionsSkipped)" -ForegroundColor Yellow
    Write-Host "Packages total: $($script:InstallerExecutionSummary.PackagesTotal)"
    Write-Host "Packages installed: $($script:InstallerExecutionSummary.PackagesInstalled)" -ForegroundColor Green
    Write-Host "Packages failed: $($script:InstallerExecutionSummary.PackagesFailed)" -ForegroundColor Yellow
    Write-Host "Packages skipped: $($script:InstallerExecutionSummary.PackagesSkipped)" -ForegroundColor Yellow
    Write-Host "Post-install commands total: $($script:InstallerExecutionSummary.PostInstallCommandsTotal)"
    Write-Host "Post-install commands succeeded: $($script:InstallerExecutionSummary.PostInstallCommandsSucceeded)" -ForegroundColor Green
    Write-Host "Post-install commands failed: $($script:InstallerExecutionSummary.PostInstallCommandsFailed)" -ForegroundColor Yellow

    Write-Host 'Action outcomes:' -ForegroundColor Cyan
    foreach ($actionName in $script:InstallerActionStatus.Keys) {
        $status = $script:InstallerActionStatus[$actionName]
        $statusColor = 'Yellow'
        if ($status -eq 'Succeeded') {
            $statusColor = 'Green'
        }
        Write-Host " - ${actionName}: $status" -ForegroundColor $statusColor
        Write-InstallerLog -Message "Action outcome: $actionName = $status"
    }

    foreach ($line in $summaryLines) {
        Write-InstallerLog -Message $line
    }
}

function ConvertTo-InstallerObjectArray {
    param(
        $Value
    )

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [System.Array]) {
        return @($Value)
    }

    return @($Value)
}

function Get-InstallerBundlesFromConfigObject {
    param(
        $ConfigObject
    )

    if ($null -eq $ConfigObject) {
        return @()
    }

    $bundlesProperty = $null
    foreach ($property in $ConfigObject.PSObject.Properties) {
        if ($property.Name -ieq 'bundles') {
            $bundlesProperty = $property.Value
            break
        }
    }

    return @(ConvertTo-InstallerObjectArray -Value $bundlesProperty)
}

function Get-BundleConfig {
    # Fetches and parses the remote bundle config.
    # Returns a hashtable: { Bundles = @(...); NetworkFailed = $true/$false }
    # Bundles entries have at minimum Description and BundleUrl properties.
    # Optional: RequiredManagers = @('winget','scoop',...)
    param(
        [string]$ConfigUri = $script:BundleConfigUri
    )

    try {
        Write-Host "Fetching bundle configuration..." -ForegroundColor Cyan
        $configContent = Invoke-WebRequest -Uri $ConfigUri -UseBasicParsing -ErrorAction Stop
        $configObject = $configContent.Content | ConvertFrom-Json -ErrorAction Stop
        $bundles = @(Get-InstallerBundlesFromConfigObject -ConfigObject $configObject)
        return @{ Bundles = $bundles; NetworkFailed = $false }
    }
    catch {
        Write-InstallerLog -Message "Failed to access bundle config from '$ConfigUri': $($_.Exception.Message)" -Level 'WARN'
        return @{ Bundles = @(); NetworkFailed = $true }
    }
}

function Write-InstallerLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    if ([string]::IsNullOrWhiteSpace($script:InstallerLogPath)) {
        return
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $script:InstallerLogPath -Value "[$timestamp] [$Level] $Message"
}

function Initialize-InstallerLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    if (-not (Test-Path -Path $BasePath -PathType Container)) {
        New-Item -Path $BasePath -ItemType Directory -Force | Out-Null
    }

    $logName = "forensicos-install-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss')
    $script:InstallerLogPath = Join-Path -Path $BasePath -ChildPath $logName
    New-Item -Path $script:InstallerLogPath -ItemType File -Force | Out-Null
    Write-InstallerLog -Message "Installer log initialized at $script:InstallerLogPath"
}

function Start-InstallerConsoleTranscript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    if (-not (Test-Path -Path $BasePath -PathType Container)) {
        New-Item -Path $BasePath -ItemType Directory -Force | Out-Null
    }

    $transcriptName = "forensicos-install-console-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss')
    $script:InstallerConsoleTranscriptPath = Join-Path -Path $BasePath -ChildPath $transcriptName

    try {
        Start-Transcript -Path $script:InstallerConsoleTranscriptPath -Force -ErrorAction Stop | Out-Null
        $script:InstallerConsoleTranscriptStarted = $true
        Write-InstallerLog -Message "Console transcript initialized at $script:InstallerConsoleTranscriptPath"
        Write-Host "Console transcript file: $script:InstallerConsoleTranscriptPath" -ForegroundColor Green
    }
    catch {
        $script:InstallerConsoleTranscriptStarted = $false
        Write-InstallerLog -Message "Failed to initialize console transcript: $($_.Exception.Message)" -Level 'WARN'
        Write-Host "Warning: Failed to initialize console transcript. $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Stop-InstallerConsoleTranscript {
    if (-not $script:InstallerConsoleTranscriptStarted) {
        return
    }

    try {
        Stop-Transcript | Out-Null
        $script:InstallerConsoleTranscriptStarted = $false
        Write-InstallerLog -Message "Console transcript completed at $script:InstallerConsoleTranscriptPath"
    }
    catch {
        Write-InstallerLog -Message "Failed to stop console transcript cleanly: $($_.Exception.Message)" -Level 'WARN'
    }
}

function Add-InstallerEnvironmentPathEntry {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Path', 'PYTHONPATH')]
        [string]$VariableName,
        [Parameter(Mandatory = $true)]
        [string]$EntryPath,
        [switch]$CreateDirectory
    )

    if ([string]::IsNullOrWhiteSpace($EntryPath)) {
        return
    }

    $normalizedPath = [System.IO.Path]::GetFullPath($EntryPath).TrimEnd('\\')

    if ($CreateDirectory -and -not (Test-Path -Path $normalizedPath -PathType Container)) {
        New-Item -Path $normalizedPath -ItemType Directory -Force | Out-Null
    }

    $machineValue = [Environment]::GetEnvironmentVariable($VariableName, 'Machine')
    $machineEntries = @()
    if (-not [string]::IsNullOrWhiteSpace($machineValue)) {
        $machineEntries = @($machineValue -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $entryExists = $false
    foreach ($existingEntry in $machineEntries) {
        if ($existingEntry.TrimEnd('\\') -ieq $normalizedPath) {
            $entryExists = $true
            break
        }
    }

    if (-not $entryExists) {
        $machineEntries += $normalizedPath
        [Environment]::SetEnvironmentVariable($VariableName, ($machineEntries -join ';'), 'Machine')
        Write-InstallerLog -Message ("Added '{0}' to machine {1}." -f $normalizedPath, $VariableName)
    }

    # Refresh current session from User + Machine values so newly added entries work immediately.
    $sessionEntries = @()
    $userValue = [Environment]::GetEnvironmentVariable($VariableName, 'User')
    $updatedMachineValue = [Environment]::GetEnvironmentVariable($VariableName, 'Machine')

    if (-not [string]::IsNullOrWhiteSpace($updatedMachineValue)) {
        $sessionEntries += @($updatedMachineValue -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    if (-not [string]::IsNullOrWhiteSpace($userValue)) {
        foreach ($userEntry in ($userValue -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
            $alreadyInSession = $false
            foreach ($sessionEntry in $sessionEntries) {
                if ($sessionEntry.TrimEnd('\\') -ieq $userEntry.TrimEnd('\\')) {
                    $alreadyInSession = $true
                    break
                }
            }

            if (-not $alreadyInSession) {
                $sessionEntries += $userEntry
            }
        }
    }

    Set-Item -Path ("Env:{0}" -f $VariableName) -Value ($sessionEntries -join ';')
}

function Set-ForensicOSToolsBasePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    if ([string]::IsNullOrWhiteSpace($BasePath)) {
        return
    }

    $resolvedBasePath = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\\')
    $env:ForensicOSToolsBasePath = $resolvedBasePath

    try {
        [Environment]::SetEnvironmentVariable('ForensicOSToolsBasePath', $resolvedBasePath, 'Machine')
        Write-InstallerLog -Message "Set machine ForensicOSToolsBasePath to $resolvedBasePath"
    }
    catch {
        Write-InstallerLog -Message "Failed to set machine ForensicOSToolsBasePath: $($_.Exception.Message)" -Level 'WARN'
    }

    try {
        [Environment]::SetEnvironmentVariable('ForensicOSToolsBasePath', $resolvedBasePath, 'User')
        Write-InstallerLog -Message "Set user ForensicOSToolsBasePath to $resolvedBasePath"
    }
    catch {
        Write-InstallerLog -Message "Failed to set user ForensicOSToolsBasePath: $($_.Exception.Message)" -Level 'WARN'
    }
}

function Set-PipGlobalPrefix {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PrefixPath,
        [string]$PythonCommand,
        [string]$PyCommand,
        [string]$PipCommand
    )

    if ([string]::IsNullOrWhiteSpace($PrefixPath)) {
        throw 'Pip prefix path cannot be empty.'
    }

    $normalizedPrefixPath = [System.IO.Path]::GetFullPath($PrefixPath)
    if (-not (Test-Path -Path $normalizedPrefixPath -PathType Container)) {
        New-Item -Path $normalizedPrefixPath -ItemType Directory -Force | Out-Null
    }

    $configuredWith = $null

    if (-not [string]::IsNullOrWhiteSpace($PythonCommand) -and $PythonCommand -notmatch '\\WindowsApps\\') {
        $pythonVersionOutput = & $PythonCommand --version 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $pythonVersionOutput -match 'Python\s+\d') {
            & $PythonCommand -m pip config --global set global.prefix $normalizedPrefixPath
            if ($LASTEXITCODE -eq 0) {
                $configuredWith = $PythonCommand
            }
        }
    }

    if ($null -eq $configuredWith -and -not [string]::IsNullOrWhiteSpace($PyCommand) -and $PyCommand -notmatch '\\WindowsApps\\') {
        $pyVersionOutput = & $PyCommand --version 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $pyVersionOutput -match 'Python\s+\d') {
            & $PyCommand -m pip config --global set global.prefix $normalizedPrefixPath
            if ($LASTEXITCODE -eq 0) {
                $configuredWith = $PyCommand
            }
        }
    }

    if ($null -eq $configuredWith -and -not [string]::IsNullOrWhiteSpace($PipCommand) -and $PipCommand -notmatch '\\WindowsApps\\') {
        $pipVersionOutput = & $PipCommand --version 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $pipVersionOutput -match 'pip\s+\d') {
            & $PipCommand config --global set global.prefix $normalizedPrefixPath
            if ($LASTEXITCODE -eq 0) {
                $configuredWith = $PipCommand
            }
        }
    }

    if ($null -eq $configuredWith) {
        throw "Failed to set pip global.prefix to '$normalizedPrefixPath' because no usable python/py/pip command was available."
    }

    Write-InstallerLog -Message ("Configured pip global.prefix = '{0}' using '{1}'" -f $normalizedPrefixPath, $configuredWith)
}

function Set-SmartScreenState {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )

    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
    if (-not (Test-Path -Path $policyPath)) {
        New-Item -Path $policyPath -Force | Out-Null
    }

    if ($Enabled) {
        Set-ItemProperty -Path $policyPath -Name 'EnableSmartScreen' -Type DWord -Value 1
        Set-ItemProperty -Path $policyPath -Name 'ShellSmartScreenLevel' -Type String -Value 'Warn'
        Write-Host 'SmartScreen enabled (Warn).' -ForegroundColor Green
        Write-InstallerLog -Message 'SmartScreen enabled (Warn).'
    }
    else {
        Set-ItemProperty -Path $policyPath -Name 'EnableSmartScreen' -Type DWord -Value 0
        Set-ItemProperty -Path $policyPath -Name 'ShellSmartScreenLevel' -Type String -Value 'Off'
        Write-Host 'SmartScreen disabled for installation phase.' -ForegroundColor Yellow
        Write-InstallerLog -Message 'SmartScreen disabled for installation phase.' -Level 'WARN'
    }
}

function Invoke-CustomPathSetup {
    param(
        [ValidateSet('Container', 'Leaf')]
        [string]$PathType = 'Container'
    )
    <#
    .SYNOPSIS
    Prompts user for a custom installation path or file path with validation and autocomplete support.
    .DESCRIPTION
    Prompts the user to enter a path. When PathType is Container (default) it validates that the
    folder exists or can be created. When PathType is Leaf it validates that the file exists.
    The input supports PowerShell's native path autocomplete (Tab key).
    .EXAMPLE
    Invoke-CustomPathSetup
    Invoke-CustomPathSetup -PathType Leaf
    #>
    if ($PathType -eq 'Leaf') {
        Write-Host "`n--- Select File ---" -ForegroundColor Cyan
        Write-Host "Enter the file path (or press Tab for autocomplete):"
    }
    else {
        Write-Host "`n--- Define Custom Install Path ---" -ForegroundColor Cyan
        Write-Host "Enter the folder path where you want to install (or press Tab for autocomplete):"
    }

    $validPath = $false
    $path = $null
    $script:ForensPathPromptCancelled = $false
    $script:ForensPathPromptCancelReason = 'Esc'

    # Temporarily bind Escape to cancel this prompt while keeping PSReadLine autocomplete.
    $hasPsReadLine = ($null -ne (Get-Command -Name Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue))
    if ($hasPsReadLine) {
        Set-PSReadLineKeyHandler -Key Escape -BriefDescription 'CancelInput' -LongDescription 'Cancel path prompt' -ScriptBlock {
            param($key, $arg)
            $script:ForensPathPromptCancelled = $true
            $script:ForensPathPromptCancelReason = 'Esc'
            [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        }
        Set-PSReadLineKeyHandler -Key Ctrl+c -BriefDescription 'CancelInput' -LongDescription 'Cancel path prompt' -ScriptBlock {
            param($key, $arg)
            $script:ForensPathPromptCancelled = $true
            $script:ForensPathPromptCancelReason = 'Ctrl+C'
            [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        }
    }

    try {
        while (-not $validPath) {
            try {
                $path = PSConsoleHostReadLine
            }
            catch [System.Management.Automation.PipelineStoppedException] {
                throw 'Installation cancelled by user (Ctrl+C).'
            }

            if ($script:ForensPathPromptCancelled) {
                throw "Installation cancelled by user ($script:ForensPathPromptCancelReason)."
            }

            if ($null -eq $path) {
                throw 'Installation cancelled by user.'
            }

            # Trim quotes if user entered them
            $path = $path -replace '^["'']|["'']$', ''

            # Expand environment variables (e.g., %USERPROFILE%)
            $path = [System.Environment]::ExpandEnvironmentVariables($path)

            # Reject empty/whitespace-only values.
            if ([string]::IsNullOrWhiteSpace($path)) {
                Write-Host "Path cannot be empty. Please try again." -ForegroundColor Yellow
                continue
            }

            if ($PathType -eq 'Leaf') {
                # File mode: the file must already exist.
                if (Test-Path -Path $path -PathType Leaf) {
                    $validPath = $true
                    Write-Host "File confirmed: $path" -ForegroundColor Green
                }
                else {
                    Write-Host "File not found. Please try again." -ForegroundColor Yellow
                }
            }
            else {
                # Folder mode: accept existing folder or offer to create one.
                if (Test-Path -Path $path -PathType Container) {
                    $validPath = $true
                    Write-Host "Path confirmed: $path" -ForegroundColor Green
                }
                elseif (Test-Path -Path (Split-Path -Path $path -Parent) -PathType Container) {
                    $confirm = Read-Host "Path does not exist. Create it? (Y/n)"
                    if ($confirm -eq 'Y' -or $confirm -eq 'y' -or $confirm -eq '') {
                        try {
                            New-Item -ItemType Directory -Path $path -Force | Out-Null
                            $validPath = $true
                            Write-Host "Folder created: $path" -ForegroundColor Green
                        }
                        catch {
                            Write-Host "Failed to create folder: $_" -ForegroundColor Red
                        }
                    }
                }
                else {
                    Write-Host "Invalid path. Parent folder does not exist. Please try again." -ForegroundColor Yellow
                }
            }
        }
    }
    finally {
        if ($hasPsReadLine) {
            Set-PSReadLineKeyHandler -Key Escape -Function RevertLine
            Set-PSReadLineKeyHandler -Key Ctrl+c -Function CopyOrCancelLine
        }

        Remove-Variable -Name ForensPathPromptCancelled -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name ForensPathPromptCancelReason -Scope Script -ErrorAction SilentlyContinue
    }

    # Normalize path so values with/without trailing backslash behave consistently.
    return [System.IO.Path]::GetFullPath($path)
}

function Invoke-PackagePostInstallCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageId,
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    if ([string]::IsNullOrWhiteSpace($Command)) {
        return $true
    }

    Write-Host "Running post-install command for '$PackageId'..." -ForegroundColor Cyan
    Write-InstallerLog -Message "Running post-install command for '$PackageId': $Command"

    try {
        Invoke-Expression $Command
        if ($LASTEXITCODE -ne 0) {
            Write-InstallerLog -Message "Post-install command failed for '$PackageId' with exit code $LASTEXITCODE" -Level 'ERROR'
            Write-Host "Post-install command failed for '$PackageId' (exit code $LASTEXITCODE)." -ForegroundColor Yellow
            return $false
        }
        else {
            Write-InstallerLog -Message "Post-install command completed for '$PackageId'"
            return $true
        }
    }
    catch {
        Write-InstallerLog -Message "Post-install command exception for '$PackageId': $($_.Exception.Message)" -Level 'ERROR'
        Write-Host "Post-install command failed for '$PackageId': $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

function Invoke-PackageBundleInstall {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallBasePath,
        [Parameter(Mandatory = $true)]
        [hashtable]$InstallConfig,
        [string]$BundlePath
    )

    if ([string]::IsNullOrWhiteSpace($BundlePath)) {
        Write-InstallerLog -Message 'No package bundle provided. Skipping package bundle installation.' -Level 'WARN'
        Write-Host 'No package bundle provided. Skipping package bundle installation.' -ForegroundColor Yellow
        return
    }

    # Support URL bundles: download to a temp file first
    $tempBundlePath = $null
    if ($BundlePath -match '^https?://') {
        Write-Host "Downloading bundle from: $BundlePath" -ForegroundColor Cyan
        Write-InstallerLog -Message "Downloading bundle from URL: '$BundlePath'"
        try {
            $tempBundlePath = [System.IO.Path]::GetTempFileName() + '.ubundle'
            Invoke-WebRequest -Uri $BundlePath -OutFile $tempBundlePath -UseBasicParsing -ErrorAction Stop
            $BundlePath = $tempBundlePath
            Write-InstallerLog -Message "Bundle downloaded to temp file: '$BundlePath'"
        }
        catch {
            throw "Failed to download package bundle from '$BundlePath': $($_.Exception.Message)"
        }
    }

    if (-not (Test-Path -Path $BundlePath -PathType Leaf)) {
        throw "Package bundle file not found: $BundlePath"
    }

    $bundleObject = $null
    try {
        $bundleObject = Get-Content -Path $BundlePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse package bundle '$BundlePath': $($_.Exception.Message)"
    }
    finally {
        # Clean up temp file if we downloaded a bundle
        if ($null -ne $tempBundlePath -and (Test-Path -Path $tempBundlePath -PathType Leaf)) {
            Remove-Item -Path $tempBundlePath -Force -ErrorAction SilentlyContinue
        }
    }

    $packages = @()
    if ($null -ne $bundleObject -and $null -ne $bundleObject.packages) {
        $packages = @($bundleObject.packages)
    }

    if ($packages.Count -eq 0) {
        Write-InstallerLog -Message "No packages found in bundle '$BundlePath'" -Level 'WARN'
        Write-Host "No packages found in bundle '$BundlePath'." -ForegroundColor Yellow
        return
    }

    Write-Host "`nInstalling packages from bundle: $BundlePath" -ForegroundColor Cyan
    Write-InstallerLog -Message "Starting package bundle installation from '$BundlePath'"

    foreach ($package in $packages) {
        $script:InstallerExecutionSummary.PackagesTotal++
        $packageId = "$($package.Id)"
        $packageName = "$($package.Name)"
        $packageVersion = "$($package.Version)"
        $packageSource = "$($package.Source)"
        $managerName = "$($package.ManagerName)"
        $normalizedManagerName = if ([string]::IsNullOrWhiteSpace($managerName)) { '' } else { $managerName.Trim().ToLowerInvariant() }
        $postInstallCommand = $null
        $resolvedVersion = $packageVersion
        $overrideVersion = $null
        $overridesNextLevelOpts = $false
        $customInstallLocation = $null

        if ($null -ne $package.InstallationOptions -and $null -ne $package.InstallationOptions.PostInstallCommand) {
            $postInstallCommand = "$($package.InstallationOptions.PostInstallCommand)"
        }

        if ($null -ne $package.InstallationOptions) {
            if ($null -ne $package.InstallationOptions.OverridesNextLevelOpts) {
                $overridesNextLevelOpts = [bool]$package.InstallationOptions.OverridesNextLevelOpts
            }

            if ($null -ne $package.InstallationOptions.Version) {
                $overrideVersion = "$($package.InstallationOptions.Version)"
            }

            if ($null -ne $package.InstallationOptions.CustomInstallLocation) {
                $customInstallLocation = "$($package.InstallationOptions.CustomInstallLocation)"
                if (-not [string]::IsNullOrWhiteSpace($customInstallLocation)) {
                    if ($customInstallLocation -imatch '^c:\\tools(\\|$)') {
                        $resolvedToolsBasePath = $env:ForensicOSToolsBasePath
                        if ([string]::IsNullOrWhiteSpace($resolvedToolsBasePath)) {
                            $resolvedToolsBasePath = $InstallBasePath
                        }

                        if (-not [string]::IsNullOrWhiteSpace($resolvedToolsBasePath)) {
                            $locationSuffix = ''
                            if ($customInstallLocation.Length -gt 8) {
                                $locationSuffix = $customInstallLocation.Substring(8).TrimStart('\\')
                            }

                            if ([string]::IsNullOrWhiteSpace($locationSuffix)) {
                                $customInstallLocation = $resolvedToolsBasePath
                            }
                            else {
                                $customInstallLocation = Join-Path -Path $resolvedToolsBasePath -ChildPath $locationSuffix
                            }

                            Write-InstallerLog -Message "Mapped bundle CustomInstallLocation prefix 'C:\tools' to '$resolvedToolsBasePath' for package '$packageId'."
                        }
                    }

                    $expandedCustomInstallLocation = [System.Environment]::ExpandEnvironmentVariables($customInstallLocation)
                    if (-not [string]::IsNullOrWhiteSpace($expandedCustomInstallLocation)) {
                        $customInstallLocation = $expandedCustomInstallLocation
                    }
                }
                if ([string]::IsNullOrWhiteSpace($customInstallLocation)) { $customInstallLocation = $null }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($overrideVersion)) {
            if ($overridesNextLevelOpts) {
                $resolvedVersion = $overrideVersion
                Write-InstallerLog -Message "Using InstallationOptions.Version '$resolvedVersion' for package '$packageId' (OverridesNextLevelOpts=true)."
            }
            elseif ([string]::IsNullOrWhiteSpace($resolvedVersion)) {
                $resolvedVersion = $overrideVersion
                Write-InstallerLog -Message "Using InstallationOptions.Version '$resolvedVersion' for package '$packageId' (fallback because package.Version is empty)."
            }
            else {
                Write-InstallerLog -Message "Package '$packageId' has InstallationOptions.Version '$overrideVersion' but OverridesNextLevelOpts is false; using package.Version '$resolvedVersion'."
            }
        }

        if ([string]::IsNullOrWhiteSpace($packageId)) {
            Write-InstallerLog -Message 'Skipped package with missing Id in bundle.' -Level 'WARN'
            $script:InstallerExecutionSummary.PackagesSkipped++
            continue
        }

        $displayName = if ([string]::IsNullOrWhiteSpace($packageName)) { $packageId } else { "$packageName ($packageId)" }
        Write-Host "Installing package: $displayName via manager '$managerName'" -ForegroundColor Cyan
        Write-InstallerLog -Message "Installing package '$displayName' via manager '$managerName'"

        $installSucceeded = $false

        switch ($normalizedManagerName) {
            'chocolatey' {
                if (-not $InstallConfig.Chocolatey) {
                    Write-InstallerLog -Message "Skipped Chocolatey package '$packageId' because Chocolatey was not selected for installation." -Level 'WARN'
                    Write-Host "Skipped '$packageId' (Chocolatey not selected)." -ForegroundColor Yellow
                    $script:InstallerExecutionSummary.PackagesSkipped++
                    continue
                }

                if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
                    Write-InstallerLog -Message "Skipped Chocolatey package '$packageId' because choco command is not available." -Level 'WARN'
                    $script:InstallerExecutionSummary.PackagesSkipped++
                    continue
                }

                $chocoArgs = @('install', $packageId, '-y')
                if (-not [string]::IsNullOrWhiteSpace($resolvedVersion)) {
                    $chocoArgs += @('--version', $resolvedVersion)
                }
                if (-not [string]::IsNullOrWhiteSpace($packageSource)) {
                    $resolvedPackageSource = $packageSource.Trim()
                    if ($resolvedPackageSource -ieq 'community') {
                        $resolvedPackageSource = 'chocolatey'
                        Write-InstallerLog -Message "Mapped Chocolatey source alias 'community' to '$resolvedPackageSource' for package '$packageId'"
                    }

                    $chocoArgs += @('--source', $resolvedPackageSource)
                }

                & choco @chocoArgs
                if ($LASTEXITCODE -eq 0) {
                    $installSucceeded = $true
                }
                else {
                    Write-InstallerLog -Message "Chocolatey install failed for '$packageId' with exit code $LASTEXITCODE" -Level 'ERROR'
                }
            }
            'scoop' {
                if (-not $InstallConfig.Scoop) {
                    Write-InstallerLog -Message "Skipped Scoop package '$packageId' because Scoop was not selected for installation." -Level 'WARN'
                    Write-Host "Skipped '$packageId' (Scoop not selected)." -ForegroundColor Yellow
                    $script:InstallerExecutionSummary.PackagesSkipped++
                    continue
                }

                if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
                    Write-InstallerLog -Message "Skipped Scoop package '$packageId' because scoop command is not available." -Level 'WARN'
                    $script:InstallerExecutionSummary.PackagesSkipped++
                    continue
                }

                $scoopTarget = $packageId
                if (-not [string]::IsNullOrWhiteSpace($packageSource) -and $packageId -notmatch '/') {
                    $normalizedSource = $packageSource.Trim().ToLowerInvariant()
                    if ($normalizedSource -ne 'main') {
                        $scoopTarget = "$packageSource/$packageId"
                    }
                }

                & scoop install $scoopTarget
                if ($LASTEXITCODE -eq 0) {
                    $installSucceeded = $true
                }
                else {
                    Write-InstallerLog -Message "Scoop install failed for '$packageId' with exit code $LASTEXITCODE" -Level 'ERROR'
                }
            }
            'winget' {
                if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
                    Write-InstallerLog -Message "Skipped winget package '$packageId' because winget command is not available." -Level 'WARN'
                    $script:InstallerExecutionSummary.PackagesSkipped++
                    continue
                }

                $wingetArgs = @('install', '--id', $packageId, '--exact', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity', '--silent', '--force')
                if (-not [string]::IsNullOrWhiteSpace($resolvedVersion)) {
                    $wingetArgs += @('--version', $resolvedVersion)
                }
                if (-not [string]::IsNullOrWhiteSpace($packageSource)) {
                    $wingetArgs += @('--source', $packageSource)
                }
                if (-not [string]::IsNullOrWhiteSpace($customInstallLocation)) {
                    $wingetArgs += @('--location', $customInstallLocation)
                }

                & winget @wingetArgs
                if ($LASTEXITCODE -eq 0) {
                    $installSucceeded = $true
                }
                else {
                    Write-InstallerLog -Message "winget install failed for '$packageId' with exit code $LASTEXITCODE" -Level 'ERROR'
                }
            }
            'pip' {
                if (-not $InstallConfig.PipPackages) {
                    Write-InstallerLog -Message "Skipped pip package '$packageId' because pip package installation was not selected." -Level 'WARN'
                    Write-Host "Skipped '$packageId' (pip not selected)." -ForegroundColor Yellow
                    $script:InstallerExecutionSummary.PackagesSkipped++
                    continue
                }

                $pythonCmd = Get-Command python -All -ErrorAction SilentlyContinue |
                    Where-Object { $_.Source -notmatch '\\WindowsApps\\' } |
                    Select-Object -First 1
                if (-not $pythonCmd) {
                    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
                }

                $pyCmd = Get-Command py -All -ErrorAction SilentlyContinue |
                    Where-Object { $_.Source -notmatch '\\WindowsApps\\' } |
                    Select-Object -First 1
                if (-not $pyCmd) {
                    $pyCmd = Get-Command py -ErrorAction SilentlyContinue
                }

                $pipCmd = Get-Command pip -All -ErrorAction SilentlyContinue |
                    Where-Object { $_.Source -notmatch '\\WindowsApps\\' } |
                    Select-Object -First 1
                if (-not $pipCmd) {
                    $pipCmd = Get-Command pip -ErrorAction SilentlyContinue
                }
                $pythonCmdPath = $null
                if ($pythonCmd) {
                    $pythonVersionOutput = & $pythonCmd.Source --version 2>&1 | Out-String
                    if ($LASTEXITCODE -eq 0 -and $pythonVersionOutput -match 'Python\s+\d') {
                        $pythonCmdPath = $pythonCmd.Source
                    }
                }

                $pyCmdPath = $null
                if ($pyCmd) {
                    $pyVersionOutput = & $pyCmd.Source --version 2>&1 | Out-String
                    if ($LASTEXITCODE -eq 0 -and $pyVersionOutput -match 'Python\s+\d') {
                        $pyCmdPath = $pyCmd.Source
                    }
                }

                $pipCmdPath = $null
                if ($pipCmd) {
                    $pipVersionOutput = & $pipCmd.Source --version 2>&1 | Out-String
                    if ($LASTEXITCODE -eq 0 -and $pipVersionOutput -match 'pip\s+\d') {
                        $pipCmdPath = $pipCmd.Source
                    }
                }

                $pipPrefixPath = Join-Path -Path $InstallBasePath -ChildPath 'python_scripts'
                $pipScriptsPath = Join-Path -Path $pipPrefixPath -ChildPath 'Scripts'
                $pipSitePackagesPath = Join-Path -Path $pipPrefixPath -ChildPath 'Lib\site-packages'
                Add-InstallerEnvironmentPathEntry -VariableName 'Path' -EntryPath $pipScriptsPath -CreateDirectory
                Add-InstallerEnvironmentPathEntry -VariableName 'PYTHONPATH' -EntryPath $pipSitePackagesPath -CreateDirectory
                Set-PipGlobalPrefix -PrefixPath $pipPrefixPath -PythonCommand $pythonCmdPath -PyCommand $pyCmdPath -PipCommand $pipCmdPath

                $pipSpecifier = $packageId
                if (-not [string]::IsNullOrWhiteSpace($resolvedVersion)) {
                    $pipSpecifier = "$packageId==$resolvedVersion"
                }

                if (-not [string]::IsNullOrWhiteSpace($pythonCmdPath)) {
                    & $pythonCmdPath -m pip install --prefix $pipPrefixPath --no-warn-script-location $pipSpecifier
                }
                elseif (-not [string]::IsNullOrWhiteSpace($pyCmdPath)) {
                    & $pyCmdPath -m pip install --prefix $pipPrefixPath --no-warn-script-location $pipSpecifier
                }
                elseif (-not [string]::IsNullOrWhiteSpace($pipCmdPath)) {
                    & $pipCmdPath install --prefix $pipPrefixPath --no-warn-script-location $pipSpecifier
                }
                else {
                    Write-InstallerLog -Message "Skipped pip package '$packageId' because no usable python/py/pip command is available." -Level 'WARN'
                    $script:InstallerExecutionSummary.PackagesSkipped++
                    continue
                }

                if ($LASTEXITCODE -eq 0) {
                    $installSucceeded = $true
                }
                else {
                    Write-InstallerLog -Message "pip install failed for '$packageId' with exit code $LASTEXITCODE" -Level 'ERROR'
                }
            }
            'winps' {
                try {
                    $installModuleParams = @{
                        Name = $packageId
                        Force = $true
                        Scope = 'AllUsers'
                        ErrorAction = 'Stop'
                    }

                    if (-not [string]::IsNullOrWhiteSpace($resolvedVersion)) {
                        $installModuleParams['RequiredVersion'] = $resolvedVersion
                    }

                    Install-Module @installModuleParams
                    $installSucceeded = $true
                }
                catch {
                    Write-InstallerLog -Message "PowerShell module install failed for '$packageId': $($_.Exception.Message)" -Level 'ERROR'
                }
            }
            default {
                Write-InstallerLog -Message "Skipped package '$packageId' because manager '$managerName' is not supported." -Level 'WARN'
                Write-Host "Skipped '$packageId' (unsupported manager '$managerName')." -ForegroundColor Yellow
                $script:InstallerExecutionSummary.PackagesSkipped++
                continue
            }
        }

        if ($installSucceeded) {
            $script:InstallerExecutionSummary.PackagesInstalled++
            Write-InstallerLog -Message "Package installed successfully: '$displayName' via '$managerName'"
            if (-not [string]::IsNullOrWhiteSpace($postInstallCommand)) {
                $script:InstallerExecutionSummary.PostInstallCommandsTotal++
                $postInstallOk = Invoke-PackagePostInstallCommand -PackageId $packageId -Command $postInstallCommand
                if ($postInstallOk) {
                    $script:InstallerExecutionSummary.PostInstallCommandsSucceeded++
                }
                else {
                    $script:InstallerExecutionSummary.PostInstallCommandsFailed++
                }
            }
        }
        else {
            $script:InstallerExecutionSummary.PackagesFailed++
            Write-InstallerLog -Message "Package installation failed: '$displayName' via '$managerName'" -Level 'ERROR'
        }
    }

    Write-InstallerLog -Message 'Completed package bundle installation'
}

function Invoke-PipPackageInstall {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScanRootPath
    )

    $pythonManagerPackageId = 'Python.PythonInstallManager'

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget was not found in PATH.'
    }

    $packageInstalled = $false
    $listOutput = & winget list --id $pythonManagerPackageId --exact --accept-source-agreements 2>&1 | Out-String
    if ($listOutput -match [Regex]::Escape($pythonManagerPackageId)) {
        $packageInstalled = $true
    }

    if (-not $packageInstalled) {
        Write-Host "Installing $pythonManagerPackageId..." -ForegroundColor Cyan
        Write-InstallerLog -Message "Installing prerequisite package '$pythonManagerPackageId'"
        & winget install --id $pythonManagerPackageId --exact --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            Write-InstallerLog -Message "Failed to install '$pythonManagerPackageId'" -Level 'ERROR'
            throw "Failed to install package: $pythonManagerPackageId"
        }
    }

    # Refresh full process environment from Machine then User so newly installed commands are available now.
    $machineEnvironment = [Environment]::GetEnvironmentVariables('Machine')
    foreach ($entry in $machineEnvironment.GetEnumerator()) {
        if ($null -ne $entry.Key) {
            Set-Item -Path ("Env:{0}" -f $entry.Key) -Value $entry.Value
        }
    }
    $userEnvironment = [Environment]::GetEnvironmentVariables('User')
    foreach ($entry in $userEnvironment.GetEnumerator()) {
        if ($null -ne $entry.Key) {
            Set-Item -Path ("Env:{0}" -f $entry.Key) -Value $entry.Value
        }
    }

    $pymanagerCmd = Get-Command pymanager -All -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notmatch '\\WindowsApps\\' } |
        Select-Object -First 1
    if (-not $pymanagerCmd) {
        $pymanagerCmd = Get-Command pymanager -ErrorAction SilentlyContinue
    }
    if (-not $pymanagerCmd) {
        throw 'pymanager command is not available after installation.'
    }

    $pymanagerVersionOutput = & $pymanagerCmd.Source --version 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw 'pymanager command is not usable after installation.'
    }

    Write-Host 'Running pymanager install --configure --yes...' -ForegroundColor Cyan
    Write-InstallerLog -Message 'Running pymanager install --configure --yes'
    & $pymanagerCmd.Source install --configure --yes
    if ($LASTEXITCODE -ne 0) {
        Write-InstallerLog -Message 'pymanager install --configure --yes failed' -Level 'ERROR'
        throw 'pymanager install --configure --yes failed.'
    }

    # Refresh full process environment again after configuration in case pymanager updates shims/aliases.
    $machineEnvironment = [Environment]::GetEnvironmentVariables('Machine')
    foreach ($entry in $machineEnvironment.GetEnumerator()) {
        if ($null -ne $entry.Key) {
            Set-Item -Path ("Env:{0}" -f $entry.Key) -Value $entry.Value
        }
    }
    $userEnvironment = [Environment]::GetEnvironmentVariables('User')
    foreach ($entry in $userEnvironment.GetEnumerator()) {
        if ($null -ne $entry.Key) {
            Set-Item -Path ("Env:{0}" -f $entry.Key) -Value $entry.Value
        }
    }

    if (-not (Test-Path -Path $ScanRootPath -PathType Container)) {
        Write-Warning "Custom path does not exist, skipping requirements scan: $ScanRootPath"
        return
    }

    $pythonCmd = Get-Command python -All -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notmatch '\\WindowsApps\\' } |
        Select-Object -First 1
    if (-not $pythonCmd) {
        $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    }

    $pyCmd = Get-Command py -All -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notmatch '\\WindowsApps\\' } |
        Select-Object -First 1
    if (-not $pyCmd) {
        $pyCmd = Get-Command py -ErrorAction SilentlyContinue
    }

    $pipCmd = Get-Command pip -All -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notmatch '\\WindowsApps\\' } |
        Select-Object -First 1
    if (-not $pipCmd) {
        $pipCmd = Get-Command pip -ErrorAction SilentlyContinue
    }
    $pythonCmdPath = $null
    if ($pythonCmd) {
        $pythonVersionOutput = & $pythonCmd.Source --version 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $pythonVersionOutput -match 'Python\s+\d') {
            $pythonCmdPath = $pythonCmd.Source
        }
    }

    $pyCmdPath = $null
    if ($pyCmd) {
        $pyVersionOutput = & $pyCmd.Source --version 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $pyVersionOutput -match 'Python\s+\d') {
            $pyCmdPath = $pyCmd.Source
        }
    }

    $pipCmdPath = $null
    if ($pipCmd) {
        $pipVersionOutput = & $pipCmd.Source --version 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $pipVersionOutput -match 'pip\s+\d') {
            $pipCmdPath = $pipCmd.Source
        }
    }
    $pipPrefixPath = Join-Path -Path $ScanRootPath -ChildPath 'python_scripts'
    $pipScriptsPath = Join-Path -Path $pipPrefixPath -ChildPath 'Scripts'
    $pipSitePackagesPath = Join-Path -Path $pipPrefixPath -ChildPath 'Lib\site-packages'
    Add-InstallerEnvironmentPathEntry -VariableName 'Path' -EntryPath $pipScriptsPath -CreateDirectory
    Add-InstallerEnvironmentPathEntry -VariableName 'PYTHONPATH' -EntryPath $pipSitePackagesPath -CreateDirectory
    Set-PipGlobalPrefix -PrefixPath $pipPrefixPath -PythonCommand $pythonCmdPath -PyCommand $pyCmdPath -PipCommand $pipCmdPath

    if ([string]::IsNullOrWhiteSpace($pythonCmdPath) -and [string]::IsNullOrWhiteSpace($pyCmdPath) -and [string]::IsNullOrWhiteSpace($pipCmdPath)) {
        throw 'No usable python/py/pip command is available after pymanager configuration.'
    }

    Write-Host "Pip prefix configured at: $pipPrefixPath" -ForegroundColor Green
    Write-InstallerLog -Message "Pip prefix configured at '$pipPrefixPath'"

    $requirementsFiles = Get-ChildItem -Path $ScanRootPath -File -Filter 'requirements.txt' -Recurse -ErrorAction SilentlyContinue |
        Sort-Object FullName

    if (-not $requirementsFiles) {
        Write-Host "No requirements.txt files found under: $ScanRootPath" -ForegroundColor Yellow
        Write-InstallerLog -Message "No requirements.txt files found under '$ScanRootPath'. Prefix configuration was applied; skipping package installation." -Level 'WARN'
        return
    }

    foreach ($requirementsFile in $requirementsFiles) {
        Write-Host "Installing pip packages from: $($requirementsFile.FullName)" -ForegroundColor Cyan
        Write-InstallerLog -Message "Installing pip requirements from '$($requirementsFile.FullName)'"

        if (-not [string]::IsNullOrWhiteSpace($pythonCmdPath)) {
            & $pythonCmdPath -m pip install --prefix $pipPrefixPath --no-warn-script-location -r $requirementsFile.FullName
        }
        elseif (-not [string]::IsNullOrWhiteSpace($pyCmdPath)) {
            & $pyCmdPath -m pip install --prefix $pipPrefixPath --no-warn-script-location -r $requirementsFile.FullName
        }
        else {
            & $pipCmdPath install --prefix $pipPrefixPath --no-warn-script-location -r $requirementsFile.FullName
        }

        if ($LASTEXITCODE -ne 0) {
            Write-InstallerLog -Message "pip install failed for '$($requirementsFile.FullName)'" -Level 'ERROR'
            throw "pip install failed for requirements file: $($requirementsFile.FullName)"
        }
    }
    Write-InstallerLog -Message 'Completed pip package installation'
}

function Invoke-UniGetUIInstall {
    param(
        [Parameter(Mandatory = $false)]
        [string]$SettingsUri = $script:UniGetUISettingsUri
    )

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-InstallerLog -Message 'winget was not found in PATH for UniGetUI installation' -Level 'ERROR'
        throw 'winget was not found in PATH.'
    }

    Write-Host 'Installing UniGetUI...' -ForegroundColor Cyan
    Write-InstallerLog -Message 'Running: winget install --exact --id Devolutions.UniGetUI --source winget'
    & winget install --exact --id Devolutions.UniGetUI --source winget
    if ($LASTEXITCODE -ne 0) {
        Write-InstallerLog -Message 'UniGetUI installation failed' -Level 'ERROR'
        throw 'UniGetUI installation failed.'
    }

    Write-InstallerLog -Message 'UniGetUI installation completed'

    if ([string]::IsNullOrWhiteSpace($SettingsUri)) {
        Write-InstallerLog -Message 'UniGetUI settings URI is empty; skipping settings import.' -Level 'WARN'
        Write-Host 'UniGetUI settings URI not configured. Skipping settings import.' -ForegroundColor Yellow
        return
    }

    $forensicosConfigDir = Join-Path -Path $env:ProgramData -ChildPath 'Forensicos'
    $settingsFilePath = Join-Path -Path $forensicosConfigDir -ChildPath 'unigetui-settings.json'
    $settingsImportPath = $null
    try {
        if (-not (Test-Path -Path $forensicosConfigDir -PathType Container)) {
            New-Item -Path $forensicosConfigDir -ItemType Directory -Force | Out-Null
        }

        try {
            Write-Host 'Downloading UniGetUI settings...' -ForegroundColor Cyan
            Write-InstallerLog -Message "Downloading UniGetUI settings from '$SettingsUri' to '$settingsFilePath'"
            Invoke-WebRequest -Uri $SettingsUri -OutFile $settingsFilePath -UseBasicParsing -ErrorAction Stop
            $settingsImportPath = $settingsFilePath
        }
        catch {
            Write-InstallerLog -Message "Failed to download UniGetUI settings from '$SettingsUri': $($_.Exception.Message)" -Level 'WARN'
            Write-Host "Warning: Failed to download UniGetUI settings. Select a local settings file to continue, or cancel to skip import." -ForegroundColor Yellow

            try {
                $settingsImportPath = Invoke-CustomPathSetup -PathType Leaf
                Write-InstallerLog -Message "User provided local UniGetUI settings file: '$settingsImportPath'"
            }
            catch {
                Write-InstallerLog -Message "UniGetUI settings file selection cancelled after download failure: $($_.Exception.Message)" -Level 'WARN'
                Write-Host 'UniGetUI settings import skipped.' -ForegroundColor Yellow
                return
            }
        }

        if ([string]::IsNullOrWhiteSpace($settingsImportPath)) {
            Write-InstallerLog -Message 'No UniGetUI settings file available for import; skipping settings import.' -Level 'WARN'
            Write-Host 'No UniGetUI settings file available. Skipping settings import.' -ForegroundColor Yellow
            return
        }

        $uniGetUiExe = $null
        $uniGetUiCommand = Get-Command -Name 'UniGetUI.exe' -ErrorAction SilentlyContinue
        if ($uniGetUiCommand) {
            $uniGetUiExe = $uniGetUiCommand.Source
        }
        else {
            $candidatePaths = @(
                (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs\UniGetUI\UniGetUI.exe'),
                (Join-Path -Path $env:ProgramFiles -ChildPath 'UniGetUI\UniGetUI.exe'),
                (Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'UniGetUI\UniGetUI.exe')
            )

            foreach ($candidatePath in $candidatePaths) {
                if (-not [string]::IsNullOrWhiteSpace($candidatePath) -and (Test-Path -Path $candidatePath -PathType Leaf)) {
                    $uniGetUiExe = $candidatePath
                    break
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($uniGetUiExe)) {
            throw 'UniGetUI executable not found after installation. Cannot import settings.'
        }

        Write-Host 'Importing UniGetUI settings...' -ForegroundColor Cyan
        Write-InstallerLog -Message "Importing UniGetUI settings with: $uniGetUiExe --import-settings $settingsImportPath"
        & $uniGetUiExe --import-settings $settingsImportPath
        if ($LASTEXITCODE -ne 0) {
            throw "UniGetUI settings import failed with exit code $LASTEXITCODE"
        }

        Write-Host 'UniGetUI settings imported successfully.' -ForegroundColor Green
        Write-InstallerLog -Message "UniGetUI settings imported successfully from '$settingsImportPath'"
    }
    catch {
        Write-InstallerLog -Message "UniGetUI settings import failed (continuing): $($_.Exception.Message)" -Level 'WARN'
        Write-Host "Warning: UniGetUI settings import failed. Continuing without settings import. $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Invoke-ChocolateyInstall {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallBasePath
    )

    $chocoInstallPath = Join-Path -Path $InstallBasePath -ChildPath 'chocolatey'

    # Set install location before running the installer so Chocolatey lands in the tools folder.
    $env:ChocolateyInstall = $chocoInstallPath
    Write-Host "Setting Chocolatey install path to: $chocoInstallPath" -ForegroundColor Cyan
    Write-InstallerLog -Message "Setting ChocolateyInstall env var to $chocoInstallPath"

    Write-Host 'Installing Chocolatey...' -ForegroundColor Cyan
    Write-InstallerLog -Message 'Running Chocolatey installer'
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        $chocoScript = Invoke-WebRequest -Uri 'https://community.chocolatey.org/install.ps1' -UseBasicParsing
        & ([scriptblock]::Create($chocoScript.Content))
        if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
            throw 'Chocolatey installer completed but choco command is not available.'
        }

        $machineChocolateyInstall = [Environment]::GetEnvironmentVariable('ChocolateyInstall', 'Machine')
        if ([string]::IsNullOrWhiteSpace($machineChocolateyInstall) -or $machineChocolateyInstall -ne $chocoInstallPath) {
            [Environment]::SetEnvironmentVariable('ChocolateyInstall', $chocoInstallPath, 'Machine')
            Write-InstallerLog -Message "ChocolateyInstall machine env var was missing or different; set to $chocoInstallPath"
        }
        else {
            Write-InstallerLog -Message "ChocolateyInstall machine env var already set to expected value: $machineChocolateyInstall"
        }
    }
    catch {
        Write-InstallerLog -Message "Chocolatey installation failed: $($_.Exception.Message)" -Level 'ERROR'
        throw "Chocolatey installation failed: $($_.Exception.Message)"
    }

    Write-InstallerLog -Message "Chocolatey installed at $chocoInstallPath"
    Write-Host "Chocolatey installed at: $chocoInstallPath" -ForegroundColor Green

    # Register Mandiant VM-Packages feed (FLARE-VM + Commando VM tools)
    Write-Host "Adding Chocolatey source: $script:MandiantChocoSourceName..." -ForegroundColor Cyan
    Write-InstallerLog -Message "Adding Chocolatey source '$script:MandiantChocoSourceName' -> '$script:MandiantChocoSourceUri'"
    try {
        & choco source add --name=$script:MandiantChocoSourceName --source=$script:MandiantChocoSourceUri
        if ($LASTEXITCODE -ne 0) {
            Write-InstallerLog -Message "Warning: choco source add for '$script:MandiantChocoSourceName' returned exit code $LASTEXITCODE" -Level 'WARN'
            Write-Host "Warning: Failed to add Chocolatey source '$script:MandiantChocoSourceName' (exit code $LASTEXITCODE)." -ForegroundColor Yellow
        }
        else {
            Write-Host "Chocolatey source '$script:MandiantChocoSourceName' added." -ForegroundColor Green
            Write-InstallerLog -Message "Chocolatey source '$script:MandiantChocoSourceName' added successfully."
        }
    }
    catch {
        Write-InstallerLog -Message "Warning: Exception adding Chocolatey source '$script:MandiantChocoSourceName': $($_.Exception.Message)" -Level 'WARN'
        Write-Host "Warning: Exception adding Chocolatey source '$script:MandiantChocoSourceName': $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Invoke-ScoopInstall {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallBasePath
    )

    $scoopDir = Join-Path -Path $InstallBasePath -ChildPath 'scoop'
    $scoopGlobalDir = Join-Path -Path $InstallBasePath -ChildPath 'scoop-global-apps'
    $scoopConfigHome = Join-Path -Path $scoopDir -ChildPath '.config'

    if (-not (Test-Path -Path $scoopDir -PathType Container)) {
        New-Item -Path $scoopDir -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path -Path $scoopGlobalDir -PathType Container)) {
        New-Item -Path $scoopGlobalDir -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path -Path $scoopConfigHome -PathType Container)) {
        New-Item -Path $scoopConfigHome -ItemType Directory -Force | Out-Null
    }

    # Set Scoop paths from the selected custom path instead of installer path parameters.
    [Environment]::SetEnvironmentVariable('SCOOP', $scoopDir, 'Machine')
    [Environment]::SetEnvironmentVariable('SCOOP_GLOBAL', $scoopGlobalDir, 'Machine')
    [Environment]::SetEnvironmentVariable('XDG_CONFIG_HOME', $scoopConfigHome, 'Machine')

    $env:SCOOP = $scoopDir
    $env:SCOOP_GLOBAL = $scoopGlobalDir
    $env:XDG_CONFIG_HOME = $scoopConfigHome

    Write-Host "Scoop directory: $scoopDir" -ForegroundColor Cyan
    Write-Host "Scoop global directory: $scoopGlobalDir" -ForegroundColor Cyan
    Write-Host "Scoop config home (XDG_CONFIG_HOME): $scoopConfigHome" -ForegroundColor Cyan
    Write-InstallerLog -Message "Configured Scoop env vars: SCOOP=$scoopDir; SCOOP_GLOBAL=$scoopGlobalDir; XDG_CONFIG_HOME=$scoopConfigHome"

    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Host 'Scoop is already installed. Keeping existing installation and configured paths.' -ForegroundColor Yellow
        Write-InstallerLog -Message 'Scoop command already available; skipped fresh installation.'
        return
    }

    Write-Host 'Installing Scoop...' -ForegroundColor Cyan
    Write-InstallerLog -Message 'Running Scoop installer from https://get.scoop.sh/'

    try {
        $scoopInstaller = Invoke-WebRequest -Uri 'https://get.scoop.sh/' -UseBasicParsing -ErrorAction Stop
        & ([scriptblock]::Create($scoopInstaller.Content)) -RunAsAdmin -Verbose
    }
    catch {
        Write-InstallerLog -Message "Scoop installation failed: $($_.Exception.Message)" -Level 'ERROR'
        throw "Scoop installation failed: $($_.Exception.Message)"
    }

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-InstallerLog -Message 'Scoop installer completed but scoop command is not available.' -Level 'ERROR'
        throw 'Scoop installer completed but scoop command is not available.'
    }

    Write-Host "Scoop installed using base path: $InstallBasePath" -ForegroundColor Green
    Write-InstallerLog -Message "Scoop installed successfully using base path: $InstallBasePath"

        # Install recommended Scoop packages
    $scoopPackages = @('main/scoop-search', 'main/git')
    foreach ($pkg in $scoopPackages) {
        Write-Host "Installing Scoop package: $pkg" -ForegroundColor Cyan
        Write-InstallerLog -Message "Installing Scoop package: $pkg"
        try {
            & scoop install $pkg
            if ($LASTEXITCODE -ne 0) {
                Write-InstallerLog -Message "Warning: scoop install $pkg returned exit code $LASTEXITCODE" -Level 'WARN'
                Write-Host "Warning: Installation of $pkg returned exit code $LASTEXITCODE" -ForegroundColor Yellow
            }
        }
        catch {
            Write-InstallerLog -Message "Warning: Failed to install $pkg : $($_.Exception.Message)" -Level 'WARN'
            Write-Host "Warning: Failed to install $pkg : $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # Add Scoop buckets
    Write-Host "Adding Scoop extras bucket..." -ForegroundColor Cyan
    Write-InstallerLog -Message "Adding Scoop extras bucket"
    try {
        & scoop bucket add extras
        if ($LASTEXITCODE -ne 0) {
            Write-InstallerLog -Message "Warning: scoop bucket add extras returned exit code $LASTEXITCODE" -Level 'WARN'
            Write-Host "Warning: Scoop bucket add extras returned exit code $LASTEXITCODE" -ForegroundColor Yellow
        }
    }
    catch {
        Write-InstallerLog -Message "Warning: Failed to add extras bucket: $($_.Exception.Message)" -Level 'WARN'
        Write-Host "Warning: Failed to add extras bucket: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-InstallerLog -Message 'Scoop packages installation completed'
}

function Install-ForensicOSLinkerModule {
    param(
        [Parameter(Mandatory = $false)]
        [string]$ModuleUri = $script:ForensicOSLinkerModuleUri,
        [string]$ModulePsd1Uri = $script:ForensicOSLinkerModulePsd1Uri,
        [string]$ModulePsm1Uri = $script:ForensicOSLinkerModulePsm1Uri
    )

    $moduleName = 'ForensicOS.Linker'
    $backupRoot = Join-Path -Path $env:ProgramData -ChildPath "Forensicos\Modules\$moduleName"
    $backupModulePsm1 = Join-Path -Path $backupRoot -ChildPath "$moduleName.psm1"
    $backupModulePsd1 = Join-Path -Path $backupRoot -ChildPath "$moduleName.psd1"
    $allUsersModuleRoot = Join-Path -Path $env:ProgramFiles -ChildPath "WindowsPowerShell\Modules\$moduleName"
    $allUsersModulePsm1 = Join-Path -Path $allUsersModuleRoot -ChildPath "$moduleName.psm1"
    $allUsersModulePsd1 = Join-Path -Path $allUsersModuleRoot -ChildPath "$moduleName.psd1"

    # Check if module is already loaded
    if (Get-Module -Name $moduleName -ErrorAction SilentlyContinue) {
        Write-Host "Module '$moduleName' is already loaded." -ForegroundColor Yellow
        Write-InstallerLog -Message "Module '$moduleName' is already loaded; skipping installation."
        return
    }

    # Check if module is already installed
    if (Get-Module -Name $moduleName -ListAvailable -ErrorAction SilentlyContinue) {
        Write-Host "Module '$moduleName' is already installed. Importing..." -ForegroundColor Yellow
        Write-InstallerLog -Message "Module '$moduleName' is already installed; importing."
        try {
            Import-Module -Name $moduleName -Force -ErrorAction Stop
            Write-Host "Module '$moduleName' imported successfully." -ForegroundColor Green
            Write-InstallerLog -Message "Module '$moduleName' imported successfully."
            return
        }
        catch {
            Write-InstallerLog -Message "Failed to import existing module: $($_.Exception.Message)" -Level 'WARN'
            Write-Host "Warning: Failed to import existing module. Attempting fresh installation..." -ForegroundColor Yellow
        }
    }

    Write-Host 'Installing ForensicOS linker module...' -ForegroundColor Cyan

    # Ensure NuGet provider is available (required for PowerShell Gallery)
    try {
        Write-InstallerLog -Message "Ensuring NuGet provider is available"
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop | Out-Null
    }
    catch {
        Write-InstallerLog -Message "Warning: NuGet provider installation failed: $($_.Exception.Message)"
    }

    # Primary method: Install from PowerShell Gallery
    try {
        Write-InstallerLog -Message "Attempting to install module '$moduleName' from PowerShell Gallery"
        Install-Module -Name $moduleName -Force -ErrorAction Stop
        Import-Module -Name $moduleName -Force -ErrorAction Stop
        Write-InstallerLog -Message "Module '$moduleName' installed and imported successfully from PowerShell Gallery"
        Write-Host "Installed module: $moduleName (from PowerShell Gallery)" -ForegroundColor Green
        return
    }
    catch {
        Write-InstallerLog -Message "Gallery installation failed: $($_.Exception.Message). Falling back to manual installation."
    }

    # Fallback method: Download and manual install
    $resolvedPsd1Uri = $null
    $resolvedPsm1Uri = $null

    if (-not [string]::IsNullOrWhiteSpace($ModulePsd1Uri) -and -not [string]::IsNullOrWhiteSpace($ModulePsm1Uri)) {
        $resolvedPsd1Uri = $ModulePsd1Uri.Trim()
        $resolvedPsm1Uri = $ModulePsm1Uri.Trim()
        Write-InstallerLog -Message "Using explicit module file URIs for fallback download."
    }
    elseif (-not [string]::IsNullOrWhiteSpace($ModuleUri)) {
        $trimmedModuleUri = $ModuleUri.TrimEnd('/')
        $resolvedPsd1Uri = "$trimmedModuleUri/$moduleName.psd1"
        $resolvedPsm1Uri = "$trimmedModuleUri/$moduleName.psm1"
    }

    if ([string]::IsNullOrWhiteSpace($resolvedPsd1Uri) -or [string]::IsNullOrWhiteSpace($resolvedPsm1Uri)) {
        Write-InstallerLog -Message "Module URI is not configured for fallback installation." -Level 'WARN'
        Write-Host "Warning: Module URI is not configured. Skipping module installation." -ForegroundColor Yellow
        return
    }

    Write-InstallerLog -Message "Downloading module files from explicit paths for fallback installation"

    try {
        if (-not (Test-Path -Path $backupRoot -PathType Container)) {
            New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null
        }

        if (-not (Test-Path -Path $allUsersModuleRoot -PathType Container)) {
            New-Item -Path $allUsersModuleRoot -ItemType Directory -Force | Out-Null
        }

        # Download both .psm1 and .psd1 files
        $filesToDownload = @(
            @{ Uri = $resolvedPsm1Uri; OutFile = $backupModulePsm1 },
            @{ Uri = $resolvedPsd1Uri; OutFile = $backupModulePsd1 }
        )

        foreach ($file in $filesToDownload) {
            try {
                Write-InstallerLog -Message "Downloading $($file.OutFile | Split-Path -Leaf)"
                Invoke-WebRequest -Uri $file.Uri -OutFile $file.OutFile -UseBasicParsing -ErrorAction Stop

                if (-not (Test-Path -Path $file.OutFile -PathType Leaf)) {
                    throw "Download did not create file: $($file.OutFile)"
                }

                $downloadedFile = Get-Item -Path $file.OutFile -ErrorAction Stop
                if ($downloadedFile.Length -le 0) {
                    throw "Downloaded file is empty: $($file.OutFile)"
                }

                Write-InstallerLog -Message "Downloaded $($downloadedFile.Name) ($($downloadedFile.Length) bytes)"
            }
            catch {
                Write-InstallerLog -Message "Download failed for $($file.OutFile): $($_.Exception.Message)" -Level 'WARN'
                Write-Host "Warning: Failed to download module file. Skipping module installation." -ForegroundColor Yellow
                return
            }
        }

        if (-not (Test-Path -Path $backupModulePsm1 -PathType Leaf) -or -not (Test-Path -Path $backupModulePsd1 -PathType Leaf)) {
            Write-InstallerLog -Message "Module fallback download incomplete. Missing required files in $backupRoot" -Level 'WARN'
            Write-Host "Warning: Module fallback download incomplete. Skipping module installation." -ForegroundColor Yellow
            return
        }

        # Copy files to all-users module location
        Copy-Item -Path $backupModulePsm1 -Destination $allUsersModulePsm1 -Force -ErrorAction Stop
        Copy-Item -Path $backupModulePsd1 -Destination $allUsersModulePsd1 -Force -ErrorAction Stop
        Write-InstallerLog -Message "Module files copied to $allUsersModuleRoot"
        
        Import-Module -Name $moduleName -Force -ErrorAction Stop
        Write-InstallerLog -Message "Module '$moduleName' imported successfully"
        Write-Host "Installed module: $moduleName (fallback from explicit file URIs)" -ForegroundColor Green
    }
    catch {
        Write-InstallerLog -Message "Module installation/import failed: $($_.Exception.Message)" -Level 'WARN'
        Write-Host "Warning: Module installation failed, but continuing with installation. $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Invoke-PyPathSetup {
    $profilePath = $PROFILE
    $profileDir = Split-Path -Path $profilePath -Parent
    $profileLine = '$env:PATHEXT += ";.PY"'

    if (-not (Test-Path -Path $profileDir -PathType Container)) {
        New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path -Path $profilePath -PathType Leaf)) {
        New-Item -Path $profilePath -ItemType File -Force | Out-Null
        Write-Host "Created profile file: $profilePath" -ForegroundColor Green
    }

    $profileContent = Get-Content -Path $profilePath -ErrorAction SilentlyContinue
    if ($profileContent -notcontains $profileLine) {
        Add-Content -Path $profilePath -Value $profileLine
        Write-Host 'Added .PY PATHEXT entry to PowerShell profile.' -ForegroundColor Green
        Write-InstallerLog -Message 'Added .PY PATHEXT entry to profile'
    }
    else {
        Write-Host '.PY PATHEXT entry already exists in PowerShell profile.' -ForegroundColor Yellow
        Write-InstallerLog -Message '.PY PATHEXT entry already existed in profile'
    }
}

function Invoke-HtmlPathSetup {
    $profilePath = $PROFILE
    $profileDir = Split-Path -Path $profilePath -Parent
    $profileLine = '$env:PATHEXT += ";.HTML"'

    if (-not (Test-Path -Path $profileDir -PathType Container)) {
        New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path -Path $profilePath -PathType Leaf)) {
        New-Item -Path $profilePath -ItemType File -Force | Out-Null
        Write-Host "Created profile file: $profilePath" -ForegroundColor Green
    }

    $profileContent = Get-Content -Path $profilePath -ErrorAction SilentlyContinue
    if ($profileContent -notcontains $profileLine) {
        Add-Content -Path $profilePath -Value $profileLine
        Write-Host 'Added .HTML PATHEXT entry to PowerShell profile.' -ForegroundColor Green
        Write-InstallerLog -Message 'Added .HTML PATHEXT entry to profile'
    }
    else {
        Write-Host '.HTML PATHEXT entry already exists in PowerShell profile.' -ForegroundColor Yellow
        Write-InstallerLog -Message '.HTML PATHEXT entry already existed in profile'
    }
}

function Invoke-DebloaterScript {
    $debloatUrl = 'https://debloat.raphi.re/'

    Write-Host "Running Win11Debloat from latest version at: $debloatUrl" -ForegroundColor Cyan
    Write-Host 'Default mode: -Silent -CreateRestorePoint' -ForegroundColor Cyan
    Write-InstallerLog -Message "Running Win11Debloat from $debloatUrl with -Silent -CreateRestorePoint -RunDefaults"

    try {
        & ([scriptblock]::Create((irm $debloatUrl))) -Silent -CreateRestorePoint -RunDefaults
    }
    catch {
        Write-InstallerLog -Message "Debloater execution failed: $($_.Exception.Message)" -Level 'ERROR'
        throw "Debloater execution failed: $($_.Exception.Message)"
    }
}

function Invoke-SansDfirPosterDownload {
    $desktopPath = [Environment]::GetFolderPath('Desktop')
    $targetFolder = Join-Path -Path $desktopPath -ChildPath 'DFIR-SANS-POSTERS'

    if (-not (Test-Path -Path $targetFolder -PathType Container)) {
        New-Item -Path $targetFolder -ItemType Directory -Force | Out-Null
    }

    $pdfList = @(
        @{ Filename = 'Poster_Threat-Intelligence-Consumption.pdf'; Source = 'https://assets.contentstack.io/v3/assets/blt36c2e63521272fdc/blt85ecf5919805e543/Threat_Intel_Poster.pdf' },
        @{ Filename = 'Network-Forensics-Poster.pdf'; Source = 'https://assets.contentstack.io/v3/assets/blt36c2e63521272fdc/bltf474461c7e1bc333/Network_Forensis_Poster.pdf' },
        @{ Filename = 'SIFT-REMnux-Poster.pdf'; Source = 'https://assets.contentstack.io/v3/assets/blt36c2e63521272fdc/blt1bc0b6b59a82bfa5/SIFT_&_REMnux_Poster.pdf' },
        @{ Filename = 'DFIR-Smartphone-Forensics-Poster.pdf'; Source = 'https://assets.contentstack.io/v3/assets/blt36c2e63521272fdc/blt83bf07bbc4a716d9/Smartphone_Forensics_Poster.pdf' },
        @{ Filename = 'Windows-Forensics-Poster.pdf'; Source = 'https://assets.contentstack.io/v3/assets/blt36c2e63521272fdc/bltc39305369fb54116/Windows_Forensic_Poster.pdf' },
        @{ Filename = 'iOS-3rd-Party-Apps-Poster.pdf'; Source = 'https://assets.contentstack.io/v3/assets/blt36c2e63521272fdc/bltad8650d3ff00e675/iOS_Third_Party_Forensic_Poster.pdf' },
        @{ Filename = 'Zimmerman-Tools-Poster.pdf'; Source = 'https://assets.contentstack.io/v3/assets/blt36c2e63521272fdc/blt83d26bfaab457108/EZ_Tools_Poster.pdf' },
        @{ Filename = 'Hunt-Evil.pdf'; Source = 'https://assets.contentstack.io/v3/assets/blt36c2e63521272fdc/blt251af6afae29ea60/Hunt_Evil_Poster.pdf' },
        @{ Filename = 'SIFT-Cheatsheet.pdf'; Source = 'https://assets.contentstack.io/v3/assets/blt36c2e63521272fdc/blt67fa8fb616555ec1/SIFT_WorkStation_CHeat_Sheet.pdf' },
        @{ Filename = 'Windows-to-Unix-Cheatsheet.pdf'; Source = 'https://assets.contentstack.io/v3/assets/blt36c2e63521272fdc/blt0f47176890413e4d/Windows_to_Unix_Cheat_Sheet.pdf' },
        @{ Filename = 'Hex-File-Regex-Cheatsheet.pdf'; Source = 'https://assets.contentstack.io/v3/assets/blt36c2e63521272fdc/blt925c54638a43145c/Hex_and_Regex_Forensics_Cheat_Sheet.pdf' },
        @{ Filename = 'SQLite-Pocket-Reference.pdf'; Source = 'https://assets.contentstack.io/v3/assets/blt36c2e63521272fdc/blt4698e96e2d9cf51d/SQlite_Cheat_Sheet.pdf' }
    )

    Write-Host "Downloading SANS DFIR PDFs to: $targetFolder" -ForegroundColor Cyan
    Write-InstallerLog -Message "Downloading SANS DFIR PDFs to '$targetFolder'"

    $downloadFailures = 0
    foreach ($pdf in $pdfList) {
        $destinationPath = Join-Path -Path $targetFolder -ChildPath $pdf.Filename
        Write-Host "Downloading $($pdf.Filename)..." -ForegroundColor Cyan
        Write-InstallerLog -Message "Downloading SANS DFIR PDF '$($pdf.Filename)' from '$($pdf.Source)'"

        try {
            Invoke-WebRequest -Uri $pdf.Source -OutFile $destinationPath -UseBasicParsing -ErrorAction Stop
            Write-InstallerLog -Message "Downloaded SANS DFIR PDF to '$destinationPath'"
        }
        catch {
            $downloadFailures++
            Write-InstallerLog -Message "Failed to download SANS DFIR PDF '$($pdf.Filename)': $($_.Exception.Message)" -Level 'WARN'
            Write-Host "Warning: Failed to download $($pdf.Filename)." -ForegroundColor Yellow
        }
    }

    if ($downloadFailures -gt 0) {
        Write-Host "Completed SANS DFIR PDF downloads with $downloadFailures warning(s)." -ForegroundColor Yellow
        Write-InstallerLog -Message "Completed SANS DFIR PDF downloads with $downloadFailures warning(s)." -Level 'WARN'
    }
    else {
        Write-Host 'Completed SANS DFIR PDF downloads successfully.' -ForegroundColor Green
        Write-InstallerLog -Message 'Completed SANS DFIR PDF downloads successfully.'
    }
}

function Invoke-WallpaperSetup {
    # Detect primary monitor resolution; fall back to 1920x1080 if detection fails.
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $screenBounds = try { [System.Windows.Forms.Screen]::PrimaryScreen.Bounds } catch { $null }
    $screenWidth  = if ($screenBounds -and $screenBounds.Width  -gt 0) { $screenBounds.Width  } else { 1920 }
    $screenHeight = if ($screenBounds -and $screenBounds.Height -gt 0) { $screenBounds.Height } else { 1080 }

    $wallpaperBaseUrl = 'https://images.contentstack.io/v3/assets/bltabe50a4554f8e97f/blt7c9060ef50ceecab/681b2b246a96c03518561fa7/SANS-WEB_Cyber-Ranges-Page-DFIR-Netwars-Cont_1104_x_636.jpg'
    $wallpaperUrl     = "${wallpaperBaseUrl}?width=${screenWidth}&height=${screenHeight}&quality=90&format=png"
    $wallpaperPath    = Join-Path -Path $env:ProgramData -ChildPath 'Forensicos\wallpaper.png'
    $wallpaperDir     = Split-Path -Path $wallpaperPath -Parent

    Write-Host "Detected primary monitor resolution: ${screenWidth}x${screenHeight} px" -ForegroundColor Cyan
    Write-InstallerLog -Message "Detected primary monitor resolution ${screenWidth}x${screenHeight}"

    # Ensure destination directory exists
    if (-not (Test-Path -Path $wallpaperDir -PathType Container)) {
        New-Item -Path $wallpaperDir -ItemType Directory -Force | Out-Null
    }

    Write-Host 'Downloading wallpaper...' -ForegroundColor Cyan
    Write-InstallerLog -Message "Downloading wallpaper from $wallpaperUrl"
    try {
        Invoke-WebRequest -Uri $wallpaperUrl -OutFile $wallpaperPath -UseBasicParsing
    }
    catch {
        throw "Failed to download wallpaper: $($_.Exception.Message)"
    }

    # --- Desktop wallpaper (current user, no elevation required) ---
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
'@
    $SPI_SETDESKWALLPAPER = 0x0014
    $SPIF_UPDATEINIFILE   = 0x01
    $SPIF_SENDCHANGE      = 0x02
    [Wallpaper]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $wallpaperPath, $SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE) | Out-Null
    Write-Host 'Desktop wallpaper set.' -ForegroundColor Green
    Write-InstallerLog -Message "Desktop wallpaper set to $wallpaperPath"

    # --- Lock screen wallpaper (requires Administrator) ---
    # Uses the PersonalizationCSP registry path, the standard documented method for
    # setting the lock screen image on Windows 10/11 without external tools.
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin) {
        $cspPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
        if (-not (Test-Path -Path $cspPath)) {
            New-Item -Path $cspPath -Force | Out-Null
        }
        Set-ItemProperty -Path $cspPath -Name 'LockScreenImagePath'   -Value $wallpaperPath -Type String -Force
        Set-ItemProperty -Path $cspPath -Name 'LockScreenImageUrl'    -Value $wallpaperPath -Type String -Force
        Set-ItemProperty -Path $cspPath -Name 'LockScreenImageStatus' -Value 1              -Type DWord  -Force
        Write-Host 'Lock screen wallpaper set.' -ForegroundColor Green
        Write-InstallerLog -Message "Lock screen wallpaper set to $wallpaperPath"
    }
    else {
        Write-Host 'Skipped lock screen: script is not running as Administrator.' -ForegroundColor Yellow
        Write-InstallerLog -Message 'Skipped lock screen wallpaper update (not running as Administrator)' -Level 'WARN'
    }
}

function Invoke-DesktopShortcut {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    if (-not (Test-Path -Path $TargetPath -PathType Container)) {
        New-Item -Path $TargetPath -ItemType Directory -Force | Out-Null
        Write-Host "Created installation folder: $TargetPath" -ForegroundColor Green
    }

    $desktopPath  = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path -Path $desktopPath -ChildPath 'Forensicos Tools.lnk'
    $shell        = New-Object -ComObject WScript.Shell
    $shortcut     = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath  = $TargetPath
    $shortcut.Description = 'Forensicos Tools installation folder'
    $shortcut.Save()
    Write-Host "Desktop shortcut created: $shortcutPath" -ForegroundColor Green
    Write-InstallerLog -Message "Desktop shortcut created at $shortcutPath for target $TargetPath"
}

# -------

Write-Host 'Welcome to Forensicos installer'
Write-Host 'Use Space to select additional steps, Enter to continue, and Esc to cancel.'
Write-Host ''

# --- Step 1: Bundle selection ---
Write-Host '--- Package Bundle Selection ---' -ForegroundColor Cyan
$bundleConfig = Get-BundleConfig
$selectedBundlePath = $null
$selectedBundleRequiredManagers = @()
$localFileLabel = 'Select local file'

if ($bundleConfig.NetworkFailed) {
    Write-Host "Note: Could not reach bundle configuration. If this is due to a general network issue, multiple installation errors may occur." -ForegroundColor Yellow
}

# Build menu: remote bundles (if any) + always a local file option
$bundleMenuItems = @()
$localFileMenuLabel = "${localFileLabel} [required package managers: depends on selected .ubundle file]"
if ($bundleConfig.Bundles.Count -gt 0) {
    foreach ($bundle in $bundleConfig.Bundles) {
        $description = "$($bundle.Description)"
        if ([string]::IsNullOrWhiteSpace($description)) {
            $description = 'Unnamed bundle'
        }

        $requiredManagers = @()
        if ($null -ne $bundle.RequiredManagers) {
            $requiredManagers = @($bundle.RequiredManagers | ForEach-Object { "$_".Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }

        $requirementsNote = if ($requiredManagers.Count -gt 0) {
            $requiredManagers -join ', '
        }
        else {
            'not specified'
        }

        $bundleMenuItems += "$description [required package managers: $requirementsNote]"
    }
}
$bundleMenuItems += $localFileMenuLabel

Write-Host "Select a package bundle to install:" -ForegroundColor Cyan
$bundleIndex = Show-Menu -MenuItems $bundleMenuItems -ReturnIndex

if ($null -eq $bundleIndex) {
    Write-Host "Bundle selection cancelled. No packages from bundle will be installed." -ForegroundColor Yellow
    Write-InstallerLog -Message 'User cancelled bundle selection.' -Level 'WARN'
}
elseif ($bundleIndex -ge $bundleConfig.Bundles.Count) {
    try {
        $selectedBundlePath = Invoke-CustomPathSetup -PathType Leaf
        Write-InstallerLog -Message "User provided local bundle file: '$selectedBundlePath'"
    }
    catch {
        Write-Host "File selection cancelled. Bundle installation will be skipped." -ForegroundColor Yellow
        Write-InstallerLog -Message "Bundle file selection cancelled: $($_.Exception.Message)" -Level 'WARN'
    }
}
else {
    $selectedBundleEntry = $bundleConfig.Bundles[$bundleIndex]
    $selectedBundlePath = $selectedBundleEntry.BundleUrl

    if ($null -ne $selectedBundleEntry.RequiredManagers) {
        $selectedBundleRequiredManagers = @($selectedBundleEntry.RequiredManagers | ForEach-Object { "$_".Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    Write-Host "Selected bundle: $($selectedBundleEntry.Description)" -ForegroundColor Green
    Write-InstallerLog -Message "User selected bundle: '$($selectedBundleEntry.Description)' -> '$selectedBundlePath'"

}

# --- Step 2: Additional options ---
Write-Host ''

# Define menu options
$menuItems = @(
    "Define custom install path",
    "Install pip packages",
    "Install Chocolatey",
    "Install Scoop",
    "Install UniGetUI",
    "Add .py to executable paths for python script execution",
    "Add .html to executable paths for python script execution",
    "Use debloater script for Windows",
    "Download SANS DFIR posters",
    "Set forensic workstation wallpaper"
)

# Show menu and capture selection
$selectedItems = Show-Menu $menuItems -MultiSelect

# Check if user cancelled
if ($null -eq $selectedItems) {
    Write-Host "Installation cancelled."
    exit
}

# Set boolean flags based on selections for easy triggering of functions
$installConfig = @{
    CustomPath = $selectedItems -contains "Define custom install path"
    PipPackages = $selectedItems -contains "Install pip packages"
    Chocolatey = $selectedItems -contains "Install Chocolatey"
    Scoop = $selectedItems -contains "Install Scoop"
    UniGetUI = $selectedItems -contains "Install UniGetUI"
    PyPath = $selectedItems -contains "Add .py to executable paths for python script execution"
    HtmlPath = $selectedItems -contains "Add .html to executable paths for python script execution"
    Debloater = $selectedItems -contains "Use debloater script for Windows"
    SansPosters = $selectedItems -contains "Download SANS DFIR posters"
    Wallpaper = $selectedItems -contains "Set forensic workstation wallpaper"
    SelectedItems = $selectedItems
}

$EmojiIcon = [System.Convert]::toInt32("2705",16)

# Display confirmation of selections
Write-Host "`nSelected options:"
if ($installConfig.CustomPath) { Write-Host ([System.Char]::ConvertFromUtf32($EmojiIcon)) -NoNewline
    Write-Host " Define custom install path" }
if ($installConfig.PipPackages) { Write-Host ([System.Char]::ConvertFromUtf32($EmojiIcon)) -NoNewline
    Write-Host " Install pip packages" }
if ($installConfig.Chocolatey) { Write-Host ([System.Char]::ConvertFromUtf32($EmojiIcon)) -NoNewline
    Write-Host " Install Chocolatey" }
if ($installConfig.Scoop) { Write-Host ([System.Char]::ConvertFromUtf32($EmojiIcon)) -NoNewline
    Write-Host " Install Scoop" }
if ($installConfig.UniGetUI) { Write-Host ([System.Char]::ConvertFromUtf32($EmojiIcon)) -NoNewline
    Write-Host " Install UniGetUI" }
if ($installConfig.PyPath) { Write-Host ([System.Char]::ConvertFromUtf32($EmojiIcon)) -NoNewline
    Write-Host " Add .py to executable paths" }
if ($installConfig.HtmlPath) { Write-Host ([System.Char]::ConvertFromUtf32($EmojiIcon)) -NoNewline
    Write-Host " Add .html to executable paths" }
if ($installConfig.Debloater) { Write-Host ([System.Char]::ConvertFromUtf32($EmojiIcon)) -NoNewline
    Write-Host " Use debloater script" }
if ($installConfig.SansPosters) { Write-Host ([System.Char]::ConvertFromUtf32($EmojiIcon)) -NoNewline
    Write-Host " Download SANS DFIR posters" }
if ($installConfig.Wallpaper) { Write-Host ([System.Char]::ConvertFromUtf32($EmojiIcon)) -NoNewline
    Write-Host " Set forensic workstation wallpaper" }
Write-Host ""

# Initialize variables for each option
$customPath = "C:\tools"

# Execute selected options
if ($installConfig.CustomPath) { 
    $customPath = Invoke-CustomPathSetup
}

Initialize-InstallerLog -BasePath $customPath
Start-InstallerConsoleTranscript -BasePath $customPath

try {
    Reset-InstallerExecutionSummary
    Write-InstallerLog -Message ("Selected options: {0}" -f ($installConfig.SelectedItems -join '; '))
    Set-ForensicOSToolsBasePath -BasePath $customPath

    try {
        # Disable SmartScreen before installation actions.
        Set-SmartScreenState -Enabled $false

        Invoke-TrackedInstallerAction -ActionName 'Install pip packages' -ShouldRun ([bool]$installConfig.PipPackages) -Action {
            Invoke-PipPackageInstall -ScanRootPath $customPath
        }

        Invoke-TrackedInstallerAction -ActionName 'Install Chocolatey' -ShouldRun ([bool]$installConfig.Chocolatey) -Action {
            Invoke-ChocolateyInstall -InstallBasePath $customPath
            Install-ForensicOSLinkerModule
        }

        Invoke-TrackedInstallerAction -ActionName 'Install Scoop' -ShouldRun ([bool]$installConfig.Scoop) -Action {
            Invoke-ScoopInstall -InstallBasePath $customPath
            Install-ForensicOSLinkerModule
        }

        Invoke-TrackedInstallerAction -ActionName 'Install UniGetUI' -ShouldRun ([bool]$installConfig.UniGetUI) -Action {
            Invoke-UniGetUIInstall
        }

        Invoke-TrackedInstallerAction -ActionName 'Install packages from bundle' -ShouldRun $true -Action {
            Invoke-PackageBundleInstall -InstallBasePath $customPath -InstallConfig $installConfig -BundlePath $selectedBundlePath
        }

        Invoke-TrackedInstallerAction -ActionName 'Create desktop shortcut' -ShouldRun $true -Action {
            Invoke-DesktopShortcut -TargetPath $customPath
        }

        Invoke-TrackedInstallerAction -ActionName 'Add .py to executable paths' -ShouldRun ([bool]$installConfig.PyPath) -Action {
            Invoke-PyPathSetup
        }

        Invoke-TrackedInstallerAction -ActionName 'Add .html to executable paths' -ShouldRun ([bool]$installConfig.HtmlPath) -Action {
            Invoke-HtmlPathSetup
        }

        Invoke-TrackedInstallerAction -ActionName 'Use debloater script for Windows' -ShouldRun ([bool]$installConfig.Debloater) -Action {
            Invoke-DebloaterScript
        }

        Invoke-TrackedInstallerAction -ActionName 'Download SANS DFIR posters' -ShouldRun ([bool]$installConfig.SansPosters) -Action {
            Invoke-SansDfirPosterDownload
        }

        Invoke-TrackedInstallerAction -ActionName 'Set forensic workstation wallpaper' -ShouldRun ([bool]$installConfig.Wallpaper) -Action {
            Invoke-WallpaperSetup
        }
    }
    finally {
        # Re-enable SmartScreen after installation actions.
        Set-SmartScreenState -Enabled $true
    }

    Write-InstallerExecutionSummary

    Write-InstallerLog -Message 'All actions completed successfully. Reboot scheduled in 10 seconds.'
    Write-InstallerLog -Message 'Hint: Use UniGetUI to manage installed packages and updates.'
    Write-Host "Log file created: $script:InstallerLogPath" -ForegroundColor Green
    Write-Host "Console transcript file: $script:InstallerConsoleTranscriptPath" -ForegroundColor Green
    Write-Host "Hint: Use UniGetUI to manage installed packages and updates." -ForegroundColor Cyan
    Write-Host "`nAll done! The system will reboot in 10 seconds..." -ForegroundColor Green
    Start-Sleep -Seconds 10
}
finally {
    Stop-InstallerConsoleTranscript
}

Restart-Computer -Force

