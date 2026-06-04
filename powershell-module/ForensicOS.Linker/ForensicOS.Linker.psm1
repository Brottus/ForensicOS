function Test-PathEntryInValue {
    param(
        [string]$PathValue,
        [Parameter(Mandatory = $true)]
        [string]$EntryPath
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $false
    }

    $normalizedEntry = $EntryPath.Trim().TrimEnd('\\')
    if ([string]::IsNullOrWhiteSpace($normalizedEntry)) {
        return $false
    }

    $entries = @($PathValue -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($entry in $entries) {
        if ($entry.Trim().TrimEnd('\\') -ieq $normalizedEntry) {
            return $true
        }
    }

    return $false
}

function Get-ForensicOSToolsBasePath {
    $processValue = [Environment]::GetEnvironmentVariable('ForensicOSToolsBasePath', 'Process')
    if (-not [string]::IsNullOrWhiteSpace($processValue)) {
        return [System.IO.Path]::GetFullPath($processValue.Trim())
    }

    $userValue = [Environment]::GetEnvironmentVariable('ForensicOSToolsBasePath', 'User')
    if (-not [string]::IsNullOrWhiteSpace($userValue)) {
        return [System.IO.Path]::GetFullPath($userValue.Trim())
    }

    $machineValue = [Environment]::GetEnvironmentVariable('ForensicOSToolsBasePath', 'Machine')
    if (-not [string]::IsNullOrWhiteSpace($machineValue)) {
        return [System.IO.Path]::GetFullPath($machineValue.Trim())
    }

    return 'C:\tools'
}

function Add-PathEntryToScope {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EntryPath,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Process', 'User', 'Machine')]
        [string]$Scope
    )

    $currentValue = [Environment]::GetEnvironmentVariable('Path', $Scope)
    if (Test-PathEntryInValue -PathValue $currentValue -EntryPath $EntryPath) {
        return
    }

    $newValue = if ([string]::IsNullOrWhiteSpace($currentValue)) {
        $EntryPath
    }
    else {
        "$currentValue;$EntryPath"
    }

    [Environment]::SetEnvironmentVariable('Path', $newValue, $Scope)
}

function Remove-PathEntryFromScope {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EntryPath,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Process', 'User', 'Machine')]
        [string]$Scope
    )

    $currentValue = [Environment]::GetEnvironmentVariable('Path', $Scope)
    if ([string]::IsNullOrWhiteSpace($currentValue)) {
        return
    }

    $normalizedEntry = $EntryPath.Trim().TrimEnd('\\')
    $remainingEntries = @()

    $entries = @($currentValue -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($entry in $entries) {
        if ($entry.Trim().TrimEnd('\\') -ine $normalizedEntry) {
            $remainingEntries += $entry
        }
    }

    [Environment]::SetEnvironmentVariable('Path', ($remainingEntries -join ';'), $Scope)
}

function Add-LinkPathToPathIfSourceMissing {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$LinkPath
    )

    $resolvedSourcePath = (Resolve-Path -Path $SourcePath -ErrorAction Stop).ProviderPath
    $resolvedLinkPath = (Resolve-Path -Path $LinkPath -ErrorAction Stop).ProviderPath

    $processPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $effectivePath = @($processPath, $userPath, $machinePath) -join ';'

    if (Test-PathEntryInValue -PathValue $effectivePath -EntryPath $resolvedSourcePath) {
        Write-Host "Source path already in PATH, no link path update needed: $resolvedSourcePath"
        return
    }

    if (Test-PathEntryInValue -PathValue $effectivePath -EntryPath $resolvedLinkPath) {
        Write-Host "Link path already in PATH: $resolvedLinkPath"
        return
    }

    Add-PathEntryToScope -EntryPath $resolvedLinkPath -Scope 'Machine'
    Add-PathEntryToScope -EntryPath $resolvedLinkPath -Scope 'User'
    Add-PathEntryToScope -EntryPath $resolvedLinkPath -Scope 'Process'
    Write-Host "Added link path to PATH: $resolvedLinkPath" -ForegroundColor Green
}

function Add-WingetInstallPathToPath {
    <#
    .SYNOPSIS
    Adds a winget package install path to PATH when missing.

    .DESCRIPTION
    Normalizes and validates a winget package install path, checks whether it already exists in PATH
    across Process, User, and Machine scopes, and only adds it when not present in any scope.
    This is useful for packages installed to custom locations where executables are not automatically
    discoverable by command lookup.

    .PARAMETER InstallPath
    The installation directory to add to PATH.

    .PARAMETER PackageName
    Winget package folder name under CustomPath. When provided, the install path is derived as
    CustomPath\Category\PackageName (or CustomPath\PackageName when Category is omitted).

    .PARAMETER CustomPath
    Base path used with PackageName. Defaults to 'C:\tools'.

    .PARAMETER Category
    Optional subfolder under CustomPath used with PackageName.

    .EXAMPLE
    Add-WingetInstallPathToPath -InstallPath C:\Tools\MyApp
    Adds C:\Tools\MyApp to PATH across Machine, User, and Process scopes when missing.

    .EXAMPLE
    Add-WingetInstallPathToPath -InstallPath C:\PortableApps\ToolX
    Adds C:\PortableApps\ToolX to PATH when missing, without package-specific output text.

    .EXAMPLE
    Add-WingetInstallPathToPath -PackageName HindsightGUI -Category Browser
    Adds C:\tools\Browser\HindsightGUI to PATH when missing.

    .NOTES
    - PATH checks are case-insensitive and ignore trailing backslashes.
    - The install path must exist; non-existent paths are skipped.
    - Adds to Machine, User, and Process scopes for consistent behavior.
    - Requires PowerShell 5.1 or later.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByPath')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByPath')]
        [string]$InstallPath,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByName')]
        [ValidateNotNullOrEmpty()]
        [string]$PackageName,

        [Parameter(ParameterSetName = 'ByName')]
        [ValidateNotNullOrEmpty()]
        [string]$CustomPath = (Get-ForensicOSToolsBasePath),

        [Parameter(ParameterSetName = 'ByName')]
        [ValidateNotNullOrEmpty()]
        [string]$Category

    )

    $resolvedTargetPath = $InstallPath
    if ($PSCmdlet.ParameterSetName -eq 'ByName') {
        $basePath = $CustomPath
        if (-not [string]::IsNullOrWhiteSpace($Category)) {
            $basePath = Join-Path -Path $CustomPath -ChildPath $Category
        }

        $resolvedTargetPath = Join-Path -Path $basePath -ChildPath $PackageName
    }

    if ([string]::IsNullOrWhiteSpace($resolvedTargetPath)) {
        return
    }

    $resolvedInstallPath = [System.IO.Path]::GetFullPath($resolvedTargetPath).TrimEnd('\\')
    if (-not (Test-Path -Path $resolvedInstallPath -PathType Container)) {
        Write-Host "Winget install path does not exist, skipping PATH update: $resolvedInstallPath"
        return
    }

    $processPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $effectivePath = @($processPath, $userPath, $machinePath) -join ';'

    if (Test-PathEntryInValue -PathValue $effectivePath -EntryPath $resolvedInstallPath) {
        Write-Host "Winget install path already in PATH: $resolvedInstallPath"
        return
    }

    Add-PathEntryToScope -EntryPath $resolvedInstallPath -Scope 'Machine'
    Add-PathEntryToScope -EntryPath $resolvedInstallPath -Scope 'User'
    Add-PathEntryToScope -EntryPath $resolvedInstallPath -Scope 'Process'
    Write-Host "Added winget install path to PATH: $resolvedInstallPath" -ForegroundColor Green
}

function Remove-WingetInstallPathFromPath {
    <#
    .SYNOPSIS
    Removes a winget package install path from PATH.

    .DESCRIPTION
    Normalizes the provided install path and removes matching entries from PATH in Process, User,
    and Machine scopes. This is useful when uninstalling packages or cleaning up obsolete custom
    install locations.

    .PARAMETER InstallPath
    The installation directory to remove from PATH.

    .PARAMETER PackageName
    Winget package folder name under CustomPath. When provided, the install path is derived as
    CustomPath\Category\PackageName (or CustomPath\PackageName when Category is omitted).

    .PARAMETER CustomPath
    Base path used with PackageName. Defaults to 'C:\tools'.

    .PARAMETER Category
    Optional subfolder under CustomPath used with PackageName.

    .EXAMPLE
    Remove-WingetInstallPathFromPath -InstallPath C:\Tools\MyApp
    Removes C:\Tools\MyApp from PATH across Machine, User, and Process scopes.

    .EXAMPLE
    Remove-WingetInstallPathFromPath -InstallPath C:\PortableApps\ToolX
    Removes C:\PortableApps\ToolX from PATH without package-specific output text.

    .EXAMPLE
    Remove-WingetInstallPathFromPath -PackageName HindsightGUI -Category Browser
    Removes C:\tools\Browser\HindsightGUI from PATH.

    .NOTES
    - PATH matching is case-insensitive and ignores trailing backslashes.
    - Missing entries are ignored; operation is idempotent.
    - Removes from Machine, User, and Process scopes for symmetric cleanup.
    - Requires PowerShell 5.1 or later.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByPath')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByPath')]
        [string]$InstallPath,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByName')]
        [ValidateNotNullOrEmpty()]
        [string]$PackageName,

        [Parameter(ParameterSetName = 'ByName')]
        [ValidateNotNullOrEmpty()]
        [string]$CustomPath = (Get-ForensicOSToolsBasePath),

        [Parameter(ParameterSetName = 'ByName')]
        [ValidateNotNullOrEmpty()]
        [string]$Category

    )

    $resolvedTargetPath = $InstallPath
    if ($PSCmdlet.ParameterSetName -eq 'ByName') {
        $basePath = $CustomPath
        if (-not [string]::IsNullOrWhiteSpace($Category)) {
            $basePath = Join-Path -Path $CustomPath -ChildPath $Category
        }

        $resolvedTargetPath = Join-Path -Path $basePath -ChildPath $PackageName
    }

    if ([string]::IsNullOrWhiteSpace($resolvedTargetPath)) {
        return
    }

    $normalizedInstallPath = [System.IO.Path]::GetFullPath($resolvedTargetPath).TrimEnd('\\')
    if ([string]::IsNullOrWhiteSpace($normalizedInstallPath)) {
        return
    }

    Remove-PathEntryFromScope -EntryPath $normalizedInstallPath -Scope 'Machine'
    Remove-PathEntryFromScope -EntryPath $normalizedInstallPath -Scope 'User'
    Remove-PathEntryFromScope -EntryPath $normalizedInstallPath -Scope 'Process'
    Write-Host "Removed winget install path from PATH: $normalizedInstallPath" -ForegroundColor Yellow
}

function Remove-LinkPathFromPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LinkPath
    )

    $normalizedLinkPath = $LinkPath.Trim().TrimEnd('\\')
    if ([string]::IsNullOrWhiteSpace($normalizedLinkPath)) {
        return
    }

    Remove-PathEntryFromScope -EntryPath $normalizedLinkPath -Scope 'Machine'
    Remove-PathEntryFromScope -EntryPath $normalizedLinkPath -Scope 'User'
    Remove-PathEntryFromScope -EntryPath $normalizedLinkPath -Scope 'Process'
    Write-Host "Removed link path from PATH: $normalizedLinkPath" -ForegroundColor Yellow
}

function New-ChocolateyPackageToolsLink {
    <#
    .SYNOPSIS
    Creates a junction or symbolic link to a Chocolatey package's tools folder.

    .DESCRIPTION
    Creates a link (junction or symbolic link) to a Chocolatey package's tools folder at a centralized
    location. Supports organizing links into categories. If a link already exists pointing to the correct
    target, no action is taken. If a link exists pointing to the wrong target, it is removed and recreated.

    .PARAMETER ChocolateyBasePath
    The base path where Chocolatey is installed. If not provided, resolves from environment variables
    (Process scope first, then Machine scope). Typically 'C:\ProgramData\chocolatey'.

    .PARAMETER PackageName
    The name of the Chocolatey package to link. This is the folder name under Chocolatey's lib directory.
    This parameter is mandatory.

    .PARAMETER CustomPath
    The destination path where the link will be created. Defaults to 'C:\tools'.
    If a Category is specified, the link is created under CustomPath\Category\PackageName.
    If no Category is specified, the link is created at CustomPath\PackageName.

    .PARAMETER Category
    Optional category name to organize links into subdirectories. If provided, links are created at
    CustomPath\Category\PackageName. The category folder is created automatically if it doesn't exist.

    .PARAMETER LinkType
    The type of link to create: 'Junction' (default) or 'SymbolicLink'. Junctions are recommended
    for directory linking as they work across NTFS volumes.

    .PARAMETER Force
    Not used in current implementation. Included for API consistency.

    .PARAMETER PassThru
    If specified, returns the created or verified link object. Useful for validation and scripting.

    .EXAMPLE
    New-ChocolateyPackageToolsLink -PackageName ProcessMonitor
    Creates a junction at C:\tools\ProcessMonitor pointing to the ProcessMonitor package's tools folder.

    .EXAMPLE
    New-ChocolateyPackageToolsLink -PackageName SysinternalsSuite -Category "Forensics"
    Creates a junction at C:\tools\Forensics\SysinternalsSuite pointing to the SysinternalsSuite tools.

    .EXAMPLE
    New-ChocolateyPackageToolsLink -PackageName 7zip -CustomPath C:\ProgramFiles\Tools -PassThru
    Creates a junction at C:\ProgramFiles\Tools\7zip and returns the created link object.

    .EXAMPLE
    New-ChocolateyPackageToolsLink -PackageName wget -ChocolateyBasePath C:\Chocolatey -CustomPath C:\Tools
    Uses a custom Chocolatey installation path.

    .NOTES
    - The package's tools folder must exist, otherwise a warning is returned.
    - CustomPath must exist; it is not automatically created.
    - If a link already points to the correct target, the function returns without taking action.
    - If a non-link item exists at the link path, an error is thrown.
    - Requires PowerShell 5.1 or later.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$ChocolateyBasePath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageName,

        [ValidateNotNullOrEmpty()]
        [string]$CustomPath = (Get-ForensicOSToolsBasePath),

        [ValidateNotNullOrEmpty()]
        [string]$Category,

        [ValidateSet('Junction', 'SymbolicLink')]
        [string]$LinkType = 'Junction',

        [switch]$Force,

        [switch]$PassThru
    )

    if ([string]::IsNullOrWhiteSpace($ChocolateyBasePath)) {
        $ChocolateyBasePath = [Environment]::GetEnvironmentVariable('ChocolateyInstall', 'Process')
    }

    if ([string]::IsNullOrWhiteSpace($ChocolateyBasePath)) {
        $ChocolateyBasePath = [Environment]::GetEnvironmentVariable('ChocolateyInstall', 'Machine')
    }

    if ([string]::IsNullOrWhiteSpace($ChocolateyBasePath)) {
        throw 'No Chocolatey path input provided and no ChocolateyInstall environment variable found.'
    }

    $resolvedPackageRootPath = Join-Path -Path $ChocolateyBasePath -ChildPath 'lib'

    if (-not (Test-Path -Path $resolvedPackageRootPath -PathType Container)) {
        throw "Chocolatey package root path not found: $resolvedPackageRootPath"
    }

    $packagePath = Join-Path -Path $resolvedPackageRootPath -ChildPath $PackageName
    if (-not (Test-Path -Path $packagePath -PathType Container)) {
        throw "Chocolatey package folder not found: $packagePath"
    }

    $toolsPath = Join-Path -Path $packagePath -ChildPath 'tools'
    if (-not (Test-Path -Path $toolsPath -PathType Container)) {
        Write-Warning "No tools folder found for package '$PackageName' at: $packagePath"
        return $null
    }

    if (-not (Test-Path -Path $CustomPath -PathType Container)) {
        Write-Error "CustomPath does not exist: $CustomPath"
        return $null
    }

    # Create category folder if specified
    $linkParentPath = $CustomPath
    if (-not [string]::IsNullOrWhiteSpace($Category)) {
        $linkParentPath = Join-Path -Path $CustomPath -ChildPath $Category
        if (-not (Test-Path -Path $linkParentPath -PathType Container)) {
            New-Item -Path $linkParentPath -ItemType Directory -Force | Out-Null
        }
    }

    $linkPath = Join-Path -Path $linkParentPath -ChildPath $PackageName

    if (Test-Path -Path $linkPath) {
        $existingItem = Get-Item -Path $linkPath -Force

        if ($existingItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            # Get the target of the existing junction/symlink using PowerShell native property
            if ($existingItem.Target) {
                $currentTarget = $existingItem.Target
                
                # Normalize paths for comparison
                $expectedTarget = (Resolve-Path -Path $toolsPath).ProviderPath
                $currentTargetResolved = (Resolve-Path -Path $currentTarget -ErrorAction SilentlyContinue).ProviderPath
                
                if ($currentTargetResolved -eq $expectedTarget) {
                    # Junction already points to the correct location, do nothing
                    Write-Host "Link already exists (correct): $linkPath -> $currentTarget" -ForegroundColor Yellow
                    if ($PassThru) {
                        return $existingItem
                    }
                    return
                }
            }
            
            # Link points to wrong target or target couldn't be determined, remove and recreate
            Remove-Item -Path $linkPath -Force
            Write-Host "Removed outdated link: $linkPath" -ForegroundColor Yellow
        }
        else {
            throw "Path already exists and is not a link: $linkPath"
        }
    }

    $newItem = New-Item -Path $linkPath -ItemType $LinkType -Target $toolsPath
    Write-Host "Created $LinkType at: $linkPath -> $($toolsPath)" -ForegroundColor Green
    Add-LinkPathToPathIfSourceMissing -SourcePath $toolsPath -LinkPath $linkPath

    if ($PassThru) {
        return $newItem
    }
}

function New-ChocolateyAllPackageToolsLinks {
    <#
    .SYNOPSIS
    Creates junctions or symbolic links for all Chocolatey packages at a centralized location.

    .DESCRIPTION
    Iterates through all packages in the Chocolatey lib directory and creates links (junctions or
    symbolic links) to each package's tools folder at a centralized location. Supports organizing
    links into a single category. Errors during individual package processing are logged but do not
    stop the bulk operation. Packages without a tools folder are skipped with a warning.

    .PARAMETER ChocolateyBasePath
    The base path where Chocolatey is installed. If not provided, resolves from environment variables
    (Process scope first, then Machine scope). Typically 'C:\ProgramData\chocolatey'.

    .PARAMETER CustomPath
    The destination path where links will be created. Defaults to 'C:\tools'.
    If a Category is specified, links are created under CustomPath\Category\PackageName.
    If no Category is specified, links are created directly under CustomPath.

    .PARAMETER Category
    Optional category name to organize all links into a single subdirectory.
    If provided, all links are created at CustomPath\Category\PackageName.
    The category folder is created automatically if it doesn't exist.

    .PARAMETER LinkType
    The type of link to create: 'Junction' (default) or 'SymbolicLink'. Junctions are recommended
    for directory linking as they work across NTFS volumes.

    .PARAMETER Force
    Not used in current implementation. Included for API consistency.

    .PARAMETER PassThru
    If specified, returns an array of all created or verified link objects.

    .EXAMPLE
    New-ChocolateyAllPackageToolsLinks
    Creates junctions for all Chocolatey packages at C:\tools.

    .EXAMPLE
    New-ChocolateyAllPackageToolsLinks -CustomPath C:\ProgramFiles\Tools -Category "Forensics"
    Creates all package links under C:\ProgramFiles\Tools\Forensics.

    .EXAMPLE
    New-ChocolateyAllPackageToolsLinks -ChocolateyBasePath C:\Chocolatey -PassThru | Select-Object Name, Target
    Creates links using a custom Chocolatey path and returns all created link objects.

    .NOTES
    - Packages without a tools folder are skipped with a warning.
    - If an error occurs processing one package, the operation continues with remaining packages.
    - All errors are written to the error stream but do not halt execution.
    - Requires PowerShell 5.1 or later.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$ChocolateyBasePath,

        [string]$CustomPath = (Get-ForensicOSToolsBasePath),

        [string]$Category,

        [ValidateSet('Junction', 'SymbolicLink')]
        [string]$LinkType = 'Junction',

        [switch]$Force,

        [switch]$PassThru
    )

    if ([string]::IsNullOrWhiteSpace($ChocolateyBasePath)) {
        $ChocolateyBasePath = [Environment]::GetEnvironmentVariable('ChocolateyInstall', 'Process')
    }

    if ([string]::IsNullOrWhiteSpace($ChocolateyBasePath)) {
        $ChocolateyBasePath = [Environment]::GetEnvironmentVariable('ChocolateyInstall', 'Machine')
    }

    if ([string]::IsNullOrWhiteSpace($ChocolateyBasePath)) {
        throw 'No Chocolatey path input provided and no ChocolateyInstall environment variable found.'
    }

    $resolvedPackageRootPath = Join-Path -Path $ChocolateyBasePath -ChildPath 'lib'

    if (-not (Test-Path -Path $resolvedPackageRootPath -PathType Container)) {
        throw "Chocolatey package root path not found: $resolvedPackageRootPath"
    }

    $packageFolders = Get-ChildItem -Path $resolvedPackageRootPath -Directory -ErrorAction Stop | Sort-Object Name
    $results = @()

    foreach ($pkg in $packageFolders) {
        try {
            $result = New-ChocolateyPackageToolsLink -ChocolateyBasePath $ChocolateyBasePath -PackageName $pkg.Name -CustomPath $CustomPath -Category $Category -LinkType $LinkType -Force:$Force -PassThru:$PassThru
            if ($PassThru -and $null -ne $result) {
                $results += $result
            }
        }
        catch {
            Write-Error "Failed to create link for package '$($pkg.Name)': $($_.Exception.Message)"
        }
    }

    if ($PassThru) {
        return $results
    }
}

function Remove-ChocolateyPackageToolsLink {
    <#
    .SYNOPSIS
    Removes links for a specific Chocolatey package across all category folders.

    .DESCRIPTION
    Recursively searches the CustomPath for links matching the specified PackageName and removes them.
    Before deletion, verifies that each item is a reparse point (link). Only links are deleted; regular
    files or folders with matching names are preserved and logged as warnings. Useful for cleaning up
    when a package is uninstalled.

    .PARAMETER PackageName
    The name of the Chocolatey package whose links should be removed. This parameter is mandatory.
    The function searches recursively for items matching this name.

    .PARAMETER CustomPath
    The root path where links were created. Defaults to 'C:\tools'.
    The function recursively searches this path for matching links in all subdirectories and categories.

    .EXAMPLE
    Remove-ChocolateyPackageToolsLink -PackageName ProcessMonitor
    Removes all links named ProcessMonitor from C:\tools and its subdirectories.

    .EXAMPLE
    Remove-ChocolateyPackageToolsLink -PackageName 7zip -CustomPath C:\ProgramFiles\Tools
    Removes all links named 7zip from C:\ProgramFiles\Tools recursively.

    .NOTES
    - Only reparse points (junctions/symbolic links) are deleted.
    - Non-link items with matching names are logged as warnings and left intact.
    - If no matching items are found, the function returns silently.
    - Recursive search means links can be in any subdirectory level under CustomPath.
    - Requires PowerShell 5.1 or later.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageName,

        [ValidateNotNullOrEmpty()]
        [string]$CustomPath = (Get-ForensicOSToolsBasePath)
    )

    if (-not (Test-Path -Path $CustomPath -PathType Container)) {
        Write-Warning "CustomPath does not exist: $CustomPath"
        return
    }

    # Recursively search for items matching the PackageName
    $itemsToRemove = @(Get-ChildItem -Path $CustomPath -Recurse -Filter $PackageName -Force -ErrorAction SilentlyContinue)

    if ($itemsToRemove.Count -eq 0) {
        Write-Host "No items found matching package name '$PackageName' in '$CustomPath'"
        return
    }

    foreach ($item in $itemsToRemove) {
        # Verify it's a reparse point (link)
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            try {
                Remove-Item -Path $item.FullName -Force -Confirm:$true -ErrorAction Stop
                Write-Host "Removed link: $($item.FullName)" -ForegroundColor Green
                Remove-LinkPathFromPath -LinkPath $item.FullName
            }
            catch {
                Write-Error "Failed to remove link '$($item.FullName)': $($_.Exception.Message)"
            }
        }
        else {
            Write-Warning "Item exists but is not a link (not removing): $($item.FullName)"
        }
    }
}

function Remove-ChocolateyAllPackageToolsLinks {
    <#
    .SYNOPSIS
    Removes all broken links from the custom path.

    .DESCRIPTION
    Recursively scans the CustomPath for all reparse points (junctions and symbolic links) and removes
    those whose targets no longer exist. Valid links (targets still exist) are left intact. Useful for
    cleaning up orphaned links when packages are uninstalled without proper cleanup.

    .PARAMETER CustomPath
    The root path to scan for broken links. Defaults to 'C:\tools'.
    The function recursively searches this path and all subdirectories.

    .EXAMPLE
    Remove-ChocolateyAllPackageToolsLinks
    Scans C:\tools recursively and removes all broken links.

    .EXAMPLE
    Remove-ChocolateyAllPackageToolsLinks -CustomPath C:\ProgramFiles\Tools
    Scans C:\ProgramFiles\Tools recursively and removes all broken links.

    .NOTES
    - Only links with non-existent targets are removed.
    - Valid links are left untouched and logged as verbose messages.
    - If no links exist in CustomPath, the function returns silently.
    - Non-link items are ignored.
    - Requires PowerShell 5.1 or later.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$CustomPath = (Get-ForensicOSToolsBasePath)
    )

    if (-not (Test-Path -Path $CustomPath -PathType Container)) {
        Write-Warning "CustomPath does not exist: $CustomPath"
        return
    }

    # Recursively find all reparse points (links)
    $allItems = @(Get-ChildItem -Path $CustomPath -Recurse -Force -ErrorAction SilentlyContinue)
    $linksToCheck = @($allItems | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint })

    if ($linksToCheck.Count -eq 0) {
        Write-Host "No links found in '$CustomPath'"
        return
    }

    foreach ($link in $linksToCheck) {
        # Check if the link target exists
        $targetExists = $false
        
        if ($link.Target) {
            $targetExists = Test-Path -Path $link.Target -ErrorAction SilentlyContinue
        }

        if (-not $targetExists) {
            try {
                Remove-Item -Path $link.FullName -Force -Confirm:$true -ErrorAction Stop
                $targetDisplay = if ($null -ne $link.Target) { $link.Target } else { 'unknown' }
                Write-Host "Removed broken link: $($link.FullName) (target: $targetDisplay)" -ForegroundColor Green
                Remove-LinkPathFromPath -LinkPath $link.FullName
            }
            catch {
                Write-Error "Failed to remove link '$($link.FullName)': $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Link is valid (target exists): $($link.FullName) -> $($link.Target)"
        }
    }
}

function New-ScoopPackageToolsLink {
    <#
    .SYNOPSIS
    Creates a junction to a Scoop package's current folder.

    .DESCRIPTION
    Creates a link (junction or symbolic link) to a Scoop package's current folder at a centralized
    location. Supports both user and global Scoop packages. If a link already exists pointing to the
    correct target, no action is taken. If a link exists pointing to the wrong target, it is removed
    and recreated.

    .PARAMETER ScoopBasePath
    The base path where Scoop packages are installed (user scope). If not provided, resolves from
    the SCOOP environment variable. Typically 'C:\Users\<username>\scoop'.

    .PARAMETER ScoopGlobalPath
    The base path where global Scoop packages are installed. If not provided, resolves from the
    SCOOP_GLOBAL environment variable. Typically 'C:\ProgramData\scoop'.

    .PARAMETER PackageName
    The name of the Scoop package to link. This is the folder name under Scoop's apps directory.
    This parameter is mandatory.

    .PARAMETER Global
    If specified, searches for the package in SCOOP_GLOBAL instead of the user SCOOP directory.

    .PARAMETER CustomPath
    The destination path where the link will be created. Defaults to 'C:\tools'.
    If a Category is specified, the link is created under CustomPath\Category\PackageName.
    If no Category is specified, the link is created at CustomPath\PackageName.

    .PARAMETER Category
    Optional category name to organize links into subdirectories. If provided, links are created at
    CustomPath\Category\PackageName. The category folder is created automatically if it doesn't exist.

    .PARAMETER LinkType
    The type of link to create: 'Junction' (default) or 'SymbolicLink'. Junctions are recommended
    for directory linking as they work across NTFS volumes.

    .PARAMETER Force
    Not used in current implementation. Included for API consistency.

    .PARAMETER PassThru
    If specified, returns the created or verified link object. Useful for validation and scripting.

    .EXAMPLE
    New-ScoopPackageToolsLink -PackageName 7zip
    Creates a junction at C:\tools\7zip pointing to the 7zip package's current folder.

    .EXAMPLE
    New-ScoopPackageToolsLink -PackageName git -Global
    Creates a junction for the globally installed git package.

    .EXAMPLE
    New-ScoopPackageToolsLink -PackageName ProcessMonitor -Category "Forensics" -CustomPath C:\tools
    Creates a junction at C:\tools\Forensics\ProcessMonitor.

    .NOTES
    - The package's current folder must exist, otherwise a warning is returned.
    - CustomPath must exist; it is not automatically created.
    - If a link already points to the correct target, the function returns without taking action.
    - If a non-link item exists at the link path, an error is thrown.
    - Requires PowerShell 5.1 or later.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$ScoopBasePath,

        [ValidateNotNullOrEmpty()]
        [string]$ScoopGlobalPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageName,

        [switch]$Global,

        [ValidateNotNullOrEmpty()]
        [string]$CustomPath = (Get-ForensicOSToolsBasePath),

        [ValidateNotNullOrEmpty()]
        [string]$Category,

        [ValidateSet('Junction', 'SymbolicLink')]
        [string]$LinkType = 'Junction',

        [switch]$Force,

        [switch]$PassThru
    )

    # Resolve Scoop base paths
    if ([string]::IsNullOrWhiteSpace($ScoopBasePath)) {
        $ScoopBasePath = [Environment]::GetEnvironmentVariable('SCOOP', 'Process')
    }
    if ([string]::IsNullOrWhiteSpace($ScoopBasePath)) {
        $ScoopBasePath = [Environment]::GetEnvironmentVariable('SCOOP', 'Machine')
    }

    if ([string]::IsNullOrWhiteSpace($ScoopGlobalPath)) {
        $ScoopGlobalPath = [Environment]::GetEnvironmentVariable('SCOOP_GLOBAL', 'Process')
    }
    if ([string]::IsNullOrWhiteSpace($ScoopGlobalPath)) {
        $ScoopGlobalPath = [Environment]::GetEnvironmentVariable('SCOOP_GLOBAL', 'Machine')
    }

    # Determine which base path to use
    $basePath = if ($Global) { $ScoopGlobalPath } else { $ScoopBasePath }

    if ([string]::IsNullOrWhiteSpace($basePath)) {
        throw "No Scoop path found. Set SCOOP or SCOOP_GLOBAL environment variable."
    }

    $appsPath = Join-Path -Path $basePath -ChildPath 'apps'
    if (-not (Test-Path -Path $appsPath -PathType Container)) {
        throw "Scoop apps path not found: $appsPath"
    }

    $packagePath = Join-Path -Path $appsPath -ChildPath $PackageName
    if (-not (Test-Path -Path $packagePath -PathType Container)) {
        throw "Scoop package folder not found: $packagePath"
    }

    $currentPath = Join-Path -Path $packagePath -ChildPath 'current'
    if (-not (Test-Path -Path $currentPath -PathType Container)) {
        Write-Warning "No current folder found for package '$PackageName' at: $packagePath"
        return $null
    }

    if (-not (Test-Path -Path $CustomPath -PathType Container)) {
        Write-Error "CustomPath does not exist: $CustomPath"
        return $null
    }

    # Create category folder if specified
    $linkParentPath = $CustomPath
    if (-not [string]::IsNullOrWhiteSpace($Category)) {
        $linkParentPath = Join-Path -Path $CustomPath -ChildPath $Category
        if (-not (Test-Path -Path $linkParentPath -PathType Container)) {
            New-Item -Path $linkParentPath -ItemType Directory -Force | Out-Null
        }
    }

    $linkPath = Join-Path -Path $linkParentPath -ChildPath $PackageName

    if (Test-Path -Path $linkPath) {
        $existingItem = Get-Item -Path $linkPath -Force

        if ($existingItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            if ($existingItem.Target) {
                $currentTarget = $existingItem.Target
                $expectedTarget = (Resolve-Path -Path $currentPath).ProviderPath
                $currentTargetResolved = (Resolve-Path -Path $currentTarget -ErrorAction SilentlyContinue).ProviderPath
                
                if ($currentTargetResolved -eq $expectedTarget) {
                    Write-Host "Link already exists (correct): $linkPath -> $currentTarget" -ForegroundColor Yellow
                    if ($PassThru) {
                        return $existingItem
                    }
                    return
                }
            }
            
            Remove-Item -Path $linkPath -Force
            Write-Host "Removed outdated link: $linkPath" -ForegroundColor Yellow
        }
        else {
            throw "Path already exists and is not a link: $linkPath"
        }
    }

    $newItem = New-Item -Path $linkPath -ItemType $LinkType -Target $currentPath
    Write-Host "Created $LinkType at: $linkPath -> $currentPath" -ForegroundColor Green
    Add-LinkPathToPathIfSourceMissing -SourcePath $currentPath -LinkPath $linkPath

    if ($PassThru) {
        return $newItem
    }
}

function New-ScoopAllPackageToolsLinks {
    <#
    .SYNOPSIS
    Creates junctions for all Scoop packages at a centralized location.

    .DESCRIPTION
    Iterates through all packages in both user and global Scoop directories and creates links
    (junctions or symbolic links) to each package's current folder at a centralized location.
    Supports organizing links into categories. Errors during individual package processing are
    logged but do not stop the bulk operation.

    .PARAMETER ScoopBasePath
    The base path where Scoop packages are installed (user scope). If not provided, resolves from
    the SCOOP environment variable.

    .PARAMETER ScoopGlobalPath
    The base path where global Scoop packages are installed. If not provided, resolves from the
    SCOOP_GLOBAL environment variable.

    .PARAMETER CustomPath
    The destination path where links will be created. Defaults to 'C:\tools'.

    .PARAMETER Category
    Optional category name to organize all links into a single subdirectory.

    .PARAMETER LinkType
    The type of link to create: 'Junction' (default) or 'SymbolicLink'.

    .PARAMETER PassThru
    If specified, returns an array of all created or verified link objects.

    .EXAMPLE
    New-ScoopAllPackageToolsLinks
    Creates junctions for all Scoop packages at C:\tools.

    .EXAMPLE
    New-ScoopAllPackageToolsLinks -CustomPath C:\tools -Category "ScoopApps"
    Creates all Scoop package links under C:\tools\ScoopApps.

    .NOTES
    - Processes both user and global Scoop packages.
    - Packages without a current folder are skipped with a warning.
    - Requires PowerShell 5.1 or later.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$ScoopBasePath,

        [ValidateNotNullOrEmpty()]
        [string]$ScoopGlobalPath,

        [string]$CustomPath = (Get-ForensicOSToolsBasePath),

        [string]$Category,

        [ValidateSet('Junction', 'SymbolicLink')]
        [string]$LinkType = 'Junction',

        [switch]$PassThru
    )

    # Resolve Scoop base paths
    if ([string]::IsNullOrWhiteSpace($ScoopBasePath)) {
        $ScoopBasePath = [Environment]::GetEnvironmentVariable('SCOOP', 'Process')
    }
    if ([string]::IsNullOrWhiteSpace($ScoopBasePath)) {
        $ScoopBasePath = [Environment]::GetEnvironmentVariable('SCOOP', 'Machine')
    }

    if ([string]::IsNullOrWhiteSpace($ScoopGlobalPath)) {
        $ScoopGlobalPath = [Environment]::GetEnvironmentVariable('SCOOP_GLOBAL', 'Process')
    }
    if ([string]::IsNullOrWhiteSpace($ScoopGlobalPath)) {
        $ScoopGlobalPath = [Environment]::GetEnvironmentVariable('SCOOP_GLOBAL', 'Machine')
    }

    $results = @()

    # Process user Scoop packages
    if (-not [string]::IsNullOrWhiteSpace($ScoopBasePath)) {
        $userAppsPath = Join-Path -Path $ScoopBasePath -ChildPath 'apps'
        if (Test-Path -Path $userAppsPath -PathType Container) {
            $packageFolders = Get-ChildItem -Path $userAppsPath -Directory -ErrorAction SilentlyContinue | Sort-Object Name
            foreach ($pkg in $packageFolders) {
                try {
                    $result = New-ScoopPackageToolsLink -ScoopBasePath $ScoopBasePath -PackageName $pkg.Name -CustomPath $CustomPath -Category $Category -LinkType $LinkType -Global:$false -PassThru:$PassThru
                    if ($PassThru -and $null -ne $result) {
                        $results += $result
                    }
                }
                catch {
                    Write-Error "Failed to create link for Scoop package '$($pkg.Name)': $($_.Exception.Message)"
                }
            }
        }
    }

    # Process global Scoop packages
    if (-not [string]::IsNullOrWhiteSpace($ScoopGlobalPath)) {
        $globalAppsPath = Join-Path -Path $ScoopGlobalPath -ChildPath 'apps'
        if (Test-Path -Path $globalAppsPath -PathType Container) {
            $packageFolders = Get-ChildItem -Path $globalAppsPath -Directory -ErrorAction SilentlyContinue | Sort-Object Name
            foreach ($pkg in $packageFolders) {
                try {
                    $result = New-ScoopPackageToolsLink -ScoopGlobalPath $ScoopGlobalPath -PackageName $pkg.Name -CustomPath $CustomPath -Category $Category -LinkType $LinkType -Global:$true -PassThru:$PassThru
                    if ($PassThru -and $null -ne $result) {
                        $results += $result
                    }
                }
                catch {
                    Write-Error "Failed to create link for global Scoop package '$($pkg.Name)': $($_.Exception.Message)"
                }
            }
        }
    }

    if ($PassThru) {
        return $results
    }
}

function Remove-ScoopPackageToolsLink {
    <#
    .SYNOPSIS
    Removes links for a specific Scoop package across all category folders.

    .DESCRIPTION
    Recursively searches the CustomPath for links matching the specified PackageName and removes them.
    Before deletion, verifies that each item is a reparse point (link). Only links are deleted; regular
    files or folders with matching names are preserved. Useful for cleaning up when a Scoop package
    is uninstalled.

    .PARAMETER PackageName
    The name of the Scoop package whose links should be removed. This parameter is mandatory.

    .PARAMETER CustomPath
    The root path where links were created. Defaults to 'C:\tools'.
    The function recursively searches this path for matching links in all subdirectories and categories.

    .EXAMPLE
    Remove-ScoopPackageToolsLink -PackageName 7zip
    Removes all links named 7zip from C:\tools and its subdirectories.

    .EXAMPLE
    Remove-ScoopPackageToolsLink -PackageName git -CustomPath C:\tools
    Removes all links named git from C:\tools recursively.

    .NOTES
    - Only reparse points (junctions/symbolic links) are deleted.
    - Non-link items with matching names are logged as warnings and left intact.
    - Recursive search means links can be in any subdirectory level under CustomPath.
    - Requires PowerShell 5.1 or later.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageName,

        [ValidateNotNullOrEmpty()]
        [string]$CustomPath = (Get-ForensicOSToolsBasePath)
    )

    if (-not (Test-Path -Path $CustomPath -PathType Container)) {
        Write-Warning "CustomPath does not exist: $CustomPath"
        return
    }

    $itemsToRemove = @(Get-ChildItem -Path $CustomPath -Recurse -Filter $PackageName -Force -ErrorAction SilentlyContinue)

    if ($itemsToRemove.Count -eq 0) {
        Write-Host "No items found matching Scoop package name '$PackageName' in '$CustomPath'"
        return
    }

    foreach ($item in $itemsToRemove) {
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            try {
                Remove-Item -Path $item.FullName -Force -Confirm:$true -ErrorAction Stop
                Write-Host "Removed link: $($item.FullName)" -ForegroundColor Green
                Remove-LinkPathFromPath -LinkPath $item.FullName
            }
            catch {
                Write-Error "Failed to remove link '$($item.FullName)': $($_.Exception.Message)"
            }
        }
        else {
            Write-Warning "Item exists but is not a link (not removing): $($item.FullName)"
        }
    }
}

function Remove-ScoopAllPackageToolsLinks {
    <#
    .SYNOPSIS
    Removes all broken Scoop package links from the custom path.

    .DESCRIPTION
    Recursively scans the CustomPath for all reparse points (junctions and symbolic links) and removes
    those whose targets no longer exist. Valid links (targets still exist) are left intact. Useful for
    cleaning up orphaned links when packages are uninstalled.

    .PARAMETER CustomPath
    The root path to scan for broken links. Defaults to 'C:\tools'.
    The function recursively searches this path and all subdirectories.

    .EXAMPLE
    Remove-ScoopAllPackageToolsLinks
    Scans C:\tools recursively and removes all broken Scoop links.

    .EXAMPLE
    Remove-ScoopAllPackageToolsLinks -CustomPath C:\tools
    Scans C:\tools recursively for broken Scoop package links and removes them.

    .NOTES
    - Only links with non-existent targets are removed.
    - Valid links are left untouched.
    - Non-link items are ignored.
    - Requires PowerShell 5.1 or later.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$CustomPath = (Get-ForensicOSToolsBasePath)
    )

    if (-not (Test-Path -Path $CustomPath -PathType Container)) {
        Write-Warning "CustomPath does not exist: $CustomPath"
        return
    }

    $allItems = @(Get-ChildItem -Path $CustomPath -Recurse -Force -ErrorAction SilentlyContinue)
    $linksToCheck = @($allItems | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint })

    if ($linksToCheck.Count -eq 0) {
        Write-Host "No links found in '$CustomPath'"
        return
    }

    foreach ($link in $linksToCheck) {
        $targetExists = $false
        
        if ($link.Target) {
            $targetExists = Test-Path -Path $link.Target -ErrorAction SilentlyContinue
        }

        if (-not $targetExists) {
            try {
                Remove-Item -Path $link.FullName -Force -Recurse -ErrorAction Stop
                $targetDisplay = if ($null -ne $link.Target) { $link.Target } else { 'unknown' }
                Write-Host "Removed broken link: $($link.FullName) (target: $targetDisplay)" -ForegroundColor Green
                Remove-LinkPathFromPath -LinkPath $link.FullName
            }
            catch {
                Write-Error "Failed to remove link '$($link.FullName)': $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Link is valid (target exists): $($link.FullName) -> $($link.Target)"
        }
    }
}

Export-ModuleMember -Function Add-WingetInstallPathToPath, Remove-WingetInstallPathFromPath, New-ChocolateyPackageToolsLink, New-ChocolateyAllPackageToolsLinks, Remove-ChocolateyPackageToolsLink, Remove-ChocolateyAllPackageToolsLinks, New-ScoopPackageToolsLink, New-ScoopAllPackageToolsLinks, Remove-ScoopPackageToolsLink, Remove-ScoopAllPackageToolsLinks
