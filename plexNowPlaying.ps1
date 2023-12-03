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
$timerCommandList = $env.TimerCommands -split ','

# Function to fetch current title, year, director, first 5 actors, current position, and total duration from Plex for a specific user
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

            # Create a hashtable to return multiple values
            $result = @{
                Title = $title
                Year = $year
                Directors = $directors
                Actors = $actors
                ViewOffsetTime = $viewOffsetTime
                DurationTime = $durationTime
                FullText = ""
            }

            if ($mediaType -eq "episode") {
                $result.FullText = "$showTitle S$season E$episode - $title ($year) Dir: $directors. $actors ($viewOffsetTime/$durationTime)"
            } else {
                $result.FullText = "$title ($year) Dir: $directors. $actors ($viewOffsetTime/$durationTime)"
            }   
            
            return $result         
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

# Initialize a flag to indicate if a command was processed
$commandProcessed = $false

# Main loop to read chat and respond to commands
while($true) {
    $readData = $reader.ReadLine()
    Write-LogMessage -Message "Received: $readData" -Level "DEBUG"

    # Reset command processed flag at the beginning of each loop
    $commandProcessed = $false

    if ($readData -match "PING :tmi.twitch.tv") {
        $writer.WriteLine("PONG :tmi.twitch.tv")
        $writer.Flush()
        Write-LogMessage -Message "PONG sent." -Level "DEBUG"
    }

    foreach ($command in $commandList) {
        if ($readData -match ":.*?$command" -and -not $commandProcessed) {
            $currentTime = Get-Date
            $timeSinceLastCommand = $currentTime - $lastCommandTime

            if ($timeSinceLastCommand.TotalSeconds -ge $cooldownInterval) {
                $currentTitleInfo = GetCurrentTitleFromPlex
                if ($null -ne $currentTitleInfo) {
                    $response = "PRIVMSG $channel :$($currentTitleInfo.FullText)"
                    $writer.WriteLine($response)
                    $writer.Flush()
                    Write-LogMessage -Message "Response sent: $($currentTitleInfo.FullText)" -Level "INFO"
                    $commandProcessed = $true
                }
                $lastCommandTime = $currentTime
            } else {
                Write-LogMessage -Message "Cooldown active. Skipping command execution." -Level "DEBUG"
            }
        }
    }

    foreach ($timerCommand in $timerCommandList) {
        if ($readData -match ":.*?$timerCommand" -and -not $commandProcessed) {
            $currentTime = Get-Date
            $timeSinceLastCommand = $currentTime - $lastCommandTime

            if ($timeSinceLastCommand.TotalSeconds -ge $cooldownInterval) {
                $currentTitleInfo = GetCurrentTitleFromPlex
                if ($null -ne $currentTitleInfo) {
                    $response = "PRIVMSG $channel :$($currentTitleInfo.ViewOffsetTime)/$($currentTitleInfo.DurationTime)"
                    $writer.WriteLine($response)
                    $writer.Flush()
                    Write-LogMessage -Message "Sent: $response" -Level "INFO"
                    $commandProcessed = $true
                }
                $lastCommandTime = $currentTime
            } else {
                Write-LogMessage -Message "Cooldown in effect. Skipping command." -Level "DEBUG"
            }
        }
    }
}
