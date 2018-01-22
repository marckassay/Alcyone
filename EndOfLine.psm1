$script:ReportCollection
$script:SUT = $false

function ConvertTo-LF {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Path,

        [switch]$SkipIgnoreFile,

        [switch]$ExportReportData,

        [switch]$WhatIf
    )
    $Path | Convert-EOL -EOL 'LF' `
        -SkipIgnoreFile:$SkipIgnoreFile.IsPresent `
        -ExportReportData:$ExportReportData.IsPresent `
        -WhatIf:$WhatIf.IsPresent
}

function ConvertTo-CRLF {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Path,

        [switch]$SkipIgnoreFile,

        [switch]$ExportReportData,

        [switch]$WhatIf
    )
    $Path | Convert-EOL -EOL 'CRLF' `
        -SkipIgnoreFile:$SkipIgnoreFile.IsPresent `
        -ExportReportData:$ExportReportData.IsPresent `
        -WhatIf:$WhatIf.IsPresent
}

function Convert-EOL {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Path,

        [ValidateSet("LF", "CRLF")]
        [string]$EOL,

        [switch]$SkipIgnoreFile,

        [switch]$ExportReportData,

        [switch]$WhatIf
    )

    if ($SkipIgnoreFile.IsPresent -eq $false) {
        $IgnoreHashTable = Import-GitIgnoreFile $Path
    }

    $ConfirmationMessage = New-ConfirmationMessage -EOL $EOL -WhatIf:$WhatIf.IsPresent
    $Decision = Request-Confirmation -Message $ConfirmationMessage -WhatIf:$WhatIf.IsPresent

    if ($Decision -eq $true) {
        Start-ConversionProcess -Path $Path `
            -EOL $EOL `
            -IgnoreHashTable $IgnoreHashTable `
            -ExportReportData:$ExportReportData.IsPresent `
            -WhatIf:$WhatIf.IsPresent
    }
    else {
        Write-Output -InputObject "Operation has been cancelled, no files have been modified."
    }
}

function Import-GitIgnoreFile {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Path
    )
    
    try {
        Push-Location
        if ($Path | Test-Path -PathType Container) {
            $Path | Set-Location
            $IgnoreFile = Get-ChildItem -Path . -Recurse -Depth 3 -Filter ".gitignore" | Select-Object -First 1
        }
        else {
            $Path | Get-ItemPropertyValue -Name DirectoryName #| Set-Location
            $IgnoreFile = Get-ParentItem -Path $Path -Name '.gitignore' -Recurse
        }

        $GitIgnoreContents = $IgnoreFile | `
            Get-Content | `
            Where-Object {($_.Length -gt 0) -and ($_.StartsWith('#') -ne $true)}

        $FolderEntries = @()
        $FileEntries = @()

        $GitIgnoreContents | ForEach-Object { 
            # https://git-scm.com/docs/gitignore
            if ($_ -match '\w/') {
                # test to see which top-level folders exist
                if (Join-Path -Path . -ChildPath $_ -Resolve -ErrorAction SilentlyContinue | Test-Path -PathType Container) {
                    $FolderEntries += $_.Trim('/')
                }
            }
            else {
                # test to see which top-level files exist
                if (Join-Path -Path . -ChildPath $_ -Resolve -ErrorAction SilentlyContinue | Test-Path -PathType Leaf) {
                    # call Trim() here for element will be a string in quotes.
                    $FileEntries += $_.Trim()
                }
            }
        }

        Pop-Location

        # since .git folder is not listed in .gitignore, add it to FolderEntries
        $FolderEntries += '.git'
        
        $IgnoreHashTable = @{
            FolderEntries = $FolderEntries
            FileEntries   = $FileEntries
        }

        if ($IgnoreFile) {
            Write-Host ("Imported and will be using the following ignore file: " + $IgnoreFile.FullName)
        }
        
        $IgnoreHashTable
    }
    catch {

    }
}

function Get-ParentItem {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Path,

        [Parameter(Mandatory = $true, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [switch]$Recurse
    )

    if ($Path | Test-Path -PathType Leaf) {
        $Path = $Path | Get-ItemPropertyValue -Name DirectoryName
    }

    $CurrentDirectory = $(Get-Item $Path)
    
    $FoundItem = Get-ChildItem -Path $CurrentDirectory -Filter $Name

    if (($Recurse.IsPresent -eq $true) -and ($FoundItem -eq $null) -and ($CurrentDirectory.Parent.FullName -ne $null)) {
        Get-ParentItem -Path $CurrentDirectory.Parent.FullName -Name $Name -Recurse
    }
    else {
        $FoundItem
    }
}

function New-ConfirmationMessage {
    [CmdletBinding()]
    Param
    (
        [ValidateSet("LF", "CRLF")]
        [string]$EOL,

        [switch]$WhatIf
    )
    
    if ($WhatIf.IsPresent -eq $false) {
        $ConfirmationMessage = @"
You have requested to convert all files to ${EOL} end-of-line (EOL) characters."
"@
    }
    else {
        $ConfirmationMessage = @"
You have requested to see what files will be converted to ${EOL} end-of-line (EOL) characters."
"@
    }

    $ConfirmationMessage
}

function Request-Confirmation {
    Param
    (
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Message,

        [switch]$WhatIf
    )
    
    if ($WhatIf.IsPresent -eq $false) {
        $Question = "Do you want to proceed in modifying file(s)?"
    }
    else {
        $Question = "Since 'WhatIf' has been switched, do you want to see what file(s) would have been modified?"
    }

    $Yes = [System.Management.Automation.Host.ChoiceDescription]::new("&Yes")
    $Yes.HelpMessage = "Executes operation"
    $No = [System.Management.Automation.Host.ChoiceDescription]::new("&No")
    $No.HelpMessage = "Aborts operation"

    if ($script:SUT -eq $false) {
        [bool]$Decision = !($Host.UI.PromptForChoice($Message, $Question, @($Yes, $No), 1))
    }
    else {
        [bool]$Decision = $true
    }

    $Decision
}

function Start-ConversionProcess {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Path,

        [Parameter(Mandatory = $false)]
        [object[]]$IgnoreHashTable,

        [ValidateSet("LF", "CRLF")]
        [string]$EOL,

        [switch]$ExportReportData,

        [switch]$WhatIf
    )
    
    try {
        # TODO: report ignored items?
        <# 
        $IgnoreHashTable.FolderEntries | ForEach-Object {
            $ReportCollection += $_
        } 
        #>
        $script:ReportCollection = @()

        Push-Location
      
        if (($Path | Test-Path) -eq $false) {
            if ($Path | Test-Path -PathType Container -IsValid) {
                throw [System.IO.DirectoryNotFoundException]::new()
            }
            elseif ($Path | Test-Path -PathType Leaf -IsValid) {
                throw [System.IO.FileNotFoundException]::new()
            }
            else {
                throw [System.IO.IOException]::new() 
            }
        }
        else {
            if ($Path | Test-Path -PathType Container) {
                Invoke-RecurseFolders -Path $Path[0] `
                    -EOL $EOL `
                    -IgnoreHashTable $IgnoreHashTable `
                    -WhatIf:$WhatIf.IsPresent
            }
            else {
                $script:ReportCollection += Get-FileObject `
                    -FilePath $Path[0] `
                    -EOL $EOL `
                    -WhatIf:$WhatIf.IsPresent | `
                    Write-File | `
                    Out-ReportData
            }
        }

        Pop-Location
        
        if ($ExportReportData.IsPresent -eq $false) {
            Format-ReportTable -EOL $EOL -WhatIf:$WhatIf.IsPresent
        }
        else {
            $script:ReportCollection
        }
    }
    catch [System.IO.DirectoryNotFoundException] {
        Write-Error -Message ("The following directory cannot be found: $Path")
        Pop-Location
    }
    catch [System.IO.FileNotFoundException] {
        Write-Error -Message ("The following file cannot be found: $Path")
        Pop-Location
    }
    catch [System.IO.IOException] {
        Write-Error -Message ("The following is invalid: $Path")
        Pop-Location
    }
}

# NOTE: Algorithm by Brian Nadjiwon:
# https://social.technet.microsoft.com/Forums/windowsserver/en-US/71a473c7-7cee-4c48-ab02-491703aa1f5f/getchilditem-with-millions-of-files
# 
function Invoke-RecurseFolders {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $false)]
        [string]$Path,
        
        [ValidateSet("LF", "CRLF")]
        [string]$EOL,

        [Parameter(Mandatory = $false)]
        [object[]]$IgnoreHashTable,

        [switch]$WhatIf
    )

    Set-Location -Path $Path
    # HACK: when -File and -Exclude are switched on Get-ChildItem, it doesnt return 
    # anything; hence the piped Where-Object to determine if its a file.  This
    # seems to be fixed in PowerShell Core 6.0.0
    #
    # https://github.com/PowerShell/PowerShell/issues/5699
    #
    [string[]]$Files = Get-ChildItem . -Exclude $IgnoreHashTable.FileEntries | Where-Object {$_.PSIsContainer -eq $false}
    ForEach ($File in $Files) {
        $script:ReportCollection += Get-FileObject `
            -FilePath $File `
            -EOL $EOL `
            -WhatIf:$WhatIf.IsPresent | `
            Write-File | `
            Out-ReportData
    }

    [string[]]$Folders = Get-ChildItem . -Directory -Exclude $IgnoreHashTable.FolderEntries
    ForEach ($Folder in $Folders) {
        Invoke-RecurseFolders -Path $Folder `
            -EOL $EOL `
            -IgnoreHashTable $IgnoreHashTable `
            -WhatIf:$WhatIf.IsPresent

        Set-Location -Path '..'
    }
}

function Format-ReportTable {
    [CmdletBinding()]
    Param
    (
        [ValidateSet("LF", "CRLF")]
        [string]$EOL,

        [switch]$WhatIf
    )
    
    if ($script:ReportCollection.Count -gt 0) {
        $ModifiedCount = 0
        $script:ReportCollection | ForEach-Object {
            if ($_.Modified) {
                $ModifiedCount++
            }
        }
 
        if ($WhatIf.IsPresent) {
            $ColHeaderForModified = "Would be Modified    "
            $SummaryMessage = "A total of '$ModifiedCount' files would have been modified with " + $EOL + " end-of-line (EOL) characters."
        }
        else {
            $ColHeaderForModified = "Modified    "
            $SummaryMessage = "A total of '$ModifiedCount' files has been modified with " + $EOL + " end-of-line (EOL) characters."
        }

        $script:ReportCollection | `
            Sort-Object -property `
        @{Expression = "Modified"; Descending = $true}, `
        @{Expression = "FilePath"; Descending = $false} | `
            Format-Table `
        @{Label = "Name    "; Expression = {($_.FilePath)}}, `
        @{Label = $ColHeaderForModified; Expression = {($_.Modified)}; Alignment = "Left"}, `
        @{Label = "Reason Not Modified    "; Expression = {
                if ($_.EmptyFile) {
                    "File is empty"
                }
                elseif ($_.EncodingNotCompatiable) {
                    $mesg = "Encoding is not compatiable"
                    if ($_.FileEncoding) {
                        $mesg += " - " + $_.FileEncoding
                    }
                    $mesg
                }
                elseif ($_.SameEOLAsRequested) {
                    "Same EOL as requested"
                }
            } ; Alignment = "Left"
        } -AutoSize
    }
    else {
        if ($WhatIf.IsPresent) {
            $SummaryMessage = @"

No files would have been modified with $EOL end-of-line (EOL) characters.
"@
        }
        else {
            $SummaryMessage = @"

No files has been modified with $EOL end-of-line (EOL) characters.
"@
        }
    }
    Write-Host $SummaryMessage
}

function Get-FileObject {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [ValidateSet("LF", "CRLF")]
        [string]$EOL,
        
        [switch]$WhatIf
    )

    $Data = [PsCustomObject]@{
        EOL                    = $EOL
        FilePath               = ''
        FileItem               = $null
        FileContent            = ''
        FileEOL                = ''
        FileEncoding           = $null
        EncodingNotCompatiable = $false
        SameEOLAsRequested     = $false
        EmptyFile              = $false
        EndsWithEmptyNewLine   = $false
        Modified               = $false
        WhatIf                 = $WhatIf.IsPresent
    }
    
    Write-Verbose ("Opening: " + $FilePath)
    $Data.FilePath = Resolve-Path $FilePath -Relative
    $Data.FileItem = Get-Item -Path $FilePath
    $Data.EmptyFile = $Data.FileItem.Length -eq 0

    if ($Data.EmptyFile -eq $false) {
        # unicode: U+000D | byte (decimal): 13 | html: \r\n | powershell: `r`n
        [byte]$CR = 0x0D
        # unicode: U+000A | byte (decimal): 10 | html: \n | powershell: `n
        [byte]$LF = 0x0A
        # TODO: would be nice to pipe StreamReader into Test-Encoding...
        $Data.EncodingNotCompatiable = !(Test-Encoding -Path $Data.FileItem.FullName 'utf8')

        if ($Data.EncodingNotCompatiable -eq $false) {

            $StreamReader = New-Object -TypeName System.IO.StreamReader -ArgumentList $Data.FileItem.FullName
            
            $Data.FileEncoding = $StreamReader.CurrentEncoding
            
            if ($Data.FileEncoding -is [System.Text.UTF8Encoding]) {
            
                $Data.FileContent = $StreamReader.ReadToEnd()
            
                $FileAsBytes = [System.Text.Encoding]::UTF8.GetBytes($Data.FileContent)
                $FileAsBytesLength = $FileAsBytes.Length
            }

            $IndexOfLF = $FileAsBytes.IndexOf($LF)
            if (($IndexOfLF -ne -1) -and ($FileAsBytes[$IndexOfLF - 1] -ne $CR)) {
                $Data.FileEOL = 'LF'
                if ($FileAsBytesLength) {
                    $Data.EndsWithEmptyNewLine = ($FileAsBytes.Get($FileAsBytesLength - 1) -eq $LF) -and `
                    ($FileAsBytes.Get($FileAsBytesLength - 2) -eq $LF)
                }

                $Data.SameEOLAsRequested = $Data.FileEOL -eq $Data.EOL
            }
            elseif (($IndexOfLF -ne -1) -and ($FileAsBytes[$IndexOfLF - 1] -eq $CR)) {
                $Data.FileEOL = 'CRLF'
                if ($FileAsBytesLength) {
                    $Data.EndsWithEmptyNewLine = ($FileAsBytes.Get($FileAsBytesLength - 1) -eq $LF) -and `
                    ($FileAsBytes.Get($FileAsBytesLength - 3) -eq $LF)
                }

                $Data.SameEOLAsRequested = $Data.FileEOL -eq $Data.EOL
            }
            else {
                $Data.FileEOL = 'unknown'
            }
            
            $StreamReader.Close()
        }
    }

    $Data
}

function Write-File {
    [CmdletBinding()]
    Param
    (
        [Parameter(ValueFromPipeline = $true)]
        [PSCustomObject]$Data
    )

    if (($Data.SameEOLAsRequested -eq $false) -and `
        ($Data.EmptyFile -eq $false) -and `
        ($Data.EncodingNotCompatiable -eq $false)) {
 
        if ($Data.WhatIf -eq $false) {
            New-Object -TypeName System.IO.StreamWriter -ArgumentList $Data.FileItem.FullName -OutVariable StreamWriter | Out-null

            if ($Data.EOL -eq 'LF') {
                $Data.FileContent = $Data.FileContent -replace "`r", ""
                if ($Data.EndsWithEmptyNewLine) {
                    $Data.FileContent + "`n"
                }
            }
            elseif ($Data.EOL -eq 'CRLF') {
                $Data.FileContent = $Data.FileContent -replace "`r`n", ""
                if ($Data.EndsWithEmptyNewLine) {
                    $Data.FileContent + "`r`n"
                }
            }

            try {
                $StreamWriter.Write($Data.FileContent)
                $StreamWriter.Flush()
                $StreamWriter.Close()
            }
            catch {
                Write-Error ("EndOfLine threw an exception when writing to: " + $Data.FileItem.FullName)
            }
        }
        $Data.Modified = $true
    }
    # free-up memory; no longer need FileContent data
    $Data.FileContent = '[removed]'
    
    $Data
}

function Out-ReportData {
    [CmdletBinding()]
    Param 
    (
        [Parameter(ValueFromPipeline = $true)]
        [PSCustomObject]$Data
    )

    if ($Data.Modified -eq $true) {
        if ($Data.WhatIf -eq $false) {
            Write-Verbose ("  Modifying file")
        }
        else {
            Write-Verbose ("  Would have modified file")
        }
    }
    else {
        if ($Data.EmptyFile) {
            Write-Verbose ("  This file has been excluded since it is empty.") 
        }
        elseif ($Data.SameEOLAsRequested) {
            Write-Verbose ("  This file has been excluded since the end-of-line characters are the same as requested to convert.") 
        }
        elseif ($Data.EncodingNotCompatiable) {
            Write-Verbose ("  This file has been excluded since it is not UTF-8 encoded.")
        }
    }

    Write-Verbose ("Closing file")

    $Data
}

Export-ModuleMember -Function ConvertTo-LF
Export-ModuleMember -Function ConvertTo-CRLF