@{
    RootModule            = 'ForensicOS.Linker.psm1'
    ModuleVersion         = '1.0.0'
    GUID                  = 'e7f4c1a8-9b2d-4e6f-8c3a-1d5b9a2f7e4c'
    Author                = 'Forensicos'
    CompanyName           = 'Forensicos'
    Copyright             = '(c) 2026 Forensicos. All rights reserved.'
    Description           = 'Creates junction and symbolic links for Chocolatey and Scoop package tools to a centralized location. Supports single package or bulk linking of all installed packages.'
    PowerShellVersion     = '5.1'
    FunctionsToExport     = @('Add-WingetInstallPathToPath', 'Remove-WingetInstallPathFromPath', 'New-ChocolateyPackageToolsLink', 'New-ChocolateyAllPackageToolsLinks', 'Remove-ChocolateyPackageToolsLink', 'Remove-ChocolateyAllPackageToolsLinks', 'New-ScoopPackageToolsLink', 'New-ScoopAllPackageToolsLinks', 'Remove-ScoopPackageToolsLink', 'Remove-ScoopAllPackageToolsLinks')
    CmdletsToExport       = @()
    VariablesToExport     = @()
    AliasesToExport       = @()
    PrivateData           = @{
        PSData = @{
            Tags                       = @('Chocolatey', 'Scoop', 'Linker', 'Tools', 'Forensics', 'Package-Manager', 'Windows')
            LicenseUri                 = 'https://github.com/Forensicos/wingetrepo/blob/main/LICENSE'
            ProjectUri                 = 'https://github.com/Forensicos/wingetrepo'
            ReleaseNotes               = 'v1.0.0 - Creates junction/symbolic links for Chocolatey and Scoop package tools to a centralized location.'
            Prerelease                 = ''
            RequireLicenseAcceptance   = $false
        }
    }
    RequiredModules       = @()
    RequiredAssemblies    = @()
    ModuleList            = @()
    FileList              = @()
}
