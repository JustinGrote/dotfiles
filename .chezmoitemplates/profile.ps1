#requires -version 5

#region Checkpoint
$showPromptCheckpoint = $false
# function Checkpoint ($CheckpointName, [Switch]$AsWriteHost,[Switch]$Reset) {
#     if ($Reset) {
#         $SCRIPT:checkpointStartTime = [datetime]::now
#     }
#     if (-not $SCRIPT:processStartTime) {
#         $SCRIPT:processStartTime = (Get-Process -Id $pid).starttime
#         $SCRIPT:checkpointStartTime = [datetime]::now
#         [int]$cp = ($checkpointStartTime - $processStartTime).totalmilliseconds
#     } else {
#         [int]$cp = ([datetime]::now - $checkpointStartTime).totalmilliseconds
#     }

#     if ($showPromptCheckpoint) {
#         $debugpreference = 'Continue'
#         $message = "$([char]27)[95m${cp}ms: $CheckpointName$([char]27)[0m"
#         if ($AsWriteHost) {
#             Write-Host -Fore Magenta $Message
#         } else {
#             Write-Debug $Message -Verbose
#         }
#     }
# }
#endregion Checkpoint

#region EditorStuff
if ((Get-Module PSReadLine).version -ge '2.1.0') {
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
}
Set-PSReadLineOption -MaximumHistoryCount 32767 #-HistorySavePath "$([environment]::GetFolderPath('ApplicationData'))\Microsoft\Windows\PowerShell\PSReadLine\history.txt"
# Set-PSReadLineKeyHandler -Key "Ctrl+f" -Function ForwardWord

#Set editor to VSCode or nano if present
if (Get-Command code -Type Application -ErrorAction SilentlyContinue) {
    $ENV:EDITOR='code'
} elseif (Get-Command nano -Type Application -ErrorAction SilentlyContinue) {
    $ENV:EDITOR='nano'
}

Set-PSReadLineKeyHandler -Description 'Edit current directory with Visual Studio Code' -Chord Ctrl+Shift+e -ScriptBlock {
    if (Get-Command code-insiders -ErrorAction SilentlyContinue) { code-insiders . } else {
        code .
    }
}
#endregion EditorStuff

#region CredentialDefaults
$CredentialVaultName = 'PSDefaultCredentials'
if (
    (Get-Command Get-Secret -Module 'Microsoft.Powershell.SecretManagement' -ErrorAction SilentlyContinue) -and 
    (Get-SecretVault 'PSDefaultCredentials' -ErrorAction SilentlyContinue)
) {
    @{
        'Publish-Module:NuGetApiKey' = $(Get-Secret -Name 'PSGalleryApiKey' -Vault 'PSDefaultCredentials' -asplaintext)
        'Publish-PSResource:ApiKey' = $(Get-Secret -Name 'PSGalleryApiKey' -Vault 'PSDefaultCredentials' -asplaintext)
        'Connect-PRTGServer:Credential' = $(Get-Secret -Name 'PRTGDefault' -Vault 'PSDefaultCredentials')
        'Connect-VIServer:Credential' = $(Get-Secret -Name 'VMAdmin' -Vault 'PSDefaultCredentials')
    }.GetEnumerator().Foreach{
        $PSDefaultCredentials[$PSItem.Name] = $PSItem.Value
    }
}
#endregion CredentialDefaults



#region VSCodeTheme
if ($env:TERM_PROGRAM -eq 'VSCode' -or $env:WT_SESSION) {
    if ($psedition -eq 'core') {
        $e = "`e"
    } else {
        $e = [char]0x1b
    }

    if ($PSEdition -eq 'Core') {
        Set-PSReadLineOption -Colors @{
            Command            = "$e[93m"
            Comment            = "$e[32m"
            ContinuationPrompt = "$e[37m"
            Default            = "$e[37m"
            Emphasis           = "$e[96m"
            Error              = "$e[31m"
            Keyword            = "$e[35m"
            Member             = "$e[96m"
            Number             = "$e[35m"
            Operator           = "$e[37m"
            Parameter          = "$e[37m"
            Selection          = "$e[37;46m"
            String             = "$e[33m"
            Type               = "$e[34m"
            Variable           = "$e[96m"
        }
    }

    #Verbose Text should be distinguishable, some hosts set this to yellow
    $host.PrivateData.DebugBackgroundColor = 'Black'
    $host.PrivateData.DebugForegroundColor = 'Magenta'
    $host.PrivateData.ErrorBackgroundColor = 'Black'
    $host.PrivateData.ErrorForegroundColor = 'Red'
    $host.PrivateData.ProgressBackgroundColor = 'DarkCyan'
    $host.PrivateData.ProgressForegroundColor = 'Yellow'
    $host.PrivateData.VerboseBackgroundColor = 'Black'
    $host.PrivateData.VerboseForegroundColor = 'Cyan'
    $host.PrivateData.WarningBackgroundColor = 'Black'
    $host.PrivateData.WarningForegroundColor = 'DarkYellow'

    if ($env:WT_SESSION) {
        [Console]::Title = ''
    } else {
        [Console]::Title = "Powershell $($PSVersionTable.PSVersion.Major)"
    }
}
#endregion VSCodeTheme

#Set Window Title to icon-only for Windows Terminal, otherwise display Powershell version

# checkpoint WTSession

#region ShortHands
$shortHands = @{
    terraform = 'tf'
    pulumi = 'pul'
    kubectl = 'k'
}
$shorthands.keys.Foreach{
    if (Get-Command $PSItem -Type Application -ErrorAction SilentlyContinue) {
        Set-Alias -Name $shortHands.$PSItem -Value $PSItem 
    }
}
#endregion Shorthands

#region Helpers

function cicommit { git commit --amend --no-edit;git push -f }

function bounceCode { Get-Process code* | Stop-Process;code }

function debugOn { $GLOBAL:VerbosePreference = 'Continue';$GLOBAL:DebugPreference = 'Continue' }

function testprompt {
    Import-Module "$HOME\Projects\PowerPrompt\PowerPrompt\PowerPrompt.psd1" -Force
    Get-PowerPromptDefaultTheme
}

function Invoke-WebScript {
    param (
        [string]$uri,
        [Parameter(ValueFromRemainingArguments)]$myargs
    )
    Invoke-Expression "& {$(Invoke-WebRequest $uri)} $myargs"
}

function starshipc {
    <#
    .SYNOPSIS
    Enable starship command autocompletions
    #>
    Invoke-Expression ((starship completions powershell) -join "`n")
}

#endregion Helpers



#region Integrations

#Scoop Fast Search Integration
if (Get-Command scoop-search -Type Application -ErrorAction SilentlyContinue) { Invoke-Expression (&scoop-search --hook) }

#Force TLS 1.2 for all connections
if ($PSEdition -eq 'Desktop') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

#Enable concise errorview for PS7 and up
if ($psversiontable.psversion.major -ge 7) {
    $ErrorView = 'ConciseView'
}

#Starship Prompt
if (Get-Command starship -CommandType Application -ErrorAction SilentlyContinue) {
    #Separate Prompt for vscode. We don't use the profile so this works for both integrated and external terminal modes
    if ($ENV:VSCODE_GIT_IPC_HANDLE) {
        $ENV:STARSHIP_CONFIG = "$HOME\.config\starship-vscode.toml"
    }
    #Get Starship Prompt Initializer
    [string]$starshipPrompt = (& starship init powershell --print-full-init) -join "`n"

    #Kludge: Take a common line and add a suffix to it
    $stubToReplace = 'prompt {'
    $replaceShim = {
        $env:STARSHIP_ENVVAR = if (Test-Path Variable:/PSDebugContext) {
            "`u{1f41e}"
        } else {
            $null
        }
    }

    $starshipPrompt = $starshipPrompt -replace 'prompt \{',"prompt { $($replaceShim.ToString())"
    if ($starshipPrompt -notmatch 'STARSHIP_ENVVAR') {Write-Error 'Starship shimming failed, check $profile'}

    . ([ScriptBlock]::create($starshipPrompt))
    if ((Get-Module PSReadline).Version -ge '2.1.0') {
        Set-PSReadLineOption -PromptText "`e[32m❯ ", '❯ '
    }
}
#endregion Integrations

#Powershell 5.1 helper for emojis
# function Get-Unicode ([String[]]$UnicodeChars) {
#     $result = New-Object Text.StringBuilder
#     $UnicodeChars.Split(' ').foreach{
#         $char = [Char]::ConvertFromUtf32(
#             [Convert]::ToInt32(($PSItem -replace '^U\+'),16)
#         )
#         $result.append($char) > $null
#     }
#     [String]$result
# }