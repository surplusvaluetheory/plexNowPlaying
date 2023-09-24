# Don't forget to set the execution policy.
# Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
# This one is very permissive when run as administrator:
# set-executionpolicy remotesigned
# or run this as current user:
# Set-ExecutionPolicy -Scope CurrentUser remotesigned

# Load the .env file
$env:EnvFile = '.\.env'
$env = Get-Content -Path $env:EnvFile | ConvertFrom-StringData

# Initialize logging function
function Log-Message {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

# Function to fetch current title, year, and director from Plex for a specific user
function GetCurrentTitleFromPlex {
    $PlexToken = $env.PlexToken
    $PlexUrl = $env.PlexUrl
    $desiredUser = $env.DesiredUser

    $headers = @{
        "Accept" = "application/json"
        "X-Plex-Token" = $PlexToken
    }

    try {
        $PlexResponse = Invoke-RestMethod -Uri "$PlexUrl/status/sessions" -Headers @{ 'X-Plex-Token' = $PlexToken }

        $userSession = $PlexResponse.MediaContainer.Video | Where-Object {
            $_.User.title -eq $desiredUser
        }

        if ($null -ne $userSession) {
            $title = $userSession.title
            $year = $userSession.year
            $director = $userSession.Director.tag
            return "$title ($year) Directed by: $director"
        } else {
            Log-Message -Message "No media currently playing for user $desiredUser." -Level "ERROR"
            return $null
        }

    } catch {
        Log-Message -Message "Error fetching data from Plex: $_" -Level "ERROR"
        return $null
    }
}

# Twitch IRC Configuration
$server = $env.TwitchServer
$port = $env.TwitchPort
$nick = $env.TwitchNick
$password = $env.TwitchPassword

# Check if the password already starts with 'oauth:', if not, prepend it
if ($password -notmatch "^oauth:") {
    $password = "oauth:$password"
}

$channel = $env.TwitchChannel

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
    Log-Message -Message "Received: $readData" -Level "DEBUG"

    if ($readData -match "PING :tmi.twitch.tv") {
        $writer.WriteLine("PONG :tmi.twitch.tv")
        $writer.Flush()
        Log-Message -Message "PONG sent." -Level "DEBUG"
    }

    if ($readData -match ":.*?!np") {
        $currentTime = Get-Date
        $timeSinceLastCommand = $currentTime - $lastCommandTime

        if ($timeSinceLastCommand.TotalSeconds -ge 30) {
            $currentTitle = GetCurrentTitleFromPlex
            if ($currentTitle -ne $null) {
                $response = "PRIVMSG $channel :Now Playing: $currentTitle"
                $writer.WriteLine($response)
                $writer.Flush()
                Log-Message -Message "Sent: $response" -Level "INFO"

                # Update last command time
                $lastCommandTime = $currentTime
            } else {
                Log-Message -Message "Couldn't fetch current title from Plex" -Level "ERROR"
            }
        } else {
            Log-Message -Message "Cooldown in effect. Skipping command." -Level "DEBUG"
        }
    }
}
