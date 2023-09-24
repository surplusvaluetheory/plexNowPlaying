# Twitch-Plex Bot

This project contains a PowerShell script `plexNowPlaying.ps1` that connects to a Twitch chat and displays currently playing titles from Plex Media Server upon command.

## Getting Started

Follow these steps to get the project up and running.

### Prerequisites

1. PowerShell
2. A Plex Media Server account and its token
3. A Twitch account and its OAuth token

### Configuration

#### Environment Variables

1. Rename the `example.env` file to `.env`.
2. Open `.env` in your preferred text editor.
3. Update the variables with the relevant information:

```plaintext
PlexToken=YourPlexToken                # Your Plex authentication token
PlexUrl=https://yourplexurl.plex.direct:32400 # Plex server URL
DesiredUser=yourplexusername            # The Plex username to fetch the data for
TwitchServer=irc.chat.twitch.tv         # Twitch IRC server
TwitchPort=6697                         # Twitch IRC port (SSL)
TwitchNick=yourTwitchUsername           # Your Twitch username
TwitchPassword=oauthasdfasddfasdfasdfasdfasdf # Your Twitch OAuth token
TwitchChannel=#yourtwitchchatchannel    # The Twitch channel to join
```

- To get your Plex token, follow the instructions on the [Plex Support page](https://support.plex.tv/articles/204059436-finding-an-authentication-token-x-plex-token/).
  
- To get your Twitch OAuth token, you can use [Twitch Token Generator](https://twitchtokengenerator.com/).

#### Execution Policy

You may also need to set the PowerShell execution policy to run the script. Open PowerShell as an administrator and run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

or for the current user:

```powershell
Set-ExecutionPolicy -Scope CurrentUser remotesigned
```

## Usage

After updating the `.env` file and setting the execution policy, run the PowerShell script.

```powershell
.\plexNowPlaying.ps1
```

Your bot should now be running, and it will display currently playing Plex titles in the Twitch chat when triggered by the `!np` command.
