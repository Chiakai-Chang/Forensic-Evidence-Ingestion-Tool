<#
.SYNOPSIS
    Digital Evidence Ingestion, Archiving and Integrity Verification Tool
.DESCRIPTION
    1. Resolves Windows 260-character long path limitation using virtual drive mapping.
    2. Dynamically clones network mapped drives (Y:, Z:, etc.) from User to Admin context.
    3. Uses Robocopy core to preserve all original metadata and timestamps (DCOPY:DAT / COPY:DAT).
    4. Automatically creates and preserves the original source root folder name at the destination.
    5. Implements dual-stage SHA-256 hashing to ensure chain of custody and evidence integrity.
    6. Features time-stamped manifest files to prevent overwrite on repeated execution.
    7. Safeguards source integrity by copying the final manifest back only after unmounting.
    8. Provides an interactive verification prompt prior to initiating execution.
.VERSION
    20260625_v6
.AUTHOR
    Chiakai Chang (contact.chiakai.chang@gmail.com)
.LEGAL
    This tool is developed for forensic evidence collection and chain of custody preservation.
#>

Add-Type -AssemblyName System.Windows.Forms

function Sync-NetworkDrives {
    $RegPath = "HKCU:\Network"
    if (Test-Path $RegPath) {
        Get-ChildItem $RegPath | ForEach-Object {
            $DriveLetter = "$($_.PSChildName):"
            $RemotePath = (Get-ItemProperty $_.PSPath).RemotePath
            if (-not (Test-Path $DriveLetter) -and $RemotePath) {
                try {
                    Start-Process cmd -ArgumentList "/c net use $DriveLetter `"$RemotePath`" /persistent:no" -WindowStyle Hidden -Wait
                } catch {}
            }
        }
    }
}

Sync-NetworkDrives

function Select-FolderDialog ($Title) {
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.Title = $Title
    $OpenFileDialog.Filter = "Folders|`n" 
    $OpenFileDialog.CheckFileExists = $false
    $OpenFileDialog.CheckPathExists = $true
    $OpenFileDialog.ValidateNames = $false
    $OpenFileDialog.FileName = "Select_This_Folder" 
    
    $Result = $OpenFileDialog.ShowDialog()
    if ($Result -eq [System.Windows.Forms.DialogResult]::OK) {
        return [System.IO.Path]::GetDirectoryName($OpenFileDialog.FileName)
    } else {
        return $null
    }
}

Clear-Host
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "            Forensic Evidence Ingestion Tool           " -ForegroundColor Cyan
Write-Host "     Version: 20260625 | Author: Chiakai Chang         " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host " [Features] " -ForegroundColor Yellow
Write-Host " 1. Resolves long path issues via dynamic virtual drive mapping." -ForegroundColor Gray
Write-Host " 2. Preserves original metadata and folder structure for inspection." -ForegroundColor Gray
Write-Host " 3. Generates relative SHA-256 manifest with secure time-stamps." -ForegroundColor Gray
Write-Host "=======================================================" -ForegroundColor Cyan

$SourceDir = Select-FolderDialog "STEP 1: Select SOURCE Evidence Folder"
if (-not $SourceDir) { Write-Host "[CANCEL] No source folder selected. Exiting..." -ForegroundColor Red; pause; exit }

$TargetDir = Select-FolderDialog "STEP 2: Select DESTINATION Archiving Folder"
if (-not $TargetDir) { Write-Host "[CANCEL] No destination folder selected. Exiting..." -ForegroundColor Red; pause; exit }

$FolderName = Split-Path $SourceDir -Leaf
$FinalTargetDir = Join-Path $TargetDir $FolderName

# -----------------------------------------------------------------
# Path Verification and interactive confirmation
# -----------------------------------------------------------------
Write-Host "`n=================== PATH VERIFICATION ===================" -ForegroundColor Yellow
Write-Host " Please verify the ingestion paths carefully:" -ForegroundColor Yellow
Write-Host " -> SOURCE      : $SourceDir" -ForegroundColor Green
Write-Host " -> DESTINATION : $FinalTargetDir" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Yellow

$Confirm = Read-Host "Proceed with ingestion? [Y/N] (Default is Y)"
if ($Confirm -like "n*" -or $Confirm -like "N*") {
    Write-Host "`n[CANCEL] Ingestion terminated by user. Exiting safely..." -ForegroundColor Red
    pause; exit
}

if (-not (Test-Path $FinalTargetDir)) {
    New-Item -ItemType Directory -Path $FinalTargetDir | Out-Null
}

$AvailableDrive = $null
foreach ($DriveLetter in ([char]'X'..[char]'D')) {
    $CheckDrive = "$([char]$DriveLetter):"
    if (-not (Test-Path $CheckDrive)) {
        $AvailableDrive = $CheckDrive
        break
    }
}

if (-not $AvailableDrive) {
    Write-Host "[ERROR] No available drive letter found from X: to D:. Exiting..." -ForegroundColor Red
    pause; exit
}
Write-Host "`n[PREP] Allocating Virtual Drive: [ $AvailableDrive ]" -ForegroundColor Yellow

Write-Host "[1/5] Mapping virtual drive to bypass long path limit..." -ForegroundColor Yellow
subst $AvailableDrive "$SourceDir"

Write-Host "[2/5] Calculating SOURCE SHA-256 manifest..." -ForegroundColor Cyan
# Exclude pre-existing manifests to ensure idempotency
$SourceFiles = Get-ChildItem -Path "${AvailableDrive}\" -Recurse -File | Where-Object { $_.Name -notlike "Evidence_Manifest_*.csv" -and $_.Name -ne "證據雜湊值清單.csv" }
$SourceTotal = $SourceFiles.Count
$SourceManifest = @{}
$HashReport = @()
$Counter = 0

foreach ($File in $SourceFiles) {
    $Counter++
    if ($Counter % 5000 -eq 0 -or $Counter -eq $SourceTotal) {
        Write-Host "-> Progress: [ $Counter / $SourceTotal ]" -ForegroundColor Gray
    }
    try {
        $FileHash = (Get-FileHash -Path $File.FullName -Algorithm SHA256).Hash
        $RelativePath = $File.FullName.Substring(3) 
        $SourceManifest[$RelativePath] = $FileHash
        
        $HashReport += [PSCustomObject]@{
            "RelativePath" = $RelativePath
            "SHA256"       = $FileHash
            "ModifiedTime" = $File.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            "Size_Bytes"   = $File.Length
            "Verification" = "Pending"
        }
    } catch {
        Write-Host "⚠️ Cannot read file: $($File.FullName)" -ForegroundColor Yellow
    }
}

Write-Host "[3/5] Copying directory structure and preserving metadata (Robocopy)..." -ForegroundColor Cyan
Write-Host "-> Transporting bytes... Progress will be shown below:" -ForegroundColor Gray
robocopy "${AvailableDrive}\" "$FinalTargetDir" /E /DCOPY:DAT /COPY:DAT /R:2 /W:2 /NFL

# Explicitly preserve metadata (timestamps & attributes) of the root folder itself
try {
    $SrcItem = Get-Item $SourceDir
    $DestItem = Get-Item $FinalTargetDir
    $DestItem.CreationTime = $SrcItem.CreationTime
    $DestItem.LastWriteTime = $SrcItem.LastWriteTime
    $DestItem.LastAccessTime = $SrcItem.LastAccessTime
    $DestItem.Attributes = $SrcItem.Attributes
} catch {
    Write-Host "⚠️ Warning: Could not preserve root folder metadata." -ForegroundColor Yellow
}

Write-Host "[4/5] Ingestion completed. Unmounting virtual drive..." -ForegroundColor Yellow
subst $AvailableDrive /d

# Write initial manifest before verification to safeguard against Ctrl+C
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$CsvFileName = "Evidence_Manifest_${Timestamp}.csv"
$CsvPath = Join-Path $FinalTargetDir $CsvFileName

try {
    $HashReport | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
    Write-Host ">> Initial manifest saved to Destination Folder." -ForegroundColor Gray
} catch {
    Write-Host "⚠️ Warning: Could not write initial manifest to destination." -ForegroundColor Yellow
}

try {
    Copy-Item -Path $CsvPath -Destination $SourceDir -Force
    Write-Host ">> Initial manifest synchronized back to Source Folder." -ForegroundColor Gray
} catch {
    Write-Host "⚠️ Warning: Could not write initial manifest back to source." -ForegroundColor Yellow
}

Write-Host "`n-------------------------------------------------------" -ForegroundColor Yellow
Write-Host "[DATA COPIED SUCCESSFULLY] Proceed to post-verification?" -ForegroundColor Yellow
Write-Host "💡 NOTE: Hashing remote NAS folders may take 5-10 minutes." -ForegroundColor Gray
Write-Host "💡 NOTE: You can press [Ctrl + C] to skip verification safely at any time." -ForegroundColor DarkYellow

$Signature = @'
[DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
public static extern int MessageBoxTimeout(IntPtr hWnd, String text, String caption, uint type, short wLanguageId, uint dwMilliseconds);
'@
$MsgBox = "[Win32.Win32MessageBox]" -as [type]
if ($MsgBox -eq $null) {
    $MsgBox = Add-Type -TypeDefinition $Signature -Name "Win32MessageBox" -Namespace "Win32" -PassThru
}

$ButtonType = 65572 
$TimeoutMs = 10000 

$MsgText = "Evidence files ingested successfully!`n`nDo you want to verify SHA-256 integrity on the destination?`n(Will auto-start verification in 10 seconds)"
$Response = $MsgBox::MessageBoxTimeout([IntPtr]::Zero, $MsgText, "Forensic Integrity Verification", $ButtonType, 0, $TimeoutMs)

if ($Response -eq 6 -or $Response -eq 32000) {
    Write-Host "`n[5/5] Verifying DESTINATION integrity via SHA-256 cross-matching..." -ForegroundColor Cyan
    Write-Host "🚨 Press [Ctrl + C] to terminate verification if urgent. Files are already safe." -ForegroundColor DarkYellow
    
    $MatchCount = 0
    $MismatchCount = 0
    
    foreach ($Item in $HashReport) {
        $RelPath = $Item."RelativePath"
        $FullDestPath = Join-Path $FinalTargetDir $RelPath
        
        if (Test-Path $FullDestPath) {
            try {
                $DestHash = (Get-FileHash -Path $FullDestPath -Algorithm SHA256).Hash
                if ($DestHash -eq $Item."SHA256") {
                    $Item."Verification" = "SUCCESS"
                    $MatchCount++
                } else {
                    $Item."Verification" = "ERROR_HASH_MISMATCH"
                    $MismatchCount++
                }
            } catch {
                $Item."Verification" = "ERROR_CANNOT_READ"
                $MismatchCount++
            }
        } else {
            $Item."Verification" = "FAILED_MISSING"
            $MismatchCount++
        }
    }
    
    # Overwrite the CSV with updated verification status
    try {
        $HashReport | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
        # Sync updated manifest back to source
        Copy-Item -Path $CsvPath -Destination $SourceDir -Force
        Write-Host ">> Final manifest synchronized back to Source Folder." -ForegroundColor Gray
    } catch {
        Write-Host "⚠️ Warning: Could not write final manifest." -ForegroundColor Yellow
    }
    
    Write-Host "`n====================== VERIFICATION REPORT ======================" -ForegroundColor Cyan
    Write-Host " Verified & Matched Files : $MatchCount" -ForegroundColor Green
    if ($MismatchCount -gt 0) {
        Write-Host " ❌ Corrupted/Missing Files: $MismatchCount (Check $CsvFileName!)" -ForegroundColor Red
    } else {
        Write-Host "  Evidence Integrity     : 100% MATCH. SHA-256 verification complete." -ForegroundColor Green
    }
} else {
    Write-Host "`n[5/5] Verification skipped by forensic examiner." -ForegroundColor Yellow
}

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host " SUCCESS: Evidence ingestion workflow completed!" -ForegroundColor Green
Write-Host " Target Directory: $FinalTargetDir" -ForegroundColor Gray
Write-Host " Manifest File   : $CsvFileName" -ForegroundColor Gray
Write-Host "=======================================================" -ForegroundColor Green
pause