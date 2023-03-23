using namespace System.Management.Automation
using namespace System.Management.Automation.Language
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
$HistorySavePath = Join-Path (Split-Path (Get-PSReadLineOption).HistorySavePath) 'history.txt'
Set-PSReadLineOption -HistorySavePath $HistorySavePath

$PSReadlineVersion = (Get-Module PSReadLine).version

if ($PSReadlineVersion -ge '2.1.0') {
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key 'Alt+RightArrow' -Function 'AcceptNextSuggestionWord'
}

# Stolen and modified from https://github.com/PowerShell/PSReadLine/blob/master/PSReadLine/SamplePSReadLineProfile.ps1
# F1 for help on the command line - naturally
Set-PSReadLineKeyHandler -Key F1 `
    -BriefDescription CommandHelp `
    -LongDescription 'Open the help window for the current command' `
    -ScriptBlock {
    param($key, $arg)

    $ast = $null
    $tokens = $null
    $errors = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$errors, [ref]$cursor)

    $commandAst = $ast.FindAll( {
            $node = $args[0]
            $node -is [CommandAst] -and
            $node.Extent.StartOffset -le $cursor -and
            $node.Extent.EndOffset -ge $cursor
        }, $true) | Select-Object -Last 1

    if ($commandAst -ne $null) {
        $commandName = $commandAst.GetCommandName()
        if ($commandName -ne $null) {
            $command = $ExecutionContext.InvokeCommand.GetCommand($commandName, 'All')
            if ($command -is [Management.Automation.AliasInfo]) {
                $commandName = $command.ResolvedCommandName
            }

            if ($commandName -ne $null) {
                #First try online
                try {
                    Get-Help $commandName -Online -ErrorAction Stop
                } catch [InvalidOperationException] {
                    if ($PSItem -notmatch 'The online version of this Help topic cannot be displayed') {throw}
                    Get-Help $CommandName -ShowWindow
                }
            }
        }
    }
}

# Insert text from the clipboard as a here string
Set-PSReadLineKeyHandler -Key Ctrl+Alt+V `
                         -BriefDescription PasteAsHereString `
                         -LongDescription "Paste the clipboard text as a here string" `
                         -ScriptBlock {
    param($key, $arg)

    Add-Type -Assembly PresentationCore
    if ([System.Windows.Clipboard]::ContainsText())
    {
        # Get clipboard text - remove trailing spaces, convert \r\n to \n, and remove the final \n.
        $text = ([System.Windows.Clipboard]::GetText() -replace "\p{Zs}*`r?`n","`n").TrimEnd()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert("@'`n$text`n'@")
    }
    else
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::Ding()
    }
}

# Sometimes you want to get a property of invoke a member on what you've entered so far
# but you need parens to do that.  This binding will help by putting parens around the current selection,
# or if nothing is selected, the whole line.
Set-PSReadLineKeyHandler -Key 'Alt+(' `
                         -BriefDescription ParenthesizeSelection `
                         -LongDescription "Put parenthesis around the selection or entire line and move the cursor to after the closing parenthesis" `
                         -ScriptBlock {
    param($key, $arg)

    $selectionStart = $null
    $selectionLength = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    if ($selectionStart -ne -1)
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, '(' + $line.SubString($selectionStart, $selectionLength) + ')')
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
    }
    else
    {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, '(' + $line + ')')
        [Microsoft.PowerShell.PSConsoleReadLine]::EndOfLine()
    }
}


# Each time you press Alt+', this key handler will change the token
# under or before the cursor.  It will cycle through single quotes, double quotes, or
# no quotes each time it is invoked.
Set-PSReadLineKeyHandler -Key "Alt+'" `
                         -BriefDescription ToggleQuoteArgument `
                         -LongDescription "Toggle quotes on the argument under the cursor" `
                         -ScriptBlock {
    param($key, $arg)

    $ast = $null
    $tokens = $null
    $errors = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$errors, [ref]$cursor)

    $tokenToChange = $null
    foreach ($token in $tokens)
    {
        $extent = $token.Extent
        if ($extent.StartOffset -le $cursor -and $extent.EndOffset -ge $cursor)
        {
            $tokenToChange = $token

            # If the cursor is at the end (it's really 1 past the end) of the previous token,
            # we only want to change the previous token if there is no token under the cursor
            if ($extent.EndOffset -eq $cursor -and $foreach.MoveNext())
            {
                $nextToken = $foreach.Current
                if ($nextToken.Extent.StartOffset -eq $cursor)
                {
                    $tokenToChange = $nextToken
                }
            }
            break
        }
    }

    if ($tokenToChange -ne $null)
    {
        $extent = $tokenToChange.Extent
        $tokenText = $extent.Text
        if ($tokenText[0] -eq '"' -and $tokenText[-1] -eq '"')
        {
            # Switch to no quotes
            $replacement = $tokenText.Substring(1, $tokenText.Length - 2)
        }
        elseif ($tokenText[0] -eq "'" -and $tokenText[-1] -eq "'")
        {
            # Switch to double quotes
            $replacement = '"' + $tokenText.Substring(1, $tokenText.Length - 2) + '"'
        }
        else
        {
            # Add single quotes
            $replacement = "'" + $tokenText + "'"
        }

        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
            $extent.StartOffset,
            $tokenText.Length,
            $replacement)
    }
}

#Set editor to VSCode or nano if present
if (Get-Command code -Type Application -ErrorAction SilentlyContinue) {
    $ENV:EDITOR = 'code'
} elseif (Get-Command nano -Type Application -ErrorAction SilentlyContinue) {
    $ENV:EDITOR = 'nano'
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
    (Get-SecretVault $CredentialVaultName -ErrorAction SilentlyContinue)
) {
    @{
        'Publish-Module:NuGetApiKey'    = $(Get-Secret -Name 'PSGalleryApiKey' -Vault $CredentialVaultName -AsPlainText)
        'Publish-PSResource:ApiKey'     = $(Get-Secret -Name 'PSGalleryApiKey' -Vault $CredentialVaultName -AsPlainText)
        'Connect-PRTGServer:Credential' = $(Get-Secret -Name 'PRTGDefault' -Vault $CredentialVaultName)
        'Connect-VIServer:Credential'   = $(Get-Secret -Name 'VMAdmin' -Vault $CredentialVaultName)
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

    if ($PSStyle) {
        $PSStyle.Formatting.Debug = $PSStyle.Foreground.Magenta
        $PSStyle.Formatting.Verbose = $PSStyle.Foreground.Cyan
        $PSStyle.Formatting.Error = $PSStyle.Foreground.BrightRed
        $PSStyle.Formatting.Warning = $PSStyle.Foreground.Yellow
        $PSStyle.FileInfo.Directory = $PSStyle.Foreground.Blue
        $PSStyle.Progress.View = 'Minimal'
        $PSStyle.Formatting.FormatAccent = $PSStyle.Foreground.BrightBlack
        $PSStyle.Formatting.TableHeader = $PSStyle.Foreground.BrightBlack
    }

    if ($env:WT_SESSION) {
        [Console]::Title = ''
    } else {
        [Console]::Title = "Powershell $($PSVersionTable.PSVersion.Major)"
    }
}
#endregion VSCodeTheme

#region ShortHands
$shortHands = @{
    terraform = 'tf'
    pulumi    = 'pul'
    kubectl   = 'k'
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

function Invoke-WebScript {
    param (
        [string]$uri,
        [Parameter(ValueFromRemainingArguments)]$myargs
    )
    Invoke-Expression "& {$(Invoke-WebRequest $uri)} $myargs"
}

#endregion Helpers

#region Integrations

#Scoop Fast Search Integration
if (Get-Command scoop-search -Type Application -ErrorAction SilentlyContinue) { Invoke-Expression (&scoop-search --hook) }

#Force TLS 1.2 for all WinPS 5.1 connections
if ($PSEdition -eq 'Desktop') {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

#Enable concise errorview for PS7 and up
if ($psversiontable.psversion.major -ge 7) {
    $ErrorView = 'ConciseView'
}

#Enable new fancy progress bar
if ($psversiontable.psversion -ge 7) {
    #Windows Terminal
    if ($ENV:WT_SESSION) {
        $PSStyle.Progress.UseOSCIndicator = $true
    }
}

#Enable AzPredictor if present
if ((Get-Module psreadline).Version -gt 2.1.99 -and (Get-Command 'Enable-AzPredictor' -ErrorAction SilentlyContinue)) {
    Enable-AzPredictor
}

#Oh-My-Posh custom prompt
try {
    (@(& oh-my-posh init pwsh --config="$HOME\.config\oh-my-posh\rastan.omp.yaml" --print) -join "`n") | Invoke-Expression
} catch [CommandNotFoundException] {
    Write-Verbose "PROFILE: oh-my-posh not found on this system, skipping prompt"
}
#endregion Integrations
