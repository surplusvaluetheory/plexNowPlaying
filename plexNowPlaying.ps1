# Don't forget to set the execution policy.
# `Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process`
# This one is very permissive when run as administrator:
# `set-executionpolicy remotesigned`
# or run this as current user:
# `Set-ExecutionPolicy -Scope CurrentUser remotesigned`

# Load the .env file
$env:EnvFile = '.\.env'
$env = Get-Content -Path $env:EnvFile | ConvertFrom-StringData

# Initialize logging function
function Write-LogMessage {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

# Read cooldown value from .env file
$cooldownInterval = [int]$env.CooldownInterval
# Read command list from .env file and split by comma
$commandList = $env.Commands -split ','

# Updated function to fetch current title, year, director, first 5 actors, current position, and total duration from Plex for a specific user
function GetCurrentTitleFromPlex {
    $PlexToken = $env.PlexToken
    $PlexUrl = $env.PlexUrl
    $desiredUser = $env.DesiredUser

    $headers = @{
        "Accept" = "application/xml"
        "X-Plex-Token" = $PlexToken
    }

    try {
        $PlexResponse = Invoke-RestMethod -Uri "$PlexUrl/status/sessions" -Headers $headers -Method Get

        $userSession = $PlexResponse.MediaContainer.Video | Where-Object {
            $_.User.title -eq $desiredUser
        }

        if ($null -ne $userSession) {
            $title = $userSession.title
            $year = $userSession.year
            $directors = ($userSession.Director | Select-Object -Property tag).tag -join ', '
            $actors = ($userSession.Role | Select-Object -First 5).tag -join ', '
            $viewOffset = [math]::Round($userSession.viewOffset / 1000)  # In seconds
            $duration = [math]::Round($userSession.duration / 1000)  # In seconds
            $mediaType = $userSession.type
            $showTitle = $userSession.grandparentTitle
            $season = $userSession.parentIndex
            $episode = $userSession.index

            $viewOffsetTime = if ($viewOffset -ge 3600) {
                (New-TimeSpan -Seconds $viewOffset).ToString("hh\:mm\:ss")
            } else {
                (New-TimeSpan -Seconds $viewOffset).ToString("mm\:ss")
            }

            $durationTime = if ($duration -ge 3600) {
                (New-TimeSpan -Seconds $duration).ToString("hh\:mm\:ss")
            } else {
                (New-TimeSpan -Seconds $duration).ToString("mm\:ss")
            }

            if ($actors -ne '') {
                $actors = "Feat: " + $actors -replace ',([^,]*)$', ' and$1'
            }

            if ($mediaType -eq "episode") {
                return "$showTitle S$season E$episode - $title ($year) Dir: $directors. $actors ($viewOffsetTime/$durationTime)"
            } else {
                return "$title ($year) Dir: $directors. $actors ($viewOffsetTime/$durationTime)"
            }            
        } else {
            Write-LogMessage -Message "No media currently playing for user $desiredUser." -Level "ERROR"
            return $null
        }

    } catch {
        Write-LogMessage -Message "Error fetching data from Plex: $_" -Level "ERROR"
        return $null
    }
}

# Twitch IRC Configuration
$server = "irc.chat.twitch.tv"
$port = 6697
$nick = $env.TwitchNick
$password = $env.TwitchPassword

# Check if the password already starts with 'oauth:', if not, prepend it
if ($password -notmatch "^oauth:") {
    $password = "oauth:$password"
}

$channel = $env.TwitchChannel

# Handle '#' in Twitch channel name
if ($channel -notmatch "^#") {
    $channel = "#$channel"
}

# Create TCP Client and connect to Twitch IRC
$client = New-Object System.Net.Sockets.TcpClient
$client.Connect($server, $port)
$sslStream = New-Object System.Net.Security.SslStream $client.GetStream()
$sslStream.AuthenticateAsClient($server)
$writer = New-Object System.IO.StreamWriter $sslStream
$reader = New-Object System.IO.StreamReader $sslStream

# Send authentication and join channel
$writer.WriteLine("PASS $password")
$writer.WriteLine("NICK $nick")
$writer.WriteLine("JOIN $channel")
$writer.Flush()

# Initialize last command time
$lastCommandTime = Get-Date -Date "01/01/1970 00:00:00"

# Main loop to read chat and respond to !np
while($true) {
    $readData = $reader.ReadLine()
    Write-LogMessage -Message "Received: $readData" -Level "DEBUG"

    if ($readData -match "PING :tmi.twitch.tv") {
        $writer.WriteLine("PONG :tmi.twitch.tv")
        $writer.Flush()
        Write-LogMessage -Message "PONG sent." -Level "DEBUG"
    }

    foreach ($command in $commandList) {
        if ($readData -match ":.*?$command") {
            $currentTime = Get-Date
            $timeSinceLastCommand = $currentTime - $lastCommandTime
    
            if ($timeSinceLastCommand.TotalSeconds -ge $cooldownInterval) {
                $currentTitle = GetCurrentTitleFromPlex
                if ($null -ne $currentTitle) {
                    $response = "PRIVMSG $channel :$currentTitle"
                    $writer.WriteLine($response)
                    $writer.Flush()
                    Write-LogMessage -Message "Response sent: $currentTitle" -Level "INFO"
                }
                $lastCommandTime = $currentTime
            } else {
                Write-LogMessage -Message "Cooldown active. Skipping command execution." -Level "DEBUG"
            }
        }
    }
}
